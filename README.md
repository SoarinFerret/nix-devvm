# nix-devvm

A lightweight NixOS development VM using [microvm.nix](https://github.com/microvm-nix/microvm.nix) and QEMU. It mounts your current working directory into the VM at `/workspace` via virtiofs.

## Usage

Run the VM from any project directory:

```sh
nix run github:soarinferret/nix-devvm
```

The VM will start with your current directory shared at `/workspace`. VM state is stored per-project in `~/.local/share/devvm/`.

## Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `devvm.hostname` | string | `"devvm"` | VM hostname |
| `devvm.username` | string | `"dev"` | Default user account name (also used for autologin and initial password) |
| `devvm.cpus` | int | `4` | Number of virtual CPUs |
| `devvm.memorySize` | int | `4096` | Memory in megabytes |
| `devvm.storeOverlaySize` | int | `8192` | Writable nix store overlay disk size in megabytes |
| `devvm.packages` | list of packages | curl, wget, htop, jq, file, unzip, zip, devbox, claude-code | Packages installed in the VM |

## Customization

### Using as a library

The flake exports a `mkDevvm` helper that builds a customized VM package. Add `nix-devvm` as a flake input and call `mkDevvm` with extra NixOS modules:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-devvm.url = "github:soarinferret/nix-devvm";
  };

  outputs = { nixpkgs, nix-devvm, ... }: let
    system = "x86_64-linux";
  in {
    packages.${system}.default = nix-devvm.lib.${system}.mkDevvm {
      extraModules = [
        {
          devvm.cpus = 8;
          devvm.memorySize = 8192;
          devvm.packages = with nixpkgs.legacyPackages.${system}; [
            curl
            git
            nodejs
          ];

          # Any NixOS options work here too
          programs.fish.enable = true;
          programs.git.enable = true;
        }
      ];
    };
  };
}
```