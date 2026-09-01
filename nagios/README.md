# nagios-dockerized

Nagios Core in Docker, designed for deployment behind an existing Traefik instance.

## Design

Monitoring configuration is immutable and version controlled:

```text
nagios/conf.d/*.cfg
        |
        | docker build / COPY
        v
/usr/local/nagios/etc/conf.d/*.cfg
        |
        v
Nagios image
```

There is intentionally **no bind mount for Nagios object configuration** in
`docker-compose.yml`. A configuration change therefore requires a new image
build and container recreation.

Nagios runtime state is stored in the named `nagios_var` volume. The container
root filesystem is read-only; `/run`, `/tmp` and Apache's log directory use
tmpfs. Notifications are disabled by default until a real notification transport is configured.

## Versions

- Ubuntu 24.04
- Nagios Core 4.5.14
- Nagios Plugins 2.5

## Initial test target

`nagios/conf.d/nextcloud.cfg` monitors `nc2.elastic2ls.com` with:

1. `https://nc2.elastic2ls.com/status.php`
   - HTTPS/SNI
   - certificate hostname verification
   - HTTP 200
   - response contains `"installed":true`
   - WARNING after 5 seconds, CRITICAL after 10 seconds
2. TLS certificate lifetime
   - WARNING below 30 days
   - CRITICAL below 14 days

The host check itself uses the Nextcloud status endpoint, so the target is not
incorrectly marked DOWN merely because ICMP is filtered.

## Configuration

Create the local environment file:

```bash
cp .env.example .env
```

Set at least:

```dotenv
NAGIOS_HOSTNAME=nagios.elastic2ls.com
NAGIOSADMIN_PASSWORD=<long-random-password>
```

The external Docker network must already exist:

```bash
docker network inspect proxy_net >/dev/null 2>&1 || docker network create proxy_net
```

## Build and start

```bash
docker compose build --no-cache nagios
docker compose up -d nagios
```

Nagios validates all `*.cfg` files during `docker build` and again before the
container starts. An invalid repository configuration therefore fails before
Nagios becomes active.

## Verify

```bash
docker compose ps
docker compose logs -f nagios
```

Manual configuration validation:

```bash
docker compose exec nagios \
  /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg
```

Manual Nextcloud application check:

```bash
docker compose exec nagios \
  /usr/local/nagios/libexec/check_http \
  -H nc2.elastic2ls.com -S --sni --verify-host \
  -u /status.php -e 200 -s '"installed":true' -w 5 -c 10 -t 15
```

Manual certificate check:

```bash
docker compose exec nagios \
  /usr/local/nagios/libexec/check_http \
  -H nc2.elastic2ls.com -S --sni --verify-host -C 30,14 -t 15
```

## Add another monitored service

Add another `*.cfg` file below `nagios/conf.d/`, for example:

```text
nagios/conf.d/pihole.cfg
```

Then rebuild and redeploy:

```bash
docker compose build nagios
docker compose up -d nagios
```

Because the configuration is copied into the image, the running container can
never silently diverge from the Git revision used to build it.
