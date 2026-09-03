# Sensu migration of the Nagios checks

This directory converts the Nagios monitoring set from 2026-09-02 to Sensu Go Configuration-as-Code.

## What is included

The Sensu agent runs all remote checks under the `monitoring` subscription. Each check uses `proxy_entity_name`, so events are assigned to the monitored host (for example `nc2.elastic2ls.com`) rather than to the central agent `monitoring-proxy`.

The agent image contains small check scripts using `curl`, `dig`, `openssl`, and `nc`. This keeps the monitoring definitions self-contained in Git and avoids manually installing Nagios plugins in a running container.

### Targets migrated

| Target | Checks |
|---|---|
| `nc2.elastic2ls.com` | TCP 443, Nextcloud `/status.php`, expected public A record, TLS expiry |
| `pi.elastic2ls.com` | TCP 443, Pi-hole HTTPS, expected public A record, TLS expiry, Pi-hole DNS resolver, Unbound resolver on 5335 |
| `sensu.elastic2ls.com` | TCP 443, Sensu HTTPS, expected public A record, TLS expiry |
| `sx.elastic2ls.com` | TCP 443, SearXNG content, expected public A record, TLS expiry |
| `yt2.elastic2ls.com` | TCP 443, youtube-dl content, expected public A record, TLS expiry |
| `www.elastic2ls.com` | HTTPS availability, public DNS, TLS expiry |
| `www.fachadmin.de` | HTTPS availability, public DNS, TLS expiry |
| `www.terraform-in-der-praxis.de` | HTTPS availability, public DNS, TLS expiry |
| `www.bonn-zeigt-gesicht.de` | HTTPS availability, public DNS, TLS expiry |

There are 34 Sensu checks in total. Five of them represent the Nagios host-level TCP/443 checks. For the four external websites, the Nagios host check and service availability check were effectively the same HTTPS check, so only one Sensu check is created for each website.

## Layout

```text
.
├── .env.example
├── Dockerfile.agent
├── docker-compose.yml
├── checks/
│   ├── check_dns.sh
│   ├── check_http.sh
│   ├── check_tcp.sh
│   └── check_tls.sh
├── resources/
│   └── checks/
│       ├── bonn-zeigt-gesicht.yml
│       ├── elastic2ls.yml
│       ├── fachadmin.yml
│       ├── nc2.yml
│       ├── pi.yml
│       ├── sensu.yml
│       ├── sx.yml
│       ├── terraform-in-der-praxis.yml
│       └── yt2.yml
└── scripts/
    ├── apply-config.sh
    ├── compose.sh
    └── start-sensu.sh
```

## Important before starting

Copy the example environment file:

```bash
cp .env.example .env
```

Set `SENSU_ADMIN_PASS` to the password that is **currently stored in Sensu**. If the existing `sensu_state` volume is already initialized, changing `.env` does not reset the admin password.

The stack assumes the existing external Docker network `proxy_net` exists. The Sensu agent joins that network so it can query the `pihole` and `unbound` containers by Docker DNS name.

The agent also joins `sensu_egress`. For compatibility with legacy `docker-compose`, this network is attached by `scripts/start-sensu.sh` after container startup using `docker network connect --gw-priority 1`. This mirrors the dedicated Nagios egress network so checks against `152.53.46.232` leave through a separate Docker bridge instead of `proxy_net`.

## Start and load all checks

```bash
./scripts/start-sensu.sh
```

The script:

1. builds and starts the backend and monitoring agent,
2. runs the one-shot `sensu-config` service,
3. recursively loads all YAML files from `resources/`,
4. lists the resulting Sensu checks.

For later configuration-only changes:

```bash
./scripts/compose.sh run --rm sensu-config
```

This executes:

```bash
sensuctl create -r -f /resources
```

so the repository remains the intended source of truth.

## Useful commands

List checks:

```bash
./scripts/compose.sh run --rm sensu-config
```

Agent logs:

```bash
./scripts/compose.sh logs -f sensu-agent
```

Backend logs:

```bash
./scripts/compose.sh logs -f sensu-backend
```

Show services:

```bash
./scripts/compose.sh ps
```

## Check intervals

The intervals preserve the previous Nagios intent:

- application/HTTP checks: 5 minutes
- expected public A records: 5 minutes
- Pi-hole/Unbound resolver checks: 5 minutes
- TLS for internal `*.elastic2ls.com` services: 60 minutes
- external-site DNS: 30 minutes
- external-site TLS: 12 hours

Sensu does not model Nagios host/service states or `max_check_attempts` in the same way. The checks emit every scheduled result. If notifications are added later, a Sensu event filter can reproduce the previous three-attempt notification threshold.

## Expected existing failures

The migration deliberately preserves TLS hostname verification. If a target currently has a hostname/certificate mismatch, the corresponding Sensu check will remain CRITICAL rather than masking the problem.


## Docker Compose compatibility

The scripts automatically detect whether the host provides Docker Compose v2 (`docker compose`) or the legacy standalone binary (`docker-compose`). The compose YAML intentionally avoids `gw_priority`, because legacy docker-compose does not support that key. The dedicated `sensu_egress` network is attached afterwards by `start-sensu.sh` with Docker Engine's `--gw-priority 1` option.
