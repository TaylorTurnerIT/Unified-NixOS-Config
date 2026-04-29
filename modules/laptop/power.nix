# modules/laptop/power.nix
# Power management for tuvalu-laptop — battery life over performance.
# auto-cpufreq: dynamic CPU frequency scaling based on actual load, not just AC/battery state.
# Applied to tuvalu-laptop only via tags.laptop = true.
{ pkgs, ... }:
{
  # auto-cpufreq — smarter than TLP for dynamic workloads
  services.auto-cpufreq = {
    enable = true;
    settings = {
      battery = {
        governor         = "powersave";
        turbo            = "auto";       # allows turbo when genuinely needed
        energy_perf_pref = "power";
        scaling_max_freq = 2300000;      # cap at base clock on battery (2.3GHz i7-10610U)
      };
      charger = {
        governor         = "performance";
        turbo            = "auto";
        energy_perf_pref = "performance";
      };
    };
  };

  # Suspend and lid behavior
  services.logind = {
    lidSwitch             = "suspend";
    lidSwitchExternalPower = "ignore";   # lid close while charging: do nothing
    extraConfig = ''
      IdleAction=suspend
      IdleActionSec=5min
      HandlePowerKey=suspend
    '';
  };

  # Power button: suspend rather than shutdown
  powerManagement.enable = true;
}
