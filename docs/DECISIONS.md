# Architecture Decision Records

> One entry per significant decision. Format: context, the decision, the rationale, and any known tradeoffs or follow-up actions.
> Decisions are append-only. If a decision is reversed, add a new entry referencing the old one — do not delete history.

---

## ADR-001: Headscale over Tailscale

**Date:** 2026-04-17
**Status:** Decided

**Context:**
Tailscale is the current overlay VPN connecting all personal machines. It is a managed, proprietary service with a freemium model. A FOSS self-hosted alternative exists: Headscale, which reimplements the Tailscale control plane and is compatible with all Tailscale clients.

**Decision:**
Migrate from Tailscale to Headscale as the WireGuard mesh control plane.

**Rationale:**
- Headscale is fully FOSS and self-hosted, satisfying the project's 1.1 principle.
- The primary feature lost by leaving Tailscale is the DERP relay network (Tailscale's global relay infrastructure for NAT traversal when direct WireGuard connections cannot be established). This is an acceptable loss — direct connections are preferred and the homelab has a stable public IP via the Oracle VPS if a relay is ever needed.
- Headscale is sufficiently mature for personal/homelab use.
- All existing Tailscale clients (Linux, Windows, iOS, Android) work with a Headscale control plane with no client changes beyond pointing at the self-hosted coordination URL.

**Tradeoffs:**
- DERP relay fallback is lost. Connections that previously fell back to Tailscale's relays will need direct routes or a self-hosted DERP node if that becomes a problem.
- Headscale is not feature-identical to Tailscale — some newer Tailscale features (e.g., app connectors, certain ACL extensions) may not be implemented yet.
- Operational burden of running the control plane falls on the homelab. If the Headscale node is unreachable, new peers cannot join, but existing connections continue.

**Follow-up:**
- Deploy Headscale as a Podman container on the homelab network infrastructure VM.
- Declare Headscale config in NixOS via OpenTofu.
- Evaluate whether a self-hosted DERP node is needed after observing real-world connection reliability.

---

## ADR-002: Renovate Bot for Automated Dependency Updates

**Date:** 2026-04-17
**Status:** Decided

**Context:**
The project requires automated detection of upstream updates (NixOS flake inputs, container image digests, package versions) with automatic pull request creation including changelogs. The security rules (6.4) mandate this as a hard requirement.

**Decision:**
Use **Renovate Bot** (self-hosted) as the automated dependency update and PR creation tool.

**Rationale:**
- Renovate is fully FOSS (BUSL for the hosted version, Apache 2.0 for the self-hosted runner).
- It has native support for Nix flake inputs, container image digests (OCI), and general package ecosystems.
- It integrates directly with Gitea via its Gitea platform driver.
- PRs include changelogs, release notes, and links to upstream diffs — exactly the required behavior.
- Highly configurable: update schedules, automerge rules for patch-level changes, grouping of related updates, and branch naming conventions are all declarable in `renovate.json`.
- Runs as a scheduled job (Gitea Actions cron or a Podman container with a timer).

**Tradeoffs:**
- Renovate's Nix support is good but not perfect — some obscure input types may require custom datasource configuration.
- Requires a Gitea bot user account with write access to open PRs.
- Configuration can become complex for large monorepos; start simple and extend.

**Follow-up:**
- Deploy Renovate as a Podman container on the homelab, scheduled nightly.
- Create a `renovate` Gitea bot user, declare it in OpenTofu/FreeIPA.
- Commit a `renovate.json` to the monorepo root covering: NixOS flake inputs, container digests, and any other package ecosystems in scope.
- Configure automerge for patch-level container digest bumps with passing CI. Major/minor updates always require manual PR review.

---

## ADR-003: VLAN Network Segmentation

**Date:** 2026-04-17
**Status:** Decided

**Context:**
The home network currently has no enforced segmentation. All devices — personal machines, IoT devices, homelab servers, and guests — share the same L2 broadcast domain. This means a compromised IoT device or guest machine has direct network-layer access to the homelab and identity infrastructure. As the homelab grows to host critical services (FreeIPA, Vaultwarden, Authentik), this is not an acceptable risk posture.

**Decision:**
Segment the physical network into six VLANs enforced by a managed switch and an OPNsense (or equivalent) router with stateful inter-VLAN firewall rules:

- VLAN 10 — Management (router, switch, IPMI/BMC, hypervisor control plane)
- VLAN 20 — Infrastructure (homelab VMs and services)
- VLAN 30 — Trusted / Private (personal machines, trusted devices)
- VLAN 40 — IoT (smart home, printers, consumer devices)
- VLAN 50 — Guest (visitor devices, internet only)
- VLAN 60 — DMZ / Public Servers (services that accept inbound internet connections)

Inter-VLAN routing is restricted by a default-deny firewall policy. All permitted flows are declared explicitly. Full routing table is documented in PROJECT_RULES.md Section 10.5.

Within each VM on VLAN 20, Podman networks provide a second layer of container-to-container isolation. VLAN adjacency does not imply container-level access.

**Rationale:**
- Isolates the most sensitive infrastructure (identity, secrets, monitoring) from user devices and IoT.
- Contains blast radius — a compromised IoT device or guest machine cannot reach the homelab.
- Provides a clean DMZ for any services that require public inbound access, with no path to the infrastructure VLAN.
- Management VLAN with no internet access and admin-only entry prevents network device compromise from being a pivot point.
- Podman network layering within VMs means even services on the same VM are not automatically mutually accessible.

**Tradeoffs:**
- Requires a managed switch and a router capable of inter-VLAN routing with firewall policy (OPNsense or equivalent). Basic consumer routers do not support this.
- Initial setup complexity is higher than a flat network. Ongoing maintenance requires updating firewall rules when new services are added.
- Some IoT devices behave poorly when isolated from the local network (e.g., mDNS-dependent devices). This can be addressed with an mDNS reflector/proxy scoped to declared VLAN pairs.

**Follow-up:**
- Select and deploy a managed switch and OPNsense (or equivalent) router.
- Declare VLAN and firewall config in OPNsense via OpenTofu (OPNsense has an API-driven provider).
- Configure wireless AP with VLAN tagging (separate SSIDs for Trusted, IoT, and Guest).
- Evaluate mDNS reflector need after initial VLAN deployment.

---

## ADR-004: Homelab VM Separation Strategy

**Date:** 2026-04-17
**Status:** Decided

**Context:**
The homelab runs multiple services with different trust levels, update frequencies, and availability requirements. Running all services on a single host OS with no isolation means a misconfigured service, a runaway process, or a bad update can affect every other service simultaneously. There is also no clean way to reboot for a kernel update without taking everything down at once.

**Decision:**
Separate homelab services across four NixOS VMs on a single physical host, managed via KVM/QEMU declared through the NixOS `virtualisation` module:

- VM1 — Network & Identity: Headscale, FreeIPA, internal DNS, Caddy. Lives on VLAN 20.
- VM2 — Application Services: Gitea, Authentik, Vaultwarden, Nextcloud, Renovate, attic. Lives on VLAN 20.
- VM3 — Observability: Grafana, Loki, Prometheus, Alertmanager. Lives on VLAN 20.
- VM4 — User/Public Services: Game servers, public-facing services. Lives on VLAN 60 (DMZ).

**Rationale:**
- **Dependency isolation:** VM1 (identity and DNS) can be kept stable while VM2 (application services) is updated frequently. A reboot of VM2 does not interrupt authentication.
- **Blast radius containment:** A compromised or broken service in one VM cannot directly affect services in another VM.
- **Observability correctness:** VM3 (monitoring) must be separated from what it monitors. Monitoring co-located with VM2 would go dark precisely when VM2 has a problem — the worst time to lose visibility.
- **DMZ separation:** VM4 lives in VLAN 60 (DMZ) rather than VLAN 20. A compromise of a public-facing game server cannot reach the identity or application infrastructure.
- **Independent update cycles:** Each VM can be rebooted, snapshotted, and rolled back independently.

**What this does NOT provide:**
VMs on a single physical host do not protect against host hardware failure. If the physical server reboots or fails, all four VMs go down. This is accepted for now. The HA roadmap (see PROJECT_RULES.md Section 11.4) addresses this with a second physical machine running a FreeIPA replica and Headscale standby as the first milestone.

**Tradeoffs:**
- Four VMs adds operational overhead compared to running everything on bare metal. Mitigated by declaring all VM definitions in NixOS (no manual `virt-manager` state) and using deploy-rs to update VM guests the same way as physical hosts.
- Memory and CPU must be allocated across VMs. The dual-socket Xeon / 144GB DDR3 homelab has ample headroom for this workload.
- Cross-VM service dependencies (e.g., VM2 services authenticating against FreeIPA on VM1) must traverse the VLAN 20 network path. This is by design and is secured by the VLAN firewall and Headscale mesh.

**Follow-up:**
- Define VM NixOS configs in the monorepo under `hosts/vm1/`, `hosts/vm2/`, etc.
- Declare VM hardware specs (vCPU, RAM, disk, VLAN NIC) in the physical host's NixOS config.
- Migrate services from current homelab setup to VMs in dependency order: VM1 first, then VM3, then VM2, then VM4.
- Establish snapshot discipline before each migration step.

---

## ADR-005: OpenTofu Remote State Backend

**Date:** 2026-04-17
**Status:** Decided (closes OQ-009)

**Context:**
The monorepo is intentionally public (FOSS philosophy, community sharing goal). OpenTofu generates a `terraform.tfstate` file at apply time that contains plaintext values for everything provisioned: FreeIPA admin passwords, Authentik API keys, database credentials, and any other provider-returned secrets. If this file is committed to the public repo, those values are fully exposed. This is a critical finding from the external security review.

Unlike sops-nix secrets (where key names are visible but values are encrypted), tfstate exposure is total — values are plaintext JSON.

**Decision:**
MinIO (Apache 2.0) as the OpenTofu S3-compatible remote state backend. Deployed as a
rootless Podman container on VM2. OpenTofu state files are stored in a dedicated
`tofu-state` bucket. State never touches the Git repository.

MinIO is chosen as a **general-purpose S3-compatible object store** for the entire
infrastructure — not just OpenTofu state. All services that need object storage use
the same MinIO instance with bucket-level isolation:

```
MinIO buckets:
  tofu-state/       ← OpenTofu remote state (one key per workspace)
  gitea-artifacts/  ← Gitea Actions build artifacts and cache
  loki-chunks/      ← Loki log chunk storage (long-term retention)
  backups/          ← rclone backup staging before Google Drive push
  nextcloud/        ← Optional: Nextcloud external storage backend
```

**State locking:**
The OpenTofu S3 backend requires a DynamoDB-compatible table for state locking.
MinIO does not natively implement the DynamoDB API. Resolution: use the OpenTofu
`http` backend for locking via a lightweight locking endpoint, or deploy
`terraform-locks` (a minimal DynamoDB-compatible locking service). Decision on the
specific locking implementation is deferred to implementation — both approaches are
well-documented and do not affect the MinIO choice itself.

**Bootstrap procedure (chicken-and-egg):**
The first `tofu apply` in any module must be run with local state, then migrated:
1. Run `tofu init` without backend config (local state)
2. Run `tofu apply` to create MinIO bucket and locking infrastructure
3. Add backend config to `backend.tf`
4. Run `tofu init -migrate-state` to move state into MinIO
5. Confirm local state file is empty/removed
6. Add MinIO credentials to break-glass materials (ADR-006)

**Rationale:**
- MinIO is FOSS (Apache 2.0), self-hosted, and S3-compatible — works with OpenTofu's
  native S3 backend with no additional tooling.
- As a general-purpose object store, MinIO eliminates the need for separate storage
  solutions as the infrastructure grows. One service, multiple bucket consumers.
- Clean separation from application databases — IaC state should not share a
  PostgreSQL instance with Authentik or Gitea.
- Larger MinIO deployments support erasure coding and distributed mode if the
  homelab ever expands to multiple nodes.

**Tradeoffs:**
- MinIO is an additional service on VM2 with its own operational overhead.
  Mitigated by NixOS quadlet declaration and Renovate image updates.
- State locking requires either a DynamoDB-compatible sidecar or the http backend
  approach — adds minor complexity at bootstrap time.

**Follow-up:**
- Deploy MinIO on VM2 as a Podman quadlet unit with all bucket definitions.
- Document first-apply bootstrap procedure in BOOTSTRAP_SEQUENCE.md (Phase 4).
- Add MinIO root credentials to sops-nix and to break-glass materials.
- Configure per-bucket access policies (least-privilege per service).
- Add MinIO to Prometheus scrape targets and Grafana dashboard.

---

## ADR-006: Break-Glass Recovery Protocol

**Date:** 2026-04-17
**Status:** Pending — approach agreed, specifics not yet formalized or tested.

**Context:**
The infrastructure has a circular dependency chain: physical host -> VM1 (DNS + Identity) -> VM2 (Gitea) -> CI/CD -> Deployment. If VM1 is broken, FreeIPA is unavailable, which means SSSD authentication fails on all machines, SSH hostname resolution may fail, and the CI/CD pipeline cannot be used to push a fix. The recovery tools are locked behind the broken layer.

Each personal machine (desktop, laptop) must independently be capable of recovering the homelab without any homelab service running.

**Direction:**
Establish a formal, tested break-glass protocol with materials stored on each personal machine and on an offline encrypted USB.

**Components required (not yet finalized):**
1. Emergency local accounts on each VM and the physical host, declared in NixOS, bypassing FreeIPA/SSSD entirely. Credentials in Vaultwarden and on the break-glass USB.
2. Ed25519 SSH keys pre-authorized on each emergency account, stored on-disk on each personal machine — not only in FreeIPA.
3. Static IP fallback declared in NixOS (`networking.hosts`) on desktop and laptop, mapping VM hostnames to VLAN 20 IPs so DNS failure does not also break SSH.
4. Physical host VLAN 10 / iDRAC6 IP on the fallback list.
5. Offline encrypted USB containing: SSH private keys, Vaultwarden vault export, iDRAC credentials, break-glass procedure document, NixOS installer ISO.
6. Bootstrap procedure document: step-by-step "VM1 is completely gone, rebuild from scratch" that assumes no Gitea, no FreeIPA, no DNS, only a machine with the USB and a static IP.

**Unresolved:**
- Encryption method for the offline USB (LUKS? VeraCrypt? age-encrypted archive?).
- Testing cadence — quarterly drill proposed but not committed to.
- Whether static IP fallback should be always-on in `networking.hosts` or only activated manually. Always-on is safer (can't forget to enable it) but slightly noisy.
- Exact content checklist for the USB — not yet written.

**Follow-up:**
- Finalize USB encryption method.
- Write the bootstrap procedure document.
- Populate and test the USB against an actual simulated VM1 failure.
- Commit testing cadence to calendar.

---

## ADR-007: Headscale ACL Policy — Oracle VPS Isolation

**Date:** 2026-04-17
**Status:** Pending — policy structure agreed, not yet declared in OpenTofu.

**Context:**
The Oracle VPS is a full Headscale mesh peer. If it is compromised, a naive full-mesh configuration gives the attacker WireGuard-level access to every other peer on the mesh. The security review identified this as a high-severity lateral movement risk.

The requirement is that the Oracle VPS can forward any port (80, 443, 25565 for Minecraft, etc.) to the homelab, but can only route that traffic to VM4 (DMZ). It must have zero path to VM1, VM2, VM3, personal machines, or any other peer.

**Direction:**
Tag-based Headscale ACL with default-deny. The Oracle VPS is tagged `tag:dmz-proxy`. VM4 is tagged `tag:dmz-server`. The ACL explicitly permits only `tag:dmz-proxy` -> `tag:dmz-server` on any port. No other traffic from the VPS is permitted.

**Draft policy:**
```json
{
  "tagOwners": {
    "tag:dmz-proxy":  ["autogroup:admin"],
    "tag:dmz-server": ["autogroup:admin"],
    "tag:admin":      ["autogroup:admin"]
  },
  "acls": [
    {
      "action": "accept",
      "src":    ["tag:admin"],
      "dst":    ["*:*"]
    },
    {
      "action": "accept",
      "src":    ["tag:dmz-proxy"],
      "dst":    ["tag:dmz-server:*"]
    }
  ]
}
```

**Unresolved:**
- Headscale ACL format compatibility: Headscale's ACL support is close to but not identical to Tailscale's HuJSON policy format. Policy must be tested against the specific Headscale version deployed.
- Whether `tag:dmz-proxy` should be permitted to receive SSH from `tag:admin` for management, or whether all Oracle VPS management is handled out-of-band (Oracle Cloud console).
- OpenTofu Headscale provider support for ACL policy — needs verification; may require a file-based config approach instead.

**Follow-up:**
- Verify Headscale ACL format for deployed version.
- Decide Oracle VPS SSH management approach.
- Declare ACL policy in OpenTofu or as a NixOS-managed config file on VM1.
- Test: after policy applied, verify a machine tagged `tag:dmz-proxy` cannot ping VM1 or VM2.

---

## ADR-008: CI/CD Runner Isolation

**Date:** 2026-04-17
**Status:** Pending — approach agreed, not yet implemented.

**Context:**
The monorepo is public. Any person can open a pull request. The Gitea Actions runner executes on the homelab. If the runner is not properly isolated, a malicious PR could execute code in the homelab environment, potentially exfiltrating secrets or pivoting to internal services via the Headscale mesh.

Additionally, even for trusted contributors, a runner with excessive permissions is an unnecessary risk surface.

**Direction:**
- Runner executes in an ephemeral, unprivileged Podman container, launched fresh per job and destroyed after. No persistent state between jobs.
- Runner has no access to `sops-age-key`, no Headscale peer membership, and no direct path to internal services during the build/test phase.
- Build and test phase is pure Nix evaluation: `nix flake check`, build system toplevels, declared tests. Requires outbound internet access to binary cache and nixpkgs only.
- Deployment is a separate, privileged pipeline stage that runs only on protected branches (main) after build passes. Deploy SSH key is injected at runtime from Gitea's secret store, not present in the runner environment during build.
- PRs from contributors outside the declared trusted list require manual approval before any pipeline stage runs — including build, not just deploy.

**Unresolved:**
- Trusted contributor list definition: who is trusted without manual approval?
- Whether the runner Podman container should have any network access during build or be fully airgapped and served only from the attic cache.
- Gitea's PR approval gate configuration — needs testing to confirm it blocks the runner, not just the merge button.
- Runner resource limits (CPU, RAM, disk) to prevent resource exhaustion from a malicious or runaway build.

**Follow-up:**
- Implement ephemeral runner container definition in NixOS.
- Configure Gitea branch protection and external PR approval gate.
- Define and document trusted contributor criteria.
- Test: submit a PR from an untrusted account, verify runner does not execute.
- Test: verify runner container has no access to sops-age-key or internal mesh after job completes.

---

## ADR-009: Network Hardware Selection

**Date:** 2026-04-17
**Status:** Pending — architecture decided (ADR-003), physical hardware not yet selected.

**Context:**
The six-VLAN segmentation architecture (ADR-003) requires a managed switch capable of 802.1Q VLAN tagging and a router/firewall capable of inter-VLAN routing with stateful firewall rules between segments. The current home network hardware is not documented and may not support these requirements.

**Requirements:**
- Managed switch: 802.1Q VLAN tagging, sufficient port count for homelab + personal machines + AP uplink, ideally rack-mountable for the C2100 rack.
- Router/firewall: OPNsense or equivalent — stateful inter-VLAN firewall, DHCP per VLAN, DNS forwarding to FreeIPA, API-driven configuration for OpenTofu.
- Wireless AP: VLAN-aware, supports multiple SSIDs mapped to different VLANs (Trusted, IoT, Guest minimum). Client isolation on IoT SSID.

**Direction:**
OPNsense as the router/firewall OS is the strong preference — it is FOSS, has an active REST API, and has OpenTofu/Terraform provider support for declarative firewall config. Hardware to run it on is unselected.

**Unresolved:**
- Specific switch model and port count.
- OPNsense hardware: dedicated mini-PC (e.g., Protectli, Topton), repurposed machine, or VM on the homelab (not recommended — router should not depend on the machine it routes).
- Wireless AP model (Ubiquiti UniFi, TP-Link Omada, OpenWRT-compatible hardware).
- Whether existing consumer hardware can be repurposed or net-new purchases are required.
- mDNS reflector: needed for IoT devices that use mDNS for discovery (Chromecast, AirPlay, etc.) when isolated to VLAN 40. Avahi with reflector mode, or OPNsense's mdnsrepeater plugin. Decision deferred until post-VLAN deployment evaluation.

**Follow-up:**
- Audit existing hardware against requirements.
- Select and procure switch, OPNsense hardware, and AP if needed.
- Declare OPNsense VLAN and firewall config in OpenTofu.
- Evaluate mDNS reflector need after first IoT VLAN deployment.

---

## ADR-010: Observability Stack

**Date:** 2026-04-17
**Status:** Decided (closes OQ-003)

**Context:**
Security rules (6.8) require centralized log aggregation, alerting on security-relevant events, and monitoring of all critical services.

**Decision:**
Full observability stack on VM3 (isolated from what it monitors):

- **Grafana** — visualization and dashboards (Authentik SSO, accessible at `grafana.internal.tongatime.us`)
- **Loki** — log aggregation with Medallion pipeline (Bronze/Silver/Gold). Chunks stored in MinIO `loki-chunks/` bucket for scalable long-term retention.
- **Prometheus** — metrics collection via pull scrape. Recording rules derive Gold-layer metrics from Silver log patterns.
- **Alertmanager** — alert routing to ntfy.sh webhook receiver.
- **ntfy.sh** — self-hosted push notification server on VM2 (not VM3 — it is a service, not observability infrastructure). Alertmanager sends webhooks to ntfy.sh which pushes to personal devices.

**Alerting architecture:**
```
Alertmanager → webhook → ntfy.sh (VM2) → push notification → phone / desktop
```

ntfy.sh is FOSS (Apache 2.0), requires no account, no phone number, and no cloud
dependency. The ntfy.sh apps for iOS, Android, and desktop subscribe to topics.
Alertmanager posts to a topic URL. Alerts arrive as push notifications within seconds.
Notification topics are separated by severity: `infra-critical`, `infra-warning`, `infra-info`.

**Log retention policy:**
```
Bronze (raw journald):     14 days  ← operational debugging window
Silver (parsed/labeled):   30 days  ← investigation window
Gold (derived metrics):    90 days  ← trend analysis and capacity planning
tlog sessions (audit):     90 days  ← security audit retention (separate policy)
Loki chunks in MinIO:      compressed, no hard delete within policy windows
```

**Loki storage:**
Loki chunks are stored in the MinIO `loki-chunks/` bucket rather than on the VM3
local disk. This allows log retention to grow without VM3 disk pressure and aligns
with MinIO's role as the general-purpose object store.

**Scrape targets (Prometheus):**
```
VM1: node_exporter :9100, freeipa_exporter :9101, headscale_exporter :9102
VM2: node_exporter :9100, postgres_exporter :9187, redis_exporter :9121,
     gitea native metrics :3000/metrics, authentik :9300/metrics,
     minio :9000/minio/health/live, ntfy.sh :80/metrics
VM3: node_exporter :9100 (self-monitoring)
VM4: node_exporter :9100
Desktop: node_exporter :9100
```

**Dashboard strategy:**
Import community dashboards as a baseline for each service, then extend with
custom panels for homelab-specific metrics (FreeIPA auth failures, tlog session
counts, SSSD cache hit rates). Community dashboards are imported via Grafana
provisioning declared in NixOS — not clicked in the UI.

**Rationale:**
- ntfy.sh over Matrix/Element: push notifications are faster, lighter, and require
  no persistent chat infrastructure. Matrix is valuable as a communication platform
  but is overkill as an alerting target.
- ntfy.sh over email: no MTA required, no email configuration, works instantly.
  Email alerting can be added later as a secondary channel if desired.
- Loki chunks in MinIO: decouples log storage from VM3 disk, fits the general-purpose
  object store strategy, and enables log retention scaling without VM3 changes.

**Tradeoffs:**
- ntfy.sh on VM2 means alert delivery depends on VM2 being operational. If VM2 goes
  down, alerts about VM2 going down cannot be delivered via ntfy.sh. Mitigation:
  VM3 Alertmanager is the real alerting engine — a future secondary channel (email
  via a minimal SMTP relay, or a cloud ntfy.sh fallback) handles VM2 outage alerts.
  This is a known gap accepted for now.

**Follow-up:**
- Deploy ntfy.sh on VM2 as Podman quadlet unit.
- Configure Alertmanager webhook receivers for `infra-critical`, `infra-warning`, `infra-info` topics.
- Configure Loki to use MinIO `loki-chunks/` bucket as object storage backend.
- Declare all Prometheus scrape targets in NixOS VM3 config.
- Provision baseline Grafana dashboards via NixOS (not UI clicks).
- Write initial alert rules for: FreeIPA auth failures, SSSD unavailable, disk >85%,
  VM unreachable, certificate expiry <14 days, tlog recording gap.

---

---

## ADR-011: DNS Architecture — Split-Horizon with Subdomain Delegation

**Date:** 2026-04-17
**Status:** Decided

**Context:**
The project needs a DNS strategy that satisfies four requirements simultaneously:
1. Internal services resolve to private VLAN 20 IPs from inside the network.
2. Public services resolve to the Oracle VPS IP from anywhere.
3. Internal services are unreachable and unresolvable from outside the network.
4. Valid, browser-trusted TLS certificates are available for both internal and public services without a private CA.

The registered domain `tongatime.us` is managed on Cloudflare. The goal is `*.tongatime.us` naming for all services.

Two options were evaluated:

**Option A — FreeIPA owns the full `tongatime.us` zone internally.**
FreeIPA BIND is authoritative for all of `tongatime.us` on the internal network. Cloudflare is completely shadowed for internal clients. Any public record that internal machines need must be manually mirrored into FreeIPA. A FreeIPA DNS failure makes the entire `tongatime.us` zone unresolvable internally, including public records unrelated to the homelab.

**Option B — FreeIPA owns only `internal.tongatime.us`.**
Cloudflare retains authority over the parent zone. FreeIPA is authoritative for the `internal.tongatime.us` subdomain only. Internal machines point their resolver at FreeIPA, which answers authoritatively for `*.internal.tongatime.us` and forwards everything else upstream to Cloudflare. No manual record mirroring. A FreeIPA failure only affects `*.internal.tongatime.us` resolution — public records continue resolving via Cloudflare.

**Decision:**
Option B. FreeIPA BIND is authoritative for `internal.tongatime.us` only. Cloudflare manages `tongatime.us` as the parent zone.

**Domain and naming assignments:**

```
Registered domain:     tongatime.us  (Cloudflare)
Internal subdomain:    internal.tongatime.us  (FreeIPA BIND authoritative)
Kerberos realm:        TONGATIME.US
FreeIPA domain:        internal.tongatime.us

Public services (Cloudflare A records, Oracle VPS IP):
  mc.tongatime.us          Minecraft server
  hs.tongatime.us          Headscale coordination endpoint
  [other public services as needed]

Internal services (FreeIPA BIND only, no Cloudflare record):
  ipa.internal.tongatime.us        FreeIPA admin UI
  auth.internal.tongatime.us       Authentik SSO
  git.internal.tongatime.us        Gitea
  vault.internal.tongatime.us      Vaultwarden
  grafana.internal.tongatime.us    Grafana
  cache.internal.tongatime.us      attic binary cache
  renovate.internal.tongatime.us   Renovate Bot (if it has a UI)
  nextcloud.internal.tongatime.us  Nextcloud (if deployed)

Management (FreeIPA BIND, VLAN 10 IPs, not reachable from VLAN 20+):
  idrac.internal.tongatime.us      iDRAC6 management interface
  switch.internal.tongatime.us     Managed switch admin
  router.internal.tongatime.us     OPNsense admin UI
```

**How internal resolution works:**
1. DHCP on each VLAN hands out FreeIPA's IP as the DNS resolver.
2. An internal machine queries `git.internal.tongatime.us`.
3. FreeIPA BIND answers authoritatively: `10.20.1.x`.
4. An internal machine queries `mc.tongatime.us` (public service).
5. FreeIPA BIND does not own `tongatime.us`, so it forwards upstream to Cloudflare.
6. Cloudflare returns the Oracle VPS IP. Correct result, no mirroring needed.

**How external resolution works:**
1. An external client queries `git.internal.tongatime.us`.
2. Cloudflare has an NS delegation record: `internal.tongatime.us NS ns1.internal.tongatime.us`.
3. The resolver attempts to reach FreeIPA BIND — which is on VLAN 20 and not publicly reachable.
4. Query times out or returns SERVFAIL. Internal services are unresolvable from outside. This is the intended behavior.
5. An external client queries `mc.tongatime.us` — Cloudflare returns the Oracle VPS IP normally.

**TLS certificate strategy:**
All certificates — both public and internal — are issued by Let's Encrypt via DNS-01 ACME challenge against the Cloudflare API. DNS-01 does not require the service to be publicly reachable over HTTP. Caddy on each VM uses the Cloudflare DNS provider plugin to satisfy the challenge. This means:
- `git.internal.tongatime.us` gets a real, browser-trusted Let's Encrypt certificate despite having no public DNS record and being unreachable from outside.
- The FreeIPA internal CA is still used for Kerberos KDC and LDAP certificates (client-to-FreeIPA communication), but not for service TLS presented to browsers.
- The Cloudflare API key for DNS-01 is stored in sops-nix and injected into Caddy's environment at runtime.

**Cloudflare DNS management:**
All Cloudflare DNS records are managed exclusively via OpenTofu using the Cloudflare provider. The Cloudflare dashboard is never used for manual record creation. `tofu plan` produces a diff equivalent to the previous shell-script-based Cloudflare sync workflow. `tofu apply` on merge to main pushes changes automatically via Gitea Actions.

**Rationale:**
- Option B scopes FreeIPA's DNS authority to what it actually owns, limiting blast radius of a FreeIPA DNS failure.
- No manual record mirroring — public records resolve correctly internally without duplication.
- `*.internal.tongatime.us` is self-documenting: the subdomain communicates visibility at a glance, which benefits others reading the public repo.
- Internal services are structurally unreachable from outside without any firewall rule being required to enforce it — DNS resolution simply fails at the external boundary.
- DNS-01 certificates for internal services eliminate the need for users or browsers to trust the FreeIPA CA, which would be required if the internal CA issued service certificates.

**Tradeoffs:**
- Internal service URLs are one level deeper (`git.internal.tongatime.us` vs `git.tongatime.us`). Acceptable — these URLs are only typed by the operator and are autocompleted in practice.
- The Cloudflare NS delegation record for `internal.tongatime.us` points at a non-publicly-reachable server. External queries time out rather than returning NXDOMAIN. This is arguably better (obscures the existence of the subdomain) but is worth being aware of.
- FreeIPA must be configured as a forwarding resolver in addition to an authoritative server. This is standard FreeIPA/BIND configuration but must be explicitly set up.

**Follow-up:**
- Add Cloudflare NS delegation record for `internal.tongatime.us` pointing at FreeIPA's internal IP via OpenTofu.
- Configure FreeIPA BIND as authoritative for `internal.tongatime.us` and forwarding for all other zones.
- Configure DHCP on each VLAN to hand out FreeIPA's VLAN 20 IP as the DNS resolver.
- Install Caddy's Cloudflare DNS provider plugin on all VMs that terminate TLS.
- Store Cloudflare API token (scoped to DNS edit on `tongatime.us` only) in sops-nix.
- Declare all internal DNS records in OpenTofu using the FreeIPA DNS provider.
- Declare all public DNS records in OpenTofu using the Cloudflare provider.

## Open Questions

> Items that block or significantly affect pending ADRs. These need answers before the relevant ADR can be finalized.

### OQ-001: Internal Domain Name
**Blocks:** FreeIPA deployment, Kerberos realm configuration, internal DNS, all service hostnames.
**Question:** What is the internal domain for the homelab?
**Status:** RESOLVED. See ADR-011.
- Registered domain: `tongatime.us` (Cloudflare)
- Internal subdomain: `internal.tongatime.us` (FreeIPA BIND authoritative)
- Kerberos realm: `TONGATIME.US`
- Public services: `*.tongatime.us` (Cloudflare records, Oracle VPS)
- Internal services: `*.internal.tongatime.us` (FreeIPA only, no public DNS records)

### OQ-002: Laptop Migration Strategy
**Blocks:** Laptop NixOS host config, SSSD enrollment, break-glass materials for the laptop.
**Question:** Full NixOS (wipe Windows), or dual-boot NixOS + Windows 11?
**Status:** RESOLVED. See ADR-018.
Full NixOS. Windows is wiped. Work will provide a separate machine for any Windows-native requirements. By the time migration is complete, no Windows dependency will remain.

### OQ-003: Alerting Target for Observability
**Blocks:** ADR-010 (Observability Stack), specifically the Alertmanager configuration.
**Question:** Where should infrastructure alerts be delivered?
**Status:** RESOLVED. See ADR-010 (updated) and ADR-020.
- Tool: self-hosted ntfy.sh (FOSS, push notifications to all personal devices)
- Alertmanager webhook receiver → ntfy.sh → phone/desktop notifications
- ntfy.sh deployed as a Podman container on VM2
- No account, no phone number, no cloud dependency required
- MinIO also serves as a general-purpose S3-compatible object store beyond just OpenTofu state

### OQ-004: iDRAC6 Express vs Enterprise — Hardware Verification
**Blocks:** VLAN 10 isolation for out-of-band management (Section 11.5).
**Question:** Does the C2100 currently have an iDRAC6 Enterprise card installed (dedicated NIC) or only iDRAC6 Express (shared LOM)? Express cannot be cleanly isolated to VLAN 10 without also carrying host traffic on the same port.
**Action:** Physically inspect the server or check `racadm getsysinfo` output for iDRAC version and NIC type.
**Status:** Unverified. If Express only, an Enterprise card must be sourced and installed before VLAN 10 setup.

### OQ-005: Vaultwarden Backup and Recovery Strategy
**Blocks:** Treating Vaultwarden as critical infrastructure (Section 6.2) requires a backup posture.
**Question:** How is the Vaultwarden SQLite database (or Postgres if migrated) backed up? Where do backups go? What is the recovery procedure if VM2 is destroyed? Vaultwarden is in the circular dependency chain — if it goes down and the break-glass USB is unavailable, no credentials are accessible.
Candidates: encrypted backup to a separate ZFS dataset with snapshot replication, push to an encrypted remote (Backblaze B2, rclone to an encrypted target), or regular export to the offline break-glass USB.
**Status:** Unanswered.

### OQ-006: Self-Hosted DERP Node Evaluation
**Blocks:** ADR-001 follow-up item. Accepted loss in the Headscale decision, but needs a real-world evaluation.
**Question:** After Headscale is deployed and in use, do any connections fail to establish direct WireGuard paths and require relay? If yes, a self-hosted DERP node (Tailscale's DERP server is open source) may be needed, hosted on the Oracle VPS.
**Status:** Deferred until post-deployment observation. Revisit after 30 days of Headscale operation.

### OQ-007: Work Active Directory Trust Configuration
**Blocks:** ADR for AD interoperability, laptop SSSD configuration.
**Question:** Does the work environment allow personal Linux laptops to join the corporate AD domain directly? If yes, direct SSSD AD enrollment on the laptop is the simpler path. If no (common in strict enterprise environments), the FreeIPA cross-forest trust is required.
Additionally: what is the corporate AD domain name? Required for FreeIPA trust configuration.
**Status:** Unanswered. Requires checking with the work IT environment.

### OQ-008: Public-Facing Domain for Oracle VPS Services
**Blocks:** Caddy configuration on the Oracle VPS, Let's Encrypt certificate issuance, public DNS records.
**Question:** What public domain name do public-facing services use?
**Status:** RESOLVED. See ADR-011.
- Domain: `tongatime.us` managed on Cloudflare.
- Public services use `<name>.tongatime.us` with A records pointing at the Oracle VPS IP.
- Certificates issued via Let's Encrypt DNS-01 challenge against Cloudflare API (no HTTP reachability required).
- Internal services at `*.internal.tongatime.us` also use DNS-01 for certificates despite having no public DNS record.

### OQ-009: OpenTofu State Backend — MinIO vs PostgreSQL
**Blocks:** ADR-005 finalization.
**Question:** MinIO (S3-compatible, dedicated state store, cleaner separation) or PostgreSQL?
**Status:** RESOLVED. See ADR-005 (updated).
- Decision: MinIO
- Rationale: MinIO is a general-purpose S3-compatible object store that serves multiple
  consumers beyond OpenTofu state — Gitea Actions artifact storage, rclone backup staging,
  any future service needing object storage. One infrastructure piece, many uses.
  PostgreSQL mixing IaC state with application databases is not clean separation.
- State locking: MinIO S3 backend with DynamoDB-compatible locking via a lightweight
  sidecar or the OpenTofu http backend locking endpoint.

---

## Action Items

> Concrete tasks with no decision ambiguity. These do not need an ADR but need to be tracked.

| ID | Item | Depends On | Status |
|----|------|-----------|--------|
| AI-001 | Verify iDRAC6 Express vs Enterprise on C2100 | None | Pending |
| AI-002 | Source iDRAC6 Enterprise card if not already installed | AI-001 | Pending |
| AI-003 | Set up iDRAC6 on VLAN 10, static IP, credentials in Vaultwarden | AI-001, VLAN hardware | Pending |
| AI-004 | Procure managed switch, OPNsense hardware, and VLAN-capable AP | ADR-009 | Pending |
| AI-005 | Generate Ed25519 break-glass SSH keys for each personal machine | None | Pending |
| AI-006 | Declare static IP fallback in `networking.hosts` on desktop and laptop | OQ-001 resolved (internal.tongatime.us) | Pending |
| AI-007 | Create and populate offline break-glass encrypted USB | ADR-006 | Pending |
| AI-008 | Write bootstrap procedure document (VM1 from scratch, no services running) | ADR-006 | Pending |
| AI-009 | Schedule and conduct first break-glass drill | AI-007, AI-008 | Pending |
| AI-010 | Add desktop hardware specs to PROJECT_RULES.md Section 11.4 | None | Done -- see AI-034 for post-migration confirmation |
| AI-011 | Add laptop hardware specs to PROJECT_RULES.md Section 11.4 | None | Done |
| AI-012 | Define ZFS dataset layout for VM disk images and service data on RAIDZ2 pool | None | Pending |
| AI-013 | Create `renovate` bot user in FreeIPA/OpenTofu with scoped Gitea access | ADR-002 | Pending |
| AI-014 | Write `renovate.json` config for monorepo (flake inputs, container digests) | ADR-002 | Pending |
| AI-015 | Evaluate mDNS reflector need after initial VLAN 40 deployment | ADR-003, ADR-009 | Deferred |
| AI-016 | Observe Headscale connection reliability for 30 days, evaluate DERP need | ADR-001, OQ-006 | Deferred |
| AI-017 | Confirm Headscale ACL format compatibility for deployed version | ADR-007 | Pending |
| AI-018 | Test CI/CD runner isolation: untrusted PR must not trigger runner | ADR-008 | Pending |
| AI-019 | Order ThinkPad T15 Gen1 replacement battery (01AV493 or equivalent) | ADR-018 | Pending |
| AI-020 | Back up all Windows data from laptop before wipe (documents, browser profiles, any non-GitHub projects) | ADR-018 | Pending |
| AI-021 | Back up desktop game saves not covered by Steam Cloud before reinstall | ADR-017 | Pending |
| AI-022 | Source libfprint-compatible USB fingerprint reader for desktop ($15-25) | Section 12.6 | Pending |
| AI-023 | Audit desktop NTFS drives -- identify what is still needed before wiping secondary drives | ADR-017 | Pending |
| AI-024 | Format 1.82TB desktop HDD to ext4, declare mount at /mnt/overflow in NixOS | ADR-017 | Pending |
| AI-025 | Purchase Nitrokey FIDO2, enroll in Authentik and Vaultwarden | Section 12.6 | Deferred -- after system is operational |
| AI-026 | Enroll fingerprint on laptop via fprintd-enroll after NixOS install | ADR-015 | Pending |
| AI-027 | Run one-week impermanence discovery pass on each machine post-install, finalize persistence list | ADR-015 | Pending |
| AI-028 | Deploy Nextcloud on VM2 with 1TB ZFS dataset (tank/nextcloud/data) | ADR-017 | Pending |
| AI-029 | Write and test rclone + age backup job, declare in Gitea Actions | ADR-017 | Pending |
| AI-030 | Test full restore from Google Drive backup before declaring backup operational | ADR-029 | Pending |
| AI-031 | Declare Sunshine as NixOS systemd service on desktop with VA-API encoding | ADR-016 | Pending |
| AI-032 | Declare Moonlight in laptop Home Manager, gated on tags.laptop | ADR-016 | Pending |
| AI-033 | Monitor Apollo/Artemis releases for Linux client and virtual display support | FC-004 | Ongoing |
| AI-034 | Update PROJECT_RULES.md 11.4 with full desktop specs once confirmed post-migration | None | Pending |
| AI-035 | Verify exact nixos-hardware module name for ThinkPad T15 Gen1 (check flake.nix module list at github.com/NixOS/nixos-hardware) | None | Pending |
| AI-036 | Import verified nixos-hardware ThinkPad module into laptop host config | AI-035 | Pending |
| AI-037 | Audit what the nixos-hardware module covers and document any gaps that need manual override in hosts/laptop/hardware.nix | AI-036 | Pending |
| AI-038 | Declare tlog in modules/core/ssh-recording.nix with SSSD session_recording scope=all | None | Pending |
| AI-039 | Add journald state to impermanence persistence list on all hosts (required for tlog recording continuity across reboots) | ADR-019, ADR-015 | Pending |
| AI-040 | Configure Loki pipeline stage to parse tlog JSON fields into Silver-layer labels (user, hostname, session_id, duration) | ADR-019, ADR-014 | Pending |
| AI-041 | Set Bronze-layer retention window for tlog entries in Loki config (90 days minimum) | ADR-019 | Pending |
| AI-042 | Declare ProxyJump SSH client config in home/taylor/security.nix via Home Manager matchBlocks | ADR-019 | Pending |
| AI-043 | Test end-to-end: SSH to a VM, verify tlog entry appears in Loki, replay session in Grafana | AI-038, AI-040 | Pending |

---

## ADR-012: Deployment Strategy Policy per VM

**Date:** 2026-04-17
**Status:** Decided

**Context:**
Three standard deployment strategies exist: blue-green (full environment switch), rolling (gradual instance replacement), and canary (small traffic percentage first). Applying the wrong strategy to the wrong service creates either unnecessary risk (rolling a stateful service with a data schema change) or unnecessary operational overhead (treating a disposable DMZ game server like a critical identity node).

**Decision:**
Assign a default deployment strategy to each VM tier based on its service criticality and statefulness:

- VM1 (Network & Identity): Blue-green only. NixOS system generations implement this natively. The previous generation remains bootable as an instant rollback. Mixed-version operation of FreeIPA or DNS is never permitted.
- VM2 (Application Services): Blue-green preferred for stateful services (Vaultwarden, Gitea, Authentik, Nextcloud). Rolling acceptable for stateless services and container image digest bumps with no data migration.
- VM3 (Observability): Rolling acceptable. Observability services are stateless enough that mixed-version operation during a rolling update does not corrupt data.
- VM4 (DMZ): Any strategy. Services here are treated as disposable. Rolling is the default for simplicity.
- Canary: Not yet applicable. Requires multiple replicas. Revisit when the HA second physical machine introduces FreeIPA and Headscale replicas.

**Rationale:**
- VM1 blue-green is a correctness requirement, not just a preference. A FreeIPA version mismatch during a rolling update could corrupt the LDAP database or cause Kerberos ticket validation failures across all enrolled machines simultaneously.
- Rolling for VM3 is safe because Prometheus and Loki have no shared mutable state that a version mismatch could corrupt — the worst outcome is a brief gap in metrics collection.
- Codifying this explicitly prevents the default of "whatever the tool does" from producing an unsafe rollout strategy on a critical service.

**Tradeoffs:**
- Blue-green for VM2 stateful services requires disciplined snapshot discipline before each update — the previous NixOS generation is the rollback mechanism, but database state at the application layer is not automatically rolled back by switching generations. Snapshot before stateful updates is a hard requirement.

**Follow-up:**
- Declare per-VM deployment strategy in deploy-rs configuration.
- Document snapshot-before-update procedure for VM2 stateful services.

---

## ADR-013: Redis as Shared Cache Service on VM2

**Date:** 2026-04-17
**Status:** Decided

**Context:**
Authentik requires Redis as a hard dependency. Rather than treating Redis as an Authentik-internal implementation detail (which would result in duplicated Redis instances as more services are added), it is formalized as a shared infrastructure service on VM2.

**Decision:**
Deploy a single Redis instance on VM2 as a shared cache. Applications use logical database separation (integer `SELECT` index per application) to isolate their namespaces within the same instance. Redis is VM2-local only — not exposed to VLAN 20 or any other VM.

**Rationale:**
- Avoids Redis instance sprawl as the service count on VM2 grows.
- Logical database separation provides sufficient namespace isolation for the homelab's trust model — all services sharing Redis are already co-tenants of VM2 with equivalent trust levels.
- If a future service requires cross-VM cache access, it gets a dedicated Redis instance on its own VM. The shared instance scope is explicitly bounded to VM2.

**Tradeoffs:**
- A Redis failure on VM2 affects all services that depend on it simultaneously. Mitigated by Redis's high reliability and the fact that VM2 already represents a shared fate boundary for all its services.
- Logical database separation is a namespace convention, not a hard security boundary. A misconfigured client could theoretically access another application's database index. Acceptable within VM2's trust model; would not be acceptable across VMs.

**Follow-up:**
- Declare Redis as a NixOS quadlet unit on VM2 with `appendonly yes` persistence.
- Assign and document logical database index per service (e.g., 0=Authentik, 1=next service).
- Store the index assignment table in the monorepo alongside the Redis NixOS config.

---

## ADR-014: Observability Stack — Alert and Log Structure Standards

**Date:** 2026-04-17
**Status:** Decided (extends ADR-010)

**Context:**
ADR-010 decided the observability tool set (Grafana + Loki + Prometheus + Alertmanager) but left the operational standards for alert design and log organization unspecified. Two patterns from general DevOps practice address this directly.

**Decision:**

**Alert time-window requirement:**
All Alertmanager rules must include an explicit `for:` duration clause. No rule fires on a single data point. Minimum window for any alert is 2 minutes; recommended for most infrastructure alerts is 5 minutes. This prevents alert storms from transient spikes and ensures every alert represents a sustained, actionable condition.

Example structure:
```yaml
- alert: FreeIPAAuthFailureRate
  expr: rate(freeipa_auth_failures_total[5m]) > 0.1
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "Sustained FreeIPA authentication failure rate above threshold"
```

**Loki Medallion log structure:**
Loki log streams are organized in three conceptual tiers:

- Bronze: Raw logs as emitted, retained at full fidelity with a long retention window. No parsing. Exists for auditing and forensics.
- Silver: Parsed and labeled streams with structured fields extracted at Loki ingest via pipeline stages. Fields such as `user`, `event_type`, `source_ip`, and `service` are extracted and indexed. Used for operational queries and incident investigation.
- Gold: Prometheus metrics derived from log patterns via Loki recording rules or Prometheus relabeling. These become the time-series counters and gauges that Alertmanager evaluates. Alerting is always against Gold-layer metrics, never against raw log queries, to keep alert evaluation fast and deterministic.

**Rationale:**
- Time-windowed alerts eliminate the primary cause of alert fatigue in homelab monitoring — a single failed health check firing an alert that resolves itself 10 seconds later.
- The Medallion log structure prevents the "pipeline jungle" failure mode: unstructured, undocumented log data in a single flat stream that nobody can query reliably after six months.
- Separating alerting (Gold metrics) from investigation (Silver streams) from archival (Bronze raw) means each layer can have its own retention policy without compromising the others.

**Tradeoffs:**
- Loki pipeline stage configuration adds upfront setup work per service. Worth it; undone by the ongoing cost of unstructured logs.
- Gold-layer metric derivation from logs adds a processing step. At homelab scale this is negligible.

---

---

## ADR-019: SSH Session Recording — tlog via SSSD

**Date:** 2026-04-17
**Status:** Decided

**Context:**
FreeIPA + SSSD + Headscale handle identity, access control, and network isolation well, but leave a gap in the audit layer: there is no record of what happens inside an SSH session after authentication succeeds. A user logs in, runs commands, and exits. HBAC confirms they were allowed in, but nothing records what they did. This is the missing layer for a "send an attacker your config" security posture — the config being public means the audit trail needs to be strong.

Three categories of solution were evaluated:

- **Bastion host products (Warpgate, Teleport):** Introduce a dedicated service that proxies SSH connections and records them. Warpgate (Apache 2.0) is FOSS and non-conflicting with FreeIPA. Teleport wants to replace FreeIPA's SSH CA, creating a competing identity system. Both add new infrastructure.
- **tlog via PAM:** Install tlog and add `pam_tlog.so` to individual PAM service stacks. Works but requires per-service configuration on every host.
- **tlog via SSSD session recording:** SSSD 1.16+ has a native `[session_recording]` config block that invokes `tlog-rec-session` automatically for every FreeIPA-authenticated terminal session. Single config block, universally applied across all enrolled hosts. No per-service PAM work.

Short-lived / rotating SSH credentials (Warpgate and Teleport both support this) were also evaluated. Decided overkill given the existing Ed25519 key + FreeIPA HBAC posture.

**Decision:**
tlog (Red Hat, GPL-2.0) via SSSD's session recording integration. Declared in `modules/core/ssh-recording.nix` and applied to every host. No additional bastion infrastructure. Recordings flow to journald -> Loki -> Grafana via the existing pipeline.

**How it works:**
1. User SSHs to any enrolled host. SSSD authenticates against FreeIPA (Kerberos + LDAP).
2. SSSD's `[session_recording]` config (scope = all) invokes `tlog-rec-session` as the session wrapper before handing control to the user's shell.
3. tlog records every byte of input and output with millisecond timestamps, structured as JSON.
4. Recordings are written to journald under the `tlog` syslog identifier.
5. Loki's journald scraper picks them up and routes them into the Bronze log layer with a long retention window.
6. Sessions are searchable and replayable in Grafana.

**SSH ProxyJump convention:**
VM1 (Network & Identity) is the declared entry point for all homelab SSH access, enforced via `programs.ssh.matchBlocks` in Home Manager. VM2, VM3, and VM4 are accessed via `ProxyJump = "vm1"`. This is convention, not hard ACL enforcement -- direct Headscale access remains available for break-glass. The convention ensures every session is recorded on VM1 (the jump) and on the target VM, providing two independent recording points per session.

**Rationale:**
- tlog via SSSD is the most natural fit: SSSD is already on every host, FreeIPA is the identity provider, and the integration was designed specifically for this stack (Red Hat ships tlog alongside FreeIPA in RHEL).
- No new infrastructure. Recordings flow through the existing Loki pipeline.
- Universal coverage: every FreeIPA-authenticated SSH session on every host is recorded without per-host or per-service configuration.
- Structured JSON output means sessions are searchable (by user, host, command, time) not just viewable.
- The double-recording from ProxyJump (VM1 + target) provides redundancy -- if one recording is incomplete the other covers it.

**Tradeoffs:**
- tlog adds a small overhead to session startup (wrapping the shell in the recorder). Negligible in practice.
- Journald storage for session recordings must be accounted for in log retention planning. tlog sessions can be verbose for long interactive sessions. The Bronze retention window for tlog entries should be set longer than operational logs but with size-based rotation if needed.
- The ProxyJump convention is not technically enforced -- a user with a Headscale peer can still SSH directly to VM2 bypassing VM1. This is intentional (break-glass), but means direct access will not have the VM1 recording. The target VM recording still applies.

**What was ruled out:**
- Teleport: conflicts with FreeIPA as a competing SSH CA and identity provider. Not compatible with the existing stack without significant rework.
- Warpgate: good FOSS option, not needed at this scale since tlog covers the recording requirement without a bastion. Revisit if a centralized web UI for session replay becomes a priority (FC-005).
- PAM-only tlog: more configuration surface than SSSD integration, no benefit.
- Rotating SSH credentials: evaluated and declined as overkill given the existing posture.

**Follow-up:**
- Declare tlog in `modules/core/ssh-recording.nix` with SSSD `[session_recording]` scope = all.
- Add tlog to the persistence list in impermanence config (journald state must survive reboots for recording continuity).
- Configure Loki pipeline stage to parse tlog JSON fields and promote them to Silver-layer labels: `user`, `hostname`, `session_id`, `duration`.
- Set Bronze retention window for tlog entries (recommend 90 days minimum).
- Declare ProxyJump SSH config in `home/taylor/security.nix` via Home Manager.
- Test: verify session is recorded end-to-end after first VM deployment. Replay a recorded session in Grafana before declaring tlog operational.

---

## FC-005: Warpgate — SSH Bastion with Web UI

**Verdict:** Deferred.
**Trigger:** A centralized web UI for browsing, searching, and replaying recorded SSH sessions becomes operationally desirable, OR hard technical enforcement of the ProxyJump convention (not just convention) is required.
**Value when triggered:** Warpgate (Apache 2.0, Rust) provides an SSH bastion that hard-enforces all connections through a single point, a web UI for session management and replay, per-client permissions, and HTTP/MySQL proxy support alongside SSH. It does not conflict with FreeIPA -- it delegates identity to existing SSH keys and SSSD.
**Current alternative:** tlog via SSSD + Grafana for session replay. Adequate. The Grafana replay path is more friction than a dedicated Warpgate UI but is functional and uses no additional infrastructure.

---

## ADR-020: Push Notifications — ntfy.sh

**Date:** 2026-04-17
**Status:** Decided (part of OQ-003 resolution)

**Context:**
Alertmanager requires a notification target. Several options were evaluated:
email (requires MTA), Matrix/Element (persistent chat, full homelab service),
Signal (requires phone number), ntfy.sh (lightweight push notification server).

**Decision:**
Self-hosted ntfy.sh (Apache 2.0) deployed as a Podman container on VM2.
Alertmanager sends webhook POST requests to ntfy.sh topic endpoints.
ntfy.sh apps on personal devices subscribe to topics and receive push notifications.

**Topic structure:**
```
https://ntfy.internal.tongatime.us/infra-critical  ← pages immediately
https://ntfy.internal.tongatime.us/infra-warning   ← check within the hour
https://ntfy.internal.tongatime.us/infra-info      ← informational, batched
```

Alertmanager routes by severity label to the appropriate topic.
Personal devices subscribe to all three topics with different notification urgency settings.

**Authentication:**
ntfy.sh supports access control via an ACL file. Alertmanager authenticates with
a service credential stored in sops-nix. Personal devices authenticate with a
read-only token stored in Vaultwarden. The ntfy.sh instance is not publicly
accessible — it is behind Caddy on the internal mesh only.

**Rationale:**
- Zero external dependencies — no account, no phone number, no cloud relay.
- Trivially simple: Alertmanager POSTs JSON to a URL, ntfy.sh delivers it.
- Apps available for iOS, Android, desktop (Linux, macOS, Windows), and web.
- FOSS (Apache 2.0), actively maintained, well-documented Alertmanager integration.
- Lightweight: minimal resource footprint on VM2.

**Known limitation (mitigated by ADR-021):**
If VM2 is the subject of the alert (e.g., VM2 goes down), ntfy.sh on VM2 cannot
deliver the alert. This is mitigated by the Oracle VPS redundant monitoring stack
(ADR-021): VM3 Alertmanager routes all alerts to BOTH VM2 ntfy.sh (primary) and
VPS ntfy.sh (secondary). If VM2 is down, VPS ntfy.sh delivers the alert independently.

**Follow-up:**
- Deploy ntfy.sh on VM2 as Podman quadlet.
- Configure ACL: Alertmanager write token, personal device read tokens in Vaultwarden.
- Declare ntfy.sh hostname: `ntfy.internal.tongatime.us`.
- Configure Alertmanager receivers for all three topic severity tiers.
- Install ntfy.sh app on phone and both personal machines, subscribe to all topics.
- Configure VM3 Alertmanager to route to BOTH VM2 ntfy.sh (primary) and VPS ntfy.sh (secondary, see ADR-021).
- Test: trigger a manual test alert, confirm delivery within 10 seconds on both paths.

---

## ADR-021: Oracle VPS Redundant Monitoring Stack

**Date:** 2026-04-17
**Status:** Decided

**Context:**
The primary observability stack runs on VM3 (Grafana + Loki + Prometheus + Alertmanager)
with ntfy.sh on VM2 as the alert delivery mechanism. Two failure modes are unaddressed:

1. If VM2 goes down, ntfy.sh cannot deliver alerts about VM2 failing (self-alerting problem, noted in ADR-020).
2. If VM3 goes entirely dark, there is no monitoring infrastructure left to detect or alert on the failure.

The Oracle VPS is an always-on, off-site machine with spare capacity after accounting
for its Caddy proxy role. It is ideally positioned as an independent monitoring standby.

**Constraint:**
The Oracle VPS is a free-tier instance with limited resources. The redundant stack
must be extremely lightweight — total RAM budget is 200MB or less. Full mirrors of
Grafana or Loki are out of scope.

**Decision:**
Deploy a minimal three-service redundant monitoring stack on the Oracle VPS:

- **VictoriaMetrics** (single-node, Apache 2.0) — receives Prometheus `remote_write`
  from VM3 and stores a copy of all metrics. Provides PromQL query capability if
  VM3 is down. Single binary, ~50-80MB RAM at homelab scale.
- **Alertmanager** (Apache 2.0) — receives forwarded alerts from VM3 Alertmanager
  and fires independently if VM3's heartbeat stops. ~20-30MB RAM.
- **ntfy.sh** (Apache 2.0) — independent alert delivery path. If VM2 is down, VPS
  ntfy.sh delivers alerts that VM2 ntfy.sh cannot. ~10-20MB RAM.

**Total estimated RAM:** ~80-130MB. Well within even a 1GB Oracle free tier instance.

**Architecture — push model, no new ACL changes:**
All data flows from the homelab outward to the VPS. The VPS never initiates connections
into the homelab. No Headscale ACL changes are required.

```
VM3 Prometheus ──── remote_write ──────────────────► VPS VictoriaMetrics
VM3 Alertmanager ── forwarded alerts ──────────────► VPS Alertmanager
VM3 Alertmanager ── DeadMansSwitch heartbeat ──────► VPS Alertmanager
                                                           │
                                          if heartbeat stops: fire alert
                                                           │
                                                    VPS ntfy.sh ──► phone

VM3 Alertmanager also sends all alerts ────────────► VM2 ntfy.sh (primary path)
                                       simultaneously► VPS ntfy.sh (secondary path)
```

**Dead man's switch (heartbeat):**
VM3 Prometheus has a permanently-active alert called `DeadMansSwitch`:
```yaml
- alert: DeadMansSwitch
  expr: vector(1)
  labels:
    severity: critical
  annotations:
    summary: "VM3 monitoring heartbeat — if this stops firing, VM3 is down"
```
VM3 Alertmanager forwards this to VPS Alertmanager and silences it locally.
VPS Alertmanager expects to receive this alert continuously. If it stops arriving
for more than 2 minutes, VPS Alertmanager fires `MonitoringDown` to VPS ntfy.sh.
This is the signal that VM3 itself has failed.

**What the VPS stack does NOT include:**
- Grafana — too heavy, unnecessary for a standby. PromQL queries can be run directly
  against VictoriaMetrics HTTP API when needed.
- Loki — logs are not replicated off-site. The VPS is an alerting and metrics standby,
  not a log mirror. Log retention lives entirely on VM3/MinIO.
- Full dashboard suite — standby only; access is for incident investigation, not
  day-to-day operations.

**Notification topics on VPS ntfy.sh:**
Identical topic structure to VM2 ntfy.sh. Personal devices subscribe to BOTH
VM2 and VPS ntfy.sh topics — delivery is guaranteed as long as either is reachable.

**VPS ntfy.sh access:**
VPS ntfy.sh is accessible at `ntfy.tongatime.us` (public Cloudflare record, port 443
via Caddy on the VPS). Unlike the internal ntfy.sh which is mesh-only, the VPS
instance is publicly reachable so that alerts arrive even when the Headscale mesh
has a problem. Access is token-authenticated; write tokens are restricted to
Alertmanager service accounts. Read/subscribe tokens in Vaultwarden.

**Metric retention on VPS:**
VictoriaMetrics retains 7 days of metrics (short window — this is a standby, not
an archive). VM3 Prometheus is the authoritative long-term store. The 7-day window
covers the incident investigation period after a VM3 failure.

**Rationale:**
- Addresses both self-alerting failure modes (VM2 down, VM3 down) in one decision.
- Push model requires zero Headscale ACL changes — homelab initiates all connections.
- Three Go binaries with trivial resource footprint — appropriate for a free-tier VPS.
- VictoriaMetrics is significantly lighter than Prometheus and handles remote_write
  natively as its primary ingestion path.
- Public VPS ntfy.sh endpoint means alerts work even during Headscale mesh problems.

**Tradeoffs:**
- VPS ntfy.sh is publicly reachable (token-authenticated). Acceptable given the
  VPS is already a public-facing machine with hardened OpenSSH and Caddy.
- 7-day metric retention on VPS is short. Acceptable — this is a standby for
  incident response, not long-term capacity planning.
- Adds three services to Oracle VPS operational scope. Mitigated by NixOS + Nix
  declarative management (already managing Caddy there).

**Follow-up:**
- Declare VictoriaMetrics, Alertmanager, and ntfy.sh in Oracle VPS NixOS config.
- Configure VM3 Prometheus `remote_write` to VPS VictoriaMetrics endpoint.
- Configure VM3 Alertmanager to forward all alerts to VPS Alertmanager AND to
  route all severity alerts to BOTH VM2 ntfy.sh and VPS ntfy.sh simultaneously.
- Write `DeadMansSwitch` alert rule on VM3 Prometheus.
- Configure VPS Alertmanager to silence `DeadMansSwitch` and fire `MonitoringDown`
  if heartbeat gaps exceed 2 minutes.
- Add `ntfy.tongatime.us` Cloudflare A record via OpenTofu.
- Subscribe personal devices to VPS ntfy.sh topics in addition to VM2 topics.
- Test: stop VM3, confirm `MonitoringDown` alert fires from VPS within 3 minutes.
- Test: stop VM2, confirm alerts still arrive via VPS ntfy.sh.

## Future Considerations
---

## FC-006: flake-parts for Flake Output Composition

**Verdict:** Deferred — evaluate when flake output types expand beyond nixosConfigurations.
**What it is:** A library that structures `flake.nix` outputs using a module system. Instead of manually constructing output attribute sets, outputs are composed from imported flake modules. Each host or feature can declare itself as a flake module rather than being explicitly listed in a central outputs function.
**Current alternative:** Raw flake outputs with manually constructed `nixosConfigurations`. The `mkHost.nix` tag system handles module composition at the NixOS layer. This is adequate while the flake exposes only NixOS configurations.
**Trigger:** The flake begins exposing multiple output types in meaningful quantity — packages, devShells, checks, formatters, Home Manager configurations — alongside NixOS configs. At that point manual output construction becomes error-prone and repetitive. flake-parts resolves this by making each output type a composable module.
**Value when triggered:** Cleaner `flake.nix` that does not need to enumerate all hosts and output types explicitly. New hosts and output types register themselves via imports rather than requiring edits to the central outputs function. Many large public NixOS configs (snowfall-lib style) use this approach.
**Tradeoffs to evaluate:** Additional abstraction layer over standard flake outputs. Steeper learning curve for contributors unfamiliar with flake-parts. Requires adding `flake-parts` as a flake input. Debugging flake evaluation errors becomes slightly more indirect.
**Reference:** https://flake.parts

---

## FC-007: Dendritic Pattern for Module Composition

**Verdict:** Deferred — evaluate as a successor to the current mkHost tag system if module interdependencies grow complex.
**What it is:** A module composition pattern where each module declares its own dependencies internally rather than relying on a central orchestrator. The configuration tree is traversed bottom-up — a module like `gaming/steam.nix` imports `gaming/proton.nix` and `gaming/controllers.nix` directly, so the orchestrator (`mkHost.nix`) only needs to know the top-level entry point, not the full dependency graph.
**Current alternative:** The `mkHost.nix` tag system — hosts declare boolean feature tags, mkHost reads them and composes the module set centrally. mkHost is the orchestrator that knows the full shape of every feature's module set.
**Trigger:** The mkHost tag system becomes difficult to maintain because adding a new sub-feature requires editing both the feature module AND mkHost.nix. Specifically: more than ~15 tags, features with multi-level internal dependencies, or a need to test modules in isolation without the full mkHost context.
**Value when triggered:** Modules become fully self-contained and testable without the orchestrator. Adding a new sub-feature (e.g., a new gaming tool) only requires editing the relevant gaming module — mkHost.nix does not change. The dependency graph is explicit and local rather than implicit and central. Easier for Claude Code to reason about because each module file tells the full story of what it needs.
**Tradeoffs to evaluate:** Module files become more complex (they own their imports). Harder to get a single-glance view of what a host actually includes — requires traversing the tree. Potential for circular import issues if not carefully managed. The current flat tag model is simpler to explain and audit.
**Relationship to FC-006:** Dendritic and flake-parts are independent — either can be adopted without the other. However, they compose naturally: flake-parts handles output-level composition, dendritic handles module-level composition. A mature config could use both.
**Reference:** Community pattern — no single canonical implementation. Search "dendritic nix modules" for examples in the wild.



> Tools evaluated and deliberately deferred. Revisit when the stated trigger condition is met. Do not adopt before the trigger — the operational overhead is not justified at current scale.

### FC-001: Apache Kafka
**Verdict:** Deferred.
**Trigger:** Log volume or automation event complexity grows beyond what direct Loki ingest and Gitea webhooks handle cleanly. Specifically: need for guaranteed log delivery across VM reboots, multiple independent consumers of the same event stream, or tolerance for VM3 downtime without log loss during ingest.
**Value when triggered:** Decouples log producers from Loki. If VM3 is rebooting, Kafka buffers logs until it recovers. Also enables event-driven automation where multiple services react to the same event independently (e.g., a Gitea push triggers both a CI pipeline and a backup).
**Current alternative:** Direct Loki agent scraping. Gitea native webhooks for event-driven triggers. Adequate at current scale.

### FC-002: Apache Airflow
**Verdict:** Deferred.
**Trigger:** Gitea Actions workflows develop more than one branching condition or require per-step retry logic with conditional failure handling. Practical trigger: a nightly backup chain, a weekly audit workflow, or any workflow with more than ~5 interdependent steps where Gitea Actions YAML becomes difficult to reason about.
**Value when triggered:** Native DAG modeling, per-task retry with backoff, conditional branching, a web UI for workflow history and manual retriggers. Materially better than Gitea Actions for long-running multi-step operational workflows.
**Current alternative:** Gitea Actions cron jobs. Adequate until workflow complexity justifies the operational overhead of running Airflow on VM2.

### FC-003: Canary Deployments
**Verdict:** Deferred.
**Trigger:** Second physical machine online with FreeIPA replica and Headscale standby, enabling multiple replicas of at least one service.
**Value when triggered:** Validate new versions against a small traffic slice before full rollout. Directly applicable to FreeIPA and Headscale upgrades once replicas exist.
**Current alternative:** Blue-green via NixOS generations. Adequate for single-instance services.

---

## ADR-015: Impermanence on Both Machines

**Date:** 2026-04-17
**Status:** Decided

**Context:**
NixOS supports an "impermanence" pattern where the root filesystem is a tmpfs wiped on every boot. Only explicitly declared paths persist across reboots. All declared system software remains available via the persistent /nix partition. User data lives on a persistent /persist partition. The machine boots into a structurally identical state every time.

**Decision:**
Impermanence is enabled on both the desktop and laptop from day one of each machine's NixOS installation. Not after stabilization — from the first boot.

**Rationale:**
- Config drift is structurally impossible. The running system is always exactly what the NixOS config declares.
- Any malware, session artifacts, or junk that accumulates in root-owned paths during a session is eliminated on reboot automatically.
- Stale auth state (SSSD caches, Kerberos ticket remnants outside the declared cache) is cleaned on every reboot.
- Aligns directly with the "send an attacker your config and they shrug" posture — the config being the complete and accurate description of system state becomes a hard guarantee.
- Boot times improve marginally (no fsck on the ephemeral root).
- The discovery cost (one week of noticing undeclared paths that need persisting) is bounded and one-time.

**Disk layout (both machines):**
Root (/) is tmpfs. /nix holds the Nix store on a persistent btrfs partition. /persist holds all surviving system and user state. /boot/efi and /boot are standard.

**Required persistence list:**
- `/var/lib/fprint` -- fingerprint enrollment
- `/var/lib/bluetooth` -- paired devices
- `/var/lib/nixos` -- NixOS UID/GID state
- `/var/lib/sss` -- SSSD offline credential cache (critical for laptop offline login)
- `/var/log` -- logs across reboots
- `/etc/NetworkManager/system-connections` -- saved WiFi (laptop)
- `/etc/machine-id` -- stable FreeIPA enrollment identity
- `/etc/ssh/ssh_host_ed25519_key` + `.pub` -- SSH host key

**Tradeoffs:**
- First week of use surfaces undeclared paths. Expected and bounded.
- Any service that writes state to an undeclared path will reset on reboot. Caught during initial setup; add to persistence list when discovered.
- Slightly more complex initial partition layout compared to a standard NixOS install.

**Follow-up:**
- Use the `impermanence` NixOS module for declarative persistence list management.
- Run both machines for one week post-install and audit any state loss before declaring the persistence list stable.
- Document final persistence list in the host NixOS config with comments explaining why each entry exists.

---

## ADR-016: Game Streaming — Sunshine + Moonlight

**Date:** 2026-04-17
**Status:** Decided

**Context:**
The desktop needs a self-hosted game streaming server so the laptop can access it remotely over the Headscale mesh. Apollo (Sunshine fork) and Artemis (Moonlight fork) were evaluated as alternatives. The user identified them as potentially superior modern options.

**Evaluation:**
- Apollo is a Sunshine fork with added features (virtual display auto-resolution, per-client permissions, save file management per client).
- Artemis (Moonlight Noir) is its paired client, currently shipping Android APKs only. It does not support Linux or Windows PCs as clients.
- Apollo's virtual display feature -- its primary differentiator -- is currently Windows-only on the server side. Linux support is planned but not yet shipped.
- Apollo is a personal fork. Security maintenance is less rigorous than LizardByte's Sunshine, which has shipped dedicated security fixes.
- For the specific use case of desktop (Linux server) to laptop (Linux client), the client must be Moonlight regardless of the server choice. Mixing Apollo server with Moonlight client is valid but loses the integrated features Apollo/Artemis offer as a matched pair.

**Decision:**
Sunshine (LizardByte, GPL-3.0) as the server on the desktop. Moonlight as the client on the laptop. Apollo/Artemis added to Future Considerations (FC-004) for re-evaluation when Artemis ships a Linux client.

**Rationale:**
- Sunshine is the more mature, better-maintained, better-Linux-supported option for a Linux-to-Linux streaming setup.
- AMD VA-API hardware encoding is well-supported in Sunshine on Linux.
- Moonlight is the only available Linux PC client regardless of server choice.
- Apollo's differentiating features either require Windows or require Artemis as the client. Neither applies here.

**Tradeoffs:**
- Apollo/Artemis may surpass Sunshine/Moonlight once Linux support matures. The decision is revisable.

**Follow-up:**
- Declare Sunshine as a NixOS systemd service on the desktop, with VA-API encoding enabled.
- Declare Moonlight in laptop Home Manager, gated on `tags.laptop`.
- Stream routes over Headscale mesh -- configure Sunshine to accept connections from the Headscale peer IP range.
- Monitor Apollo releases for Linux virtual display and Artemis releases for Linux client. Re-evaluate at next major version of either.

---

## ADR-017: File Sync and Backup Architecture

**Date:** 2026-04-17
**Status:** Decided

**Context:**
The desktop migration removes most local NTFS drives from active use. Active working files need to be available on both machines. Game saves need to survive OS reinstalls. A backup strategy is needed that is not dependent on a single machine or the homelab being available.

**Decision:**
Two-layer architecture:

**Layer 1 -- Active sync (Nextcloud on VM2):**
- Nextcloud deployed on VM2 with a dedicated 1TB ZFS dataset (`tank/nextcloud/data`).
- Nextcloud desktop sync client declared in Home Manager on both machines.
- Game save directories watched by the Nextcloud client and declared in `home/taylor/sync.nix`.
- This is the primary file access layer -- not Google Drive, not a network share.
- 1TB initial allocation. ZFS datasets expand dynamically; no migration needed to increase quota.

**Layer 2 -- Encrypted cold backup (rclone + age -> Google Drive):**
- rclone with age encryption pushes nightly snapshots to Google Drive (2TB, already subscribed).
- What is backed up: Nextcloud data export, Vaultwarden database export, critical home directory contents, VM2 database dumps.
- Google Drive stores only encrypted blobs. Google has no access to plaintext.
- Backup job runs as a scheduled Gitea Actions workflow on VM2.
- This layer is disaster recovery only -- not accessed day-to-day.

**Desktop secondary drive (1.82TB HDD):**
- Formatted to ext4, mounted at `/mnt/overflow`. Declared in NixOS.
- Used for large local scratch files (ISOs, raw assets, large game installs).
- Not synced, not backed up. Treated as replaceable local scratch.

**Rationale:**
- Sync is not backup. Nextcloud versioning helps but is not a substitute for an independent backup target.
- Using Google Drive as a dumb encrypted storage backend extracts value from an existing subscription without creating a dependency on Google's ecosystem.
- A 1TB Nextcloud dataset is sufficient for active working files. The secondary drive handles large files that do not need to live in Nextcloud.
- Gitea Actions as the backup scheduler keeps the automation in the same system as all other scheduled jobs, consistent with FC-002 deferral rationale.

**Tradeoffs:**
- Gitea Actions as backup scheduler means backup failure visibility depends on Gitea being operational. Mitigated by the Alertmanager integration -- a failed backup job sends an alert.
- rclone + age adds a dependency on the age key being available for restoration. The age key is on the break-glass USB (ADR-006).

**Follow-up:**
- Deploy Nextcloud on VM2 with `tank/nextcloud/data` ZFS dataset.
- Declare Nextcloud client in Home Manager with watched sync directories.
- Write rclone backup script, declare age encryption key in sops-nix on VM2.
- Create Gitea Actions scheduled workflow for nightly backup.
- Test restore procedure before declaring backup operational.

---

## ADR-018: Laptop Migration -- Full NixOS, No Dual Boot

**Date:** 2026-04-17
**Status:** Decided (closes OQ-002)

**Context:**
The ThinkPad T15 Gen1 currently runs Windows 11 Pro. The question was whether to dual-boot NixOS alongside Windows or replace Windows entirely.

**Decision:**
Full NixOS. Windows is wiped entirely. No dual-boot partition.

**Rationale:**
- Work will provide a separate machine for any Windows-native requirements. No personal Windows dependency remains.
- Dual-boot adds complexity to the NixOS disk layout, wastes partition space, and creates a second OS to maintain.
- The work AD environment learning goal is better served by the FreeIPA cross-forest trust setup than by keeping a Windows partition.
- By the time migration is complete, no workflow will require Windows.

**Battery note:**
Battery replacement (part 01AV493 or equivalent) is planned before or alongside the migration. The current 2-hour runtime at 100% represents significant degradation. Power management tuning is written for a healthy battery.

**Follow-up:**
- Order replacement battery before scheduling migration.
- Back up any remaining Windows-specific data before wiping.
- Close OQ-002.

---

## FC-004: Apollo + Artemis (Streaming Alternatives)

**Verdict:** Deferred. See ADR-016.
**Trigger:** Artemis ships a stable Linux PC client AND Apollo ships Linux virtual display support. Both conditions must be met -- Artemis Linux client is the binding constraint since Moonlight is required as the client regardless of server choice until then.
**Value when triggered:** Auto-resolution virtual display matching client resolution/framerate, per-client permission management, per-client save file management. Better integrated ecosystem experience than Sunshine/Moonlight.
**Current alternative:** Sunshine + Moonlight. Fully adequate for the current use case.
