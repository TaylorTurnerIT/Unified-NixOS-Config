# modules/gaming/proton.nix
# Proton-GE via the nix-gaming flake — declarative, version-pinned, no runtime downloads.
# Do NOT use ProtonUp-Qt — it is the imperative alternative and conflicts with this approach.
{ inputs, pkgs, ... }:
{
  # STEAM_EXTRA_COMPAT_TOOLS_PATHS — tells Steam where to find Proton-GE
  environment.sessionVariables = {
    STEAM_EXTRA_COMPAT_TOOLS_PATHS = "$HOME/.steam/root/compatibilitytools.d";
  };

  environment.systemPackages = [
    # Proton-GE from the nix-gaming flake — select from available versions
    inputs.nix-gaming.packages.${pkgs.system}.proton-ge
  ];
}
