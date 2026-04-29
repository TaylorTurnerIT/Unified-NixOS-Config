# modules/laptop/wifi.nix
# WiFi configuration for tuvalu-laptop.
# NetworkManager handles connection management.
# iwlwifi power save level 2 — balances battery savings against latency spikes.
# Level 5 (maximum) causes noticeable latency spikes during remote work; level 2 does not.
{ pkgs, ... }:
{
  networking.networkmanager.enable = true;

  # iwlwifi power management — level 2 out of 5
  # Higher levels save more power but introduce latency spikes (breaks remote work feel)
  boot.extraModprobeConfig = ''
    options iwlwifi power_save=1
    options iwlmvm power_scheme=2
  '';

  environment.systemPackages = with pkgs; [
    networkmanager-openvpn  # VPN support in NetworkManager
  ];
}
