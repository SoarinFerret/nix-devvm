# nix-devvm

A lightweight NixOS development VM using [microvm.nix](https://github.com/microvm-nix/microvm.nix) and QEMU. It mounts your current working directory into the VM at `/workspace` via virtiofs.

## Usage

Run the VM from any project directory:

```sh
nix run github:cernesti/nix-devvm
```

The VM will start with your current directory shared at `/workspace`. VM state is stored per-project in `~/.local/share/devvm/`.

## Options

Configure the VM by editing the inline module in `flake.nix`:

```nix
nixosConfigurations.devvm = nixpkgs.lib.nixosSystem {
  inherit system;
  modules = [
    microvm.nixosModules.microvm
    ./vm.nix
    {
      devvm.hostname = "myvm";
      devvm.username = "myuser";
      devvm.cpus = 8;
      devvm.memorySize = 8192;
    }
  ];
};
```

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `devvm.hostname` | string | `"devvm"` | VM hostname |
| `devvm.username` | string | `"dev"` | Default user account name (also used for autologin and initial password) |
| `devvm.cpus` | int | `4` | Number of virtual CPUs |
| `devvm.memorySize` | int | `4096` | Memory in megabytes |
| `devvm.storeOverlaySize` | int | `8192` | Writable nix store overlay disk size in megabytes |
| `devvm.packages` | list of packages | curl, wget, htop, jq, file, unzip, zip, devbox, claude-code | Packages installed in the VM |
| `devvm.extraConfig` | attrs | `{}` | Extra NixOS configuration merged into the VM |

## Extra configuration

Use `devvm.extraConfig` to set any NixOS options without modifying `vm.nix`:

```nix
{
  devvm.extraConfig = {
    programs.fish.enable = true;
    programs.git.enable = true;
    programs.neovim = {
      enable = true;
      defaultEditor = true;
    };
  };
}
```
