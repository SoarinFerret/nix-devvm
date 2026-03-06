{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    microvm.url = "github:microvm-nix/microvm.nix";
    microvm.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    microvm,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};

    devvm-runner = self.nixosConfigurations.devvm.config.microvm.declaredRunner;
  in {
    packages.${system} = {
      devvm = pkgs.writeShellScriptBin "devvm" ''
        PROJECT_DIR="$(pwd)"
        STATE_DIR="$HOME/.local/share/devvm/$(echo -n "$PROJECT_DIR" | md5sum | cut -d' ' -f1)"
        mkdir -p "$STATE_DIR"
        cd "$STATE_DIR"

        # Start virtiofsd directly (bypassing supervisord which changes cwd to /)
        ${pkgs.virtiofsd}/bin/virtiofsd \
          --socket-path=devvm-virtiofs-workspace.sock \
          --shared-dir="$PROJECT_DIR" \
          --thread-pool-size "$(nproc)" \
          --posix-acl --xattr &
        VIRTIOFSD_PID=$!
        cleanup() { kill "$VIRTIOFSD_PID" 2>/dev/null; wait "$VIRTIOFSD_PID" 2>/dev/null; }
        trap cleanup EXIT

        # Wait for virtiofsd socket to be ready
        while [ ! -S devvm-virtiofs-workspace.sock ]; do sleep 0.1; done

        ${devvm-runner}/bin/microvm-run
      '';

      default = self.packages.${system}.devvm;
    };

    nixosConfigurations.devvm = nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        microvm.nixosModules.microvm
        ./vm.nix
        {
          # Override defaults here, e.g.:
          # devvm.hostname = "myvm";
          # devvm.username = "myuser";
          # devvm.cpus = 8;
          # devvm.memorySize = 8192;
          # devvm.storeOverlaySize = 16384;
          # devvm.packages = [ pkgs.curl pkgs.git ];
          # devvm.extraConfig = {
          #   programs.fish.enable = true;
          #   programs.git.enable = true;
          # };
        }
      ];
    };
  };
}
