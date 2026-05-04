# modules/desktop/kde.nix
{ pkgs, ... }:
{
  services.displayManager.sddm = {
    enable         = true;
    wayland.enable = true;
  };

  services.desktopManager.plasma6.enable = true;

  services.pipewire = {
    enable            = true;
    alsa.enable       = true;
    alsa.support32Bit = true;
    pulse.enable      = true;
    jack.enable       = true;
    lowLatency.enable = true;
  };

  services.pulseaudio.enable = false;
  security.rtkit.enable      = true;
}
