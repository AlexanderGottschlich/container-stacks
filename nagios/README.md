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
2. builds and starts Nagios on that network
3. attaches `proxy_net`
4. restores the egress default route
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
