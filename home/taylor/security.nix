# home/taylor/security.nix
{ pkgs, ... }:
{
  programs.ssh = {
    enable                = true;
    enableDefaultConfig   = false;
    matchBlocks."*" = {
      serverAliveInterval = 60;
      serverAliveCountMax = 3;
      addKeysToAgent      = "yes";
    };
    # Phase 2: add ProxyJump blocks for VMs
  };

  programs.gpg.enable = true;

  services.gpg-agent = {
    enable              = true;
    defaultCacheTtl     = 3600;
    pinentry.package    = pkgs.pinentry-qt;
  };

  home.packages = with pkgs; [ fprintd ];
}
