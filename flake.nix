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
