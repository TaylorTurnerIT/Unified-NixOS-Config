# modules/desktop/fonts.nix
{ pkgs, ... }:
{
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      fira-code
      fira-code-symbols
      font-awesome
      (nerdfonts.override { fonts = [ "FiraCode" "JetBrainsMono" ]; })
    ];
    fontconfig.defaultFonts = {
      monospace = [ "FiraCode Nerd Font" ];
      sansSerif = [ "Noto Sans" ];
      serif     = [ "Noto Serif" ];
    };
  };
}
