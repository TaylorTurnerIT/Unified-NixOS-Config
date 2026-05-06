# modules/core/security.nix
# Firewall, sudo, polkit, and host hardening — applied to every host.
# Default policy: deny inbound, allow outbound.
{ ... }:
{
  networking.firewall = {
    enable          = true;
    # Specific ports opened per-module (gaming, sunshine, etc.)
    # Never open ports here — open them in the module that needs them
    allowedTCPPorts = [];
    allowedUDPPorts = [];
  };

  # sudo — wheel group only, no password caching after session
  security.sudo = {
    enable         = true;
    wheelNeedsPassword = true;
  };

  # polkit — required for KDE authentication dialogs
  security.polkit.enable = true;

  # Kernel hardening
  boot.kernel.sysctl = {
    "kernel.dmesg_restrict"              = 1;
    "net.ipv4.tcp_syncookies"            = 1;
    "net.ipv6.conf.all.accept_redirects" = 0;
  };
}
