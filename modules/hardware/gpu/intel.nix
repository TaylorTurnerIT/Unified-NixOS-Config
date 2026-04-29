# modules/hardware/gpu/intel.nix
# Intel iGPU driver and VA-API hardware video decode.
# Applied to tuvalu-laptop-laptop (laptop) only via tags.intelGpu = true.
# i7-10610U uses iHD driver (intel-media-driver) — NOT the legacy i965 driver.
{ pkgs, ... }:
{
  # modesetting driver — preferred over legacy intel driver on modern kernels
  services.xserver.videoDrivers = [ "modesetting" ];

  hardware.graphics = {
    enable = true;
    # 32-bit NOT required — gaming disabled on laptop
    extraPackages = with pkgs; [
      intel-media-driver  # iHD — required for VA-API on 10th gen Intel (i7-10610U)
                          # Do NOT use i965-va-driver — wrong generation
      libva               # VA-API library
      libva-utils         # vainfo — verify VA-API is working
      intel-gpu-tools     # intel_gpu_top — GPU utilization CLI
    ];
  };

  # VA-API environment variables
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";   # explicit iHD selection
  };
}
