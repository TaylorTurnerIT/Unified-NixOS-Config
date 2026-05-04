# home/taylor/browser.nix
{ pkgs, ... }:
{
  programs.firefox = {
    enable = true;
    
    profiles.taylor = {
      isDefault = true;
      settings = {
        # General UI & Behavior
        "browser.startup.page" = 3; # Restore previous session
        "general.autoScroll" = true; # Middle-click scrolling
        "media.videocontrols.picture-in-picture.video-toggle.enabled" = false;
        "signon.rememberSignons" = false; # Defer to your external password manager
        "browser.aboutConfig.showWarning" = false;

        # New Tab Page Decluttering
        "browser.newtabpage.enabled" = false;
        "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
        "browser.newtabpage.activity-stream.feeds.topsites" = false;
        "browser.newtabpage.activity-stream.showSponsoredCheckboxes" = false;
        "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;

        # Privacy, Anti-Tracking & Fingerprinting
        "browser.contentblocking.category" = "strict";
        "network.dns.disablePrefetch" = true;
        "network.prefetch-next" = false;
        "privacy.donottrackheader.enabled" = true;
        "privacy.fingerprintingProtection" = true;
        "privacy.globalprivacycontrol.enabled" = true;
        "privacy.query_stripping.enabled" = true;
        "privacy.query_stripping.enabled.pbmode" = true;
        "privacy.trackingprotection.enabled" = true;
        "privacy.trackingprotection.emailtracking.enabled" = true;
        "privacy.trackingprotection.socialtracking.enabled" = true;

        # Multi-Account Containers
        "privacy.userContext.enabled" = true;
        "privacy.userContext.ui.enabled" = true;

        # WebRTC IP Leak Protection
        "media.peerconnection.ice.default_address_only" = true;
        "media.peerconnection.ice.no_host" = true;
        "media.peerconnection.ice.proxy_only_if_behind_proxy" = true;

        # Hardware Acceleration & DRM
        "media.ffmpeg.vaapi.enabled" = true;
        "gfx.webrender.all" = true;
        "media.eme.enabled" = true;
      };
    };
  };
}