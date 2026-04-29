# modules/gaming/steam.nix
# Steam via the NixOS module (not as a plain package — the module sets up
# the FHS chroot, controller support, and 32-bit library wiring).
# Applied to fiji-desktop (desktop) only via tags.gaming = true.
{ pkgs, ... }:
{
  # allowUnfreePredicate — scoped to Steam only, not a blanket allowUnfree = true
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (pkgs.lib.getName pkg) [
      "steam"
      "steam-unwrapped"
    ];

  programs.steam = {
    enable = true;

    # Open firewall ports for Steam Remote Play (deny-by-default firewall in core/security.nix)
    remotePlay.openFirewall      = true;

    # Open firewall ports for Source engine dedicated server (local testing before VM4)
    dedicatedServer.openFirewall = true;

    # Gamescope — micro-compositor for upscaling, VRR, frame limiting
    # Useful for games that misbehave with HDR or multi-monitor setups
    gamescopeSession.enable = true;

    # steam-run — FHS chroot for native Linux binaries that expect /lib, /usr/lib
    # Use: steam-run <binary> when a native Linux game refuses to launch on NixOS
    package = pkgs.steam.override {
      extraLibraries = pkgs: with pkgs; [];
    };
  };
}
