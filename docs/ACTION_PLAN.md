# Action Plan

> Phased implementation plan for the tongatime.us infrastructure.
> Each phase has a clear completion criteria. Nothing in a later phase
> begins until the current phase's criteria are verified.
> Cross-reference: docs/DECISIONS.md for AI- item tracking.

---

## Phase 0 — Documentation Foundation
*Start immediately. No hardware required.*

**Goal:** Complete knowledge base exists before any code is written.
Claude Code is context-aware from first session.

| Step | Task | Deliverable | AI Item |
|------|------|-------------|---------|
| 0.1 | Install Obsidian, create vault at `~/wiki/` | Vault exists | — |
| 0.2 | Install plugins: Dataview, Templater, Git, Excalidraw, Mermaid | All plugins active | — |
| 0.3 | Break PROJECT_RULES.md into ~60 atomic notes | Vault folder structure populated | — |
| 0.4 | Break DECISIONS.md into one note per ADR | 19 ADR files, all OQs, all FCs | — |
| 0.5 | Add YAML frontmatter to all service and ADR notes | Dataview queries return results | — |
| 0.6 | Create Dataview queries (pending items, open questions, decided ADRs) | All queries return correct data | — |
| 0.7 | Write Structurizr DSL in `docs/architecture/workspace.dsl` | Renders in Structurizr Lite locally | — |
| 0.8 | Write `CLAUDE.md` in monorepo root | File committed to temporary repo | — |
| 0.9 | Install Claude Code terminal CLI | `claude --version` works | — |
| 0.10 | Install llm-wiki-compiler plugin in Claude Code | `/wiki-init` command available | — |
| 0.11 | Install ekadetov/llm-wiki plugin in Claude Code | `/llm-wiki:wiki init` available | — |
| 0.12 | Ingest all documentation into wiki, compile | Wiki pages generated, graph view populated | — |

**Completion criteria:** Asking Claude Code "what port does Authentik use?" returns
the correct answer by reading the compiled wiki. Obsidian graph view shows >40 connected nodes.

---

## Phase 1 — Repository Bootstrap
*Start immediately alongside Phase 0. No hardware required.*

**Goal:** Monorepo exists with correct structure, scaffold configs, and CI pipeline stub.

| Step | Task | Deliverable | AI Item |
|------|------|-------------|---------|
| 1.1 | Create monorepo on temporary Gitea or GitHub | Repo exists with initial commit | — |
| 1.2 | Write `flake.nix` with all inputs declared | `nix flake check` passes on empty config | — |
| 1.3 | Create `hosts/` directory with stub configs for all 6 hosts | `nix eval .#nixosConfigurations` lists all | — |
| 1.4 | Create `modules/` directory structure matching declared layering | Directory skeleton committed | — |
| 1.5 | Write `lib/mkHost.nix` skeleton | Tags system compiles, no modules yet | — |
| 1.6 | Create `home/taylor/` with placeholder files | Home Manager evaluates without error | — |
| 1.7 | Write `renovate.json` covering flake inputs and container digests | File committed, ready for Gitea | AI-013, AI-014 |
| 1.8 | Write `tofu/` directory structure with backend config pointing at MinIO | `tofu init` succeeds (MinIO not live yet; expect backend error) | — |
| 1.9 | Write Cloudflare DNS records in `tofu/dns/` for public zone | `tofu plan` shows all public records | — |
| 1.10 | Write `modules/core/ssh.nix` (OpenSSH hardening) | Applies cleanly to a test config | — |
| 1.11 | Write `modules/core/ssh-recording.nix` (tlog via SSSD) | Applies cleanly to a test config | AI-038 |
| 1.12 | Write `secrets/.sops.yaml` with host age key stubs | sops-nix evaluates without error | — |
| 1.13 | Set up branch protection on `main`, PR requirement | Gitea branch rules active | — |

**Completion criteria:** `nix flake check` passes. All 6 hosts evaluate. `tofu plan`
shows expected DNS records. Repository structure matches CLAUDE.md exactly.

---

## Phase 2 — Physical Homelab Preparation
*Requires hardware procurement. Run in parallel with Phases 0 and 1.*

**Goal:** Physical hardware is ready to receive NixOS. Network segmentation enforced.

| Step | Task | Deliverable | AI Item |
|------|------|-------------|---------|
| 2.1 | Procure managed switch, OPNsense hardware, VLAN-capable AP | Hardware in hand | AI-004 |
| 2.2 | Verify iDRAC6 Express vs Enterprise on C2100 | Known iDRAC variant | AI-001 |
| 2.3 | Source iDRAC6 Enterprise card if needed | Enterprise card installed | AI-002 |
| 2.4 | Configure OPNsense with all 6 VLANs and inter-VLAN firewall rules | All VLAN rules match PORT_REFERENCE.md | — |
| 2.5 | Configure managed switch with VLAN trunks | Correct VLAN tagging verified | — |
| 2.6 | Configure wireless AP: Trusted (30), IoT (40), Guest (50) SSIDs | Devices connect to correct VLANs | — |
| 2.7 | Connect iDRAC NIC to VLAN 10 port | iDRAC web UI reachable from VLAN 30 only | AI-003 |
| 2.8 | Boot C2100 from NixOS installer, create ZFS RAIDZ2 pool | `zpool status tank` shows ONLINE | AI-012 |
| 2.9 | Define ZFS dataset layout (vms, nextcloud, backups, services) | All datasets created with correct mountpoints | AI-012 |
| 2.10 | Install NixOS on physical host, apply host config from repo | Host boots to NixOS, ZFS pool imported | — |
| 2.11 | Verify 4 VM definitions appear via `virsh list --all` | All 4 VMs in stopped state | — |

**Completion criteria:** All VLANs isolated and verified. Physical host boots NixOS.
iDRAC KVM-over-IP works from VLAN 30. `virsh list --all` shows 4 stopped VMs.

---

## Phase 3 — VM1: Network and Identity
*Requires Phase 2 complete. This phase blocks everything else.*

**Goal:** DNS, identity, Kerberos, and mesh VPN are operational. No other VM starts first.

| Step | Task | Deliverable | AI Item |
|------|------|-------------|---------|
| 3.1 | Start VM1, apply NixOS config | VM1 boots, SSSD active | — |
| 3.2 | Deploy Headscale, enroll all peers | All machines show in `tailscale status` | — |
| 3.3 | Apply Headscale ACL policy via OpenTofu | Oracle VPS cannot reach VM1/VM2 (verified) | AI-017 |
| 3.4 | Deploy FreeIPA container, apply identity resources via OpenTofu | `kinit taylor@TONGATIME.US` succeeds | — |
| 3.5 | Verify SSSD on VM1 and first personal machine | `id taylor` returns FreeIPA identity | — |
| 3.6 | Configure FreeIPA DNS for all internal hostnames | All `*.internal.tongatime.us` resolve | AI-006 |
| 3.7 | Update DHCP on each VLAN to hand out VM1 as DNS resolver | Internal DNS works on all VLANs | — |
| 3.8 | Apply Cloudflare DNS records via OpenTofu | Public records live, internal inaccessible from outside | — |
| 3.9 | Deploy Caddy on VM1, verify DNS-01 cert issuance | `ipa.internal.tongatime.us` loads with valid cert | — |
| 3.10 | Configure Oracle VPS Caddy to proxy `hs.tongatime.us` → VM1 | Headscale coordination works externally | — |

**Completion criteria:** Taylor can log into VM1 via FreeIPA Kerberos. All internal
hostnames resolve. FreeIPA web UI accessible. Oracle VPS peer cannot reach VM1 directly.
tlog recording visible in journald after an SSH session.

---

## Phase 4 — OpenTofu Remote State
*Requires Phase 3, Step 3.1 (VM2 minimal start).*

**Goal:** OpenTofu state stored in MinIO. No state file in the repository ever.

| Step | Task | Deliverable | AI Item |
|------|------|-------------|---------|
| 4.1 | Start VM2 with only MinIO declared (all other services commented out) | MinIO accessible at VM2 IP:9000 | — |
| 4.2 | Create `tofu-state` bucket in MinIO | Bucket exists, accessible | — |
| 4.3 | Migrate all OpenTofu modules to MinIO backend | `tofu state list` works from clean checkout | AI-005 (state backend) |
| 4.4 | Verify no local `terraform.tfstate` files exist in repo | `git ls-files | grep tfstate` returns nothing | — |

**Completion criteria:** `tofu plan` in any module works with no local state file.
State is accessible from both personal machines via Headscale.

---

## Phase 5 — VM2: Application Services
*Requires Phase 4 complete.*

**Goal:** All application services operational. Monorepo migrated to self-hosted Gitea.

| Step | Task | Deliverable | AI Item |
|------|------|-------------|---------|
| 5.1 | Deploy PostgreSQL and Redis | Both containers healthy, connectivity verified | — |
| 5.2 | Deploy Gitea, migrate monorepo | `git.internal.tongatime.us` accessible, all history intact | — |
| 5.3 | Deploy Gitea Actions runner (ephemeral Podman + socket proxy) | Test push triggers pipeline | AI-018 |
| 5.4 | Configure Renovate bot user in FreeIPA/OpenTofu | `renovate` user exists with scoped access | AI-013 |
| 5.5 | Deploy Renovate, verify first PR opened | At least one update PR created | AI-014 |
| 5.6 | Deploy Authentik, apply OpenTofu resources | SSO works for Gitea | — |
| 5.7 | Migrate Vaultwarden, verify all credentials accessible | All credentials present and correct | — |
| 5.8 | Deploy Nextcloud with 1TB ZFS dataset | Sync client connects, test file syncs | AI-028 |
| 5.9 | Deploy attic binary cache | Build pipeline pushes to cache, substitution works | — |
| 5.10 | Deploy ntfy.sh on VM2, configure Alertmanager receivers for 3 severity topics | Test alert received on phone within 10s | — |
| 5.11 | Configure MinIO buckets: tofu-state/, gitea-artifacts/, loki-chunks/, backups/ | All buckets created with per-bucket ACLs | — |
| 5.12 | Deploy Structurizr Lite with DSL from Phase 0.7 | C4 diagrams render at `arch.internal.tongatime.us` | — |
| 5.13 | Enable all remaining VM2 services in NixOS | All VM2 services operational | — |

**Completion criteria:** All services accessible via internal hostnames with valid certs.
Full Gitea pipeline runs end-to-end. Authentik SSO works for all registered applications.

---

## Phase 6 — VM3: Observability
*Requires Phase 5 complete. VM3 must watch VM1 and VM2 from isolation.*

**Goal:** Full observability pipeline operational. Every service visible in Grafana.

| Step | Task | Deliverable | AI Item |
|------|------|-------------|---------|
| 6.1 | Deploy Loki with Medallion pipeline configuration | Journald logs from VM1 and VM2 visible | — |
| 6.2 | Configure Loki to use MinIO `loki-chunks/` bucket for chunk storage | Loki chunks flowing to MinIO | — |
| 6.3 | Configure tlog Bronze layer with 90-day retention | tlog entries visible in Loki | AI-041 |
| 6.4 | Configure Silver-layer pipeline stages (parse tlog JSON fields) | User, hostname, session_id fields indexed | AI-040 |
| 6.5 | Deploy Prometheus with all scrape targets | All targets show `state: up` | — |
| 6.6 | Write Gold-layer recording rules for alerts | Derived metrics visible in Prometheus | — |
| 6.7 | Deploy Grafana + Alertmanager | Grafana accessible via Authentik SSO | — |
| 6.8 | Import baseline dashboards (FreeIPA, Caddy, system metrics, tlog, MinIO) | All dashboards populated with data | — |
| 6.9 | Deploy VictoriaMetrics, Alertmanager, ntfy.sh on Oracle VPS (ADR-021) | All three services running, <200MB RAM total | — |
| 6.10 | Configure VM3 Prometheus remote_write to VPS VictoriaMetrics | Metrics visible in VPS VM API | — |
| 6.11 | Write DeadMansSwitch alert rule on VM3, configure VPS Alertmanager heartbeat | Stop VM3, confirm MonitoringDown fires within 3 minutes | — |
| 6.12 | Configure VM3 Alertmanager dual routing: VM2 ntfy.sh + VPS ntfy.sh | Alerts arrive on both paths simultaneously | — |
| 6.13 | Add ntfy.tongatime.us Cloudflare record via OpenTofu | Public ntfy.sh accessible externally | — |
| 6.14 | Subscribe personal devices to VPS ntfy.sh topics (in addition to VM2) | Devices receive from both ntfy.sh instances | — |
| 6.15 | Configure Alertmanager ntfy.sh webhook receivers for 3 severity topics | Test alert received on phone via both paths | — |
| 6.16 | Test VM2 failure: stop VM2, confirm alerts still arrive via VPS | VPS ntfy.sh delivers independently | — |
| 6.17 | Write at least 5 alert rules with `for:` clauses | Alertmanager shows active rules | — |

**Completion criteria:** SSH to any VM, confirm the session appears in Grafana within
60 seconds. All scrape targets healthy. At least one alert rule active and tested.

---

## Phase 7 — tlog SSH Hardening (All Hosts)
*Requires Phase 6 complete (Loki must be receiving logs before tlog is declared operational).*

**Goal:** Every SSH session on every host is recorded and visible in Grafana.

| Step | Task | Deliverable | AI Item |
|------|------|-------------|---------|
| 7.1 | Deploy `modules/core/ssh-recording.nix` to all VMs via deploy-rs | tlog active on VM1, VM2, VM3, VM4 | AI-038 |
| 7.2 | Add journald state to impermanence persistence list | tlog state survives reboots | AI-039 |
| 7.3 | Deploy ProxyJump SSH config to both personal machines via Home Manager | `ssh vm2` routes via VM1 automatically | AI-042 |
| 7.4 | End-to-end test: SSH to VM2, verify double recording in Grafana | Both VM1 and VM2 recordings visible | AI-043 |

**Completion criteria:** Every SSH session on every enrolled host is recorded.
Double-recording (VM1 jump + target VM) confirmed. Sessions searchable by username in Grafana.

---

## Phase 8 — Desktop Migration
*Requires Phase 7 complete. Do not begin until all homelab services are verified operational.*

**Goal:** Desktop runs NixOS with full declared configuration.

| Step | Task | Deliverable | AI Item |
|------|------|-------------|---------|
| 8.1 | Audit NTFS drives, document what needs to survive | Audit document committed | AI-023 |
| 8.2 | Back up game saves not on Steam Cloud to Nextcloud | Saves confirmed in Nextcloud | AI-021 |
| 8.3 | Generate Ed25519 break-glass keys, add to FreeIPA | Keys committed to persistence list | AI-005 |
| 8.4 | Install NixOS on desktop, apply host config | Desktop boots NixOS, FreeIPA enrolled | — |
| 8.5 | Format 1.82TB HDD as ext4, declare mount in NixOS | `/mnt/overflow` accessible | AI-024 |
| 8.6 | Verify gaming stack: Steam, Proton-GE, MangoHUD, gamescope | Game launches with overlay visible | — |
| 8.7 | Verify three monitors: KScreen profiles, HDR on 1440p | All displays at correct resolution and refresh | — |
| 8.8 | Deploy Sunshine, test stream from laptop | Moonlight connects, stream is smooth | AI-031 |
| 8.9 | Enroll in Headscale, verify Headscale ACLs apply | Desktop tagged correctly | — |
| 8.10 | Configure rclone + age backup to Google Drive | First backup completes and is verified | AI-029 |
| 8.11 | Run one-week impermanence discovery pass | Persistence list stable, no unexpected resets | AI-027 |

**Completion criteria:** Desktop is the daily driver. All peripherals work. Gaming stack
verified with a real game. Impermanence discovery pass complete with no lingering issues.

---

## Phase 9 — Laptop Migration
*Requires Phase 8 complete.*

**Goal:** Laptop runs full NixOS. Windows permanently removed.

| Step | Task | Deliverable | AI Item |
|------|------|-------------|---------|
| 9.1 | Order and install replacement battery | Battery health >80%, runtime >4 hours | AI-019 |
| 9.2 | Back up all Windows data | All data confirmed in Nextcloud or elsewhere | AI-020 |
| 9.3 | Verify nixos-hardware T15 Gen1 module name | Correct module documented | AI-035 |
| 9.4 | Install NixOS on laptop, import nixos-hardware module | Laptop boots, hardware module applies | AI-036 |
| 9.5 | Audit nixos-hardware module coverage, document gaps | Gaps declared in `hosts/laptop/hardware.nix` | AI-037 |
| 9.6 | Enroll fingerprint reader | `fprintd-verify taylor` succeeds | AI-026 |
| 9.7 | Verify display scaling 1.25x | Text readable, no blurry rendering |  — |
| 9.8 | Verify WiFi and power management | Battery life improved over Windows |  — |
| 9.9 | Install Moonlight, test stream from desktop | Stream works from outside home network (via Headscale) | AI-032 |
| 9.10 | Enroll in FreeIPA and Headscale | `id taylor` returns FreeIPA identity | — |
| 9.11 | Run one-week impermanence discovery pass | Persistence list stable | AI-027 |

**Completion criteria:** Laptop is the daily mobile driver. Offline login works without
network access. Fingerprint auth works at SDDM and sudo. Moonlight streams from
anywhere via Headscale.

---

## Phase 10 — Hardening and Final Verification
*Requires Phases 8 and 9 complete.*

**Goal:** Security posture fully verified. Break-glass confirmed working. Backups restored.

| Step | Task | Deliverable | AI Item |
|------|------|-------------|---------|
| 10.1 | Populate and encrypt offline break-glass USB | USB contains all required materials | AI-007 |
| 10.2 | Write bootstrap procedure document | Documented, committed to `docs/` | AI-008 |
| 10.3 | Conduct break-glass drill: disable VM1, recover from laptop | Recovery successful using only USB materials | AI-009 |
| 10.4 | Full restore test from Google Drive | All data recovered correctly | AI-030 |
| 10.5 | Security audit: all ports match PORT_REFERENCE.md | Zero undocumented open ports | — |
| 10.6 | Security audit: Headscale ACLs tested | Oracle VPS cannot reach VM1/VM2 confirmed | — |
| 10.7 | Security audit: no plaintext secrets in repo | `git log --all -p | grep -i password` clean | — |
| 10.8 | Verify Renovate PR merged end-to-end | Full pipeline: PR → CI → merge → deploy | — |
| 10.9 | Source libfprint USB fingerprint reader for desktop | Reader enrolled and working | AI-022 |

**Completion criteria:** Break-glass drill succeeded. Backup restore succeeded.
All security audits pass. The system can be handed to Claude Code with CLAUDE.md
and every question answered from the wiki.

---

## Phase 11 — Ongoing Operations
*No completion criteria — continuous.*

| Task | Trigger | AI Item |
|------|---------|---------|
| Purchase Nitrokey FIDO2, enroll in Authentik | System operational | AI-025 |
| Resolve OQ-007: Work AD trust configuration | Starting new job / AD environment | — |
| Resolve OQ-003: Alerting target | Before completing Phase 6.8 | — |
| Resolve OQ-004: iDRAC verification | Before Phase 2.7 | AI-001 |
| Monitor Apollo/Artemis for Linux client | Ongoing | AI-033 |
| Observe Headscale DERP need after 30 days | 30 days post Phase 3.2 | AI-016 |
| Evaluate mDNS reflector for VLAN 40 | After Phase 2.6 | AI-015 |
| HA second machine for FreeIPA replica | When hardware budget allows | — |

---

## Dependency Graph (phases)

```
Phase 0 (docs)  ──┐
Phase 1 (repo)  ──┤── Phase 3 (VM1) ──── Phase 4 (state backend)
Phase 2 (hw)    ──┘         │
                             └────────── Phase 5 (VM2)
                                              │
                                         Phase 6 (VM3)
                                              │
                                         Phase 7 (tlog)
                                              │
                                         Phase 8 (desktop)
                                              │
                                         Phase 9 (laptop)
                                              │
                                         Phase 10 (hardening)
                                              │
                                         Phase 11 (ongoing)
```

Phases 0, 1, and 2 can run fully in parallel.
Phase 3 is the critical path bottleneck — nothing else can proceed until it is complete.
