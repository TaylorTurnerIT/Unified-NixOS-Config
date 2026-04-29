# Infrastructure Project Rules & Guidelines

> Living document. Update when a new decision is made or a principle is clarified.
> Check this before proposing any new tool, pattern, or architecture change.
> Companion document: DECISIONS.md

---

## 0. North Star

The goal is a **single, declarative, opinionated configuration** that governs every machine, every user, and every service across the homelab, desktop, and laptop — with zero manual configuration steps after initial bootstrap. Any change pushed to the repo propagates everywhere automatically.

---

## 1. Software Philosophy

### 1.1 FOSS First, Always
- Every tool, service, and dependency must be Free and Open Source Software by default.
- If a FOSS tool is inferior in one way, document the tradeoff and accept it rather than reaching for a proprietary option.
- **Exception — Proprietary Consideration Gate:** If a proprietary tool is demonstrably, significantly ahead of every FOSS alternative in ways that materially affect the use case, it may be brought to consideration. This is not a fast path. Before any proprietary tool is adopted, a structured evaluation must be written covering: what the tool does, why no FOSS alternative is sufficient, full feature comparison, licensing and data portability risks, vendor lock-in exposure, cost over time, and the exit strategy if the tool is discontinued or changes terms. The default answer is still FOSS. The gate exists for genuinely exceptional cases, not for convenience.

### 1.2 Prefer Established, Linux-Native Tools
- Prefer tools that are well-integrated with the Linux ecosystem and have a strong maintenance track record.
- Avoid tools that exist primarily as SaaS wrappers or that depend on third-party cloud infrastructure to function.

### 1.3 Podman Over Docker, Always
- **Podman is the container runtime for all services.** Docker is not used anywhere in this project.
- Reason: Podman is daemonless, rootless by default, systemd-native, and ships as a first-class citizen on both NixOS and Fedora-based systems. Docker requires a privileged background daemon and introduces unnecessary attack surface.
- All containers run rootless unless a specific, documented technical constraint forces otherwise.
- Docker Compose files encountered in the wild are treated as a starting point only — they are converted to Podman-compatible `quadlet` units or `podman-compose` equivalents before use.
- `docker` as a CLI alias for `podman` is acceptable for developer ergonomics but the underlying runtime is always Podman.
- **Containers that must spawn other containers (e.g., the Gitea Actions runner launching ephemeral build containers) never receive direct access to the host Podman socket.** Instead, a dedicated **Podman socket proxy container** sits between the socket and the consuming container, exposing only the specific API endpoints that container legitimately needs (e.g., container create, start, stop, logs — not image push, network manipulation, or volume deletion). The proxy is declared alongside the consumer in NixOS config and is the only container with a bind-mount to the Podman socket. This preserves rootless isolation: a compromised build container cannot escape to the host runtime or manipulate unrelated containers even if it breaks out of its own sandbox.

### 1.4 Everything Runs in a Container
- All services deployed on the homelab must be containerized. No bare-metal service installs.
- Exceptions require explicit justification: SSSD and Kerberos client daemons run on the host because they are OS-level identity infrastructure, not application services. Headscale also runs directly on the Network/Identity VM for the same reason.
- Container definitions are declared in NixOS (via Podman quadlet modules or NixOS container options) or in OpenTofu — not written by hand and started manually.
- Services that do not ship a container image must be packaged as one before deployment.

### 1.5 Avoid Lock-In
- No tool should create a dependency that makes migrating away from it prohibitively difficult.
- Data and configuration must be exportable in open formats.

---

## 2. Infrastructure as Code

### 2.1 Everything is Declarative
- If something can be declared in code, it must be. No manual configuration of any system that is in scope.
- Undeclared state is technical debt. If it exists, it must eventually be codified.

### 2.2 OpenTofu is the IaC Tool
- **OpenTofu** (not Terraform) is the chosen IaC tool for all provider-managed resources (FreeIPA, Authentik, DNS, Headscale ACLs, etc.).
- Reason: FOSS fork of Terraform, fully compatible, actively maintained, no BSL license concerns.

### 2.3 NixOS is the OS Layer
- All machines (desktop, laptop, homelab VMs) run NixOS as their OS.
- The migration path for non-NixOS machines (Bazzite desktop, Windows laptop) leads to NixOS. Interim states are acceptable during migration phases.
- **No `configuration.nix` outside the flake repo.** All config lives in the shared monorepo.
- The Oracle VPS runs Ubuntu with Nix (not full NixOS) due to Oracle Cloud constraints. Its Nix-managed services follow the same flake and declarative patterns as NixOS hosts where possible.

### 2.4 Flakes Only
- All Nix configuration uses flakes. Legacy channel-based configuration is not used.
- `flake.lock` is committed and kept up to date.

### 2.5 Home Manager Runs as a NixOS Module
- Home Manager is integrated into the NixOS module system, not run standalone.
- `nixos-rebuild switch` is the single command that applies both system and user config.

---

## 3. Repository Structure

### 3.1 Single Monorepo
- One Git repository (hosted on the homelab Gitea) contains all NixOS configs, OpenTofu state and plans, secrets references, and documentation.
- Cross-cutting concerns live in shared modules, not duplicated per-host.

### 3.2 Host Configuration via Feature Tags
- Each host declares a set of boolean feature tags (e.g., `gaming`, `amdGpu`, `laptop`, `hdr`).
- A `mkHost` helper in `lib/` composes the correct module set from these tags.
- No host-specific logic should live outside `hosts/<hostname>/`.

### 3.3 Module Layering
```
modules/core/                  -> applied to every host, no exceptions
  modules/core/ssh-recording.nix -> tlog session recording via SSSD (all hosts)
  modules/core/ssh.nix           -> OpenSSH hardening (all hosts)
modules/desktop/               -> KDE + Wayland stack
modules/hardware/              -> GPU, display, peripheral profiles
modules/gaming/                -> Steam, Proton, gamemode, controllers
modules/laptop/                -> power, HiDPI, wifi
modules/work/                  -> dev tools, secrets
home/                          -> Home Manager, user dotfiles
  home/taylor/security.nix     -> SSH client config, ProxyJump convention, key config
```

---

## 4. Identity & Authentication

### 4.1 FreeIPA is the Source of Truth
- FreeIPA is the authoritative identity directory for all users, groups, hosts, sudo rules, and HBAC policies.
- **No user is declared in `users.users` in NixOS** (except a minimal bootstrap/emergency local account).
- FreeIPA runs as a Podman container on VM1 (Network & Identity).

### 4.2 Authentik is the Web SSO Layer
- Authentik provides OIDC/SAML SSO for all self-hosted web applications (Gitea, Grafana, Nextcloud, etc.).
- Authentik is **not** the source of truth for users — it syncs from FreeIPA via LDAP.
- FreeIPA create/disable operations propagate automatically to Authentik.

### 4.3 SSSD on Every Client
- Every NixOS machine runs SSSD, configured to authenticate against FreeIPA.
- `cache_credentials = true` is mandatory for the laptop (offline use case).
- SSH public keys are stored in FreeIPA and retrieved via SSSD's SSH key integration.

### 4.4 One Login Everywhere
- A single set of credentials (Kerberos principal) grants access to: OS login (SDDM/PAM), SSH, sudo (via FreeIPA sudo rules), and all web apps (via Authentik OIDC, using FreeIPA as the backend).
- MFA is handled at the Authentik layer for web apps. Kerberos tickets handle OS-level SSO.

### 4.5 Active Directory Interoperability
- FreeIPA is configured with a cross-forest trust to Active Directory for work environment compatibility.
- The laptop is the primary machine for AD bridge scenarios.
- SSSD on the laptop is configured to handle both the home FreeIPA realm and, when on the work network, the AD realm.
- This setup also serves as a live learning environment for AD administration skills.

### 4.6 Declarative User Management via OpenTofu
- All users, groups, HBAC rules, and sudo policies are declared in OpenTofu using the FreeIPA provider.
- Adding a user = adding a resource block and running `tofu apply`. No manual `ipa` CLI calls in steady state.
- Authentik application registrations and LDAP sync config are also managed via OpenTofu.

### 4.7 Family / Multi-User Model
- The identity system is designed to support multiple household users, each with declarative, scoped permissions.
- HBAC rules enforce which users can access which machines (personal machines vs. homelab nodes).
- New family members are added by declaring a `freeipa_user` resource and the relevant HBAC/group memberships in OpenTofu.

---

## 5. Secrets Management

### 5.1 sops-nix for NixOS Secrets
- All secrets embedded in the NixOS configuration (API keys, passwords, private keys) use sops-nix.
- Each host has an age key at `/etc/sops-age-key`.
- Secrets are committed encrypted. Plaintext never touches the repo.

### 5.2 Secrets Scope
- Secrets are scoped to the minimum set of hosts that require them.
- Homelab-only secrets do not appear in desktop or laptop host configs.

---

## 6. Security

### 6.1 Security Philosophy — Silent and Opinionated
- Security is a first-class, non-negotiable requirement on par with functionality.
- However, security must never meaningfully degrade usability or convenience. Friction that trains users to work around security controls is worse than no control at all.
- The target posture is **silent security**: hardened defaults, automated enforcement, and invisible-to-the-user protections that require no ongoing manual action. Security events surface only when they need human attention.
- When a tradeoff between security and usability arises, document it explicitly. Do not quietly sacrifice one for the other.

### 6.2 Passkeys and Passwordless Authentication
- **Passkeys are the preferred authentication method everywhere they are supported.** Passwords are a fallback of last resort, not a default.
- **Vaultwarden** is the self-hosted password manager and passkey store. It is the single source for all credentials, OTP codes, and passkey storage across all devices and users.
- Vaultwarden is treated as critical infrastructure — it receives the same availability and backup treatment as FreeIPA.
- The authentication preference hierarchy is: Passkey > hardware key (FIDO2) > TOTP > strong generated password. Weak, reused, or manually chosen passwords are never acceptable for any service in scope.
- Authentik MFA flows are configured to prefer WebAuthn/passkeys where the client supports it.

### 6.3 Network Security — Zero Implicit Trust
- **Headscale** is the self-hosted WireGuard mesh control plane connecting all personal machines (desktop, laptop, homelab VMs, Oracle VPS). See ADR-001.
- No personal service is exposed to the raw public internet directly.
- Public-facing services egress through the **Oracle VPS forward proxy** (Ubuntu + Nix + Caddy). The homelab's real IP is never published in public DNS or logs.
- The Oracle VPS is a hardened DMZ node. Beyond its Caddy proxy role, it runs a minimal redundant monitoring stack (VictoriaMetrics, Alertmanager, ntfy.sh) to provide off-site alerting when homelab services are unavailable. See ADR-021. No user data, homelab secrets, or identity material lives on it.
- Internal services are reachable only over the Headscale mesh or from within VLAN 20. They are never exposed via public DNS or open firewall ports.
- The principle of least privilege applies to network paths as much as to user permissions. VLAN segmentation enforces this at the physical/L2 layer — see Section 10.

### 6.4 Updates and Patch Management
- Security updates are applied promptly. "I'll do it later" is not an acceptable update policy.
- **Renovate Bot** (self-hosted) is the automated dependency update system. It opens PRs for NixOS flake input updates, container image digest bumps, and package version changes, with changelogs attached. See ADR-002 and Section 7.4.
- NixOS system updates flow through the normal Gitea Actions pipeline. Security-tagged PRs are treated as high priority and fast-tracked.
- The Oracle VPS runs `unattended-upgrades` for OS-level security patches. Nix-managed services follow the digest-pin + Renovate PR pattern.
- Kernel updates are not blocked or delayed. Breakage from a kernel update is fixed; the update is not reverted.

### 6.5 Secrets Hygiene
- No secret, credential, or key is ever committed in plaintext to any repository, including private ones.
- SSH authentication uses Ed25519 keys only. RSA keys are not generated or trusted.
- All SSH keys are stored in FreeIPA and backed up in Vaultwarden. No key exists only on a single machine.
- Root login over SSH is disabled on all hosts. Password-based SSH authentication is disabled on all hosts.
- Service accounts get their own credentials. No service shares a credential with a human user account.

### 6.6 Firewall and Host Hardening
- All hosts run a deny-by-default firewall (`networking.firewall` in NixOS). Every open port is explicit and documented.
- Systemd service hardening options (`PrivateTmp`, `ProtectSystem`, `NoNewPrivileges`, `CapabilityBoundingSet`, etc.) are applied to all custom services. Defaults are not left unexamined.
- Brute-force protection (`fail2ban` or equivalent) runs on any host with a publicly reachable port — primarily the Oracle VPS.
- Rootless Podman containers provide an additional isolation boundary. No container runs `--privileged` unless explicitly justified and documented.

### 6.7 Certificates and PKI
- The FreeIPA internal CA is the trust root for all internal TLS (homelab services, LDAP, Kerberos KDC).
- All NixOS hosts trust the FreeIPA CA certificate, deployed declaratively via the NixOS config.
- Public-facing services on the Oracle VPS use Let's Encrypt certificates via Caddy's ACME integration.
- Self-signed certificates are never used for any service. Certificate expiry is monitored and alerted.

### 6.8 Audit and Visibility
- Logs from all critical services (FreeIPA, Authentik, SSSD, Vaultwarden, Caddy, Headscale) are aggregated centrally in VM3 (Observability). A log nobody reads is not a security control.
- Failed authentication attempts, HBAC denials, and sudo usage are surfaced in the monitoring stack.
- Security-relevant events generate alerts. Alerts must be actionable and specific — alert fatigue defeats the purpose entirely.
- **Alerting delivery:** Alertmanager routes alerts via webhook to self-hosted ntfy.sh on VM2. ntfy.sh pushes to personal devices (phone, desktop) on three severity topics: `infra-critical` (immediate), `infra-warning` (check within the hour), `infra-info` (informational). See ADR-020.
- **Alert rules use time windows, not instantaneous thresholds.** A single anomalous data point is noise. A sustained condition is a real event. Example: "alert if `freeipa_auth_failures > 10` for 5 minutes" not "alert if `freeipa_auth_failures > 10` at any point." All Alertmanager rules are written with explicit `for:` duration clauses.
- **Loki log streams follow a Medallion structure** (Bronze -> Silver -> Gold) to prevent unstructured log sprawl:
  - Bronze: raw logs exactly as emitted by the service, retained 14 days. Loki chunks stored in MinIO `loki-chunks/` bucket -- log storage scales without VM3 disk pressure.
  - Silver: parsed and labeled streams with structured fields extracted at ingest time via Loki pipeline stages (e.g., extracting `user`, `event_type`, `source_ip` from FreeIPA audit logs). Used for operational queries and investigations.
  - Gold: Prometheus metrics derived from log patterns via Loki's recording rules or Prometheus relabeling. Examples: `freeipa_auth_failures_total`, `caddy_5xx_rate`, `sssd_cache_miss_rate`. Used for dashboards and alerting. Gold-layer metrics are what Alertmanager evaluates — never raw log queries.

### 6.9 SSH Session Recording — tlog
- Every terminal session on every enrolled host is recorded using **tlog** (Red Hat, GPL-2.0), integrated via SSSD's built-in session recording support. This is the SSH audit layer.
- **Integration point:** SSSD 1.16+ has a native `[session_recording]` config block. When enabled, SSSD invokes `tlog-rec-session` automatically as the session wrapper for any FreeIPA-authenticated login. No per-service PAM configuration required — it applies universally to all SSH sessions on all SSSD-enrolled hosts from a single config block in `modules/core/ssh-recording.nix`.
- **What is recorded:** Every keystroke typed and every byte of output returned, with millisecond timestamps, session duration, authenticated username, and source IP. Recordings are structured JSON, not flat text — they are searchable, not just readable.
- **Where recordings go:** tlog writes to journald under the `tlog` syslog identifier. Loki's journald scraper picks this up automatically via the existing log pipeline. No new infrastructure is needed. Sessions are queryable in Grafana and retained at the Bronze layer with a long retention window.
- **What this enables:** Full replay of any terminal session from Grafana. Searchable audit trail: "every command run as root on VM2 in the last 30 days." Alerting on specific command patterns (e.g., `rm -rf` on a persist path). Forensic reconstruction of any incident.
- tlog is declared in `modules/core/ssh-recording.nix` and applied to every host including personal machines. There is no host where an SSH session is unrecorded.
- Session recordings are retained at a longer window than operational logs — they are the audit layer, not the debugging layer. Retention policy is declared separately in the Loki config.

---

## 7. Deployment & CI/CD

### 7.1 Gitea Actions is the CI/CD Platform
- All automation runs on Gitea Actions with a self-hosted runner on the homelab.
- The pipeline on `main` push: lint/eval -> build all host toplevels -> deploy via deploy-rs -> notify on failure.

### 7.2 deploy-rs for Safe Deployment
- `deploy-rs` is the deployment tool (not colmena, not raw SSH).
- Reason: flake-native, per-profile rollback on activation failure, essential for unattended laptop and VM deployments.

### 7.3 Binary Cache via attic
- All builds happen on the homelab runner, not on the target machines.
- Build outputs are pushed to an `attic` binary cache hosted on VM2.
- Target machines substitute from the cache rather than building locally.
- This is a hard performance requirement — deploy times must be measured in seconds, not minutes.

### 7.4 Renovate Bot for Automated Updates
- Renovate Bot runs self-hosted as a scheduled Podman container on VM2, triggering nightly.
- It opens PRs against the monorepo for: NixOS flake input updates, container image digest bumps, and any other tracked package ecosystems.
- Every PR includes upstream changelogs and release notes.
- Patch-level container digest bumps with passing CI may be configured for automerge. Minor and major updates always require manual review before merge.
- A dedicated `renovate` bot user is declared in FreeIPA/OpenTofu with scoped write access to the monorepo only.
- See ADR-002.

### 7.5 Rollback is a First-Class Requirement
- Every deployment must be recoverable. deploy-rs rollback semantics satisfy this.
- Untested configs must not be pushed to `main` directly. Use a branch + PR flow.

### 7.6 Deployment Strategy Policy per Host
Three deployment strategies are recognized. The correct one depends on the host and service type. See ADR-012.

**Blue-Green (two complete environments, instant traffic switch, instant rollback):**
- Applies to: VM1 (Network & Identity) always, and any stateful service on VM2 (FreeIPA, Vaultwarden, Gitea, Authentik).
- NixOS system generations implement this natively — a `nixos-rebuild switch` to a new generation leaves the previous generation bootable as an immediate rollback target.
- Never run mixed old/new versions of stateful services simultaneously. Always switch cleanly.

**Rolling (gradually replace running instances with the new version):**
- Acceptable for: VM3 (Observability), stateless services on VM2, and container image updates where no data migration is involved.
- Renovate-triggered container digest bumps on stateless services default to rolling.
- Not acceptable for VM1 or any service with persistent state that could be corrupted by a version mismatch during transition.

**Canary (small traffic percentage to new version before full rollout):**
- Not yet applicable — requires multiple replicas of a service. Revisit when the HA second physical machine introduces FreeIPA and Headscale replicas.

**VM4 (DMZ):**
- Any strategy is acceptable. VM4 services are treated as disposable. Rolling is the default for simplicity.

---

## 8. Desktop Environment

### 8.1 KDE Plasma on Wayland
- KDE Plasma 6 with KWin on Wayland is the desktop environment for all graphical machines. No exceptions.
- SDDM is the display manager.

### 8.2 Monitor Plug-and-Play
- The NixOS config sets Wayland env vars and KWin flags (HDR, scaling hints).
- KScreen manages runtime monitor layout profiles per connected display set.
- The declarative layer does not hard-code monitor arrangements (EDIDs vary per physical setup).

### 8.3 Gaming
- All gaming configuration lives in `modules/gaming/` and is gated behind `tags.gaming = true`. Nothing in this module is applied to the laptop or homelab hosts.
- Steam is enabled via `programs.steam.enable = true` (not as a plain package). This activates the FHS-compatible chroot Steam requires, controller support, and 32-bit library wiring. Unfree packages for Steam are permitted via `allowUnfreePredicate` scoped to `steam` and `steam-unwrapped` only -- not a blanket `allowUnfree = true`.
- Firewall: `programs.steam.remotePlay.openFirewall = true` and `programs.steam.dedicatedServer.openFirewall = true` are declared. The deny-by-default firewall (Section 6.6) otherwise blocks these ports.
- Proton-GE is managed declaratively via the `nix-gaming` flake. This is the authoritative Proton-GE source. ProtonUp-Qt is not used -- it is the imperative alternative and conflicts with the declarative philosophy.
- `programs.gamemode.enable = true` -- lets supported games request high-performance CPU governor and GPU settings for the duration of the session.
- `programs.gamescope.enable = true` -- micro-compositor for upscaling, frame limiting, and VRR-friendly fullscreen behavior on Wayland.
- MangoHUD is installed as a system package for GPU/CPU/FPS overlay. GOverlay is installed alongside it as a GUI editor for MangoHUD config, avoiding hand-editing `MangoHUD.conf`.
- `steam-run` is declared and documented as the FHS fallback for native Linux game binaries that expect standard library paths (`/lib`, `/usr/lib`) and fail on NixOS. Any non-Steam Linux executable that refuses to launch should be tried with `steam-run <binary>` before any other debugging.
- **Game launchers beyond Steam:**
  - Heroic Games Launcher: Epic Games and GOG library access. Declared in the gaming module. Primary tool for non-Steam storefronts.
  - Lutris: multi-source launcher with flexible Wine configuration. Last-resort tool when Steam, Heroic, and direct Proton do not cover a title.
  - Bottles: Wine prefix manager for standalone Windows executables with no storefront. Not declared in the standard gaming module -- available as a one-line addition when a specific need arises.
- Controller support: PS5 (DualSense), Xbox, and Switch Pro via `hid-nintendo` and `xpadneo` udev rules.
- ProtonDB is the reference for checking Linux compatibility before purchasing a title. Consult it for any game that does not have a native Linux build.

---

## 9. Hardware Profiles

### 9.1 GPU Profiles are Modules
- AMD GPU config lives in `modules/hardware/gpu/amd.nix`. Intel iGPU config lives in `modules/hardware/gpu/intel.nix`. Activated via host tags, never hard-coded per host.
- **AMD module (`modules/hardware/gpu/amd.nix`) declares:**
  - `services.xserver.videoDrivers = ["amdgpu"]`
  - `hardware.graphics.enable = true` and `hardware.graphics.enable32Bit = true` -- the 32-bit library flag is mandatory for Proton to run 32-bit Windows titles. Without it, a large portion of the game back-catalogue will silently fail. Note: `hardware.graphics` is the NixOS 24.05+ name, replacing the legacy `hardware.opengl`.
  - ROCm compute libraries for GPU-accelerated workloads.
  - RADV environment variables for Vulkan tuning.
  - `lact` (Linux AMD GPU Control Application) -- GUI for fan curves, power limits, and GPU monitoring. The Linux equivalent of AMD Adrenalin's basic controls. Declared here rather than as a system package so it is always co-located with the driver config.
  - `amdgpu_top` for CLI GPU utilization monitoring.
- **Intel module (`modules/hardware/gpu/intel.nix`) declares:**
  - `services.xserver.videoDrivers = ["modesetting"]` (preferred over the legacy `intel` driver on modern kernels)
  - VA-API hardware video decode via `intel-media-driver` (iHD, required for 10th gen i7-10610U)
  - `hardware.graphics.enable = true` -- 32-bit not required on the laptop since gaming is not enabled there.

### 9.2 Laptop Power Management
- Laptop hosts enable `modules/laptop/power.nix` which configures TLP or auto-cpufreq, suspend behavior, and lid actions.
- This module is never applied to desktop or homelab hosts.

### 9.3 nixos-hardware
- The `nixos-hardware` flake is an input to the monorepo flake. It provides community-maintained, hardware-specific NixOS modules for known machines covering kernel modules, firmware, thermal management, and device-specific quirks.
- The ThinkPad T15 Gen1 laptop imports the closest matching module from `nixos-hardware` (verified at install time -- likely `nixos-hardware.nixosModules.lenovo-thinkpad-t14s` or a direct T15 equivalent if one exists). This handles `iwlwifi` firmware, trackpoint configuration, power management defaults, and the fingerprint reader kernel interface -- all things that are tedious and error-prone to configure manually.
- The desktop (MS-7A71, consumer motherboard) does not have a `nixos-hardware` module. Hardware configuration is declared explicitly in `modules/hardware/gpu/amd.nix` and `hosts/desktop/hardware.nix` generated by `nixos-generate-config`.
- When adding any new machine, check the `nixos-hardware` flake module list before writing any manual hardware configuration. If a module exists, import it and patch only what it does not cover.

---

## 10. Networking & DNS

### 10.1 Domain Architecture
- Registered domain: `tongatime.us`, managed exclusively via OpenTofu on Cloudflare. The Cloudflare dashboard is never used for manual DNS edits.
- Internal subdomain: `internal.tongatime.us`. FreeIPA BIND is authoritative for this subdomain only.
- Public zone: `tongatime.us` remains under Cloudflare authority. FreeIPA forwards non-internal queries upstream to Cloudflare — no record mirroring required.
- Kerberos realm: `TONGATIME.US`. FreeIPA domain: `internal.tongatime.us`.
- All internal services are accessed at `<service>.internal.tongatime.us`. All public services at `<service>.tongatime.us`.
- Internal service names have no Cloudflare record and are unresolvable from outside the network by design. No firewall rule is required to enforce this — DNS resolution fails at the external boundary.
- See ADR-011 for full architecture rationale, how-it-works, and the comparison against the alternative (FreeIPA owning the full zone).

**Service namespace:**
```
Public (Cloudflare A records -> Oracle VPS IP):
  mc.tongatime.us              Minecraft server
  hs.tongatime.us              Headscale coordination endpoint

Internal (FreeIPA BIND -> VLAN 20 IPs, no public DNS record):
  ipa.internal.tongatime.us    FreeIPA admin UI
  auth.internal.tongatime.us   Authentik SSO
  git.internal.tongatime.us    Gitea
  vault.internal.tongatime.us  Vaultwarden
  grafana.internal.tongatime.us  Grafana
  cache.internal.tongatime.us  attic binary cache

Management (FreeIPA BIND -> VLAN 10 IPs, unreachable from VLAN 20+):
  idrac.internal.tongatime.us  iDRAC6 out-of-band management
  switch.internal.tongatime.us Managed switch
  router.internal.tongatime.us OPNsense admin UI
```

**TLS certificates:**
- All certificates (internal and public) are issued by Let's Encrypt via DNS-01 ACME challenge against the Cloudflare API.
- DNS-01 requires no public HTTP reachability — `vault.internal.tongatime.us` gets a real browser-trusted certificate despite being unreachable from outside.
- Caddy on each VM uses the Cloudflare DNS provider plugin. The Cloudflare API token (scoped to DNS edit on `tongatime.us` only) is stored in sops-nix.
- The FreeIPA internal CA issues certificates for Kerberos KDC and LDAP only. It is not used for browser-facing service TLS.

### 10.2 Overlay Mesh — Headscale
- Headscale is the self-hosted WireGuard mesh control plane. All personal machines, homelab VMs, and the Oracle VPS are enrolled as peers. See ADR-001.
- Headscale runs directly on VM1 (not in a container) as it is core network infrastructure.
- Headscale coordination endpoint is `hs.tongatime.us` — a public Cloudflare A record pointing at the Oracle VPS, which proxies the coordination traffic through to VM1 via Caddy. This means Headscale's control plane is reachable for peer enrollment from anywhere without exposing VM1 directly.
- Headscale ACLs are declared in OpenTofu and enforce which peers can communicate — not all peers can reach all peers. See ADR-007.
- Standard Tailscale clients are used on all endpoints (fully compatible with Headscale). No Tailscale coordination servers are contacted.

### 10.3 VLAN Segmentation
Physical network traffic is segmented into six VLANs, enforced by a managed switch and an OPNsense (or equivalent) router with stateful inter-VLAN firewall rules.

```
VLAN 10 — Management
  Hosts:    Router admin interface, managed switch, IPMI/BMC, hypervisor control plane.
  Internet: None — no outbound internet access, ever.
  Access:   Admin-only, initiated from VLAN 30 (Trusted) on declared ports only.
  Rule:     No other VLAN initiates connections here. Most locked-down segment.

VLAN 20 — Infrastructure
  Hosts:    VM1 (Network/Identity), VM2 (App Services), VM3 (Observability).
  Internet: Outbound only — update pulls and Let's Encrypt ACME. No inbound from internet.
  Access:   VLAN 30 (Trusted) can reach declared service ports only.
            VM-to-VM communication within this VLAN is further restricted by per-VM
            host firewalls and Podman networks — VLAN adjacency is not open access.
  Rule:     Infrastructure never initiates connections to user VLANs.

VLAN 30 — Trusted / Private
  Hosts:    Desktop, laptop, partner's devices, fully trusted personal hardware.
  Internet: Full outbound.
  Access:   Can reach VLAN 20 services on declared ports. Can manage VLAN 10 on declared
            admin ports. Can push commands to VLAN 40 on declared control ports only.
  Rule:     Highest-privilege user VLAN. Still subject to declared firewall rules.

VLAN 40 — IoT
  Hosts:    Smart home devices, TVs, printers, streaming sticks, game consoles,
            and any embedded or consumer device that cannot be fully audited.
  Internet: Outbound allowed (most IoT devices require cloud access).
  Access:   Cannot initiate connections to any other VLAN. Wireless client isolation
            enabled — IoT devices cannot communicate with each other laterally.
  Rule:     Treat every device here as potentially compromised.

VLAN 50 — Guest
  Hosts:    Visitor devices, temporary access.
  Internet: Outbound only, rate-limited.
  Access:   Zero visibility into any other VLAN.
  Rule:     No credentials, no internal DNS, no homelab access whatsoever.

VLAN 60 — DMZ / Public Servers
  Hosts:    VM4 (User/Public Services) — game servers, public-facing services.
  Internet: Inbound on declared ports + full outbound.
  Access:   Can reach VLAN 20 only on declared auth callback ports. Cannot reach any
            other VLAN.
  Rule:     Treat all hosts here as untrusted. Assume compromise is possible.
            The Oracle VPS handles most public-facing use cases — this VLAN exists
            for on-prem services that genuinely require inbound internet connections.
```

### 10.4 Podman Networks Within VMs
- VLANs are the L2/L3 boundary between VMs. Podman networks are the L2 boundary between containers within a VM. Both layers are active and complementary.
- Every service group runs on a named, isolated internal Podman network. Containers are added to networks explicitly — only connections required for the service to function are permitted.
- Only containers that must be reachable from outside the VM publish ports to the VM's VLAN interface. Backend containers (databases, caches, workers) are never directly reachable from the VLAN.
- Example: Authentik's worker, Redis, and PostgreSQL share a private Podman network. Only the Authentik proxy publishes a port to VLAN 20. Redis and PostgreSQL are unreachable from outside the VM.
- Podman network definitions are declared in NixOS config, not created manually.

### 10.5 Inter-VLAN Routing Rules Summary
```
Source          Destination        Verdict
-----------     ---------------    -------
VLAN 10         Any                Deny all outbound (management interfaces only)
VLAN 20         Internet           Allow outbound (updates, ACME)
VLAN 20         Any VLAN           Deny initiated outbound connections
VLAN 30         VLAN 20            Allow on declared service ports
VLAN 30         VLAN 10            Allow on declared admin ports only
VLAN 30         VLAN 40            Allow on declared control ports only
VLAN 30         Internet           Allow full outbound
VLAN 40         Any VLAN           Deny all
VLAN 40         Internet           Allow outbound
VLAN 50         Any VLAN           Deny all
VLAN 50         Internet           Allow outbound (rate-limited)
VLAN 60         VLAN 20            Allow on declared auth callback ports only
VLAN 60         Any other VLAN     Deny all
Internet        VLAN 60            Allow on declared public ports
Internet        Any other VLAN     Deny all
```

---

## 11. Homelab Architecture & VM Separation

### 11.1 Philosophy — Isolation Without Sprawl
- Services are separated across VMs to contain blast radius, enable independent update and reboot cycles, and enforce clean dependency boundaries.
- VMs on a single physical host do **not** provide high availability against host hardware failure — they provide operational isolation. True HA against a host going down requires a second physical machine and is a future goal (see 11.7).
- The VM count is kept minimal. New VMs require explicit justification. Preference is to add a service to an existing VM unless there is a meaningful isolation reason not to.

### 11.2 VM Layout

```
VM1 — Network & Identity         (highest priority — everything else depends on this)
  VLAN:     20 (Infrastructure), peered into Headscale mesh
  Services: Headscale, FreeIPA (Podman), internal DNS (via FreeIPA BIND), Caddy
  Reboot:   Almost never. Changes here are the most carefully staged and tested.
  Why:      Identity and name resolution underpin every other service. Separating this VM
            means rebooting VM2, VM3, or VM4 does not affect auth or DNS.

VM2 — Application Services       (stateful, tolerates brief downtime)
  VLAN:     20 (Infrastructure)
  Services: Gitea, Authentik, Vaultwarden, Nextcloud, Renovate Bot, attic binary cache,
            Redis (shared cache — see 11.2a)
  Reboot:   Low frequency. Most Renovate-triggered updates apply here.
  Why:      These services are important but a 30-60 second blip does not break workflows.
            Grouping them keeps the VM count manageable.

VM3 — Observability              (must survive VM1 and VM2 going down to be useful)
  VLAN:     20 (Infrastructure)
  Services: Grafana, Loki, Prometheus, Alertmanager
  Reboot:   Infrequent, on its own independent schedule.
  Why:      Monitoring must be isolated from what it monitors. If observability is on VM2
            and VM2 goes down, there is no visibility into the outage. This separation is a
            correctness requirement, not a preference.

VM4 — User / Public Services     (lowest priority, safe to reboot or destroy at any time)
  VLAN:     60 (DMZ)
  Services: Game servers, public Minecraft, any service requiring inbound internet connections
  Reboot:   On-demand.
  Why:      Public-facing services carry a different threat model. Placing them in their own
            VM and in the DMZ VLAN means a compromise here cannot laterally reach identity
            or application infrastructure.
```

### 11.2a Redis — Shared Cache Service on VM2
Redis is deployed as a single shared instance on VM2 rather than duplicated per service. It is already a hard dependency of Authentik; formalizing it as shared infrastructure avoids redundant instances as the service count grows.

- Redis runs as a rootless Podman container on VM2's internal Podman network.
- Applications connect to Redis using **logical database separation** (`SELECT 0` for Authentik, subsequent integers for each additional consumer) — no data crosses between application namespaces.
- Redis is not published to the VLAN 20 interface. It is only reachable from containers on VM2's internal Podman network. No service on another VM connects to Redis directly.
- If a future service requires cross-VM cache access, that service gets its own Redis instance on its own VM. The shared instance is VM2-local only.
- Redis is declared in NixOS as a quadlet unit. Persistence (`appendonly yes`) is enabled so cache state survives container restarts. The persistence file lives on the VM2 ZFS dataset.

### 11.3 Physical Host -- Dell PowerEdge C2100

```
Chassis:    Dell PowerEdge C2100, 2U rackmount
CPUs:       2x Intel Xeon X5675 (6 cores / 12 threads each, 3.06GHz base, Turbo)
            Total: 12 cores / 24 threads
RAM:        144GB DDR3 ECC (18x 8GB dual-rank RDIMMs @ 1333MHz)
Storage:    16x 600GB 2.5" SAS drives (hardware backplane with SAS expander)
            Configured as ZFS RAIDZ2 (16-disk, 2-drive fault tolerance)
            Usable: ~8.2TB raw ((16-2) x 600GB)
Management: iDRAC6 (Express built-in; Enterprise NIC upgrade recommended -- see 11.6)
Network:    Onboard dual-port Intel GbE (LOM) + additional PCIe NICs as needed
```

**Storage note -- ZFS RAIDZ2 over hardware RAID 6:**
NixOS has native, first-class ZFS support. ZFS provides per-block checksumming, silent corruption detection, and native snapshots that hardware RAID controllers do not. ZFS snapshots are used directly for VM disk image backups before major updates. Eliminating dependence on a proprietary RAID controller removes a firmware black box from the path. RAIDZ2 provides identical two-drive fault tolerance to RAID 6 with full auditability.

**Planned VM resource allocation:**
```
Host OS overhead:          4 vCPU,  8GB RAM
VM1 Network & Identity:    4 vCPU, 12GB RAM  (FreeIPA is memory-intensive)
VM2 Application Services:  6 vCPU, 32GB RAM  (multiple stateful services)
VM3 Observability:         4 vCPU,  8GB RAM
VM4 DMZ / Public:          4 vCPU,  8GB RAM
                          --       -------
Total allocated:          22 vCPU, 68GB RAM
Unallocated reserve:       2 vCPU, 76GB RAM  (future VMs or burst headroom)
```

### 11.4 Hardware Inventory -- Personal Machines

```
Desktop (MS-7A71):
  CPU:      Intel Core i7-7700K (4 cores / 8 threads, 4.5GHz boost)
  GPU:      AMD Radeon RX 6700 XT (discrete, amdgpu)
  RAM:      32GB DDR4
  Storage:  ~930GB SSD (primary, NixOS target)
            ~1.82TB HDD (secondary, local overflow scratch -- keep installed, pre-configured)
  Display:  3x external monitors (1920x1080 60Hz, 1920x1080 144Hz, 2560x1440 180Hz HDR)
  OS:       Bazzite DX -> NixOS migration
  Tags:     gaming=true, amdGpu=true, multiMonitor=true, hdr=true, laptop=false
  Peripherals: Razer Kiyo webcam, LG G915 TKL keyboard (wireless), Logitech G502 Hero mouse

Laptop (Lenovo ThinkPad T15 Gen1 -- 20S7S4CW06):
  CPU:      Intel Core i7-10610U (4 cores / 8 threads, 4.9GHz boost)
  GPU:      Intel UHD Graphics (integrated only, no discrete -- clean iGPU setup)
  RAM:      32GB DDR4
  Storage:  ~953GB SSD (single drive, ~41% used pre-migration)
  Display:  1920x1080 @ 1.25x scaling in 16" built-in (60Hz)
  Battery:  Degraded -- replacement (01AV493 or equivalent) planned before migration
  OS:       Windows 11 Pro -> Full NixOS (no dual-boot, see ADR-018)
  Tags:     gaming=false, amdGpu=false, intelGpu=true, laptop=true, hidpi=true
  Built-in: Fingerprint reader (libfprint compatible), TPM 2.0, WiFi 6
  Notes:    Primary use is mobile productivity. Battery life over performance.
            Always connected over WiFi -- never docked as primary use.
```

### 11.5 Out-of-Band Management -- iDRAC6

The Dell PowerEdge C2100 includes iDRAC6, Dell's Baseboard Management Controller (BMC). It is an independent microcontroller that runs continuously as long as the server has power, entirely separate from the main CPUs and OS. It provides remote console access, power control, hardware health monitoring, and remote ISO mounting regardless of the state of the host OS or any VM.

**iDRAC6 Express vs. Enterprise:**
- Express (built-in): Uses a shared LOM port. The iDRAC and the host OS share the same physical NIC, making true VLAN 10 isolation difficult since the port carries both management and host traffic.
- Enterprise (add-in card): Provides a dedicated physical NIC exclusively for iDRAC. This is the correct configuration for this architecture -- the dedicated NIC is connected only to VLAN 10 with no host OS traffic sharing the port.
- Action required: Verify which version is installed. If Express only, source and install an iDRAC6 Enterprise card before completing VLAN 10 setup.

**iDRAC configuration rules:**
- iDRAC NIC is connected exclusively to a VLAN 10 (Management) switch port. No other VLAN.
- Static IP assigned on the VLAN 10 subnet. No DHCP.
- iDRAC credentials are stored in Vaultwarden and on the offline break-glass USB. They are not sourced from FreeIPA -- iDRAC must remain accessible when FreeIPA is down.
- iDRAC firmware is kept updated. Updates are tracked manually since Renovate does not cover Dell firmware.
- iDRAC web UI and SSH (racadm) access is permitted only from VLAN 30 (Trusted) via the VLAN 10 admin firewall rule.

**What iDRAC enables for break-glass recovery:**
- KVM-over-IP: full keyboard and video console including BIOS POST and kernel panics, from any Trusted machine.
- Remote power control: power on, off, hard reset, graceful shutdown.
- Virtual media: mount a NixOS installer or recovery ISO remotely without physical access to the chassis.
- Hardware health visibility: temperatures, fans, PSU status, drive presence -- all accessible without a running OS.

### 11.6 VM Technology (KVM/QEMU)
- All VMs run NixOS as guests.
- The hypervisor stack is KVM/QEMU, declared via the NixOS `virtualisation` module on the physical host.
- VM definitions (vCPU count, RAM allocation, disk size, VLAN-tagged NIC) are declared in NixOS on the host. No manual `virt-manager` clicks. No undeclared state.
- VM disks live on the homelab's fast storage. Snapshots are taken before any major update to a VM.

### 11.7 High Availability Roadmap
- **Current:** Single physical host running four VMs. Resilient to software failures and misconfigurations via snapshots and deploy-rs rollback. Not resilient to host hardware failure.
- **Next milestone:** A second physical machine hosting a FreeIPA replica and a Headscale standby. This alone means identity and DNS survive a full primary host reboot — the highest-value HA improvement available for a two-machine setup.
- FreeIPA natively supports multi-master replication with no third-party tooling required.
- Remaining services (Gitea, Authentik, etc.) can tolerate downtime during a host reboot. Address them after the identity HA milestone is reached.

---

## 12. Endpoint Configuration

### 12.1 Shared Philosophy
- Desktop and laptop share a single Home Manager configuration for the user profile. Hardware-specific behavior is the only divergence point.
- Any package or tool added to Home Manager is available on both machines. Desktop-only or laptop-only packages are the exception, not the rule, and must be justified by a hardware constraint.
- NixOS impermanence is enabled on both machines from day one. See ADR-015.

### 12.2 Home Manager Structure
```
home/taylor/
  default.nix         -- imports all below, no hardware logic here
  shell.nix           -- Fish config, Starship, aliases, env vars, Fish plugins, direnv
  terminal.nix        -- Ptyxis, zellij, all terminal utility packages (fully synced)
  dev.nix             -- git+delta config, lazygit, jq, yq, editors, languages
  kde/                -- KDE dotfiles, kwinrc, theme, panel layout (shared)
  security.nix        -- SSH keys, GPG config, fprintd enrollment, FIDO2 config
  sync.nix            -- Nextcloud client config, watched sync directories
  streaming.nix       -- Moonlight client config (laptop only, gated on tags.laptop)
```

Everything in `shell.nix` and `terminal.nix` is fully synced between desktop and laptop with zero divergence. These files contain no hardware conditionals. The same shell behavior, the same utilities, and the same terminal configuration appear identically on both machines.

### 12.3 Impermanence Layout

Both machines use the same partition scheme under impermanence. Root is a tmpfs wiped on every boot. Only explicitly declared paths survive.

**Desktop disk layout:**
```
/dev/sdX1   512MB    vfat     /boot/efi
/dev/sdX2   1GB      ext4     /boot
/dev/sdX3   200GB    btrfs    /nix           (Nix store -- persistent, never wiped)
/dev/sdX4   remaining btrfs   /persist       (all surviving state lives here)
tmpfs                          /              (wiped on boot)

Secondary drive (~1.82TB):
  Formatted ext4, mounted at /mnt/overflow   (local scratch, no sync)
  Declared in NixOS. Pre-configured but not relied upon for active data.
```

**Laptop disk layout:**
```
/dev/nvme0n1p1  512MB    vfat    /boot/efi
/dev/nvme0n1p2  1GB      ext4    /boot
/dev/nvme0n1p3  150GB    btrfs   /nix
/dev/nvme0n1p4  remaining btrfs  /persist
tmpfs                             /
```

**Required persistence declarations (both machines):**
```nix
environment.persistence."/persist" = {
  directories = [
    "/var/lib/fprint"                         # fingerprint enrollment
    "/var/lib/bluetooth"                      # paired devices (desktop)
    "/var/lib/nixos"                          # NixOS UID/GID state
    "/var/lib/sss"                            # SSSD offline credential cache
    "/var/log"                                # logs across reboots
    "/etc/NetworkManager/system-connections"  # saved WiFi networks (laptop)
  ];
  files = [
    "/etc/machine-id"                         # stable ID for FreeIPA enrollment
    "/etc/ssh/ssh_host_ed25519_key"           # SSH host key
    "/etc/ssh/ssh_host_ed25519_key.pub"
  ];
};
```

The SSSD credential cache (`/var/lib/sss`) on the persistence list is mandatory for the laptop. Without it, offline login after a reboot without FreeIPA access is impossible.

### 12.4 Display and Scaling
- Desktop: KWin HDR enabled for the 2560x1440 180Hz display. KScreen manages multi-monitor layout at runtime. No display arrangement is hard-coded in NixOS.
- Laptop: 1.25x scaling (matches the Windows DPI setting in use). Declared via `services.xserver.dpi` or equivalent Wayland scaling config. 96 * 1.25 = 120 DPI effective.

### 12.5 Power Management (Laptop Only)
- Primary goal: battery life over performance. The i7-10610U is power-efficient but defaults to high-performance behavior without intervention.
- `auto-cpufreq` is used over TLP for dynamic governor switching. It adjusts CPU frequency scaling based on actual load rather than on AC/battery state alone.
- WiFi power saving is enabled but with a careful setting -- aggressive WiFi power saving introduces latency spikes that break remote work feel. Use `iwlwifi` powersave at level 2, not maximum.
- Screen timeout and suspend are set aggressively: screen off at 2 minutes idle, suspend at 5 minutes idle on battery.
- Hibernate threshold: if battery reaches 10%, hibernate to disk (requires swap or dedicated hibernate partition on /persist). This protects against data loss from unexpected shutdown on a degraded battery during migration.
- Battery replacement (part 01AV493 or equivalent) is planned before migration. Power tuning is written for a healthy battery and will improve further post-replacement.

### 12.6 Biometric Authentication
- Laptop: built-in fingerprint reader enabled via `services.fprintd.enable = true`. Enrolled at first login. Used for PAM authentication at SDDM, sudo, and polkit prompts.
- Desktop: USB fingerprint reader to be sourced at migration time. Any `libfprint`-compatible device. Budget $15-25. No rush -- keyboard password auth at desktop SDDM is acceptable until sourced.
- FIDO2 hardware key: Nitrokey FIDO2, deferred until system is operational. Vaultwarden browser extension handles passkeys in the interim (already in use). When purchased, enrolled in Authentik as a hardware MFA factor and used as a second factor for all Authentik-protected services.
- The fingerprint reader at the OS level and the FIDO2 key for web services are intentionally separate concerns. The fingerprint solves PAM convenience. The FIDO2 key solves phishing-resistant web authentication.

### 12.6a SSH Client Configuration
SSH client configuration is declared in `home/taylor/security.nix` via `programs.ssh.matchBlocks`. Both machines get the identical SSH config — no divergence.

**ProxyJump convention:** VM1 (Network & Identity) is the conventional entry point for all homelab SSH. VM2, VM3, and VM4 are accessed via ProxyJump through VM1. This is a convention enforced by SSH config, not by Headscale ACLs — direct access remains possible for break-glass scenarios. The convention ensures that the initial authentication event is always recorded by tlog on VM1 before proceeding to the target.

```nix
# home/taylor/security.nix (SSH matchBlocks excerpt)
programs.ssh = {
  enable = true;
  matchBlocks = {
    # VM1 -- direct entry point, all other VMs jump through here
    "vm1" = {
      hostname = "vm1.internal.tongatime.us";
      user = "taylor";
      identityFile = "~/.ssh/id_ed25519";
    };
    # VM2, VM3, VM4 -- always via ProxyJump through VM1
    "vm2" = {
      hostname = "vm2.internal.tongatime.us";
      user = "taylor";
      identityFile = "~/.ssh/id_ed25519";
      proxyJump = "vm1";
    };
    "vm3" = {
      hostname = "vm3.internal.tongatime.us";
      user = "taylor";
      identityFile = "~/.ssh/id_ed25519";
      proxyJump = "vm1";
    };
    "vm4" = {
      hostname = "vm4.internal.tongatime.us";
      user = "taylor";
      identityFile = "~/.ssh/id_ed25519";
      proxyJump = "vm1";
    };
    # Oracle VPS -- direct, no ProxyJump (public-facing, separate trust domain)
    "vps" = {
      hostname = "hs.tongatime.us";
      user = "taylor";
      identityFile = "~/.ssh/id_ed25519";
    };
  };
};
```

The ProxyJump chain means every VM2/VM3/VM4 session is recorded twice by tlog: once on VM1 (the jump) and once on the target VM. The VM1 recording captures the authentication event and initial connection. The target VM recording captures the actual session commands. Both land in Loki.

### 12.7 Game Streaming
- Server: Sunshine (LizardByte, GPL-3.0) on the desktop. Declared as a systemd service in NixOS. Uses AMD VA-API hardware encoding via the amdgpu module. See ADR-016.
- Client: Moonlight on the laptop. Declared in Home Manager, gated on `tags.laptop`.
- Stream routes over Headscale mesh -- works from anywhere, not just the local network.
- Apollo/Artemis (forks of Sunshine/Moonlight) are monitored. Artemis does not currently support Linux as a client. Re-evaluate when Linux client support ships.

### 12.8 File Sync and Backup
- Active files: Nextcloud client on both machines syncs to VM2 Nextcloud instance. See ADR-017.
- Game saves: Nextcloud client watches Steam save directories and any non-Steam save paths declared in `sync.nix`.
- Backup: rclone with age encryption pushes Nextcloud data snapshots and critical home directory contents to Google Drive (2TB, already subscribed). rclone stages encrypted archives in MinIO `backups/` bucket before pushing to Google Drive. Runs as a scheduled Gitea Actions job nightly. Google Drive is treated as durable encrypted cold storage, not as a primary access point.
- Local overflow: the 1.82TB desktop drive is mounted at `/mnt/overflow`. Large files (ISOs, raw assets, game installs too large for the primary SSD) live here. Not synced, not backed up -- treated as replaceable scratch.

### 12.9 Terminal and Shell Stack

All terminal and shell configuration lives in `shell.nix` and `terminal.nix` in Home Manager. Both files are fully synced between desktop and laptop — no hardware conditionals, identical behavior on both machines.

**Terminal emulator: Ptyxis**
- `pkgs.ptyxis` -- GTK4/libadwaita terminal with first-class container support and a clean tab model.
- Runs on KDE Plasma via GTK4/Wayland. `gtk.enable = true` in Home Manager aligns libadwaita theming closer to the Plasma color palette.
- Ptyxis config (profiles, fonts, colors) is managed declaratively via Home Manager's `dconf` settings or XDG config files.

**Shell: Fish + Starship**
- `programs.fish.enable = true` in Home Manager. Fish is the interactive shell; Starship is the prompt.
- Fish plugins are declared via `programs.fish.plugins` in Home Manager (not installed imperatively via fisher):
  - `bass` -- runs bash scripts from Fish; essential compatibility shim for tools that emit bash init scripts.
  - `fzf.fish` -- wires fzf into Fish: Ctrl+R becomes interactive history search, Ctrl+T file picker, Alt+C directory jumper.
  - `autopair.fish` -- auto-closes brackets, quotes, and parentheses.
  - `puffer-fish` -- text expansion: `...` expands to `../..`, `....` to `../../..`, etc.

**direnv + nix-direnv (highest-value tool on this list)**
- `programs.direnv.enable = true` and `programs.direnv.nix-direnv.enable = true` in Home Manager.
- Automatically activates the dev shell when entering a directory with a `flake.nix` or `.envrc`. Deactivates on exit.
- `nix-direnv` caches shells so re-entering a previously loaded directory is instant -- no rebuild.
- Eliminates `nix develop` as a manual step entirely. Every project directory just works.

**Terminal utilities (all declared in `terminal.nix`, all synced):**

Navigation and search:
- `zoxide` -- frecency-based smart cd. `z proj` jumps to the most-visited match. Fish integration via `programs.fish.interactiveShellInit`.
- `fzf` -- fuzzy finder backing the fzf.fish plugin and available standalone.
- `fd` -- fast `find` replacement. Respects .gitignore, intuitive syntax.
- `ripgrep` -- fast `grep` replacement. Respects .gitignore, better output formatting.
- `yazi` -- TUI file manager. Fast previews for code, images, PDFs, archives. Shell integration via `ya shell-init fish` exits into the navigated directory.

File viewing:
- `bat` -- `cat` replacement with syntax highlighting, line numbers, and git change markers. Set as `$MANPAGER` for readable man pages.
- `eza` -- modern `ls`. Aliased over `ls`, `ll`, `la`, and `tree` in `shell.nix`. Shows git status, icons, tree view.
- `glow` -- renders Markdown in the terminal. Useful for READMEs and project documentation.

Shell history:
- `atuin` -- replaces shell history with a searchable SQLite database. Every command stored with timestamp, working directory, exit code, and duration. Ctrl+R becomes genuinely useful. History database lives in `/persist`. No sync server configured -- each machine builds its own local history.

System monitoring:
- `btop` -- resource monitor replacing htop. Per-core CPU, memory, disk I/O, network, and process tree. AMDGPU plugin active on desktop via the AMD GPU module.
- `gdu` -- TUI disk usage analyzer. First tool to reach for when investigating storage use under impermanence.

Multiplexer:
- `zellij` -- terminal multiplexer for persistent remote sessions. Primary use: homelab SSH sessions where panes must survive a disconnect. Layouts are declarative YAML -- a "homelab" layout opens panes connected to VM1, VM2, VM3 automatically. Distinct use case from Ptyxis tabs (local) vs. zellij panes (remote, persistent).

Reference tools:
- `tldr` -- simplified community man pages. Faster than full man for common usage patterns.
- `navi` -- interactive cheatsheet tool for commands used rarely. Personal searchable knowledge base for obscure flags and invocations.

Data tools (also in `dev.nix` for editor integration):
- `jq` -- JSON processor. Essential for API work, log parsing, and Nix JSON output.
- `yq` -- YAML processor. Useful for NixOS config inspection and infrastructure YAML.

**Standard shell aliases (declared in `shell.nix`):**
```fish
alias ls   'eza --icons'
alias ll   'eza --icons -la'
alias la   'eza --icons -a'
alias tree 'eza --icons --tree'
alias cat  'bat'
alias find 'fd'
alias grep 'rg'
alias top  'btop'
alias cd   'z'          # zoxide replaces cd after initial population
```

---

## 13. Documentation & Decision Records

### 13.1 Decisions are Recorded
- Any significant architectural decision (tool choice, pattern adoption, tradeoff accepted) is recorded in `DECISIONS.md` as an Architecture Decision Record (ADR).
- The rationale must be captured, not just the outcome. Future readers need to understand why, not just what.

### 13.2 This File is Updated First
- Before implementing a new pattern, update this file to reflect the new guideline.
- If a new tool or service contradicts an existing rule, the contradiction must be resolved here before any code is written.

### 13.3 Decisions are Append-Only
- Reversed decisions get a new ADR entry referencing the old one. History is never deleted.

### 13.4 No Em Dashes in Documentation
- Use regular dashes or restructure the sentence. Em dashes are not used in prose in this project's documentation.

---

## Appendix: Approved Tool Registry

| Layer | Tool | Notes |
|---|---|---|
| OS | NixOS (flakes) | All machines, all homelab VMs |
| Hypervisor | KVM/QEMU via NixOS virtualisation module | Physical homelab host |
| Desktop | KDE Plasma 6 + KWin (Wayland) | All graphical hosts |
| Display manager | SDDM | All graphical hosts |
| Identity directory | FreeIPA | Podman, VM1 — users, Kerberos, HBAC, PKI, DNS |
| Web SSO | Authentik | Podman, VM2 — OIDC/SAML for all web apps |
| Client auth daemon | SSSD | All NixOS clients |
| Password manager | Vaultwarden | Podman, VM2 — passkey and credential store |
| Overlay mesh VPN | Headscale | Bare, VM1 — WireGuard control plane (see ADR-001) |
| VPN clients | Tailscale client | All endpoints — pointed at Headscale, not Tailscale servers |
| Public proxy / DMZ | Oracle VPS (Ubuntu + Nix + Caddy) | Forward proxy for public-facing traffic |
| Redundant metrics | VictoriaMetrics (VPS) | Receives remote_write from VM3 Prometheus; 7-day retention standby |
| Redundant alerting | Alertmanager (VPS) | Receives forwarded alerts + dead man's switch heartbeat from VM3 |
| Redundant notifications | ntfy.sh (VPS, public) | Secondary alert delivery at ntfy.tongatime.us; token-authenticated |
| Reverse proxy | Caddy | Podman, VM1 — internal and external TLS termination |
| IaC | OpenTofu | FreeIPA, Authentik, Headscale ACLs, DNS resources |
| Secrets | sops-nix + age | NixOS-layer encrypted secrets |
| Deployment | deploy-rs | Push NixOS configs to all hosts and VMs |
| CI/CD | Gitea Actions (self-hosted runner) | Build, test, deploy pipeline |
| Binary cache | attic | Podman, VM2 — homelab-hosted Nix cache |
| Automated updates | Renovate Bot | Podman, VM2 — dependency PRs with changelogs (see ADR-002) |
| Version control | Gitea | Podman, VM2 |
| Monitoring | Grafana + Loki + Prometheus + Alertmanager | Podman, VM3 |
| Containers | Podman (rootless) | All containerized services — Docker is not used |
| Gaming (core) | nix-gaming flake + Steam + Proton-GE + gamemode + gamescope | Desktop only, tags.gaming = true |
| Gaming (overlay) | MangoHUD + GOverlay | Desktop only, tags.gaming = true |
| Gaming (launchers) | Heroic + Lutris | Desktop only, tags.gaming = true |
| Gaming (FHS fallback) | steam-run | Desktop only -- wraps native Linux binaries that expect FHS paths |
| GPU monitoring / control | LACT + amdgpu_top | Desktop only, declared in modules/hardware/gpu/amd.nix |
| Hardware profiles | nixos-hardware flake | Laptop host imports ThinkPad module; desktop uses generated hardware.nix |
| Streaming server | Sunshine (LizardByte, GPL-3.0) | Desktop only -- AMD VA-API hardware encode |
| Streaming client | Moonlight | Laptop only, gated on tags.laptop |
| File sync | Nextcloud client | Both machines -- syncs to VM2 Nextcloud |
| Backup | rclone + age | VM2 -> Google Drive, nightly Gitea Actions job |
| Network segmentation | OPNsense (or equivalent managed router) | 6-VLAN architecture, inter-VLAN firewall |
| Shared cache | Redis | Podman, VM2 — shared logical-DB cache for all VM2 services |
| Object store | MinIO (Apache 2.0) | Podman, VM2 — S3-compatible store for: OpenTofu state, Gitea artifacts, Loki chunks, rclone backup staging |
| Push notifications | ntfy.sh (Apache 2.0) | Podman, VM2 — Alertmanager webhook target; topics: infra-critical, infra-warning, infra-info |
| Glue code / internal APIs | FastAPI | Reach for this when lightweight HTTP glue is needed (webhooks, custom /metrics exporters, internal automation endpoints). Not a permanently running service by default. |
| Terminal emulator | Ptyxis | Both machines -- GTK4, libadwaita, container-aware |
| Shell | Fish + Starship | Both machines -- fully synced via Home Manager |
| Shell plugins | bass, fzf.fish, autopair.fish, puffer-fish | Both machines -- declared via programs.fish.plugins |
| Shell env manager | direnv + nix-direnv | Both machines -- auto-activates nix dev shells per directory |
| Terminal multiplexer | zellij | Both machines -- persistent remote sessions, declarative layouts |
| Smart navigation | zoxide + fzf | Both machines -- frecency cd, fuzzy find |
| Modern coreutils | bat + eza + fd + ripgrep | Both machines -- replace cat/ls/find/grep |
| File manager (TUI) | yazi | Both machines -- previews, fast navigation |
| Shell history | atuin | Both machines -- SQLite history, rich search |
| Git TUI | lazygit | Both machines (in dev.nix) |
| Git diffs | delta | Both machines (in dev.nix, set as git pager) |
| System monitor | btop | Both machines |
| Disk usage | gdu | Both machines |
| Data tools | jq + yq | Both machines (in dev.nix) |
| Reference | tldr + navi | Both machines |
| Markdown viewer | glow | Both machines |

**Future Considerations (not yet deployed, revisit when trigger condition is met):**

| Tool | Trigger to Adopt |
|---|---|
| Apache Kafka | Log volume or automation event complexity grows beyond what direct Loki ingest and Gitea webhooks handle cleanly. Specifically: need guaranteed delivery, multiple independent consumers of the same event stream, or buffer tolerance for VM3 downtime during log ingest. |
| Apache Airflow | Gitea Actions workflows develop more than one branching condition or require per-step retry logic with conditional failure handling. Specifically: nightly backup chains, weekly audit workflows, or any DAG with more than ~5 interdependent steps. |
