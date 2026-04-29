#!/usr/bin/env bash
# bootstrap.sh — scaffold the nixos-config monorepo
# Run from the directory where you want the repo created:
#   chmod +x bootstrap.sh && ./bootstrap.sh
# Creates: ./nixos-config/ with full directory structure and placeholder files

set -euo pipefail

# ---------------------------------------------------------------------------
# Directories
# ---------------------------------------------------------------------------

dirs=(
  # Hosts
  "hosts/fiji"
  "hosts/tuvalu"
  "hosts/vm1"
  "hosts/vm2"
  "hosts/vm3"
  "hosts/vm4"
  "hosts/oracle-vps"

  # Core modules — applied to every host
  "modules/core"

  # Desktop environment
  "modules/desktop"

  # Hardware profiles
  "modules/hardware/gpu"
  "modules/hardware/displays"
  "modules/hardware/peripherals"

  # Gaming — desktop only, gated on tags.gaming
  "modules/gaming"

  # Laptop-specific
  "modules/laptop"

  # Work / dev tools
  "modules/work"

  # Home Manager — taylor's user config
  "home/taylor/kde"

  # Library helpers
  "lib"

  # OpenTofu IaC
  "tofu/dns"
  "tofu/identity"
  "tofu/authentik"
  "tofu/headscale"

  # sops-nix secrets
  "secrets"

  # Documentation
  "docs/architecture"
)

for d in "${dirs[@]}"; do
  mkdir -p "$d"
done

echo "  Directories created."

# ---------------------------------------------------------------------------
# Helper — write a placeholder file with a header comment
# ---------------------------------------------------------------------------

placeholder() {
  local path="$1"
  local description="$2"
  local ext="${path##*.}"

  if [[ "$ext" == "nix" ]]; then
    cat > "$path" << EOF
# ${path}
# ${description}
# PLACEHOLDER — implement in Phase 1 / Phase 2 as noted
{ ... }:
{
}
EOF

  elif [[ "$ext" == "tf" || "$ext" == "tfvars" ]]; then
    cat > "$path" << EOF
# ${path}
# ${description}
# PLACEHOLDER — implement in Phase 2
EOF

  elif [[ "$ext" == "yaml" || "$ext" == "yml" ]]; then
    cat > "$path" << EOF
# ${path}
# ${description}
# PLACEHOLDER
EOF

  elif [[ "$ext" == "md" ]]; then
    cat > "$path" << EOF
# ${path##*/}

> ${description}
> PLACEHOLDER — fill in during implementation.
EOF

  elif [[ "$ext" == "json" ]]; then
    cat > "$path" << EOF
{
  "_comment": "${description} — PLACEHOLDER"
}
EOF

  else
    echo "# ${path} — ${description} — PLACEHOLDER" > "$path"
  fi
}

# ---------------------------------------------------------------------------
# Root files
# ---------------------------------------------------------------------------

cat > "flake.nix" << 'EOF'
# flake.nix — monorepo entrypoint
# All inputs declared here. Never add inputs without updating docs/FLAKE_INPUTS.md.
{
  description = "tongatime.us NixOS infrastructure monorepo";

  inputs = {
    # Primary package set — nixos-unstable for recent Mesa, KDE 6, hardware support
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # User environment management — runs as NixOS module, not standalone
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets management — decrypts at activation, never in Nix store
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Ephemeral root — tmpfs / with explicit persistence declarations
    impermanence.url = "github:nix-community/impermanence";

    # Hardware-specific modules — ThinkPad T15 Gen1 (tuvalu) imports from here
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # Proton-GE as a declarative Nix derivation — desktop (fiji) only
    nix-gaming = {
      url = "github:fufexan/nix-gaming";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # DEFERRED to Phase 2:
    # deploy-rs   — remote deployment with rollback
    # attic       — self-hosted Nix binary cache
  };

  outputs = { self, nixpkgs, home-manager, sops-nix, impermanence, nixos-hardware, nix-gaming, ... }@inputs:
  let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    lib = nixpkgs.lib;
    mkHost = import ./lib/mkHost.nix { inherit lib inputs; };
  in
  {
    nixosConfigurations = {

      # Desktop — MS-7A71, i7-7700K, RX 6700 XT, 3 monitors
      fiji = mkHost {
        hostname = "fiji";
        system = system;
        tags = {
          laptop       = false;
          gaming       = true;
          amdGpu       = true;
          intelGpu     = false;
          multiMonitor = true;
          hdr          = true;
        };
      };

      # Laptop — ThinkPad T15 Gen1, i7-10610U, Intel UHD, 32GB
      tuvalu = mkHost {
        hostname = "tuvalu";
        system = system;
        tags = {
          laptop       = true;
          gaming       = false;
          amdGpu       = false;
          intelGpu     = true;
          multiMonitor = false;
          hdr          = false;
        };
      };

      # Homelab VMs — DEFERRED to Phase 2
      # vm1 = mkHost { ... };
      # vm2 = mkHost { ... };
      # vm3 = mkHost { ... };
      # vm4 = mkHost { ... };

    };
  };
}
EOF

placeholder "flake.lock" "Generated by nix flake update — do not edit manually"

cat > "renovate.json" << 'EOF'
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "description": "Renovate Bot — automated dependency update PRs with changelogs",
  "extends": ["config:base"],
  "nix": {
    "enabled": true
  },
  "packageRules": [
    {
      "description": "Automerge patch-level container digest bumps with passing CI",
      "matchUpdateTypes": ["digest"],
      "automerge": true,
      "automergeType": "pr"
    },
    {
      "description": "Minor and major updates always require manual review",
      "matchUpdateTypes": ["minor", "major"],
      "automerge": false
    }
  ],
  "prConcurrentLimit": 5,
  "labels": ["renovate", "dependencies"]
}
EOF

cat > ".gitignore" << 'EOF'
# Nix
result
result-*
.direnv/

# OpenTofu — state never in repo (uses MinIO remote backend)
*.tfstate
*.tfstate.*
.terraform/
.terraform.lock.hcl
terraform.tfvars

# sops — plaintext secrets never in repo
secrets/*.dec

# Editor
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db
EOF

cat > "CLAUDE.md" << 'EOF'
# CLAUDE.md — Monorepo Context for Claude Code

> Read docs/CLAUDE.md for the full context document.
> This file is the monorepo root pointer — Claude Code reads it at session start.

See: docs/CLAUDE.md
See: docs/PROJECT_RULES.md
See: docs/DECISIONS.md
See: docs/BOOTSTRAP_SEQUENCE.md
See: docs/PORT_REFERENCE.md
See: docs/FLAKE_INPUTS.md
See: docs/ACTION_PLAN.md

## Quick Reference

Hostnames: fiji (desktop), tuvalu (laptop)
Domain: tongatime.us | Internal: internal.tongatime.us | Realm: TONGATIME.US
Phase: 1 — Personal machines only. Server deferred to Phase 2.

Never commit: tfstate, plaintext secrets, flake.lock edits, direct pushes to main.
EOF

echo "  Root files created."

# ---------------------------------------------------------------------------
# lib/
# ---------------------------------------------------------------------------

cat > "lib/mkHost.nix" << 'EOF'
# lib/mkHost.nix
# Host builder — reads tags attribute set and composes the correct module set.
# Each host declares only its tags. No direct module imports in host configs.
# See docs/CLAUDE.md for the full tag -> module mapping table.
{ lib, inputs }:

{ hostname, system, tags }:

let
  nixpkgs = inputs.nixpkgs;
  home-manager = inputs.home-manager;
  sops-nix = inputs.sops-nix;
  impermanence = inputs.impermanence;
  nixos-hardware = inputs.nixos-hardware;
  nix-gaming = inputs.nix-gaming;

  # Core modules — always applied, no exceptions
  coreModules = [
    ./modules/core/nix.nix
    ./modules/core/locale.nix
    ./modules/core/security.nix
    ./modules/core/ssh.nix
    # ssh-recording.nix — DEFERRED to Phase 2 (requires tlog + SSSD)
  ];

  # Desktop environment — all graphical hosts
  desktopModules = [
    ./modules/desktop/kde.nix
    ./modules/desktop/wayland.nix
    ./modules/desktop/fonts.nix
  ];

  # GPU modules — selected by tag
  gpuModules =
    lib.optional tags.amdGpu   ./modules/hardware/gpu/amd.nix ++
    lib.optional tags.intelGpu ./modules/hardware/gpu/intel.nix;

  # Display modules
  displayModules =
    lib.optional tags.hdr ./modules/hardware/displays/hdr.nix;

  # Gaming modules — desktop only
  gamingModules = lib.optionals tags.gaming [
    ./modules/gaming/steam.nix
    ./modules/gaming/proton.nix
    ./modules/gaming/tools.nix
    ./modules/gaming/launchers.nix
    ./modules/gaming/controllers.nix
  ];

  # Laptop modules
  laptopModules = lib.optionals tags.laptop [
    ./modules/laptop/power.nix
    ./modules/laptop/hidpi.nix
    ./modules/laptop/wifi.nix
    ./modules/laptop/battery.nix
  ];

  # nixos-hardware — laptop only, exact module verified at install time
  hardwareModules = lib.optionals tags.laptop [
    # TODO AI-035: verify exact module name for ThinkPad T15 Gen1
    # nixos-hardware.nixosModules.lenovo-thinkpad-t14s
  ];

  # nix-gaming flake modules — desktop only
  nixGamingModules = lib.optionals tags.gaming [
    nix-gaming.nixosModules.default
  ];

in
nixpkgs.lib.nixosSystem {
  inherit system;
  modules = coreModules
    ++ desktopModules
    ++ gpuModules
    ++ displayModules
    ++ gamingModules
    ++ laptopModules
    ++ hardwareModules
    ++ nixGamingModules
    ++ [
      # Host-specific config
      ./hosts/${hostname}/default.nix
      ./hosts/${hostname}/hardware.nix

      # Home Manager as NixOS module — applies system + user config in one switch
      home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.taylor = import ./home/taylor/default.nix;
        home-manager.extraSpecialArgs = { inherit inputs tags; };
      }

      # sops-nix secrets
      sops-nix.nixosModules.sops

      # Impermanence
      impermanence.nixosModules.impermanence
    ];
  specialArgs = { inherit inputs tags hostname; };
}
EOF

echo "  lib/ created."

# ---------------------------------------------------------------------------
# hosts/fiji/ (desktop)
# ---------------------------------------------------------------------------

cat > "hosts/fiji/default.nix" << 'EOF'
# hosts/fiji/default.nix
# Desktop — MS-7A71 | i7-7700K | AMD RX 6700 XT | 32GB DDR4
# Three monitors: 1920x1080@60, 1920x1080@144, 2560x1440@180 HDR
# Tags drive module composition via lib/mkHost.nix — do not import modules directly here.
{ config, pkgs, lib, tags, ... }:
{
  networking.hostName = "fiji";

  # ---------------------------------------------------------------------------
  # Local user — Phase 1 only.
  # Phase 2: replaced by SSSD/FreeIPA enrollment. This account becomes break-glass.
  # ---------------------------------------------------------------------------
  users.users.taylor = {
    isNormalUser = true;
    description  = "Taylor";
    extraGroups  = [ "wheel" "networkmanager" "video" "audio" "gamemode" ];
    # Password set via passwd on first boot — not declared here (no hash in public repo)
  };

  # ---------------------------------------------------------------------------
  # Impermanence — root is tmpfs, only declared paths survive reboots
  # ---------------------------------------------------------------------------
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/lib/nixos"          # NixOS UID/GID state
      "/var/lib/bluetooth"      # paired Bluetooth devices
      "/var/log"                # logs across reboots
      "/var/lib/fprint"         # fingerprint enrollment (for when reader is sourced)
      # Phase 2 additions:
      # "/var/lib/sss"          # SSSD offline credential cache
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];
  };

  # ---------------------------------------------------------------------------
  # Secondary drive — 1.82TB HDD, local overflow scratch
  # Format to ext4 before first boot: mkfs.ext4 /dev/sdY
  # ---------------------------------------------------------------------------
  fileSystems."/mnt/overflow" = {
    device  = "/dev/disk/by-label/overflow"; # label the drive 'overflow' during format
    fsType  = "ext4";
    options = [ "defaults" "nofail" ];       # nofail: boot succeeds if drive absent
  };

  # ---------------------------------------------------------------------------
  # sops-nix — Phase 2. Uncomment when secrets are needed.
  # ---------------------------------------------------------------------------
  # sops.defaultSopsFile = ../../secrets/fiji.yaml;
  # sops.age.keyFile     = "/persist/etc/age/fiji.key";

  system.stateVersion = "25.05";
}
EOF

placeholder "hosts/fiji/hardware.nix" "Generated by nixos-generate-config at install time — replace placeholder with real output"

echo "  hosts/fiji/ created."

# ---------------------------------------------------------------------------
# hosts/tuvalu/ (laptop)
# ---------------------------------------------------------------------------

cat > "hosts/tuvalu/default.nix" << 'EOF'
# hosts/tuvalu/default.nix
# Laptop — ThinkPad T15 Gen1 (20S7S4CW06) | i7-10610U | Intel UHD | 32GB DDR4
# 1920x1080 @ 1.25x scaling, 16", 60Hz built-in
# Tags drive module composition via lib/mkHost.nix — do not import modules directly here.
{ config, pkgs, lib, tags, ... }:
{
  networking.hostName = "tuvalu";

  # ---------------------------------------------------------------------------
  # Local user — Phase 1 only.
  # Phase 2: replaced by SSSD/FreeIPA enrollment. This account becomes break-glass.
  # ---------------------------------------------------------------------------
  users.users.taylor = {
    isNormalUser = true;
    description  = "Taylor";
    extraGroups  = [ "wheel" "networkmanager" "video" "audio" ];
    # Password set via passwd on first boot
  };

  # ---------------------------------------------------------------------------
  # Impermanence — root is tmpfs, only declared paths survive reboots
  # ---------------------------------------------------------------------------
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/lib/nixos"
      "/var/lib/bluetooth"
      "/var/lib/fprint"         # fingerprint enrollment
      "/var/log"
      "/etc/NetworkManager/system-connections"  # saved WiFi networks
      # Phase 2 additions:
      # "/var/lib/sss"          # SSSD credential cache — mandatory for offline login
    ];
    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];
  };

  # ---------------------------------------------------------------------------
  # sops-nix — Phase 2
  # ---------------------------------------------------------------------------
  # sops.defaultSopsFile = ../../secrets/tuvalu.yaml;
  # sops.age.keyFile     = "/persist/etc/age/tuvalu.key";

  system.stateVersion = "25.05";
}
EOF

placeholder "hosts/tuvalu/hardware.nix" "Generated by nixos-generate-config at install time — replace placeholder with real output. Also imports nixos-hardware ThinkPad module (AI-035: verify exact module name)"

echo "  hosts/tuvalu/ created."

# ---------------------------------------------------------------------------
# hosts/ — VM and VPS placeholders (Phase 2)
# ---------------------------------------------------------------------------

for host in vm1 vm2 vm3 vm4 oracle-vps; do
  placeholder "hosts/${host}/default.nix" "${host} — DEFERRED to Phase 2"
  placeholder "hosts/${host}/hardware.nix" "${host} hardware — DEFERRED to Phase 2"
done

echo "  hosts/vm*/ and hosts/oracle-vps/ placeholders created."

# ---------------------------------------------------------------------------
# modules/core/
# ---------------------------------------------------------------------------

cat > "modules/core/nix.nix" << 'EOF'
# modules/core/nix.nix
# Nix daemon settings — applied to every host.
# Enables flakes, configures GC, sets substituters, declares trusted users.
{ pkgs, ... }:
{
  nix = {
    package = pkgs.nixVersions.stable;

    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store   = true;
      trusted-users         = [ "root" "taylor" ];

      # Substituters — Phase 2: add attic cache (cache.internal.tongatime.us)
      substituters = [
        "https://cache.nixos.org"
        "https://nix-gaming.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-gaming.cachix.org-1:nbjlureqMbRAxR1gJ/f3hxemL9svXaZF/Ees8vCUUs4="
      ];
    };

    # Garbage collection — weekly, keep last 7 generations
    gc = {
      automatic = true;
      dates     = "weekly";
      options   = "--delete-older-than 7d";
    };
  };

  # Allow unfree packages — scoped per module, not global
  # Gaming module handles steam/nvidia allowUnfreePredicate separately
  nixpkgs.config.allowUnfree = false;
}
EOF

cat > "modules/core/locale.nix" << 'EOF'
# modules/core/locale.nix
# Timezone and locale — applied to every host.
{ ... }:
{
  time.timeZone = "America/Chicago";

  i18n = {
    defaultLocale  = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS        = "en_US.UTF-8";
      LC_IDENTIFICATION = "en_US.UTF-8";
      LC_MEASUREMENT    = "en_US.UTF-8";
      LC_MONETARY       = "en_US.UTF-8";
      LC_NAME           = "en_US.UTF-8";
      LC_NUMERIC        = "en_US.UTF-8";
      LC_PAPER          = "en_US.UTF-8";
      LC_TELEPHONE      = "en_US.UTF-8";
      LC_TIME           = "en_US.UTF-8";
    };
  };
}
EOF

cat > "modules/core/security.nix" << 'EOF'
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
    "net.ipv4.conf.all.rp_filter"        = 1;
    "net.ipv4.conf.default.rp_filter"    = 1;
    "net.ipv4.tcp_syncookies"            = 1;
    "net.ipv6.conf.all.accept_redirects" = 0;
  };
}
EOF

cat > "modules/core/ssh.nix" << 'EOF'
# modules/core/ssh.nix
# OpenSSH server hardening — applied to every host.
# Rules: Ed25519 keys only, no root login, no password auth.
{ ... }:
{
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin            = "no";
      PasswordAuthentication     = false;
      KbdInteractiveAuthentication = false;
      PubkeyAuthentication       = true;
      # Ed25519 host keys only — RSA disabled
      HostKey                    = [ "/etc/ssh/ssh_host_ed25519_key" ];
    };
  };
}
EOF

placeholder "modules/core/ssh-recording.nix" "tlog session recording via SSSD — DEFERRED to Phase 2 (requires SSSD enrollment)"

echo "  modules/core/ created."

# ---------------------------------------------------------------------------
# modules/desktop/
# ---------------------------------------------------------------------------

cat > "modules/desktop/kde.nix" << 'EOF'
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
EOF

cat > "modules/desktop/wayland.nix" << 'EOF'
# modules/desktop/wayland.nix
# Wayland environment variables and KWin flags.
# Applied to all graphical hosts. HDR flags applied separately via hdr.nix (fiji only).
{ ... }:
{
  environment.sessionVariables = {
    # Force Wayland for Qt and Electron apps
    QT_QPA_PLATFORM         = "wayland";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    GDK_BACKEND             = "wayland";
    CLUTTER_BACKEND         = "wayland";
    SDL_VIDEODRIVER         = "wayland";
    # Ozone platform for Chromium-based apps (e.g. VS Code)
    NIXOS_OZONE_WL          = "1";
    # XDG runtime directory
    XDG_SESSION_TYPE        = "wayland";
    XDG_CURRENT_DESKTOP     = "KDE";
  };

  # XDG portal — required for screen sharing, file pickers on Wayland
  xdg.portal = {
    enable = true;
    extraPortals = [];  # KDE plasma provides its own portal
  };
}
EOF

cat > "modules/desktop/fonts.nix" << 'EOF'
# modules/desktop/fonts.nix
# System fonts — all graphical hosts.
{ pkgs, ... }:
{
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts            # broad Unicode coverage
      noto-fonts-cjk-sans   # CJK character support
      noto-fonts-emoji      # emoji
      fira-code             # monospace with ligatures (terminal)
      fira-code-symbols
      font-awesome          # icons used by Starship and eza
      (nerdfonts.override { fonts = [ "FiraCode" "JetBrainsMono" ]; })
    ];
    fontconfig = {
      defaultFonts = {
        monospace = [ "FiraCode Nerd Font" ];
        sansSerif  = [ "Noto Sans" ];
        serif      = [ "Noto Serif" ];
      };
    };
  };
}
EOF

echo "  modules/desktop/ created."

# ---------------------------------------------------------------------------
# modules/hardware/
# ---------------------------------------------------------------------------

cat > "modules/hardware/gpu/amd.nix" << 'EOF'
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
EOF

cat > "modules/hardware/gpu/intel.nix" << 'EOF'
# modules/hardware/gpu/intel.nix
# Intel iGPU driver and VA-API hardware video decode.
# Applied to tuvalu (laptop) only via tags.intelGpu = true.
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
EOF

placeholder "modules/hardware/displays/hdr.nix" "KWin HDR flags for the 2560x1440 180Hz display — fiji only via tags.hdr"

placeholder "modules/hardware/peripherals/audio.nix" "PipeWire / WirePlumber low-latency profile — declared in kde.nix for now, split here if needed"

echo "  modules/hardware/ created."

# ---------------------------------------------------------------------------
# modules/gaming/
# ---------------------------------------------------------------------------

cat > "modules/gaming/steam.nix" << 'EOF'
# modules/gaming/steam.nix
# Steam via the NixOS module (not as a plain package — the module sets up
# the FHS chroot, controller support, and 32-bit library wiring).
# Applied to fiji (desktop) only via tags.gaming = true.
{ pkgs, ... }:
{
  # allowUnfreePredicate — scoped to Steam only, not a blanket allowUnfree = true
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (pkgs.lib.getName pkg) [
      "steam"
      "steam-unwrapped"
    ];

  programs.steam = {
    enable = true;

    # Open firewall ports for Steam Remote Play (deny-by-default firewall in core/security.nix)
    remotePlay.openFirewall      = true;

    # Open firewall ports for Source engine dedicated server (local testing before VM4)
    dedicatedServer.openFirewall = true;

    # Gamescope — micro-compositor for upscaling, VRR, frame limiting
    # Useful for games that misbehave with HDR or multi-monitor setups
    gamescopeSession.enable = true;

    # steam-run — FHS chroot for native Linux binaries that expect /lib, /usr/lib
    # Use: steam-run <binary> when a native Linux game refuses to launch on NixOS
    package = pkgs.steam.override {
      extraLibraries = pkgs: with pkgs; [];
    };
  };
}
EOF

cat > "modules/gaming/proton.nix" << 'EOF'
# modules/gaming/proton.nix
# Proton-GE via the nix-gaming flake — declarative, version-pinned, no runtime downloads.
# Do NOT use ProtonUp-Qt — it is the imperative alternative and conflicts with this approach.
{ inputs, pkgs, ... }:
{
  # STEAM_EXTRA_COMPAT_TOOLS_PATHS — tells Steam where to find Proton-GE
  environment.sessionVariables = {
    STEAM_EXTRA_COMPAT_TOOLS_PATHS = "$HOME/.steam/root/compatibilitytools.d";
  };

  environment.systemPackages = [
    # Proton-GE from the nix-gaming flake — select from available versions
    inputs.nix-gaming.packages.${pkgs.system}.proton-ge
  ];
}
EOF

cat > "modules/gaming/tools.nix" << 'EOF'
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
EOF

cat > "modules/gaming/launchers.nix" << 'EOF'
# modules/gaming/launchers.nix
# Game launchers beyond Steam.
# Heroic: Epic Games and GOG library access — primary non-Steam storefront tool
# Lutris: multi-source launcher with flexible Wine config — last resort when others fail
# Bottles: Wine prefix manager for standalone .exe files — not in standard module,
#          available as pkgs.bottles when a specific need arises
{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    heroic  # Epic Games + GOG launcher — integrates Proton-GE, good Linux support
    lutris  # multi-source launcher — use when Steam and Heroic do not cover a title
  ];
}
EOF

cat > "modules/gaming/controllers.nix" << 'EOF'
# modules/gaming/controllers.nix
# Controller support — udev rules for PS5 (DualSense), Xbox, and Switch Pro.
# hid-nintendo: Switch Pro and Joy-Con kernel driver
# xpadneo: improved Xbox controller driver (rumble, adaptive triggers)
{ pkgs, ... }:
{
  hardware.xpadneo.enable = true;       # Xbox controller driver (xpadneo)

  # Nintendo controller support
  services.udev.packages = with pkgs; [
    game-devices-udev-rules  # udev rules for PS4, PS5, Switch Pro, Steam Controller
  ];

  boot.extraModulePackages = with pkgs.linuxPackages; [
    hid-nintendo  # Switch Pro / Joy-Con kernel module
  ];
}
EOF

echo "  modules/gaming/ created."

# ---------------------------------------------------------------------------
# modules/laptop/
# ---------------------------------------------------------------------------

cat > "modules/laptop/power.nix" << 'EOF'
# modules/laptop/power.nix
# Power management for tuvalu (laptop) — battery life over performance.
# auto-cpufreq: dynamic CPU frequency scaling based on actual load, not just AC/battery state.
# Applied to tuvalu only via tags.laptop = true.
{ pkgs, ... }:
{
  # auto-cpufreq — smarter than TLP for dynamic workloads
  services.auto-cpufreq = {
    enable = true;
    settings = {
      battery = {
        governor         = "powersave";
        turbo            = "auto";       # allows turbo when genuinely needed
        energy_perf_pref = "power";
        scaling_max_freq = 2300000;      # cap at base clock on battery (2.3GHz i7-10610U)
      };
      charger = {
        governor         = "performance";
        turbo            = "auto";
        energy_perf_pref = "performance";
      };
    };
  };

  # Suspend and lid behavior
  services.logind = {
    lidSwitch             = "suspend";
    lidSwitchExternalPower = "ignore";   # lid close while charging: do nothing
    extraConfig = ''
      IdleAction=suspend
      IdleActionSec=5min
      HandlePowerKey=suspend
    '';
  };

  # Power button: suspend rather than shutdown
  powerManagement.enable = true;
}
EOF

cat > "modules/laptop/hidpi.nix" << 'EOF'
# modules/laptop/hidpi.nix
# Display scaling for the 1920x1080 16" built-in panel on tuvalu.
# 1.25x scaling matches the Windows DPI setting (120 DPI effective).
# Applied to tuvalu only via tags.laptop = true.
{ ... }:
{
  # Wayland scaling — 1.25x for the built-in 1920x1080 16" panel
  # KDE/KWin picks this up automatically on Wayland
  environment.sessionVariables = {
    QT_SCALE_FACTOR    = "1.25";
    GDK_SCALE          = "1";          # GTK — fractional scaling via GDK_DPI_SCALE instead
    GDK_DPI_SCALE      = "1.25";
  };

  # KDE Plasma will set its own DPI per-display via KScreen
  # This env var provides a hint for apps that bypass KScreen
  services.xserver.dpi = 120;          # 96 * 1.25 = 120 DPI
}
EOF

cat > "modules/laptop/wifi.nix" << 'EOF'
# modules/laptop/wifi.nix
# WiFi configuration for tuvalu.
# NetworkManager handles connection management.
# iwlwifi power save level 2 — balances battery savings against latency spikes.
# Level 5 (maximum) causes noticeable latency spikes during remote work; level 2 does not.
{ pkgs, ... }:
{
  networking.networkmanager.enable = true;

  # iwlwifi power management — level 2 out of 5
  # Higher levels save more power but introduce latency spikes (breaks remote work feel)
  boot.extraModprobeConfig = ''
    options iwlwifi power_save=1
    options iwlmvm power_scheme=2
  '';

  environment.systemPackages = with pkgs; [
    networkmanager-openvpn  # VPN support in NetworkManager
  ];
}
EOF

cat > "modules/laptop/battery.nix" << 'EOF'
# modules/laptop/battery.nix
# Battery protection and low-battery behavior for tuvalu.
# Hibernate at 10% — protects against data loss during sessions with degraded battery.
# Applied to tuvalu only via tags.laptop = true.
{ pkgs, ... }:
{
  # UPower — battery monitoring daemon
  services.upower = {
    enable                   = true;
    criticalPowerAction      = "Hibernate"; # hibernate at critical level (not shutdown)
    percentageCritical       = 10;
    percentageLow            = 20;
    percentageAction         = 10;
  };

  # Hibernate requires either a swap partition or swap file
  # Declare swap here or in hardware.nix — size >= RAM (32GB)
  # swapDevices = [{ device = "/persist/swapfile"; size = 32768; }];

  environment.systemPackages = with pkgs; [
    upower  # upower CLI — inspect battery status: upower -i $(upower -e | grep battery)
  ];
}
EOF

echo "  modules/laptop/ created."

# ---------------------------------------------------------------------------
# modules/work/
# ---------------------------------------------------------------------------

placeholder "modules/work/dev.nix" "Development tools, compilers, editors — Phase 1: basic tools only; Phase 2: expands"
placeholder "modules/work/secrets.nix" "sops-nix configuration — DEFERRED to Phase 2 (requires age keys and secrets.yaml)"

echo "  modules/work/ created."

# ---------------------------------------------------------------------------
# home/taylor/
# ---------------------------------------------------------------------------

cat > "home/taylor/default.nix" << 'EOF'
# home/taylor/default.nix
# Home Manager entrypoint for taylor — imports all user config files.
# NO hardware conditionals here. Hardware divergence lives in modules/ only.
# Everything here is identical on fiji and tuvalu.
{ pkgs, lib, inputs, tags, ... }:
{
  imports = [
    ./shell.nix
    ./terminal.nix
    ./dev.nix
    ./security.nix
    ./sync.nix
  ]
  # streaming.nix — laptop only (Moonlight client)
  ++ lib.optional tags.laptop ./streaming.nix;

  home.username      = "taylor";
  home.homeDirectory = "/home/taylor";

  # Let Home Manager manage itself
  programs.home-manager.enable = true;

  # XDG directories
  xdg.enable = true;

  home.stateVersion = "25.05";
}
EOF

cat > "home/taylor/shell.nix" << 'EOF'
# home/taylor/shell.nix
# Fish shell, Starship prompt, aliases, environment variables, and Fish plugins.
# Fully synced between fiji and tuvalu — no hardware conditionals.
{ pkgs, ... }:
{
  # Fish shell — interactive shell
  programs.fish = {
    enable = true;

    # Fish plugins — declared here, not installed imperatively via fisher
    plugins = [
      {
        # bass — runs bash scripts from Fish; essential for tools that emit bash init scripts
        name = "bass";
        src  = pkgs.fishPlugins.bass.src;
      }
      {
        # fzf.fish — wires fzf into Fish: Ctrl+R history, Ctrl+T file picker, Alt+C cd
        name = "fzf-fish";
        src  = pkgs.fishPlugins.fzf-fish.src;
      }
      {
        # autopair.fish — auto-closes brackets, quotes, parentheses
        name = "autopair";
        src  = pkgs.fishPlugins.autopair.src;
      }
      {
        # puffer-fish — text expansion: ... -> ../.., .... -> ../../.. etc
        name = "puffer";
        src  = pkgs.fishPlugins.puffer.src;
      }
    ];

    # Shell aliases — override GNU coreutils with modern replacements
    shellAliases = {
      # eza replaces ls — icons, git status, tree view
      ls   = "eza --icons";
      ll   = "eza --icons -la";
      la   = "eza --icons -a";
      tree = "eza --icons --tree";

      # bat replaces cat — syntax highlighting, line numbers, git markers
      cat  = "bat";

      # fd replaces find — faster, respects .gitignore, intuitive syntax
      find = "fd";

      # ripgrep replaces grep — faster, respects .gitignore, better output
      grep = "rg";

      # btop replaces htop/top — per-core CPU, memory, disk I/O, network, process tree
      top  = "btop";

      # zoxide replaces cd — frecency-based smart jump (z learns your directories)
      # 'cd' alias only works after zoxide has learned some directories
      cd   = "z";

      # Convenience
      g    = "git";
      lg   = "lazygit";
    };

    # Interactive shell initialization — runs on every Fish session start
    interactiveShellInit = ''
      # zoxide — initialize after Fish starts
      # Provides: z <partial-path> to jump to frecent directories
      ${pkgs.zoxide}/bin/zoxide init fish | source

      # atuin — replace Fish's default Ctrl+R with atuin's rich history search
      # History stored in SQLite: timestamp, directory, exit code, duration
      ${pkgs.atuin}/bin/atuin init fish | source

      # direnv — activate .envrc automatically on directory change
      # With nix-direnv: Nix dev shells activate instantly (cached)
      ${pkgs.direnv}/bin/direnv hook fish | source
    '';
  };

  # Starship — cross-shell prompt
  programs.starship = {
    enable = true;
    settings = {
      format = "$all";
      character = {
        success_symbol = "[➜](bold green)";
        error_symbol   = "[➜](bold red)";
      };
      nix_shell = {
        disabled = false;
        symbol   = " ";
      };
      git_branch.symbol = " ";
      directory.truncation_length = 4;
    };
  };

  # direnv + nix-direnv — auto-activate Nix dev shells per directory
  programs.direnv = {
    enable             = true;
    nix-direnv.enable  = true;  # caches shells — re-entry is instant, no rebuild
  };

  # atuin — shell history in SQLite
  programs.atuin = {
    enable   = true;
    settings = {
      auto_sync    = false;  # local-only; no sync server configured
      sync_address = "";
      search_mode  = "fuzzy";
      filter_mode  = "directory"; # Ctrl+R shows history for current directory first
    };
  };
}
EOF

cat > "home/taylor/terminal.nix" << 'EOF'
# home/taylor/terminal.nix
# Ptyxis terminal emulator, zellij multiplexer, and all terminal utility packages.
# Fully synced between fiji and tuvalu — no hardware conditionals.
{ pkgs, ... }:
{
  # Ptyxis — GTK4/libadwaita terminal with container support
  home.packages = with pkgs; [ ptyxis ];

  # GTK theming — aligns libadwaita (Ptyxis) closer to KDE Plasma color palette
  gtk.enable = true;

  # zellij — terminal multiplexer for persistent remote sessions
  # Primary use: homelab SSH sessions where panes must survive a disconnect
  # Distinct from Ptyxis tabs: Ptyxis = local sessions, zellij = remote persistent panes
  programs.zellij = {
    enable      = true;
    # Layouts declared as YAML in ~/.config/zellij/layouts/
    # Phase 2: declare a "homelab" layout that opens panes to vm1/vm2/vm3
  };

  # Terminal utilities — all synced, no exceptions
  home.packages = with pkgs; [
    # Navigation and search
    zoxide       # frecency-based smart cd — learns your directories, 'z proj' just works
    fzf          # fuzzy finder — backs fzf.fish Ctrl+R, Ctrl+T, Alt+C
    fd           # fast 'find' replacement — respects .gitignore, intuitive: fd pattern
    ripgrep      # fast 'grep' replacement (rg) — respects .gitignore, better output

    # File viewing
    bat          # 'cat' with syntax highlighting, line numbers, git change markers
                 # also set as MANPAGER for readable man pages
    eza          # modern 'ls' — icons, git status, tree view (aliased in shell.nix)
    glow         # renders Markdown in the terminal — for READMEs and documentation

    # File management
    yazi         # TUI file manager — fast previews for code, images, PDFs, archives
                 # shell integration: ya shell-init fish exits into navigated directory

    # System monitoring
    btop         # resource monitor — per-core CPU, memory, disk I/O, network, processes
                 # AMDGPU plugin active on fiji via the AMD GPU module
    gdu          # TUI disk usage analyzer — first tool for investigating /persist usage
                 # Usage: gdu /persist

    # Multiplexer
    # zellij declared above via programs.zellij

    # Reference
    tldr         # simplified community man pages — faster than man for common usage
    navi         # interactive cheatsheet tool — personal searchable knowledge base

    # Data processing (also in dev.nix for editor integration)
    jq           # JSON processor — essential for API work and nix eval --json | jq
    yq-go        # YAML processor — useful for NixOS config inspection
  ];

  # bat as MANPAGER — makes man pages readable with syntax highlighting
  home.sessionVariables = {
    MANPAGER = "sh -c 'col -bx | bat -l man -p'";
    MANROFFOPT = "-c";
  };
}
EOF

cat > "home/taylor/dev.nix" << 'EOF'
# home/taylor/dev.nix
# Git configuration, delta diff pager, lazygit, and development tools.
# Fully synced between fiji and tuvalu — no hardware conditionals.
{ pkgs, ... }:
{
  # Git — declarative config via Home Manager
  programs.git = {
    enable    = true;
    userName  = "Taylor";
    userEmail = "taylort3450@proton.me"; # TODO: confirm email

    # delta — syntax-highlighted diff pager
    # Replaces the default diff output with side-by-side highlighted diffs
    extraConfig = {
      core.pager         = "${pkgs.delta}/bin/delta";
      interactive.diffFilter = "${pkgs.delta}/bin/delta --color-only";
      delta = {
        navigate    = true;   # n/N to move between diff sections
        side-by-side = true;
        line-numbers = true;
      };
      merge.conflictstyle = "diff3";
      diff.colorMoved     = "default";
      init.defaultBranch  = "main";
      pull.rebase         = true;
    };
  };

  home.packages = with pkgs; [
    delta    # git diff pager — syntax highlighting, side-by-side (configured above)
    lazygit  # TUI git client — interactive rebase, hunk staging, branch management
             # keyboard-driven, good for careful commit hygiene on a public repo
  ];
}
EOF

cat > "home/taylor/security.nix" << 'EOF'
# home/taylor/security.nix
# SSH client config, GPG, and biometric auth.
# SSH ProxyJump section is commented out until Phase 2 (Headscale + VMs operational).
{ pkgs, ... }:
{
  # SSH client config — declared via Home Manager, synced to both machines
  programs.ssh = {
    enable = true;

    # Global SSH defaults
    extraConfig = ''
      ServerAliveInterval 60
      ServerAliveCountMax 3
      AddKeysToAgent yes
    '';

    # Phase 2: uncomment when Headscale mesh and VMs are operational
    # matchBlocks = {
    #   "vm1" = {
    #     hostname     = "vm1.internal.tongatime.us";
    #     user         = "taylor";
    #     identityFile = "~/.ssh/id_ed25519";
    #   };
    #   "vm2" = {
    #     hostname   = "vm2.internal.tongatime.us";
    #     user       = "taylor";
    #     identityFile = "~/.ssh/id_ed25519";
    #     proxyJump  = "vm1";
    #   };
    #   "vm3" = {
    #     hostname   = "vm3.internal.tongatime.us";
    #     user       = "taylor";
    #     identityFile = "~/.ssh/id_ed25519";
    #     proxyJump  = "vm1";
    #   };
    #   "vm4" = {
    #     hostname   = "vm4.internal.tongatime.us";
    #     user       = "taylor";
    #     identityFile = "~/.ssh/id_ed25519";
    #     proxyJump  = "vm1";
    #   };
    #   "vps" = {
    #     hostname     = "hs.tongatime.us";
    #     user         = "taylor";
    #     identityFile = "~/.ssh/id_ed25519";
    #   };
    # };
  };

  # GPG — for commit signing if desired
  programs.gpg.enable = true;
  services.gpg-agent = {
    enable         = true;
    defaultCacheTtl = 3600;
    pinentryPackage = pkgs.pinentry-qt;  # KDE-native pinentry dialog
  };

  # fprintd — fingerprint enrollment
  # Enrollment done via: fprintd-enroll taylor && fprintd-verify taylor
  # Phase 1: laptop (tuvalu) has built-in reader — enroll immediately after install
  # Phase 1: desktop (fiji) — deferred until USB fingerprint reader is sourced
  home.packages = with pkgs; [
    fprintd  # fprintd-enroll, fprintd-verify CLI tools
  ];
}
EOF

cat > "home/taylor/sync.nix" << 'EOF'
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
EOF

cat > "home/taylor/streaming.nix" << 'EOF'
# home/taylor/streaming.nix
# Moonlight game streaming client — tuvalu (laptop) only.
# Gated on tags.laptop = true in home/taylor/default.nix.
# Streams from fiji (desktop) running Sunshine over the Headscale mesh.
# Apollo/Artemis monitored as future replacement (FC-004) — see docs/DECISIONS.md.
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    moonlight-qt  # Moonlight game streaming client — connects to Sunshine on fiji
                  # Phase 2: configure with fiji's Headscale peer IP
                  # Works from anywhere via Headscale mesh (not just local network)
  ];
}
EOF

placeholder "home/taylor/kde/default.nix" "KDE dotfiles — kwinrc, plasmarc, theme, panel layout. Implement after first boot to capture preferences."

echo "  home/taylor/ created."

# ---------------------------------------------------------------------------
# tofu/ — OpenTofu placeholders (Phase 2)
# ---------------------------------------------------------------------------

placeholder "tofu/dns/main.tf"       "Cloudflare DNS records for tongatime.us public zone — Phase 2"
placeholder "tofu/dns/variables.tf"  "Cloudflare zone ID, API token reference — Phase 2"
placeholder "tofu/identity/main.tf"  "FreeIPA users, groups, HBAC, sudo rules — Phase 2"
placeholder "tofu/authentik/main.tf" "Authentik OIDC clients, LDAP sync — Phase 2"
placeholder "tofu/headscale/main.tf" "Headscale ACL policy, registered machines — Phase 2"

cat > "tofu/backend.tf" << 'EOF'
# tofu/backend.tf
# OpenTofu remote state backend — MinIO on VM2.
# DEFERRED to Phase 2. MinIO must be running before this is activated.
# Bootstrap procedure: run tofu init locally first, apply to create MinIO bucket,
# then migrate state with: tofu init -migrate-state

# terraform {
#   backend "s3" {
#     bucket                      = "tofu-state"
#     key                         = "global/terraform.tfstate"
#     region                      = "us-east-1"  # MinIO ignores region but requires a value
#     endpoint                    = "https://minio.internal.tongatime.us"
#     force_path_style            = true
#     skip_credentials_validation = true
#     skip_metadata_api_check     = true
#     skip_region_validation      = true
#   }
# }
EOF

echo "  tofu/ created."

# ---------------------------------------------------------------------------
# secrets/
# ---------------------------------------------------------------------------

placeholder "secrets/.sops.yaml" "sops-nix key configuration — age keys per host. Populate after generating keys (pre-Phase 2)"
placeholder "secrets/common.yaml" "Secrets accessible to all hosts — DEFERRED to Phase 2"
placeholder "secrets/fiji.yaml"   "Desktop-specific secrets — DEFERRED to Phase 2"
placeholder "secrets/tuvalu.yaml" "Laptop-specific secrets — DEFERRED to Phase 2"

echo "  secrets/ created."

# ---------------------------------------------------------------------------
# docs/ — copy in existing documentation
# ---------------------------------------------------------------------------

placeholder "docs/PROJECT_RULES.md"       "Project rules — copy from PROJECT_RULES.md in outputs"
placeholder "docs/DECISIONS.md"           "Architecture decision records — copy from DECISIONS.md in outputs"
placeholder "docs/CLAUDE.md"              "Claude Code context document — copy from CLAUDE.md in outputs"
placeholder "docs/BOOTSTRAP_SEQUENCE.md"  "Bootstrap sequence — copy from BOOTSTRAP_SEQUENCE.md in outputs"
placeholder "docs/PORT_REFERENCE.md"      "Port reference — copy from PORT_REFERENCE.md in outputs"
placeholder "docs/FLAKE_INPUTS.md"        "Flake inputs — copy from FLAKE_INPUTS.md in outputs"
placeholder "docs/ACTION_PLAN.md"         "Action plan — copy from ACTION_PLAN.md in outputs"
placeholder "docs/PHASE1_PLAN.md"         "Phase 1 migration plan — copy from PHASE1_PLAN.md in outputs"
placeholder "docs/architecture/workspace.dsl" "Structurizr C4 DSL — implement in Phase 0 before deployment"

echo "  docs/ created."

# ---------------------------------------------------------------------------
# Final summary
# ---------------------------------------------------------------------------

echo ""
echo "Done. Repository scaffolded at ."
echo ""
echo "File count: $(find . -type f | wc -l) files in $(find . -type d | wc -l) directories"
echo ""
echo "IMMEDIATE NEXT STEPS:"
echo "  1. (skipped)"
echo "  2. git add . && git commit -m 'feat: initial scaffold'"
echo "  3. Copy docs from outputs/ into docs/ (PROJECT_RULES.md, DECISIONS.md, etc.)"
echo "  4. Run: nix flake check   (expect errors until hardware.nix files are real)"
echo "  5. Fix any evaluation errors before touching either machine"
echo ""
echo "  Phase 1 begins in earnest once nix flake check passes."