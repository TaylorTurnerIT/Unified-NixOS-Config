# hosts/fiji-desktop/default.nix
# Desktop — MS-7A71 | i7-7700K | AMD RX 6700 XT | 32GB DDR4
# Three monitors: 1920x1080@60, 1920x1080@144, 2560x1440@180 HDR
# Tags drive module composition via lib/mkHost.nix — do not import modules directly here.
{ config, pkgs, lib, tags, ... }:
{
  networking.hostName = "fiji-desktop";

  # Use the Xanmod kernel for improved gaming performance
  boot.kernelPackages = pkgs.linuxPackages_xanmod;

  # ---------------------------------------------------------------------------
  # Bootloader & Core Filesystems (Impermanence Layout)
  # ---------------------------------------------------------------------------
  boot.loader.systemd-boot.enable      = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint     = "/boot/efi";

  fileSystems."/" = {
    device  = "none";
    fsType  = "tmpfs";
    options = [ "defaults" "size=2G" "mode=755" ];
  };
  fileSystems."/boot" = {
    device  = "/dev/disk/by-label/nixboot";
    fsType  = "ext4";
  };
  fileSystems."/boot/efi" = {
    device  = "/dev/disk/by-label/BOOT";
    fsType  = "vfat";
    options = [ "umask=0077" ];
  };
  fileSystems."/nix" = {
    device  = "/dev/disk/by-label/nixstore";
    fsType  = "btrfs";
    options = [ "compress=zstd" "noatime" ];
  };
  fileSystems."/persist" = {
    device        = "/dev/disk/by-label/persist";
    fsType        = "btrfs";
    options       = [ "compress=zstd" "noatime" ];
    neededForBoot = true;
  };

  # ---------------------------------------------------------------------------
  # Local user — Phase 1 only.
  # Phase 2: replaced by SSSD/FreeIPA enrollment. This account becomes break-glass.
  # ---------------------------------------------------------------------------
  users.users.taylor = {
    isNormalUser = true;
    description  = "Taylor";
    extraGroups  = [ "wheel" "networkmanager" "video" "audio" "gamemode" ];
    # Password set via passwd on first boot — not declared here (no hash in public repo)
  };

  # ---------------------------------------------------------------------------
  # Impermanence — root is tmpfs, only declared paths survive reboots
  # ---------------------------------------------------------------------------
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/lib/nixos"          # NixOS UID/GID state
      "/var/lib/bluetooth"      # paired Bluetooth devices
      "/var/log"                # logs across reboots
      "/var/lib/fprint"         # fingerprint enrollment (for when reader is sourced)
      # Phase 2 additions:
      # "/var/lib/sss"          # SSSD offline credential cache
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];
  };

  # ---------------------------------------------------------------------------
  # Secondary drive — 1.82TB HDD, local overflow scratch
  # Format to ext4 before first boot: mkfs.ext4 /dev/sdY
  # ---------------------------------------------------------------------------
  fileSystems."/mnt/overflow" = {
    device  = "/dev/disk/by-label/overflow"; # label the drive 'overflow' during format
    fsType  = "ext4";
    options = [ "defaults" "nofail" ];       # nofail: boot succeeds if drive absent
  };

  # ---------------------------------------------------------------------------
  # sops-nix — Phase 2. Uncomment when secrets are needed.
  # ---------------------------------------------------------------------------
  # sops.defaultSopsFile = ../../secrets/fiji-desktop.yaml;
  # sops.age.keyFile     = "/persist/etc/age/fiji-desktop.key";

  system.stateVersion = "25.05";
}