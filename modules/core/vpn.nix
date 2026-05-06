{ pkgs, ... }:
{
  # Enable the Tailscale client daemon
  services.tailscale.enable = true;

  # Tailscale requires loose reverse path filtering to route traffic correctly
  # Your current security.nix sets this to 1 (strict), which will block Tailscale traffic
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.rp_filter" = 2;
    "net.ipv4.conf.default.rp_filter" = 2;
  };

  # Open the default Tailscale port
  networking.firewall.allowedUDPPorts = [ 41641 ];
}
