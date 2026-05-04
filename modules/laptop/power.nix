# modules/laptop/power.nix
{ pkgs, ... }:
{
  services.auto-cpufreq = {
    enable = true;
    settings = {
      battery = {
        governor         = "powersave";
        turbo            = "auto";
        energy_perf_pref = "power";
        scaling_max_freq = 2300000;
      };
      charger = {
        governor         = "performance";
        turbo            = "auto";
        energy_perf_pref = "performance";
      };
    };
  };

  services.power-profiles-daemon.enable = false;

  services.logind.settings.Login = {
    HandleLidSwitch             = "suspend";
    HandleLidSwitchExternalPower = "ignore";
    IdleAction                  = "suspend";
    IdleActionSec               = "5min";
    HandlePowerKey              = "suspend";
  };

  powerManagement.enable = true;
}
