# modules/desktop/fonts.nix
# System fonts — all graphical hosts.
{ pkgs, ... }:
{
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts            # broad Unicode coverage
      noto-fonts-cjk-sans   # CJK character support
      noto-fonts-emoji      # emoji
      fira-code             # monospace with ligatures (terminal)
      fira-code-symbols
      font-awesome          # icons used by Starship and eza
      (nerdfonts.override { fonts = [ "FiraCode" "JetBrainsMono" ]; })
    ];
    fontconfig = {
      defaultFonts = {
        monospace = [ "FiraCode Nerd Font" ];
        sansSerif  = [ "Noto Sans" ];
        serif      = [ "Noto Serif" ];
      };
    };
  };
}
