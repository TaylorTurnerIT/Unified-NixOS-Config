# hosts/tuvalu-laptop/default.nix
{ config, pkgs, lib, tags, ... }:
{
  networking.hostName = "tuvalu-laptop";

  # Bootloader
  boot.loader.systemd-boot.enable      = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint     = "/boot/efi";

  # Filesystems
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

  swapDevices = [];

  # Local user — Phase 1 only. Becomes break-glass in Phase 2.
  users.users.taylor = {
    isNormalUser = true;
    description  = "Taylor";
    extraGroups  = [ "wheel" "networkmanager" "video" "audio" ];
  };

  # Impermanence
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/lib/nixos"
      "/var/lib/bluetooth"
      "/var/lib/fprint"
      "/var/log"
      "/etc/NetworkManager/system-connections"
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];
  };

  system.stateVersion = "25.05";
}
