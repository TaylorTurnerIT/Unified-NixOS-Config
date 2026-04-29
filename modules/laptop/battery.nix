# modules/laptop/battery.nix
# Battery protection and low-battery behavior for tuvalu.
# Hibernate at 10% — protects against data loss during sessions with degraded battery.
# Applied to tuvalu only via tags.laptop = true.
{ pkgs, ... }:
{
  # UPower — battery monitoring daemon
  services.upower = {
    enable                   = true;
    criticalPowerAction      = "Hibernate"; # hibernate at critical level (not shutdown)
    percentageCritical       = 10;
    percentageLow            = 20;
    percentageAction         = 10;
  };

  # Hibernate requires either a swap partition or swap file
  # Declare swap here or in hardware.nix — size >= RAM (32GB)
  # swapDevices = [{ device = "/persist/swapfile"; size = 32768; }];

  environment.systemPackages = with pkgs; [
    upower  # upower CLI — inspect battery status: upower -i $(upower -e | grep battery)
  ];
}
