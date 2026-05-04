# modules/core/ssh.nix
# OpenSSH server hardening — applied to every host.
# Rules: Ed25519 keys only, no root login, no password auth.
{ ... }:
{
  services.openssh = {
    enable = true;
    hostKeys = [
      {
        path = "/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
    settings = {
      PermitRootLogin                = "no";
      PasswordAuthentication         = false;
      KbdInteractiveAuthentication   = false;
      PubkeyAuthentication           = true;
    };
  };
}
