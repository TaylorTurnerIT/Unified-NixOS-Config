# home/taylor/default.nix
# Home Manager entrypoint for taylor — imports all user config files.
# NO hardware conditionals here. Hardware divergence lives in modules/ only.
# Everything here is identical on fiji and tuvalu.
{ pkgs, lib, inputs, tags, ... }:
{
  imports = [
    ./shell.nix
    ./terminal.nix
    ./dev.nix
    ./security.nix
    ./sync.nix
  ]
  # streaming.nix — laptop only (Moonlight client)
  ++ lib.optional tags.laptop ./streaming.nix;

  home.username      = "taylor";
  home.homeDirectory = "/home/taylor";

  # Let Home Manager manage itself
  programs.home-manager.enable = true;

  # XDG directories
  xdg.enable = true;

  home.stateVersion = "25.05";
}
