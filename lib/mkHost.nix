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
    ../modules/core/nix.nix
    ../modules/core/locale.nix
    ../modules/core/security.nix
    ../modules/core/ssh.nix
    # ssh-recording.nix — DEFERRED to Phase 2 (requires tlog + SSSD)
  ];

  # Desktop environment — all graphical hosts
  desktopModules = [
    ../modules/desktop/kde.nix
    ../modules/desktop/wayland.nix
    ../modules/desktop/fonts.nix
  ];

  # GPU modules — selected by tag
  gpuModules =
    lib.optional tags.amdGpu   ../modules/hardware/gpu/amd.nix ++
    lib.optional tags.intelGpu ../modules/hardware/gpu/intel.nix;

  # Display modules
  displayModules =
    lib.optional tags.hdr ../modules/hardware/displays/hdr.nix;

  # Gaming modules — desktop only
  gamingModules = lib.optionals tags.gaming [
    ../modules/gaming/steam.nix
    ../modules/gaming/proton.nix
    ../modules/gaming/tools.nix
    ../modules/gaming/launchers.nix
    ../modules/gaming/controllers.nix
  ];

  # Laptop modules
  laptopModules = lib.optionals tags.laptop [
    ../modules/laptop/power.nix
    ../modules/laptop/hidpi.nix
    ../modules/laptop/wifi.nix
    ../modules/laptop/battery.nix
  ];

  # nixos-hardware — laptop only, exact module verified at install time
  hardwareModules = lib.optionals tags.laptop [
    # TODO AI-035: verify exact module name for ThinkPad T15 Gen1
    # nixos-hardware.nixosModules.lenovo-thinkpad-t14s
  ];

  # nix-gaming flake modules — desktop only
  nixGamingModules = lib.optionals tags.gaming [
    nix-gaming.nixosModules.platformOptimizations
    nix-gaming.nixosModules.steamCompat
    nix-gaming.nixosModules.pipewireLowLatency
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
      ../hosts/${hostname}/default.nix
      ../hosts/${hostname}/hardware.nix

      # Home Manager as NixOS module — applies system + user config in one switch
      home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.taylor = import ../home/taylor/default.nix;
        home-manager.extraSpecialArgs = { inherit inputs tags; };
      }

      # sops-nix secrets
      sops-nix.nixosModules.sops

      # Impermanence
      impermanence.nixosModules.impermanence
    ];
  specialArgs = { inherit inputs tags hostname; };
}
