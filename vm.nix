{ config, lib, pkgs, ... }:

let
  cfg = config.devvm;
in
{
  options.devvm = {
    hostname = lib.mkOption {
      type = lib.types.str;
      default = "devvm";
      description = "Hostname for the VM.";
    };

    username = lib.mkOption {
      type = lib.types.str;
      default = "dev";
      description = "Username for the default user account.";
    };

    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [
        curl
        wget
        htop
        jq
        file
        unzip
        zip
        devbox
        claude-code
      ];
      defaultText = lib.literalExpression "[ curl wget htop jq file unzip zip devbox claude-code ]";
      description = "Packages to install in the VM.";
    };
  };

  config = {
    # Tmpfs root filesystem (ephemeral)
    fileSystems."/" = {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [ "mode=0755" "size=50%" ];
    };

    # Virtiofs: read-only nix store from host
    fileSystems."/nix/.ro-store" = {
      device = "nix-store";
      fsType = "virtiofs";
      neededForBoot = true;
    };

    # Ext4 overlay disk for writable nix store
    fileSystems."/nix/.rw-store" = {
      device = "/dev/vda";
      fsType = "ext4";
      neededForBoot = true;
    };

    # Overlayfs combining read-only store with writable overlay
    fileSystems."/nix/store" = {
      overlay = {
        lowerdir = [ "/nix/.ro-store" ];
        upperdir = "/nix/.rw-store/store";
        workdir = "/nix/.rw-store/work";
      };
      depends = [ "/nix/.ro-store" "/nix/.rw-store" ];
      neededForBoot = true;
    };

    # Virtiofs: workspace share from host
    fileSystems."/workspace" = {
      device = "workspace";
      fsType = "virtiofs";
    };

    boot.initrd.availableKernelModules = [
      "virtiofs"
      "virtio_pci"
      "virtio_blk"
      "overlay"
      "ext4"
    ];

    # Systemd initrd for faster boot
    boot.initrd.systemd.enable = true;
    boot.initrd.systemd.tpm2.enable = false;

    # No bootloader needed — QEMU boots kernel directly
    boot.loader.grub.enable = false;

    # Reduce serial ports probe time
    boot.kernelParams = [ "8250.nr_uarts=1" ];
    boot.swraid.enable = false;
    boot.blacklistedKernelModules = [ "rfkill" "intel_pstate" ];

    # Disable docs — saves closure size and boot time
    documentation.enable = false;

    # systemd-networkd is faster than scripted networking
    networking.hostName = cfg.hostname;
    networking.useNetworkd = true;
    systemd.network.wait-online.enable = false;
    systemd.tpm2.enable = false;

    # No need for nixos-rebuild in ephemeral VM
    system.switch.enable = false;

    # Auto-login on serial console
    services.getty.autologinUser = cfg.username;

    users.users.${cfg.username} = {
      uid = 1000;
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      initialPassword = cfg.username;
    };

    security.sudo.wheelNeedsPassword = false;

    environment.interactiveShellInit = ''
      if [ -d /workspace ]; then
        cd /workspace
      fi
    '';

    environment.systemPackages = cfg.packages;

    # Required for nix/devbox to work inside the VM
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
    nixpkgs.config.allowUnfree = true;

    system.stateVersion = "25.11";
  };
}
