# modules/laptop/power.nix
# Power management for tuvalu (laptop) — battery life over performance.
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

  # Disable power-profiles-daemon — conflicts with auto-cpufreq
  services.power-profiles-daemon.enable = false;

  services.logind = {
    lidSwitch              = "suspend";
    lidSwitchExternalPower = "ignore";
    settings.Login = {
      IdleAction    = "suspend";
      IdleActionSec = "5min";
      HandlePowerKey = "suspend";
    };
  };

  powerManagement.enable = true;
}
