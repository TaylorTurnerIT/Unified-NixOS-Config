# Port Reference

> Every open port in the infrastructure. If a port is not in this table,
> it should not be open. Firewall rules are derived from this document.
> Update this file before opening any new port.

---

## Legend

- **Bound to:** `0.0.0.0` = all interfaces | `127.0.0.1` = loopback only | specific IP = that interface
- **Access from:** which VLANs or network zones can reach this port
- **TLS:** whether TLS terminates at this port (C=Caddy terminates, S=service terminates, N=plaintext)

---

## Physical Host (VLAN 20)

| Port | Protocol | Service | Bound to | Access from | TLS | Notes |
|------|----------|---------|----------|-------------|-----|-------|
| 22 | TCP | OpenSSH | 0.0.0.0 | VLAN 30 via Headscale only | N | Ed25519 only, no password, no root |

---

## VLAN 10 — Management

| Port | Protocol | Service | Host | Access from | TLS | Notes |
|------|----------|---------|------|-------------|-----|-------|
| 443 | TCP | iDRAC6 Web UI | iDRAC IP | VLAN 30 only | S | iDRAC Enterprise NIC |
| 22 | TCP | iDRAC SSH (racadm) | iDRAC IP | VLAN 30 only | N | Admin CLI |
| 80 | TCP | OPNsense Web UI | Router IP | VLAN 30 only | C | Redirects to 443 |
| 443 | TCP | OPNsense Web UI | Router IP | VLAN 30 only | S | HTTPS admin |
| 443 | TCP | Managed Switch | Switch IP | VLAN 30 only | S | Switch admin UI |

---

## VM1 — Network and Identity (VLAN 20)

### Headscale (network infrastructure, not proxied)
| Port | Protocol | Service | Bound to | Access from | TLS | Notes |
|------|----------|---------|----------|-------------|-----|-------|
| 8080 | TCP | Headscale control plane | 127.0.0.1 | Caddy only | N | Caddy proxies via 443 |
| 41641 | UDP | WireGuard data plane | 0.0.0.0 | All Headscale peers | N | WireGuard encrypted |

### FreeIPA (Podman container)
| Port | Protocol | Service | Bound to | Access from | TLS | Notes |
|------|----------|---------|----------|-------------|-----|-------|
| 389 | TCP | LDAP | 127.0.0.1 | VM1 loopback (Authentik LDAP sync via Headscale mesh) | N | SSSD clients connect via Headscale |
| 636 | TCP | LDAPS | 0.0.0.0 | VLAN 20 (all VMs via Headscale) | S | TLS LDAP for SSSD clients |
| 88 | TCP/UDP | Kerberos KDC | 0.0.0.0 | VLAN 20 + VLAN 30 via Headscale | N | Kerberos auth |
| 464 | TCP/UDP | Kerberos kpasswd | 0.0.0.0 | VLAN 20 + VLAN 30 via Headscale | N | Password changes |
| 53 | TCP/UDP | DNS (BIND) | 0.0.0.0 | All VLANs (via DHCP config) | N | Authoritative for internal.tongatime.us |

### Caddy (proxying internal services)
| Port | Protocol | Service | Bound to | Access from | TLS | Notes |
|------|----------|---------|----------|-------------|-----|-------|
| 80 | TCP | Caddy (redirect) | 0.0.0.0 | VLAN 20, VLAN 30 | N | Redirects to 443 |
| 443 | TCP | Caddy (HTTPS) | 0.0.0.0 | VLAN 20, VLAN 30 | C | All *.internal.tongatime.us services |

### Services proxied by VM1 Caddy
| Hostname | Upstream | Notes |
|----------|----------|-------|
| `ipa.internal.tongatime.us` | `127.0.0.1:8443` | FreeIPA web UI |
| `hs.internal.tongatime.us` | `127.0.0.1:8080` | Headscale web UI (admin) |

---

## VM2 — Application Services (VLAN 20)

All services bind to loopback. Caddy on VM1 proxies via Headscale mesh.

### PostgreSQL
| Port | Protocol | Service | Bound to | Access from | TLS | Notes |
|------|----------|---------|----------|-------------|-----|-------|
| 5432 | TCP | PostgreSQL | 127.0.0.1 | Podman internal network only | N | Never exposed to VLAN |

### Redis
| Port | Protocol | Service | Bound to | Access from | TLS | Notes |
|------|----------|---------|----------|-------------|-----|-------|
| 6379 | TCP | Redis | 127.0.0.1 | Podman internal network only | N | Logical DB 0=Authentik, 1+=others |

### Gitea
| Port | Protocol | Service | Bound to | Access from | TLS | Notes |
|------|----------|---------|----------|-------------|-----|-------|
| 3000 | TCP | Gitea HTTP | 127.0.0.1 | Caddy only | N | Caddy proxies |
| 22 | TCP | Gitea SSH | 0.0.0.0 | VLAN 30 via Headscale | N | Git SSH clone/push |

### Authentik
| Port | Protocol | Service | Bound to | Access from | TLS | Notes |
|------|----------|---------|----------|-------------|-----|-------|
| 9000 | TCP | Authentik HTTP | 127.0.0.1 | Caddy only | N | Caddy proxies |
| 9443 | TCP | Authentik HTTPS | 127.0.0.1 | Caddy only | S | Internal TLS |

### Vaultwarden
| Port | Protocol | Service | Bound to | Access from | TLS | Notes |
|------|----------|---------|----------|-------------|-----|-------|
| 8008 | TCP | Vaultwarden HTTP | 127.0.0.1 | Caddy only | N | Caddy proxies |
| 3012 | TCP | Vaultwarden WebSocket | 127.0.0.1 | Caddy only | N | Real-time sync |

### Nextcloud
| Port | Protocol | Service | Bound to | Access from | TLS | Notes |
|------|----------|---------|----------|-------------|-----|-------|
| 8080 | TCP | Nextcloud HTTP | 127.0.0.1 | Caddy only | N | Caddy proxies |

### attic Binary Cache
| Port | Protocol | Service | Bound to | Access from | TLS | Notes |
|------|----------|---------|----------|-------------|-----|-------|
| 8080 | TCP | attic HTTP API | 127.0.0.1 | Caddy only | N | Caddy proxies |

### MinIO (OpenTofu state backend)
| Port | Protocol | Service | Bound to | Access from | TLS | Notes |
|------|----------|---------|----------|-------------|-----|-------|
| 9000 | TCP | MinIO API | 127.0.0.1 | Caddy + local only | N | S3-compatible API — buckets: tofu-state/, gitea-artifacts/, loki-chunks/, backups/ |
| 9001 | TCP | MinIO Console | 127.0.0.1 | Caddy only | N | Web UI |

### ntfy.sh
| Port | Protocol | Service | Bound to | Access from | TLS | Notes |
|------|----------|---------|----------|-------------|-----|-------|
| 80 | TCP | ntfy.sh HTTP | 127.0.0.1 | Caddy + Alertmanager only | N | Caddy proxies |

### Structurizr
| Port | Protocol | Service | Bound to | Access from | TLS | Notes |
|------|----------|---------|----------|-------------|-----|-------|
| 8080 | TCP | Structurizr Lite | 127.0.0.1 | Caddy only | N | C4 architecture diagrams |

### Services proxied by VM1 Caddy to VM2
| Hostname | Upstream | Notes |
|----------|----------|-------|
| `git.internal.tongatime.us` | `vm2-ip:3000` | Gitea web UI |
| `auth.internal.tongatime.us` | `vm2-ip:9000` | Authentik SSO |
| `vault.internal.tongatime.us` | `vm2-ip:8008` | Vaultwarden |
| `nextcloud.internal.tongatime.us` | `vm2-ip:8080` | Nextcloud |
| `cache.internal.tongatime.us` | `vm2-ip:8080` | attic cache |
| `minio.internal.tongatime.us` | `vm2-ip:9001` | MinIO console |
| `ntfy.internal.tongatime.us` | `vm2-ip:80` | ntfy.sh push notifications |
| `arch.internal.tongatime.us` | `vm2-ip:8080` | Structurizr |

---

## VM3 — Observability (VLAN 20)

| Port | Protocol | Service | Bound to | Access from | TLS | Notes |
|------|----------|---------|----------|-------------|-----|-------|
| 3100 | TCP | Loki HTTP | 127.0.0.1 | Caddy + Promtail agents | N | Log ingest and query; chunks stored in MinIO loki-chunks/ |
| 9090 | TCP | Prometheus | 127.0.0.1 | Caddy only | N | Metrics store |
| 3000 | TCP | Grafana | 127.0.0.1 | Caddy only | N | Visualization |
| 9093 | TCP | Alertmanager | 127.0.0.1 | Prometheus only | N | Alert routing |

### Prometheus scrape targets (VM3 → other hosts)
| Target | Port | Service | Notes |
|--------|------|---------|-------|
| VM1 | 9100 | node_exporter | Host metrics |
| VM1 | 9101 | freeipa_exporter | FreeIPA-specific metrics |
| VM2 | 9100 | node_exporter | Host metrics |
| VM2 | 9187 | postgres_exporter | PostgreSQL metrics |
| VM3 | 9100 | node_exporter | Self-monitoring |
| Desktop | 9100 | node_exporter | Host metrics |

### Services proxied by VM1 Caddy to VM3
| Hostname | Upstream | Notes |
|----------|----------|-------|
| `grafana.internal.tongatime.us` | `vm3-ip:3000` | Grafana (Authentik SSO) |

---

## VM4 — DMZ / Public Services (VLAN 60)

| Port | Protocol | Service | Bound to | Access from | TLS | Notes |
|------|----------|---------|----------|-------------|-----|-------|
| 25565 | TCP/UDP | Minecraft Java | 0.0.0.0 | Internet (via Oracle VPS) | N | Standard Minecraft port |
| 22 | TCP | OpenSSH | 0.0.0.0 | VLAN 30 via Headscale (tag:admin) | N | Emergency access |

---

## Oracle VPS (Public Internet + Headscale mesh)

| Port | Protocol | Service | Bound to | Access from | TLS | Notes |
|------|----------|---------|----------|-------------|-----|-------|
| 80 | TCP | Caddy (redirect) | 0.0.0.0 | Internet | N | Redirects to 443 |
| 443 | TCP | Caddy HTTPS | 0.0.0.0 | Internet | C | Public services + hs.tongatime.us |
| 25565 | TCP/UDP | Minecraft proxy | 0.0.0.0 | Internet | N | Forwards to VM4 via Headscale |
| 41641 | UDP | WireGuard (Headscale) | 0.0.0.0 | Internet | N | Headscale peer traffic |
| 22 | TCP | OpenSSH | 0.0.0.0 | tag:admin peers only | N | Hardened: Ed25519, no password |

### VPS Redundant Monitoring (inbound from homelab via Headscale mesh)
| Port | Protocol | Service | Bound to | Access from | TLS | Notes |
|------|----------|---------|----------|-------------|-----|-------|
| 8428 | TCP | VictoriaMetrics | 127.0.0.1 | Caddy + VM3 remote_write | N | Receives Prometheus remote_write from VM3 |
| 9093 | TCP | Alertmanager | 127.0.0.1 | Caddy + VM3 Alertmanager | N | Receives forwarded alerts + heartbeat from VM3 |
| 80 | TCP | ntfy.sh HTTP | 127.0.0.1 | Caddy only | N | Caddy proxies to 443 |

### Services proxied by Oracle VPS Caddy
| Hostname | Upstream | Notes |
|----------|----------|-------|
| `hs.tongatime.us` | `vm1-headscale-ip:8080` | Headscale coordination endpoint |
| `mc.tongatime.us:25565` | `vm4-ip:25565` | Minecraft (raw TCP, not HTTP) |
| `ntfy.tongatime.us` | `127.0.0.1:80` | VPS ntfy.sh — public backup alert delivery, token-authenticated |

---

## Desktop (VLAN 30)

| Port | Protocol | Service | Bound to | Access from | TLS | Notes |
|------|----------|---------|----------|-------------|-----|-------|
| 47984 | TCP | Sunshine HTTPS | 0.0.0.0 | Headscale mesh (laptop only) | S | Sunshine web UI + pairing |
| 47989 | TCP | Sunshine HTTP | 0.0.0.0 | Headscale mesh (laptop only) | N | Sunshine control |
| 47999 | UDP | Sunshine control | 0.0.0.0 | Headscale mesh (laptop only) | N | Moonlight control stream |
| 48000-48010 | UDP | Sunshine video | 0.0.0.0 | Headscale mesh (laptop only) | N | Moonlight video stream |
| 48010 | TCP | Sunshine audio | 0.0.0.0 | Headscale mesh (laptop only) | N | Moonlight audio stream |
| 8384 | TCP | Syncthing Web UI | 127.0.0.1 | Loopback only | N | If used; local access only |
| 22000 | TCP | Syncthing sync | 0.0.0.0 | Headscale mesh | N | If used |

### Steam Remote Play (opened by programs.steam.remotePlay.openFirewall)
| Port | Protocol | Notes |
|------|----------|-------|
| 27036 | TCP | Steam Remote Play |
| 27031-27036 | UDP | Steam Remote Play |

---

## Laptop (VLAN 30 / roaming)

The laptop opens no listening ports by default. All connections are outbound.
Moonlight (streaming client) connects outbound to desktop Sunshine ports above.

---

## Firewall Rules Summary

### Default policies
- **All hosts:** deny inbound, allow outbound (except where stated)
- **VLAN 10:** deny all outbound (management interfaces only)
- **VLAN 40:** deny all inbound from other VLANs (IoT isolation)
- **VLAN 50:** deny all inbound from other VLANs (guest isolation)

### Critical allowed paths
| Source | Destination | Port | Reason |
|--------|-------------|------|--------|
| VLAN 30 | VM1 VLAN 20 | 443 | Internal service access |
| VLAN 30 | VM1 VLAN 20 | 636 | LDAP auth (SSSD) |
| VLAN 30 | VM1 VLAN 20 | 88 | Kerberos |
| VLAN 30 | VM1 VLAN 20 | 53 | DNS |
| VLAN 30 | VLAN 10 | 443/22 | Management access |
| VM3 | VM1 | 9100,9101 | Prometheus scrape |
| VM3 | VM2 | 9100,9187 | Prometheus scrape |
| Oracle VPS | VM1 | 443 | Headscale coordination (via Headscale ACL) |
| Oracle VPS | VM4 | any | DMZ services (via Headscale ACL) |
| Internet | Oracle VPS | 80,443,25565 | Public services |
