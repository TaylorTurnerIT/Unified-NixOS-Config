# Flake Inputs

> All external Nix dependencies declared in flake.nix.
> Every input has a stated purpose, a pinning strategy, and an update owner.
> Renovate Bot manages update PRs for all inputs. Never update flake.lock manually.

---

## flake.nix Structure

```nix
{
  description = "tongatime.us NixOS infrastructure monorepo";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    impermanence.url = "github:nix-community/impermanence";

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    nix-gaming = {
      url = "github:fufexan/nix-gaming";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    attic = {
      url = "github:zhaofengli/attic";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, home-manager, ... }: {
    # ...
  };
}
```

---

## Input Reference

### nixpkgs
- **Purpose:** The Nix package collection. All system packages, NixOS modules, and
  library functions come from this input. The foundation of everything.
- **Channel:** `nixos-unstable` — provides the most recent packages. Appropriate
  for a fast-moving desktop/homelab setup. Use `nixos-stable` if breakage from
  frequent updates becomes a concern.
- **Why unstable:** The desktop (gaming, KDE 6.x, latest Mesa/AMDGPU) and recent
  hardware (T15 Gen1 Intel 10th gen) benefit from recent package versions. Homelab
  services use container images with digest pinning, so nixpkgs instability primarily
  affects system packages rather than running services.
- **Update strategy:** Renovate opens a PR when nixpkgs advances. Merge after
  verifying `nix flake check` passes. No manual `nix flake update`.
- **follows:** All other inputs that depend on nixpkgs use `inputs.nixpkgs.follows`
  to prevent multiple nixpkgs evaluations in the same build.

### home-manager
- **Purpose:** Declarative user environment management. Manages dotfiles, user-level
  packages, shell configuration, and application settings for the `taylor` user
  on both personal machines. All config in `home/taylor/`.
- **Integration:** Runs as a NixOS module (`home-manager.nixosModules.home-manager`),
  not standalone. `nixos-rebuild switch` applies both system and user config.
- **Follows nixpkgs:** Yes — prevents version mismatch between system and user packages.
- **Update strategy:** Updated in sync with nixpkgs. Renovate handles both.

### sops-nix
- **Purpose:** Secrets management. Decrypts sops-encrypted secrets at NixOS activation
  time and mounts them at `/run/secrets/`. Secrets are never in the Nix store.
  Age keys at `/etc/sops-age-key` per host.
- **Scope:** All hosts. `modules/work/secrets.nix` configures sops-nix. Individual
  service configs reference secret paths rather than values.
- **Follows nixpkgs:** Yes.
- **Update strategy:** Renovate. Sops-nix updates are low-risk — the API is stable.

### deploy-rs
- **Purpose:** Push NixOS configurations to remote hosts over SSH. Provides
  rollback on activation failure — if a new config fails to activate, the previous
  generation is automatically restored. Used by Gitea Actions pipeline.
- **Why not colmena or raw nixos-rebuild:** deploy-rs is flake-native and provides
  per-profile rollback semantics which are critical for unattended VM deployments.
- **Follows nixpkgs:** Yes.
- **Update strategy:** Renovate. Test rollback behavior after any deploy-rs update.

### impermanence
- **Purpose:** Provides the NixOS module and Home Manager module for declaring which
  paths survive reboots on an ephemeral-root (tmpfs) system. Used on both personal
  machines. `environment.persistence."/persist"` declares all surviving paths.
- **Does not follow nixpkgs:** impermanence is a library module, not a package
  collection — it has no meaningful nixpkgs dependency to follow.
- **Update strategy:** Renovate. Low update frequency; API is stable.

### nixos-hardware
- **Purpose:** Community-maintained, machine-specific NixOS modules for known hardware.
  The ThinkPad T15 Gen1 imports a module from this input covering: iwlwifi firmware,
  trackpoint, power management defaults, and fingerprint reader kernel interface.
  The C2100 desktop does not use this input (no matching module; uses generated
  hardware.nix instead).
- **Channel:** `master` — hardware modules are added and updated continuously.
  Pinning to a release would miss hardware fixes.
- **Does not follow nixpkgs:** nixos-hardware tracks its own nixpkgs dependency
  for hardware-specific packages that may lag nixos-unstable.
- **Update strategy:** Renovate. After any update, verify the T15 Gen1 module
  still applies cleanly and check for new modules that might be relevant.
- **Usage:** `nixos-hardware.nixosModules.<module-name>` imported in laptop host.

### nix-gaming
- **Purpose:** Provides Proton-GE (GloriousEggroll's Proton fork) as a declarative
  Nix derivation, and other gaming-related packages not in nixpkgs. Used exclusively
  on the desktop via `tags.gaming = true`.
- **Why not ProtonUp-Qt:** ProtonUp-Qt is imperative (downloads at runtime). nix-gaming
  packages Proton-GE as a proper Nix derivation: reproducible, version-pinned,
  buildable from the cache, no runtime downloads.
- **Follows nixpkgs:** Yes.
- **Update strategy:** Renovate. Each new Proton-GE release appears as a flake update.
  New Proton-GE versions improve game compatibility — update frequently.

### attic
- **Purpose:** Self-hosted Nix binary cache. The attic server runs on VM2.
  The attic client (from this flake) is used by the Gitea Actions runner to push
  build results to the cache. All other hosts substitute from the cache rather
  than building locally.
- **Follows nixpkgs:** Yes.
- **Update strategy:** Renovate. Coordinate attic client and server updates — they
  should be on the same version. Update both in the same PR.
- **Cache URL:** `https://cache.internal.tongatime.us`

---

## Input Dependency Graph

```
nixpkgs (nixos-unstable)
  ├── home-manager       (follows nixpkgs)
  ├── sops-nix           (follows nixpkgs)
  ├── deploy-rs          (follows nixpkgs)
  ├── nix-gaming         (follows nixpkgs)
  └── attic              (follows nixpkgs)

impermanence               (independent)
nixos-hardware             (independent, tracks own nixpkgs)
```

The `follows` declarations prevent multiple nixpkgs evaluations. Without them,
a build could evaluate nixpkgs 6+ times (once per input), significantly increasing
evaluation time and memory usage.

---

## Inputs NOT Used (and Why)

### flake-utils
Not used. Modern NixOS flakes do not need flake-utils for the standard
`nixosConfigurations`, `homeConfigurations`, and `packages` output patterns.
Adding it introduces a dependency for no benefit.

### nix-darwin
Not used. No macOS machines in scope.

### nixpkgs-stable
Not used. `nixos-unstable` is the chosen channel. If a specific package needs
a stable version, use `nixpkgs.lib.nixpkgs.legacyPackages` with an inline override
rather than adding a second nixpkgs input.

---

## Updating Inputs

Renovate handles all input updates via PR. For manual updates when needed:

```bash
# Update a single input
nix flake update nixpkgs

# Update all inputs
nix flake update

# After updating, always verify
nix flake check
nix build .#nixosConfigurations.desktop.config.system.build.toplevel

# Commit the updated flake.lock
git add flake.lock
git commit -m "chore: update flake inputs"
```

Never merge a flake.lock update without a passing `nix flake check`.
