# hosts/tuvalu/default.nix
# Laptop — ThinkPad T15 Gen1 (20S7S4CW06) | i7-10610U | Intel UHD | 32GB DDR4
# 1920x1080 @ 1.25x scaling, 16", 60Hz built-in
# Tags drive module composition via lib/mkHost.nix — do not import modules directly here.
{ config, pkgs, lib, tags, ... }:
{
  networking.hostName = "tuvalu";

  # ---------------------------------------------------------------------------
  # Local user — Phase 1 only.
  # Phase 2: replaced by SSSD/FreeIPA enrollment. This account becomes break-glass.
  # ---------------------------------------------------------------------------
  users.users.taylor = {
    isNormalUser = true;
    description  = "Taylor";
    extraGroups  = [ "wheel" "networkmanager" "video" "audio" ];
    # Password set via passwd on first boot
  };

  # ---------------------------------------------------------------------------
  # Impermanence — root is tmpfs, only declared paths survive reboots
  # ---------------------------------------------------------------------------
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/lib/nixos"
      "/var/lib/bluetooth"
      "/var/lib/fprint"         # fingerprint enrollment
      "/var/log"
      "/etc/NetworkManager/system-connections"  # saved WiFi networks
      # Phase 2 additions:
      # "/var/lib/sss"          # SSSD credential cache — mandatory for offline login
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];
  };

  # ---------------------------------------------------------------------------
  # sops-nix — Phase 2
  # ---------------------------------------------------------------------------
  # sops.defaultSopsFile = ../../secrets/tuvalu.yaml;
  # sops.age.keyFile     = "/persist/etc/age/tuvalu.key";

  system.stateVersion = "25.05";
}
