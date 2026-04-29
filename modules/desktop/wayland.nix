# modules/desktop/wayland.nix
# Wayland environment variables and KWin flags.
# Applied to all graphical hosts. HDR flags applied separately via hdr.nix (fiji-desktop only).
{ ... }:
{
  environment.sessionVariables = {
    # Force Wayland for Qt and Electron apps
    QT_QPA_PLATFORM         = "wayland";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    GDK_BACKEND             = "wayland";
    CLUTTER_BACKEND         = "wayland";
    SDL_VIDEODRIVER         = "wayland";
    # Ozone platform for Chromium-based apps (e.g. VS Code)
    NIXOS_OZONE_WL          = "1";
    # XDG runtime directory
    XDG_SESSION_TYPE        = "wayland";
    XDG_CURRENT_DESKTOP     = "KDE";
  };

  # XDG portal — required for screen sharing, file pickers on Wayland
  xdg.portal = {
    enable = true;
    extraPortals = [];  # KDE plasma provides its own portal
  };
}
