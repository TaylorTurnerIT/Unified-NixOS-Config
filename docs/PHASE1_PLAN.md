# Phase 1 Migration Plan

**Scope:** Personal machines only — fiji (desktop) and tuvalu (laptop).
No server. No Headscale. No FreeIPA. No SSSD.
Everything that runs independently on each machine is configured here.
Phase 2 handles server migration and enrollment.

**Hostnames:** fiji (desktop, MS-7A71 / i7-7700K / RX 6700 XT), tuvalu (laptop, ThinkPad T15 Gen1 / i7-10610U)

---

## What Phase 1 Includes

- NixOS with impermanence (ephemeral root) on both machines
- KDE Plasma 6 on Wayland with SDDM
- Full Home Manager user config (identical on both machines)
- Fish shell, Starship, all terminal utilities, all aliases
- Ptyxis terminal, zellij multiplexer
- direnv + nix-direnv (auto-activating Nix dev shells)
- atuin (shell history in SQLite)
- AMD GPU module on fiji (amdgpu, ROCm, RADV, LACT, 32-bit libs)
- Intel iGPU module on tuvalu (modesetting, VA-API iHD)
- Gaming stack on fiji (Steam, Proton-GE, gamemode, gamescope, MangoHUD, Heroic, Lutris)
- Laptop power management on tuvalu (auto-cpufreq, suspend, battery, WiFi)
- Display scaling 1.25x on tuvalu (120 DPI)
- Fingerprint reader enrollment on tuvalu
- Sunshine (streaming server) on fiji
- Moonlight (streaming client) on tuvalu
- Nextcloud client installed (server configured in Phase 2)
- Local taylor user (becomes break-glass account in Phase 2 when SSSD takes over)

## What Phase 1 Excludes (Deferred to Phase 2)

- SSSD / FreeIPA enrollment
- Headscale / WireGuard mesh
- Kerberos authentication
- tlog session recording
- sops-nix secrets (no secrets needed in Phase 1)
- attic binary cache (use cache.nixos.org for now)
- deploy-rs remote deployment
- SSH ProxyJump config (commented out in security.nix)
- Nextcloud server URL configuration
- AD cross-forest trust

---

## Step 1 — Bootstrap the Monorepo

Do this now, on your current machine (Bazzite or WSL). Nothing gets installed
on either target machine until the flake evaluates cleanly.

### 1.1 Run the scaffold script

```bash
chmod +x bootstrap.sh
./bootstrap.sh
cd nixos-config
git init && git add . && git commit -m "feat: initial scaffold"
```

### 1.2 Copy documentation into docs/

```bash
# From wherever you saved the outputs:
cp PROJECT_RULES.md  docs/
cp DECISIONS.md      docs/
cp CLAUDE.md         docs/
cp BOOTSTRAP_SEQUENCE.md docs/
cp PORT_REFERENCE.md docs/
cp FLAKE_INPUTS.md   docs/
cp ACTION_PLAN.md    docs/
cp PHASE1_PLAN.md    docs/
git add docs/ && git commit -m "docs: add full documentation set"
```

### 1.3 Push to a remote

Create a repo on GitHub (or wherever you have access right now) and push.
It migrates to self-hosted Gitea in Phase 2.

```bash
git remote add origin <your-repo-url>
git push -u origin main
```

### 1.4 Verify the flake evaluates

```bash
nix flake check
```

This will fail with errors about `hardware.nix` files being placeholders. That is
expected and correct — the real `hardware.nix` files are generated at install time.
Fix any other evaluation errors before proceeding. The build must succeed for both
hosts (substituting placeholder hardware configs) before you touch either machine.

```bash
# These should both produce a derivation path, not an error
nix build .#nixosConfigurations.fiji.config.system.build.toplevel   --dry-run
nix build .#nixosConfigurations.tuvalu.config.system.build.toplevel --dry-run
```

---

## Step 2 — Desktop Migration (fiji)

Do not begin until Step 1.4 passes.

### 2.1 Pre-migration checklist

- [ ] `nix build .#nixosConfigurations.fiji.config.system.build.toplevel --dry-run` succeeds
- [ ] Game saves identified: which games use Steam Cloud? Which do not?
- [ ] Non-Steam-Cloud saves manually copied to external drive or Google Drive
- [ ] 222GB drive contents audited — anything needed from it?
- [ ] Current BIOS settings photographed or noted (boot order, XMP profile)
- [ ] Monitor cable arrangement documented (which display on which port)
- [ ] Repo accessible from the NixOS installer (USB or network)

### 2.2 Boot the NixOS installer

Download the latest NixOS minimal or graphical ISO.
Boot from USB. Connect to network.

```bash
# Enable flakes in the installer session
export NIX_CONFIG="experimental-features = nix-command flakes"

# Clone the repo
nix-shell -p git --run "git clone <your-repo-url> /tmp/nixos-config"
```

### 2.3 Partition and format the primary SSD

```bash
# Identify the primary SSD (check with lsblk — look for the ~930GB drive)
# Replace sdX with your actual device

# Create partition table
parted /dev/sdX -- mklabel gpt

# EFI partition — 512MB
parted /dev/sdX -- mkpart ESP fat32 1MB 513MB
parted /dev/sdX -- set 1 esp on

# /boot — 1GB
parted /dev/sdX -- mkpart primary 513MB 1537MB

# /nix — 200GB (Nix store — all software lives here)
parted /dev/sdX -- mkpart primary 1537MB 206537MB

# /persist — remaining space (all surviving system state)
parted /dev/sdX -- mkpart primary 206537MB 100%

# Format
mkfs.fat  -F 32 -n BOOT /dev/sdX1
mkfs.ext4 -L nixboot    /dev/sdX2
mkfs.btrfs -L nixstore  /dev/sdX3
mkfs.btrfs -L persist   /dev/sdX4

# Mount — order matters
mount -t tmpfs none /mnt              # ephemeral root (impermanence)

mkdir -p /mnt/{boot/efi,nix,persist}
mount /dev/disk/by-label/nixboot  /mnt/boot
mount /dev/disk/by-label/BOOT     /mnt/boot/efi
mount /dev/disk/by-label/nixstore /mnt/nix
mount /dev/disk/by-label/persist  /mnt/persist
```

### 2.4 Configure the secondary drive (1.82TB HDD)

The 1.82TB drive becomes `/mnt/overflow` — local scratch, not synced, not backed up.
Do this as a separate operation so it does not affect the primary install.

```bash
# Identify the 1.82TB drive (lsblk will show it)
# Replace sdY with the correct device

mkfs.ext4 -L overflow /dev/sdY
# The NixOS config declares: fileSystems."/mnt/overflow" = { device = "/dev/disk/by-label/overflow"; }
# It mounts automatically after install.
```

### 2.5 Generate hardware config

```bash
nixos-generate-config --root /mnt --no-filesystems
# This generates hardware-configuration.nix
# Copy it into the repo as hosts/fiji/hardware.nix
cp /mnt/etc/nixos/hardware-configuration.nix /tmp/nixos-config/hosts/fiji/hardware.nix

# Commit the real hardware.nix
cd /tmp/nixos-config
git add hosts/fiji/hardware.nix
git commit -m "feat(fiji): add real hardware config from nixos-generate-config"
git push
```

### 2.6 Install

```bash
nixos-install --flake /tmp/nixos-config#fiji --no-root-passwd
```

Set taylor's password when prompted (or do it post-reboot with `passwd taylor`).

### 2.7 Reboot into NixOS

Remove the USB drive. Boot from the SSD. You should arrive at the SDDM login screen.

### 2.8 Post-install verification checklist

Work through these systematically. Note anything that fails and fix it before
moving on — impermanence issues surface as state resetting between reboots.

**KDE and display:**
- [ ] SDDM shows at a usable resolution
- [ ] KDE Plasma 6 starts on Wayland (`echo $XDG_SESSION_TYPE` returns `wayland`)
- [ ] All three monitors detected in KDE Display Settings at correct resolutions
- [ ] 2560x1440 180Hz display running at 180Hz (verify in KDE Display Settings)
- [ ] HDR available on the 1440p display (KDE Display Settings → HDR toggle)
- [ ] `echo $QT_QPA_PLATFORM` returns `wayland`

**Shell and terminal:**
- [ ] Fish is the default shell (`echo $SHELL` returns `/run/current-system/sw/bin/fish`)
- [ ] Starship prompt shows correctly
- [ ] `cat` invokes bat (with syntax highlighting)
- [ ] `ls` invokes eza (with icons)
- [ ] `grep` invokes rg (ripgrep)
- [ ] `top` invokes btop
- [ ] `z` works after visiting a few directories (`z nix` jumps to /nix or similar)
- [ ] Ctrl+R opens atuin history search
- [ ] Ptyxis launches from application menu
- [ ] zellij launches: `zellij`

**GPU and hardware:**
- [ ] `vainfo` shows AMD GPU VA-API decode support (via amdgpu)
- [ ] LACT opens and shows RX 6700 XT: `lact`
- [ ] `amdgpu_top` shows GPU utilization
- [ ] `/mnt/overflow` is mounted and accessible (1.82TB drive)
- [ ] `lsblk` shows the overflow drive correctly mounted

**Gaming:**
- [ ] Steam launches
- [ ] Proton-GE visible in Steam compatibility settings (Properties → Compatibility)
- [ ] Install and launch a small test game (something in your library with good Proton support)
- [ ] MangoHUD overlay appears during the test game (launch with `MANGOHUD=1 %command%`)
- [ ] Gamemode activates (add `gamemoderun %command%` to Steam launch options, check with `gamemoded -t`)
- [ ] Heroic launches
- [ ] `steam-run echo test` runs without error (FHS chroot works)

**Sunshine (streaming server):**
- [ ] Sunshine service running: `systemctl status sunshine`
- [ ] Sunshine web UI accessible at `https://localhost:47990`
- [ ] Initial Sunshine PIN pairing setup complete

**Impermanence:**
- [ ] Reboot the machine
- [ ] Log back in — KDE settings should be preserved (if KDE dotfiles are persisted)
- [ ] `/persist` is populated with the declared directories

### 2.9 One-week impermanence discovery

Use fiji as your primary machine for one week. Any time state unexpectedly resets
after a reboot, add the relevant path to the persistence list in `hosts/fiji/default.nix`.

Common things to watch:

```nix
# Add to environment.persistence."/persist".directories as you discover them:
"/var/lib/systemd/coredump"      # if you want coredumps
"${config.users.users.taylor.home}/.config/KDE"  # if KDE prefs reset
"${config.users.users.taylor.home}/.local/share/Steam"  # Steam installation
"${config.users.users.taylor.home}/.local/share/atuin"  # atuin history database
```

Document each addition with a comment explaining why it needs to persist.
After one week with no unexpected resets, fiji's persistence list is considered stable.

---

## Step 3 — Laptop Migration (tuvalu)

Do not begin until fiji's one-week impermanence discovery is complete.
You will have seen the common gotchas on fiji and can avoid them on tuvalu.

### 3.1 Pre-migration checklist

- [ ] Replacement battery (01AV493) installed and showing good health
  - Check in Windows: `powercfg /batteryreport` — look for Design Capacity vs Full Charge Capacity
  - Target: Full Charge Capacity > 80% of Design Capacity
- [ ] All Windows data backed up:
  - [ ] Documents, Downloads, Desktop exported
  - [ ] Browser bookmarks exported
  - [ ] WSL home directory — `wsl.exe --export Ubuntu ubuntu-backup.tar`
  - [ ] Any non-GitHub dev projects copied
- [ ] nixos-hardware module verified for T15 Gen1:
  ```bash
  # On any machine with nix
  nix flake show github:NixOS/nixos-hardware 2>/dev/null | grep -i "thinkpad.*t1[45]"
  ```
  Update `hosts/tuvalu/hardware.nix` with the exact module name before proceeding.
- [ ] `nix build .#nixosConfigurations.tuvalu.config.system.build.toplevel --dry-run` succeeds

### 3.2 Boot the NixOS installer

Same process as fiji. Boot from USB, connect to WiFi.

```bash
export NIX_CONFIG="experimental-features = nix-command flakes"
nix-shell -p git --run "git clone <your-repo-url> /tmp/nixos-config"
```

### 3.3 Partition and format

Single NVMe, Windows fully wiped:

```bash
# Identify the NVMe drive (lsblk — should be nvme0n1, ~953GB)

parted /dev/nvme0n1 -- mklabel gpt

# EFI — 512MB
parted /dev/nvme0n1 -- mkpart ESP fat32 1MB 513MB
parted /dev/nvme0n1 -- set 1 esp on

# /boot — 1GB
parted /dev/nvme0n1 -- mkpart primary 513MB 1537MB

# /nix — 150GB (Nix store)
parted /dev/nvme0n1 -- mkpart primary 1537MB 154537MB

# /persist — remaining (~780GB)
parted /dev/nvme0n1 -- mkpart primary 154537MB 100%

# Format
mkfs.fat  -F 32 -n BOOT     /dev/nvme0n1p1
mkfs.ext4 -L    nixboot      /dev/nvme0n1p2
mkfs.btrfs -L   nixstore     /dev/nvme0n1p3
mkfs.btrfs -L   persist      /dev/nvme0n1p4

# Mount
mount -t tmpfs none /mnt

mkdir -p /mnt/{boot/efi,nix,persist}
mount /dev/disk/by-label/nixboot  /mnt/boot
mount /dev/disk/by-label/BOOT     /mnt/boot/efi
mount /dev/disk/by-label/nixstore /mnt/nix
mount /dev/disk/by-label/persist  /mnt/persist
```

### 3.4 Generate hardware config and update nixos-hardware module

```bash
nixos-generate-config --root /mnt --no-filesystems
cp /mnt/etc/nixos/hardware-configuration.nix /tmp/nixos-config/hosts/tuvalu/hardware.nix
```

Edit `hosts/tuvalu/hardware.nix` to add the nixos-hardware module import at the top:

```nix
# hosts/tuvalu/hardware.nix (add this import alongside the generated content)
{ inputs, ... }:
{
  imports = [
    # TODO: replace with verified module name from:
    # nix flake show github:NixOS/nixos-hardware | grep thinkpad
    inputs.nixos-hardware.nixosModules.lenovo-thinkpad-t14s  # verify name first
    # Generated hardware config below:
  ];
  # ... rest of generated hardware-configuration.nix ...
}
```

```bash
git add hosts/tuvalu/hardware.nix
git commit -m "feat(tuvalu): add real hardware config with nixos-hardware module"
git push
```

### 3.5 Install

```bash
nixos-install --flake /tmp/nixos-config#tuvalu --no-root-passwd
```

### 3.6 First boot — enroll fingerprint immediately

```bash
# After first login to tuvalu
fprintd-enroll taylor
# Follow the prompts — place finger on reader 5 times
fprintd-verify taylor
# Should return: verification successful
```

### 3.7 Post-install verification checklist

**Display and scaling:**
- [ ] 1.25x scaling active — text sharp and readable, no blurriness or pixelation
- [ ] `echo $QT_SCALE_FACTOR` returns `1.25`
- [ ] KDE System Settings → Display shows 125% scaling
- [ ] `vainfo` shows Intel VA-API with iHD driver (not i965)

**Laptop-specific:**
- [ ] WiFi connects: `nmcli device wifi connect <SSID>` works
- [ ] Fingerprint auth works at SDDM login (test: lock screen, unlock with fingerprint)
- [ ] Fingerprint auth works for sudo (test: `sudo whoami` — finger instead of password)
- [ ] Battery shows correctly in KDE system tray power applet
- [ ] `auto-cpufreq --stats` shows active and responding to load
- [ ] Suspend works: close lid, open lid, verify screen locks and unlocks
- [ ] WiFi not causing latency spikes: `ping 8.8.8.8` for 60 seconds — watch for consistent <20ms RTT

**Battery hibernate threshold test:**
```bash
# Temporarily lower the critical threshold to test hibernate (restore afterward)
sudo systemctl stop upower
# Manually trigger hibernate: sudo systemctl hibernate
# Verify machine wakes from hibernate and session is restored
```

**Power consumption:**
- [ ] `upower -i $(upower -e | grep battery)` shows reasonable percentage
- [ ] After replacement battery, estimate runtime by watching discharge rate during light use
- [ ] Target: >4 hours on battery with normal productivity workload

**Sunshine and Moonlight streaming:**
- [ ] Moonlight installed: `moonlight --version`
- [ ] With fiji on and Sunshine running: open Moonlight, scan for hosts
- [ ] fiji appears in Moonlight (may need to enter PIN shown in Sunshine web UI)
- [ ] Stream connection established — verify video and audio quality
- [ ] Test from a different WiFi network to verify it works over Headscale (Phase 2) — deferred

**Identical terminal experience to fiji:**
- [ ] Fish shell active
- [ ] All aliases work: `cat`, `ls`, `grep`, `top`, `cd` (`z` after warming up)
- [ ] Ctrl+R opens atuin (separate history from fiji — this is correct)
- [ ] Ptyxis launches, zellij launches
- [ ] All terminal utilities present: `bat`, `eza`, `fd`, `rg`, `zoxide`, `fzf`, `yazi`, `btop`, `gdu`

### 3.8 One-week impermanence discovery

Same process as fiji. Laptop-specific things to watch for that fiji would not catch:

- Saved WiFi networks resetting (must be in persistence list: `/etc/NetworkManager/system-connections`)
- Fingerprint enrollment resetting (must be in persistence list: `/var/lib/fprint`)
- Bluetooth paired devices resetting (must be in persistence list: `/var/lib/bluetooth`)
- VPN credentials if any were migrated from Windows

After one week with no unexpected resets, tuvalu's persistence list is considered stable.

---

## Phase 1 Complete — Criteria

Phase 1 is done when all of the following are true:

- [ ] fiji is the daily driver desktop. Bazzite is gone.
- [ ] tuvalu is the daily driver laptop. Windows is gone.
- [ ] Both machines boot into a known-good state on every reboot (impermanence working)
- [ ] Both machines' persistence lists have been stable for one week
- [ ] Steam gaming verified working on fiji with a real game
- [ ] Moonlight streams from fiji to tuvalu
- [ ] Fingerprint auth working on tuvalu
- [ ] Home Manager config (shell, terminal, dev tools) is identical on both machines
- [ ] `nix rebuild switch` applies cleanly on both machines from the repo

## What Changes in Phase 2

Once Phase 1 is stable, Phase 2 begins: homelab server NixOS install and VM1 (Headscale + FreeIPA). When Phase 2 is done, the following things update automatically in the existing configs:

- `users.users.taylor` in host configs remains but becomes the break-glass account
- `modules/core/ssh-recording.nix` is uncommented (tlog)
- ProxyJump section in `home/taylor/security.nix` is uncommented
- `home/taylor/sync.nix` gets the Nextcloud server URL
- `modules/core/nix.nix` gets the attic cache substituter
- `secrets/` files are populated with real encrypted values
- `tofu/backend.tf` is uncommented (MinIO state backend)
- Phase 2 VMs are added to `flake.nix` outputs
