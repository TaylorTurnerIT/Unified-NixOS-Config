# modules/desktop/kde.nix
# KDE Plasma 6 on Wayland with SDDM — all graphical hosts.
{ pkgs, ... }:
{
  # SDDM display manager
  services.displayManager.sddm = {
    enable  = true;
    wayland.enable = true;
  };

  # KDE Plasma 6
  services.desktopManager.plasma6.enable = true;

  # PipeWire audio — replaces PulseAudio
  services.pipewire = {
    enable            = true;
    alsa.enable       = true;
    alsa.support32Bit = true;  # required for 32-bit game audio via Proton
    pulse.enable      = true;  # PulseAudio compatibility layer
    jack.enable       = true;
  };
  # Disable PulseAudio — conflicts with PipeWire
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;  # real-time scheduling for PipeWire
}
