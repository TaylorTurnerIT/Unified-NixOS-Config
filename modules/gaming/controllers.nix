# modules/gaming/controllers.nix
# Controller support — udev rules for PS5 (DualSense), Xbox, and Switch Pro.
# hid-nintendo: Switch Pro and Joy-Con kernel driver
# xpadneo: improved Xbox controller driver (rumble, adaptive triggers)
{ pkgs, ... }:
{
  hardware.xpadneo.enable = true;       # Xbox controller driver (xpadneo)

  # Nintendo controller support
  services.udev.packages = with pkgs; [
    game-devices-udev-rules  # udev rules for PS4, PS5, Switch Pro, Steam Controller
  ];

  boot.extraModulePackages = with pkgs.linuxPackages; [
    hid-nintendo  # Switch Pro / Joy-Con kernel module
  ];
}
