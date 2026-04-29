# home/taylor/streaming.nix
# Moonlight game streaming client — tuvalu (laptop) only.
# Gated on tags.laptop = true in home/taylor/default.nix.
# Streams from fiji (desktop) running Sunshine over the Headscale mesh.
# Apollo/Artemis monitored as future replacement (FC-004) — see docs/DECISIONS.md.
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    moonlight-qt  # Moonlight game streaming client — connects to Sunshine on fiji
                  # Phase 2: configure with fiji's Headscale peer IP
                  # Works from anywhere via Headscale mesh (not just local network)
  ];
}
