# Nagios Dockerized

Nagios Core is built as an immutable Docker image. Monitoring object files in
`nagios/conf.d/*.cfg` are copied into the image during `docker build`; they are
not mounted at runtime.

## Networking

This host uses an older Docker Engine / `docker-compose` combination without
`gw_priority`. Nagios therefore uses a reproducible legacy networking setup:

- `nagios_egress` – dedicated bridge and default route for monitoring checks
- `proxy_net` – existing Traefik network for the Nagios web UI

The target `nc2.elastic2ls.com` resolves to the host's own public address
`152.53.46.232`. Docker's generated NAT rules deliberately return traffic that
originates on a user-defined bridge before its published-port DNAT rule.
Therefore `scripts/start-nagios.sh` installs narrowly scoped host rules so the
Nagios connection to `152.53.46.232:443` is DNATed to Traefik and allowed across
the two Docker bridges.

The script dynamically discovers:

- the bridge device for `nagios_egress`
- the bridge device for `proxy_net`
- Traefik's current IP on `proxy_net`

No Docker network ID, bridge ID or Traefik container IP is hard-coded. Dedicated iptables chains are flushed and rebuilt on each deployment so a recreated Traefik container or Docker bridge cannot leave stale destination rules behind.

> This verifies the service by connecting to the server's public IP from a
> container on the same host. It does not replace a monitoring probe located
> outside the server/provider network if true Internet-path monitoring is needed.

## Initial setup

```bash
cp .env.example .env
```

Set a strong `NAGIOSADMIN_PASSWORD` in `.env`.

The existing Traefik deployment must already provide `proxy_net`, and the
Traefik container must be named `traefik` unless `TRAEFIK_CONTAINER` is set.

## Build and deploy

Use the deployment script rather than calling `docker-compose up` directly:

```bash
./scripts/start-nagios.sh
```

The script is idempotent. It:

1. creates/verifies `nagios_egress`
2. builds and starts Nagios with both `nagios_egress` and `proxy_net` attached from container creation
3. restores `nagios_egress` as the default route on the legacy Docker Engine
4. verifies that Apache (`www-data`) can read the runtime Basic-Auth file
5. discovers both bridge interfaces and Traefik's current IP
6. rebuilds dedicated `NAGIOS-PUBLIC-DNAT` and `NAGIOS-PUBLIC-FWD` chains from current Docker state
7. tests `152.53.46.232:443`
8. runs the Nextcloud application check

Host firewall changes require root privileges; the script uses `sudo` when it
is not itself run as root.

## Immutable monitoring configuration

The image contains:

- `nagios/conf.d/commands.cfg`
- `nagios/conf.d/nextcloud.cfg`

`nextcloud.cfg` deliberately sets:

```text
address 152.53.46.232
```

`nc2.elastic2ls.com` remains the HTTP Host header, TLS SNI value and certificate
verification name. `/status.php` must return HTTP 200 and contain
`"installed":true`.

After changing any `.cfg` file:

```bash
./scripts/start-nagios.sh
```

## Manual verification

Networks:

```bash
docker inspect nagios \
  --format '{{range $name, $cfg := .NetworkSettings.Networks}}{{$name}} -> {{$cfg.IPAddress}}{{println}}{{end}}'
```

Route:

```bash
docker-compose exec nagios ip route get 152.53.46.232
```

TCP:

```bash
docker-compose exec nagios \
  bash -c 'timeout 5 bash -c "</dev/tcp/152.53.46.232/443" && echo OK || echo FAILED'
```

Application check:

```bash
docker-compose exec nagios \
  /usr/local/nagios/libexec/check_http \
  -4 -I 152.53.46.232 \
  -H nc2.elastic2ls.com \
  -S --sni --verify-host \
  -u /status.php \
  -e 200 \
  -s '"installed":true' \
  -w 5 -c 10 -t 15
```

Nagios configuration:

```bash
docker-compose exec nagios \
  /usr/local/nagios/bin/nagios \
  -v /usr/local/nagios/etc/nagios.cfg
```

## Additional monitoring targets

The immutable image now contains one object file per monitored public service:

- `nextcloud.cfg` – Nextcloud `/status.php`, public DNS and TLS
- `pihole.cfg` – Pi-hole public HTTPS route, public DNS, TLS, Pi-hole resolver and Unbound recursion
- `youtube-dl.cfg` – `yt2.elastic2ls.com`, page-content, public DNS and TLS
- `searxng.cfg` – `sx.elastic2ls.com`, page-content, public DNS and TLS
- `sensu.cfg` – `sensu.elastic2ls.com`, HTTPS endpoint, public DNS and TLS

All public HTTPS objects use `152.53.46.232` as their immutable TCP destination.
The hostname remains the HTTP Host header/TLS SNI name. A separate DNS service
also verifies that the public A record still resolves to `152.53.46.232`.

`check_dns` requires `nslookup`; `dnsutils` is therefore installed in the image.

Unbound listens on port `5335` in the supplied Pi-hole stack. Its Nagios service uses the repository-managed command name `check_unbound_dns`, which wraps the official Nagios `check_dig` plugin against `unbound:5335`; no custom `check_unbound_dns` executable is required. The Pi-hole resolver check remains on DNS port 53.

### Deliberately not enabled yet

The supplied stack also contains Home Assistant, Jellyfin, Mediahub and Icecast.
They are only exposed as local host ports or on private Docker networks. They
should be added as a separate internal-monitoring layer rather than forcing them
through the public-443 DNAT path.

The Ghost stack has inconsistent canonical host settings in the supplied
archive (`GHOST_DOMAIN=cloudkostenkompass.de` while `GHOST_URL` points to
`blog.elastic2ls.com`). Resolve that canonical-domain choice before adding a
strict Ghost application/content check.

The youtube-dl stack and this monitoring configuration both use
`yt2.elastic2ls.com`.

## External website monitoring

The image also monitors four DNS-resolved external websites independently of
the public-IP-pinned services on this Docker host:

- `www.terraform-in-der-praxis.de`
- `www.bonn-zeigt-gesicht.de`
- `www.fachadmin.de`
- `www.elastic2ls.com`

Each website has three checks:

- HTTPS availability every 5 minutes, following redirects to the final HTTP 200 response
- public DNS resolution every 30 minutes
- TLS certificate expiry every 12 hours (WARNING below 30 days, CRITICAL below 14 days)

These checks deliberately do not use the fixed `152.53.46.232` destination.
The hostname is resolved normally at check time so that DNS and hosting changes
remain visible to Nagios.

## Traefik/backend verification

Both `nagios_egress` and `proxy_net` are declared directly in Compose. This is
intentional: Traefik must see the Nagios container on `proxy_net` from the first
Docker provider event. The entrypoint then explicitly selects `nagios_egress`
as the default route for outbound monitoring checks.

After deployment:

```bash
docker inspect nagios \
  --format '{{range $name, $cfg := .NetworkSettings.Networks}}{{$name}} -> {{$cfg.IPAddress}}{{println}}{{end}}'

docker-compose exec nagios ip route show default

docker-compose exec nagios \
  bash -c 'timeout 3 bash -c "</dev/tcp/127.0.0.1/80" && echo "Apache :80 OK" || echo "Apache :80 FAILED"'

curl -Ik https://nagios.elastic2ls.com/nagios/
```

## Runtime auth permissions

`/run` is a tmpfs. On every container start the entrypoint therefore forces:

```text
/run/nagios                  root:www-data 0750
/run/nagios/htpasswd.users   root:www-data 0640
```

The container aborts during startup if the Apache runtime user `www-data` cannot read the password file. This prevents the previous Apache `AH01620` / HTTP 500 failure mode from reaching production.

### DNS plugin build invariant

The image build verifies that `check_dns` and `check_dig` exist and are executable
under `/usr/local/nagios/libexec`. `dnsutils` supplies the required `nslookup`
and `dig` binaries before the Nagios Plugins configure/build step. The build
fails instead of producing an image with broken DNS service checks.


## Monitoring semantics

Application/website checks and TLS checks are deliberately separated:

- HTTP/Application checks verify reachability, routing, HTTP status/content and SNI.
- `TLS certificate` checks verify hostname identity and certificate expiry.
- A certificate hostname mismatch therefore makes only the TLS service CRITICAL; it does not hide application availability.
- Unbound is checked with the official `check_dig` plugin against `unbound:5335`; no repository-specific DNS plugin is required.

### yt2.elastic2ls.com TLS

The supplied container stack defines the Traefik ACME resolver as `le`, while the youtube-dl stack currently sets `TRAEFIK_CERTRESOLVER=letsencrypt`. The youtube-dl stack should use:

```env
TRAEFIK_CERTRESOLVER=le
```

Then recreate the youtube-dl container so Traefik can obtain/use the certificate for `yt2.elastic2ls.com`. Nagios intentionally keeps the TLS check CRITICAL until the served certificate matches that hostname.

## Light UI skin

This repository includes a visual-only light skin for the stock Nagios Core web UI.
The monitoring engine, CGI behavior, object configuration and authentication model
are unchanged.

The files are repository-managed and baked into the image:

```text
nagios/web/upzilla.css
nagios/web/upzilla.js
```

During the Docker build, the CSS overlay is appended to Nagios Core's
`share/stylesheets/common.css` and the small presentation helper is appended to
`share/js/nag_funcs.js`. This keeps the stock Nagios files installed by the pinned
Nagios release and adds only the repository-owned visual layer.

The skin provides:

- light navigation/sidebar
- system UI typography
- reduced borders and modern table spacing
- compact OK/WARNING/CRITICAL/UNKNOWN/PENDING badges
- subdued plugin output text
- modern form controls
- a small application header on CGI pages

After deploying a newly built image, hard-refresh the browser because the Nagios
stylesheets may be cached.
