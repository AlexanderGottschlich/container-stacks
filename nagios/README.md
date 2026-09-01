# Nagios Dockerized

Nagios Core is built as an immutable Docker image. Monitoring object files in
`nagios/conf.d/*.cfg` are copied into the image during `docker build`; they are
not mounted at runtime.

## Networking

The host runs an older Docker Engine / docker-compose combination without
`gw_priority`. Nagios therefore uses two networks through a reproducible deploy
script:

- `nagios_egress` – dedicated bridge and default route for external checks
- `proxy_net` – existing external Traefik network for the Nagios web UI

`scripts/start-nagios.sh` creates/verifies `nagios_egress`, starts Nagios on that
network, attaches `proxy_net`, re-applies the egress default route and verifies
that `152.53.46.232:443` is reachable from the container.

Because this legacy workaround must modify the container routing table, the
container has `NET_ADMIN`. Once Docker Engine supports gateway priorities, this
workaround and capability can be removed in favor of `gw_priority`.

## Initial setup

```bash
cp .env.example .env
```

Set a strong `NAGIOSADMIN_PASSWORD` in `.env`.

The existing Traefik deployment must already provide `proxy_net`.

## Build and deploy

Do not call `docker-compose up` directly for normal deployment. Use:

```bash
./scripts/start-nagios.sh
```

The script is idempotent and can be used after every Git pull or configuration
change.

## Immutable monitoring configuration

The image currently contains:

- `nagios/conf.d/commands.cfg`
- `nagios/conf.d/nextcloud.cfg`

The Nextcloud check deliberately connects to public IP `152.53.46.232`, while
using `nc2.elastic2ls.com` for HTTP Host, TLS SNI and certificate verification.
It checks `/status.php` for HTTP 200 and `"installed":true`.

After changing a `.cfg` file, run:

```bash
./scripts/start-nagios.sh
```

which rebuilds and redeploys the image.

## Validate Nagios configuration

```bash
docker-compose exec nagios \
  /usr/local/nagios/bin/nagios \
  -v /usr/local/nagios/etc/nagios.cfg
```

## Verify networks

```bash
docker inspect nagios \
  --format '{{range $name, $cfg := .NetworkSettings.Networks}}{{$name}} -> {{$cfg.IPAddress}}{{println}}{{end}}'
```

Both `nagios_egress` and `proxy_net` must be present.
