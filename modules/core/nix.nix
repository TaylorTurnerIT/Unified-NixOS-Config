# modules/core/nix.nix
# Nix daemon settings — applied to every host.
# Enables flakes, configures GC, sets substituters, declares trusted users.
{ pkgs, ... }:
{
  nix = {
    package = pkgs.nixVersions.stable;

    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store   = true;
      trusted-users         = [ "root" "taylor" ];

      # Substituters — Phase 2: add attic cache (cache.internal.tongatime.us)
      substituters = [
        "https://cache.nixos.org"
        "https://nix-gaming.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
      ];
    };

    # Garbage collection — weekly, keep last 7 generations
    gc = {
      automatic = true;
      dates     = "weekly";
      options   = "--delete-older-than 7d";
    };
  };

  # Allow unfree packages — scoped per module, not global
  # Gaming module handles steam/nvidia allowUnfreePredicate separately
  nixpkgs.config.allowUnfree = false;
}
