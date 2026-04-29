# modules/hardware/gpu/amd.nix
# AMD GPU driver, compute, Vulkan tuning, and monitoring tools.
# Applied to fiji (desktop) only via tags.amdGpu = true.
{ pkgs, ... }:
{
  # AMD GPU driver — amdgpu kernel module
  services.xserver.videoDrivers = [ "amdgpu" ];

  # OpenGL / Vulkan — 32-bit REQUIRED for Proton (32-bit Windows games)
  hardware.graphics = {
    enable      = true;
    enable32Bit = true;  # without this, large portion of game back-catalogue fails silently
    extraPackages = with pkgs; [
      amdvlk           # AMD Vulkan driver (alternative to RADV)
      rocmPackages.clr # ROCm compute runtime
    ];
    extraPackages32 = with pkgs; [
      driversi686Linux.amdvlk
    ];
  };

  # RADV (Mesa Vulkan) environment variable tuning
  environment.sessionVariables = {
    RADV_PERFTEST = "gpl";        # graphics pipeline library — reduces stutter
    AMD_VULKAN_ICD = "RADV";      # prefer RADV over amdvlk for gaming
  };

  environment.systemPackages = with pkgs; [
    lact       # Linux AMD GPU Control Application — fan curves, power limits, monitoring
               # GUI equivalent of AMD Adrenalin basic controls
    amdgpu_top # CLI GPU utilization monitor — like nvtop for AMD
  ];

  # lact daemon — must run as a service for fan control to work
  systemd.services.lactd = {
    description = "LACT AMD GPU Daemon";
    wantedBy    = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.lact}/bin/lact daemon";
      Restart   = "on-failure";
    };
  };
}
