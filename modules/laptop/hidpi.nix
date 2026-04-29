# modules/laptop/hidpi.nix
# Display scaling for the 1920x1080 16" built-in panel on tuvalu.
# 1.25x scaling matches the Windows DPI setting (120 DPI effective).
# Applied to tuvalu only via tags.laptop = true.
{ ... }:
{
  # Wayland scaling — 1.25x for the built-in 1920x1080 16" panel
  # KDE/KWin picks this up automatically on Wayland
  environment.sessionVariables = {
    QT_SCALE_FACTOR    = "1.25";
    GDK_SCALE          = "1";          # GTK — fractional scaling via GDK_DPI_SCALE instead
    GDK_DPI_SCALE      = "1.25";
  };

  # KDE Plasma will set its own DPI per-display via KScreen
  # This env var provides a hint for apps that bypass KScreen
  services.xserver.dpi = 120;          # 96 * 1.25 = 120 DPI
}
