# home/taylor/sync.nix
# Nextcloud desktop sync client.
# Client is installed in Phase 1 but server URL is not configured until Phase 2.
# Game save directories will be declared here once the server is operational.
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    nextcloud-client  # Nextcloud desktop sync client
                      # Phase 2: configure with server URL nextcloud.internal.tongatime.us
                      # Phase 2: declare watched directories for game save sync in sync.nix
  ];

  # Phase 2: uncomment and configure
  # services.nextcloud-client = {
  #   enable     = true;
  #   startInBackground = true;
  # };
}
