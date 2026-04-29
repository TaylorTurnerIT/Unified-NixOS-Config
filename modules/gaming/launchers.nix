# modules/gaming/launchers.nix
# Game launchers beyond Steam.
# Heroic: Epic Games and GOG library access — primary non-Steam storefront tool
# Lutris: multi-source launcher with flexible Wine config — last resort when others fail
# Bottles: Wine prefix manager for standalone .exe files — not in standard module,
#          available as pkgs.bottles when a specific need arises
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    heroic  # Epic Games + GOG launcher — integrates Proton-GE, good Linux support
    lutris  # multi-source launcher — use when Steam and Heroic do not cover a title
  ];
}
