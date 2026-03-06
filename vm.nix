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

    cpus = lib.mkOption {
      type = lib.types.int;
      default = 4;
      description = "Number of virtual CPUs for the VM.";
    };

    memorySize = lib.mkOption {
      type = lib.types.int;
      default = 4096;
      description = "Memory size in megabytes for the VM.";
    };

    storeOverlaySize = lib.mkOption {
      type = lib.types.int;
      default = 8192;
      description = "Size in megabytes of the writable nix store overlay disk image.";
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

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = {};
      description = "Extra NixOS configuration to merge into the VM.";
    };
  };

  config = lib.mkMerge [
    {
      microvm = {
        hypervisor = "qemu";
        mem = cfg.memorySize;
        vcpu = cfg.cpus;

        interfaces = [{
          type = "user";
          id = "eth0";
          mac = "02:00:00:00:00:01";
        }];

        shares = [
          {
            tag = "ro-store";
            source = "/nix/store";
            mountPoint = "/nix/.ro-store";
            proto = "9p";
          }
          {
            tag = "workspace";
            source = "/tmp/devvm-workspace";
            mountPoint = "/workspace";
            proto = "virtiofs";
          }
        ];

        writableStoreOverlay = "/nix/.rw-store";

        virtiofsd.group = null;

        volumes = [{
          image = "nix-store-overlay.img";
          mountPoint = config.microvm.writableStoreOverlay;
          size = cfg.storeOverlaySize;
        }];
      };

      networking.hostName = cfg.hostname;

      # Auto-login on serial console
      services.getty.autologinUser = cfg.username;

      users.users.${cfg.username} = {
        uid = 1000;
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        initialPassword = cfg.username;
      };

      security.sudo.wheelNeedsPassword = false;

      environment.systemPackages = cfg.packages;

      # Required for nix/devbox to work inside the VM
      nix.settings.experimental-features = [ "nix-command" "flakes" ];
      nixpkgs.config.allowUnfree = true;

      system.stateVersion = "25.11";
    }
    cfg.extraConfig
  ];
}
