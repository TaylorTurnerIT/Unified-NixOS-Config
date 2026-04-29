# home/taylor/security.nix
# SSH client config, GPG, and biometric auth.
# SSH ProxyJump section is commented out until Phase 2 (Headscale + VMs operational).
{ pkgs, ... }:
{
  # SSH client config — declared via Home Manager, synced to both machines
  programs.ssh = {
    enable = true;

    # Global SSH defaults
    extraConfig = ''
      ServerAliveInterval 60
      ServerAliveCountMax 3
      AddKeysToAgent yes
    '';

    # Phase 2: uncomment when Headscale mesh and VMs are operational
    # matchBlocks = {
    #   "vm1" = {
    #     hostname     = "vm1.internal.tongatime.us";
    #     user         = "taylor";
    #     identityFile = "~/.ssh/id_ed25519";
    #   };
    #   "vm2" = {
    #     hostname   = "vm2.internal.tongatime.us";
    #     user       = "taylor";
    #     identityFile = "~/.ssh/id_ed25519";
    #     proxyJump  = "vm1";
    #   };
    #   "vm3" = {
    #     hostname   = "vm3.internal.tongatime.us";
    #     user       = "taylor";
    #     identityFile = "~/.ssh/id_ed25519";
    #     proxyJump  = "vm1";
    #   };
    #   "vm4" = {
    #     hostname   = "vm4.internal.tongatime.us";
    #     user       = "taylor";
    #     identityFile = "~/.ssh/id_ed25519";
    #     proxyJump  = "vm1";
    #   };
    #   "vps" = {
    #     hostname     = "hs.tongatime.us";
    #     user         = "taylor";
    #     identityFile = "~/.ssh/id_ed25519";
    #   };
    # };
  };

  # GPG — for commit signing if desired
  programs.gpg.enable = true;
  services.gpg-agent = {
    enable         = true;
    defaultCacheTtl = 3600;
    pinentryPackage = pkgs.pinentry-qt;  # KDE-native pinentry dialog
  };

  # fprintd — fingerprint enrollment
  # Enrollment done via: fprintd-enroll taylor && fprintd-verify taylor
  # Phase 1: laptop (tuvalu) has built-in reader — enroll immediately after install
  # Phase 1: desktop (fiji) — deferred until USB fingerprint reader is sourced
  home.packages = with pkgs; [
    fprintd  # fprintd-enroll, fprintd-verify CLI tools
  ];
}
