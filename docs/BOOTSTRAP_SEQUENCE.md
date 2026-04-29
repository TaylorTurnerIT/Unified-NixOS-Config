# Bootstrap Sequence

> The exact order to bring up this infrastructure from zero on a fresh homelab.
> Each step has a verification check. Do not proceed to the next step until
> the check passes. This document assumes the physical hardware is racked and
> powered but nothing else is configured.
>
> Reference: docs/DECISIONS.md ADR-004 (VM separation), ADR-003 (VLANs)

---

## Prerequisites Checklist (before starting)

- [ ] Dell PowerEdge C2100 racked, powered, all 16 SAS drives installed
- [ ] iDRAC6 Enterprise card installed and connected to VLAN 10 switch port
- [ ] Managed switch configured with all 6 VLANs (10/20/30/40/50/60)
- [ ] OPNsense router installed with inter-VLAN firewall rules
- [ ] Wireless AP configured with tagged SSIDs (VLAN 30 Trusted, VLAN 40 IoT, VLAN 50 Guest)
- [ ] NixOS installer USB prepared (latest stable)
- [ ] Laptop and desktop connected to VLAN 30 (Trusted)
- [ ] Monorepo exists on a temporary Gitea instance or GitHub (will migrate in Step 6)
- [ ] sops-nix age keys generated for all hosts (store in Vaultwarden immediately)
- [ ] Break-glass USB populated (SSH keys, this document, credentials)

---

## Stage 0: Physical Host (C2100 NixOS Install)

The physical host runs NixOS and hosts all four VMs via KVM/QEMU.
It has no user-facing services of its own.

### Step 0.1 — ZFS Pool

Boot from NixOS installer. Create the RAIDZ2 pool:

```bash
# Identify the 16 SAS drives
ls /dev/disk/by-id/ | grep -v part

# Create RAIDZ2 pool (adjust drive IDs to match your hardware)
zpool create -o ashift=12 \
  -O compression=zstd \
  -O atime=off \
  -O xattr=sa \
  -O acltype=posixacl \
  tank raidz2 \
  /dev/disk/by-id/scsi-<drive1> \
  /dev/disk/by-id/scsi-<drive2> \
  ... (all 16 drives)

# Create datasets
zfs create -o mountpoint=/var/lib/vms tank/vms
zfs create -o mountpoint=none tank/nextcloud
zfs create -o mountpoint=/srv/nextcloud -o quota=1T tank/nextcloud/data
zfs create -o mountpoint=/var/backup tank/backups
zfs create -o mountpoint=none tank/services
zfs create -o mountpoint=/var/lib/gitea tank/services/gitea
zfs create -o mountpoint=/var/lib/vaultwarden tank/services/vaultwarden
zfs create -o mountpoint=/var/lib/postgres tank/services/postgres
```

**Verify:** `zpool status tank` shows ONLINE with 0 errors. `zfs list` shows all datasets.

### Step 0.2 — NixOS Host Install

```bash
# Generate hardware config
nixos-generate-config --root /mnt

# Apply host config from monorepo
nixos-install --flake .#homelab-host
```

**Verify:** System boots to NixOS. `zpool status` shows pool imported. All 4 VM definitions
visible via `virsh list --all` (all in stopped state).

---

## Stage 1: VM1 — Network and Identity

**VM1 must be fully operational before any other VM starts.**
Everything else depends on DNS and authentication.

Start VM1: `virsh start vm1`

### Step 1.1 — Headscale

Headscale runs bare on VM1 (not in a container — it is core network infrastructure).

```bash
# On VM1 after NixOS applies
systemctl status headscale

# Enroll personal machines (run on each machine)
tailscale up --login-server https://hs.tongatime.us --auth-key <preauth-key>
```

Apply Headscale ACL policy via OpenTofu:
```bash
cd tofu/headscale && tofu apply
```

**Verify:**
- Headscale web UI reachable at `hs.tongatime.us` from a browser
- `tailscale status` on desktop shows all enrolled peers
- From desktop: `tailscale ping vm1` succeeds
- From Oracle VPS peer: `tailscale ping vm2` FAILS (ACL enforced)
- From Oracle VPS peer: `tailscale ping vm4` succeeds

### Step 1.2 — FreeIPA

```bash
# FreeIPA container starts automatically via NixOS quadlet
systemctl status podman-freeipa

# Wait for FreeIPA to finish initialization (2-3 minutes first boot)
podman logs freeipa --follow | grep "FreeIPA server configured"

# Apply identity resources
cd tofu/identity && tofu apply
```

**Verify:**
```bash
# From VM1
kinit taylor@TONGATIME.US    # prompts for password, succeeds
klist                         # shows valid TGT
ipa user-find taylor          # returns taylor's user record
```

### Step 1.3 — DNS

FreeIPA BIND starts automatically with the FreeIPA container.

```bash
# Apply Cloudflare DNS records (public zone)
cd tofu/dns && tofu apply

# Test internal resolution from a VLAN 30 machine
# (configure laptop/desktop DNS to point at VM1 IP first)
dig vm1.internal.tongatime.us @<vm1-vlan20-ip>   # should return VM1's IP
dig tongatime.us @<vm1-vlan20-ip>                # should forward to Cloudflare

# Test external resolution is blocked
# From outside your network: dig ipa.internal.tongatime.us
# Should return SERVFAIL (FreeIPA not publicly reachable)
```

**Verify:** All internal hostnames resolve from VLAN 30. Public records resolve correctly.
`ipa.internal.tongatime.us` is unresolvable from outside the network.

### Step 1.4 — Caddy (VM1)

```bash
systemctl status caddy

# Test TLS certificate issuance
# (DNS-01 challenge against Cloudflare API)
curl -I https://ipa.internal.tongatime.us
```

**Verify:** FreeIPA web UI accessible at `https://ipa.internal.tongatime.us` with a valid
Let's Encrypt certificate. No certificate warnings.

### Step 1.5 — SSSD on VM1

```bash
# VM1 should be enrolled as an IPA client
id taylor    # returns taylor's UID/GID from FreeIPA
ssh taylor@vm1.internal.tongatime.us   # authenticates via Kerberos
```

**Verify:** `id taylor` returns correct FreeIPA-sourced identity. SSH with Kerberos ticket works.
tlog session visible in journald: `journalctl -t tlog --no-pager | tail -20`

---

## Stage 2: OpenTofu Remote State Backend

Deploy MinIO on VM2 before any further OpenTofu operations.
This stage requires VM2 to be running but only for MinIO — no other VM2 services yet.

### Step 2.1 — VM2 Minimal Start

Start VM2 with only MinIO declared. Other services are commented out until Stage 3.

```bash
virsh start vm2

# MinIO starts via NixOS quadlet
systemctl status podman-minio

# Create the state bucket
mc alias set local http://vm2.internal.tongatime.us:9000 <minio-root-user> <minio-root-password>
mc mb local/tofu-state
```

### Step 2.2 — Migrate OpenTofu State

```bash
# In each tofu/ subdirectory
cd tofu/dns
tofu init -migrate-state   # migrates from local to MinIO backend

# Repeat for all tofu/ directories
cd tofu/identity && tofu init -migrate-state
cd tofu/headscale && tofu init -migrate-state
cd tofu/authentik && tofu init -migrate-state
```

**Verify:** `tofu state list` works from a fresh checkout with no local state file.
Local `terraform.tfstate` files confirmed absent from repo.

---

## Stage 3: VM2 — Application Services

Deploy services in dependency order within VM2.
Database → Cache → Applications → Proxy

### Step 3.1 — PostgreSQL and Redis

```bash
systemctl status podman-postgres
systemctl status podman-redis

# Verify connectivity
podman exec postgres psql -U postgres -c '\l'
podman exec redis redis-cli ping   # returns PONG
```

### Step 3.2 — Gitea

```bash
systemctl status podman-gitea

# Migrate monorepo from temporary location
git remote add homelab https://git.internal.tongatime.us/taylor/nixos-config.git
git push homelab main
```

**Verify:** `https://git.internal.tongatime.us` accessible with valid cert.
Monorepo visible and all history intact.

### Step 3.3 — Gitea Actions Runner

```bash
# Runner is ephemeral Podman container launched by Gitea
# Verify by pushing a test commit and watching pipeline execute
git commit --allow-empty -m "test: verify CI pipeline"
git push homelab main
```

**Verify:** Pipeline runs. `nix flake check` passes. Build succeeds. No secrets leaked in logs.

### Step 3.4 — Authentik

```bash
systemctl status podman-authentik

# Apply Authentik resources (OIDC clients, LDAP sync)
cd tofu/authentik && tofu apply
```

**Verify:** `https://auth.internal.tongatime.us` accessible. Login with FreeIPA credentials succeeds.
Gitea "Login with Authentik" button appears and works.

### Step 3.5 — Vaultwarden

```bash
systemctl status podman-vaultwarden
```

**Verify:** `https://vault.internal.tongatime.us` accessible. Login works.
All existing credentials migrated and accessible via Bitwarden-compatible browser extension.

### Step 3.6 — Nextcloud

```bash
systemctl status podman-nextcloud

# Verify ZFS dataset is mounted
zfs list tank/nextcloud/data   # should show used/available
```

**Verify:** `https://nextcloud.internal.tongatime.us` accessible. Login works.
Desktop sync client connects. A test file syncs successfully.

### Step 3.7 — attic Binary Cache

```bash
systemctl status podman-attic

# Initialize the cache
attic login homelab https://cache.internal.tongatime.us <token>
attic cache create homelab
```

**Verify:** `nix build .#nixosConfigurations.desktop.config.system.build.toplevel`
pushes results to attic. A second machine can substitute from the cache (build skipped).

### Step 3.8 — Renovate Bot

```bash
systemctl status podman-renovate   # scheduled, may not be active

# Trigger manually to verify
podman run --rm renovate/renovate renovate --dry-run tongatime/nixos-config
```

**Verify:** Dry run shows updates found. PRs opened on next scheduled run. No secrets in PR bodies.

### Step 3.9 — Structurizr

```bash
systemctl status podman-structurizr
```

**Verify:** `https://arch.internal.tongatime.us` accessible. C4 diagrams rendering from DSL.

---

## Stage 4: VM3 — Observability

VM3 must watch VM1 and VM2 from isolation.
Deploy it fully before declaring the previous stages "done."

### Step 4.1 — Loki

```bash
systemctl status podman-loki

# Verify it is receiving journald from VM1 and VM2
# (Promtail or Loki's journald scraper must be configured on those VMs)
curl http://localhost:3100/ready   # returns "ready"
```

**Verify:** Logs from VM1 and VM2 visible in Grafana Explore. FreeIPA auth events searchable.

### Step 4.2 — Prometheus

```bash
systemctl status podman-prometheus

# Check scrape targets
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[].scrapeUrl'
```

**Verify:** All declared scrape targets show `state: up`. No targets in `down` state.

### Step 4.3 — Grafana and Alertmanager

```bash
systemctl status podman-grafana
systemctl status podman-alertmanager
```

**Verify:** `https://grafana.internal.tongatime.us` accessible via Authentik SSO.
Loki and Prometheus datasources both healthy. At least one alert rule active.

### Step 4.4 — tlog End-to-End Test

```bash
# From laptop or desktop
ssh taylor@vm2.internal.tongatime.us   # via ProxyJump through VM1
echo "tlog test command"
exit

# In Grafana Explore (Loki datasource)
# Query: {job="systemd-journal", syslog_identifier="tlog"}
# Should show the session with the test command visible
```

**Verify:** Session recorded on VM1 (ProxyJump hop) AND on VM2 (target). Both entries visible in Loki.
Session replay works. Timing and command output are accurate.

---

## Stage 5: VM4 — DMZ Services

VM4 is the lowest priority and can be started at any time after the network is up.
It operates independently — no identity or observability dependencies for basic function.

### Step 5.1 — Start VM4

```bash
virsh start vm4

# Verify it is in VLAN 60
# From VM4, ping VM1 — should FAIL (VLAN firewall)
# From VM4, curl https://external-site.com — should succeed (internet access)
```

### Step 5.2 — Game Servers (on demand)

Deploy game server containers as needed. Each gets a Caddy proxy entry on the Oracle VPS.

```bash
# Example: Minecraft
systemctl start podman-minecraft

# Oracle VPS Caddy forwards mc.tongatime.us:25565 → VM4:25565
# Verify: connect from external client using mc.tongatime.us
```

---

## Stage 6: Desktop Migration

Do not begin until VM1, VM2, and VM3 are fully verified.

### Step 6.1 — Pre-migration

- [ ] Audit all NTFS drives for data that needs to survive
- [ ] Back up game saves not on Steam Cloud to Nextcloud
- [ ] Verify Nextcloud has received all critical files
- [ ] Document current BIOS settings

### Step 6.2 — NixOS Install

```bash
# Boot NixOS installer from USB
nixos-generate-config --root /mnt
# Copy generated hardware.nix to repo at hosts/desktop/hardware.nix
nixos-install --flake .#desktop
```

### Step 6.3 — Post-install Verification

```bash
# Enroll in FreeIPA
id taylor        # returns FreeIPA identity
sudo whoami      # works via FreeIPA sudo rule

# Verify Headscale enrollment
tailscale up --login-server https://hs.tongatime.us

# Verify Nextcloud sync
# Open Nextcloud client, log in, confirm sync starts

# Verify gaming stack
steam &          # launches
# Run a game, verify Proton-GE works, MangoHUD overlay visible

# Verify Sunshine streaming
# Connect from laptop Moonlight, verify stream
```

**Impermanence discovery pass:** Run for one week. Note any state that resets unexpectedly.
Add discovered paths to the persistence list in `hosts/desktop/default.nix`.

---

## Stage 7: Laptop Migration

Do not begin until desktop migration is verified complete.

### Step 7.1 — Pre-migration

- [ ] Replacement battery installed and confirmed working
- [ ] All Windows data backed up (documents, browser profiles)
- [ ] Verify nixos-hardware T15 Gen1 module name

### Step 7.2 — NixOS Install

```bash
nixos-generate-config --root /mnt
# Copy hardware.nix to hosts/laptop/hardware.nix
nixos-install --flake .#laptop
```

### Step 7.3 — Post-install Verification

```bash
# Display scaling
# Verify: 1.25x scaling active, fonts readable, no blurry rendering

# Fingerprint enrollment
fprintd-enroll taylor
fprintd-verify taylor

# WiFi
nmcli device wifi connect <SSID>   # connects to VLAN 30 SSID

# Battery
upower -i $(upower -e | grep battery)   # shows health stats
# Verify hibernate at 10% threshold by draining to near-threshold (or manually test)

# Enroll in FreeIPA and Headscale (same as desktop)

# Moonlight
# Open Moonlight, add desktop as host, verify stream quality
```

**Impermanence discovery pass:** One week, same as desktop.

---

## Stage 8: Hardening and Final Verification

### Step 8.1 — Break-Glass Drill

```bash
# Simulate VM1 being completely unavailable
virsh stop vm1

# From laptop, using only break-glass USB materials:
# 1. Edit /etc/hosts to use static IPs
# 2. SSH to VM2 using break-glass key and emergency local account
# 3. SSH to physical host using break-glass key

# Restart VM1 and verify everything recovers
virsh start vm1
```

**Verify:** Can reach every VM and the physical host without FreeIPA, SSSD, or DNS.
Document any gaps found and update ADR-006 and break-glass USB content.

### Step 8.2 — Backup Verification

```bash
# Trigger manual backup
systemctl start gitea-actions-backup   # or however the backup job is invoked

# Verify Google Drive received the encrypted blob
# Attempt restore from Google Drive to a test VM
```

**Verify:** Restore succeeds. All data intact. Decryption with the age key on break-glass USB works.

### Step 8.3 — Security Checklist

- [ ] All Headscale ACLs tested (Oracle VPS cannot reach VM1/VM2)
- [ ] All VLAN rules verified (IoT device cannot ping desktop)
- [ ] tlog recording verified on all hosts
- [ ] All open ports match PORT_REFERENCE.md
- [ ] Renovate opened a PR and it merged successfully
- [ ] No plaintext secrets in Gitea repo (`git log --all -p | grep -i password` returns nothing)
- [ ] iDRAC firmware is current
- [ ] All Let's Encrypt certificates valid and auto-renewing

---

## Recovery Procedures

### If VM1 is unresponsive

1. Connect to iDRAC at `idrac.internal.tongatime.us` (VLAN 10)
2. Use KVM-over-IP to get console access
3. If VM1 OS is broken: `virsh destroy vm1 && virsh start vm1`
4. If physical host is broken: use iDRAC virtual media to boot NixOS installer
5. If DNS is broken before SSH is available: add static entries to `/etc/hosts` on
   personal machine using VLAN 20 IPs from PORT_REFERENCE.md

### If a personal machine cannot authenticate (FreeIPA down)

SSSD credential cache covers offline login for the laptop.
For the desktop, the local emergency account bypasses FreeIPA:

```bash
ssh -i /path/to/break-glass-key emergency@<static-ip>
```

### If the monorepo is corrupted or lost

The Gitea repo is the primary. Break-glass USB contains a clone.
To restore: `git clone` from USB, push to a new Gitea instance, redeploy.
