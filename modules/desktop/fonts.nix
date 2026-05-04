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
      nerd-fonts.fira-code
      nerd-fonts.jetbrains-mono
    ];
    fontconfig.defaultFonts = {
      monospace = [ "FiraCode Nerd Font" ];
      sansSerif = [ "Noto Sans" ];
      serif     = [ "Noto Serif" ];
    };
  };
}
