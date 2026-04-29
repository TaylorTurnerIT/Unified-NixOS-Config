# modules/gaming/tools.nix
# Gaming performance and overlay tools.
# gamemode and gamescope require specific system permissions — must use module options,
# not just systemPackages.
{ pkgs, ... }:
{
  # gamemode — requests high-performance CPU governor and GPU settings during gaming
  # Usage: gamemoderun %command% in Steam launch options
  programs.gamemode = {
    enable = true;
    settings = {
      general = {
        renice      = 10;
        ioprio      = 0;
        softrealtime = "auto";
      };
      gpu = {
        apply_gpu_optimisations = "accept-responsibility";
        gpu_device              = 0;
        amd_performance_level   = "high";  # RX 6700 XT performance mode
      };
    };
  };

  # gamescope — Valve's micro-compositor for upscaling, frame limiting, HDR
  programs.gamescope.enable = true;

  environment.systemPackages = with pkgs; [
    mangohud    # GPU/CPU/FPS overlay — add MANGOHUD=1 to Steam launch options
    goverlay    # GUI editor for MangoHUD config — avoids hand-editing MangoHUD.conf
    steam-run   # FHS chroot for native Linux binaries that expect standard library paths
                # Usage: steam-run <binary> when a Linux native game fails to launch
  ];
}
