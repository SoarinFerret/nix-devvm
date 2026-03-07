{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = {
    self,
    nixpkgs,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};

    mkDevvmSystem = extraModules: nixpkgs.lib.nixosSystem {
      inherit system;
      modules = [
        ./vm.nix
      ] ++ extraModules;
    };

    mkDevvmPackage = extraModules: let
      vm = mkDevvmSystem extraModules;
      kernel = "${vm.config.system.build.kernel.out}/${pkgs.stdenv.hostPlatform.linux-kernel.target}";
      initrd = "${vm.config.system.build.initialRamdisk}/initrd";
      toplevel = vm.config.system.build.toplevel;
      kernelParams = builtins.concatStringsSep " " vm.config.boot.kernelParams;
      mem = "8192";

      qemu = "${pkgs.qemu_kvm}/bin/qemu-system-x86_64";
      virtiofsd = "${pkgs.virtiofsd}/bin/virtiofsd";
      mkfs-ext4 = "${pkgs.e2fsprogs}/bin/mkfs.ext4";
      truncate = "${pkgs.coreutils}/bin/truncate";
      md5sum = "${pkgs.coreutils}/bin/md5sum";
      cut = "${pkgs.coreutils}/bin/cut";
      mkdir = "${pkgs.coreutils}/bin/mkdir";
      sleep = "${pkgs.coreutils}/bin/sleep";
      basename = "${pkgs.coreutils}/bin/basename";
      nproc = "${pkgs.coreutils}/bin/nproc";
    in pkgs.writeShellScriptBin "devvm" ''
      set -euo pipefail

      # Defaults
      RAM="8G"
      CPUS="4"
      OVERLAY_SIZE="20G"
      declare -a EXTRA_SHARES=()

      usage() {
        echo "Usage: devvm [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --ram SIZE        VM memory, e.g. 8G or 8192M (default: 8G)"
        echo "  --cpus N          Number of vCPUs (default: 4)"
        echo "  --overlay-size S  Nix store overlay disk size (default: 20G)"
        echo "  --share PATH      Share a host directory (format: /host/path:/guest/mount or /host/path)"
        echo "  --help            Show this help"
        exit 0
      }

      while [[ $# -gt 0 ]]; do
        case "$1" in
          --ram) RAM="$2"; shift 2 ;;
          --cpus) CPUS="$2"; shift 2 ;;
          --overlay-size) OVERLAY_SIZE="$2"; shift 2 ;;
          --share) EXTRA_SHARES+=("$2"); shift 2 ;;
          --help) usage ;;
          *) echo "Unknown option: $1"; usage ;;
        esac
      done

      PROJECT_DIR="$(pwd)"
      STATE_DIR="$HOME/.local/share/devvm/$(echo -n "$PROJECT_DIR" | ${md5sum} | ${cut} -d' ' -f1)"
      ${mkdir} -p "$STATE_DIR"

      # Create overlay disk if it doesn't exist
      OVERLAY_DISK="$STATE_DIR/overlay.raw"
      if [ ! -f "$OVERLAY_DISK" ]; then
        echo "Creating overlay disk ($OVERLAY_SIZE)..."
        ${truncate} -s "$OVERLAY_SIZE" "$OVERLAY_DISK"
        ${mkfs-ext4} -q "$OVERLAY_DISK"
      fi

      # Track child PIDs for cleanup
      declare -a CHILD_PIDS=()
      cleanup() {
        for pid in "''${CHILD_PIDS[@]}"; do
          kill "$pid" 2>/dev/null || true
        done
        wait 2>/dev/null || true
      }
      trap cleanup EXIT

      # Start virtiofsd for nix store
      NIX_STORE_SOCK="$STATE_DIR/virtiofs-nix-store.sock"
      rm -f "$NIX_STORE_SOCK"
      ${virtiofsd} \
        --socket-path="$NIX_STORE_SOCK" \
        --shared-dir=/nix/store \
        --thread-pool-size "$(${nproc})" \
        --posix-acl --xattr &
      CHILD_PIDS+=($!)

      # Start virtiofsd for workspace
      WORKSPACE_SOCK="$STATE_DIR/virtiofs-workspace.sock"
      rm -f "$WORKSPACE_SOCK"
      ${virtiofsd} \
        --socket-path="$WORKSPACE_SOCK" \
        --shared-dir="$PROJECT_DIR" \
        --thread-pool-size "$(${nproc})" \
        --posix-acl --xattr &
      CHILD_PIDS+=($!)

      # Build virtiofs chardev/device args
      declare -a FS_ARGS=(
        -chardev "socket,id=fs0,path=$NIX_STORE_SOCK"
        -device "vhost-user-fs-pci,chardev=fs0,tag=nix-store"
        -chardev "socket,id=fs1,path=$WORKSPACE_SOCK"
        -device "vhost-user-fs-pci,chardev=fs1,tag=workspace"
      )

      # Start virtiofsd for each extra share
      FS_IDX=2
      for share in "''${EXTRA_SHARES[@]}"; do
        if [[ "$share" == *":"* ]]; then
          HOST_PATH="''${share%%:*}"
          GUEST_MOUNT="''${share#*:}"
        else
          HOST_PATH="$share"
          GUEST_MOUNT="/mnt/$(${basename} "$share")"
        fi

        SHARE_SOCK="$STATE_DIR/virtiofs-share-$FS_IDX.sock"
        rm -f "$SHARE_SOCK"
        ${virtiofsd} \
          --socket-path="$SHARE_SOCK" \
          --shared-dir="$HOST_PATH" \
          --thread-pool-size "$(${nproc})" \
          --posix-acl --xattr &
        CHILD_PIDS+=($!)

        FS_ARGS+=(
          -chardev "socket,id=fs$FS_IDX,path=$SHARE_SOCK"
          -device "vhost-user-fs-pci,chardev=fs$FS_IDX,tag=share-$FS_IDX"
        )
        FS_IDX=$((FS_IDX + 1))
      done

      # Wait for all virtiofsd sockets to be ready
      SOCKETS=("$NIX_STORE_SOCK" "$WORKSPACE_SOCK")
      for idx in $(seq 2 $((FS_IDX - 1))); do
        SOCKETS+=("$STATE_DIR/virtiofs-share-$idx.sock")
      done

      for sock in "''${SOCKETS[@]}"; do
        while [ ! -S "$sock" ]; do
          ${sleep} 0.1
        done
      done

      # Launch QEMU
      exec ${qemu} \
        -name devvm \
        -M q35,accel=kvm:tcg,mem-merge=on \
        -m "$RAM" \
        -smp "$CPUS" \
        -cpu host,+x2apic,-sgx \
        -nodefaults -no-user-config \
        -no-reboot \
        -enable-kvm \
        -kernel ${kernel} \
        -initrd ${initrd} \
        -append "earlyprintk=ttyS0 console=ttyS0 reboot=t panic=-1 init=${toplevel}/init ${kernelParams}" \
        -drive "id=overlay,format=raw,file=$OVERLAY_DISK,if=none,aio=io_uring,discard=unmap" \
        -device "virtio-blk-pci,drive=overlay" \
        -numa "node,memdev=mem" \
        -object "memory-backend-memfd,id=mem,size=$RAM,share=on" \
        "''${FS_ARGS[@]}" \
        -netdev "user,id=net0" \
        -device "virtio-net-pci,netdev=net0,mac=02:00:00:00:00:01,romfile=" \
        -device "virtio-rng-pci" \
        -device "i8042" \
        -chardev "stdio,id=stdio,signal=off" \
        -serial "chardev:stdio" \
        -nographic
    '';
  in {
    lib.${system}.mkDevvm = { extraModules ? [] }: mkDevvmPackage extraModules;

    packages.${system} = {
      devvm = mkDevvmPackage [];
      default = self.packages.${system}.devvm;
    };

    nixosConfigurations.devvm = mkDevvmSystem [];
  };
}
