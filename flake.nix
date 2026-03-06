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

    mkDevvmSystem = extraModules: nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        microvm.nixosModules.microvm
        ./vm.nix
      ] ++ extraModules;
    };

    mkDevvmPackage = extraModules: let
      vm = mkDevvmSystem extraModules;
      runner = vm.config.microvm.declaredRunner;
    in pkgs.writeShellScriptBin "devvm" ''
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

      ${runner}/bin/microvm-run
    '';

    devvm-runner = self.nixosConfigurations.devvm.config.microvm.declaredRunner;
  in {
    lib.${system}.mkDevvm = { extraModules ? [] }: mkDevvmPackage extraModules;

    packages.${system} = {
      devvm = mkDevvmPackage [];
      default = self.packages.${system}.devvm;
    };

    nixosConfigurations.devvm = mkDevvmSystem [];
  };
}
