# docker-stacks

Docker Compose stacks managed via Portainer (Git sync).

## proxy-traefik
Reverse proxy with Let's Encrypt. Deploy first.

## nextcloud
Nextcloud + Postgres + Redis. Attach to proxy_net.

## Secrets
Provide via Portainer stack environment variables:
- POSTGRES_PASSWORD
- NEXTCLOUD_ADMIN_USER
- NEXTCLOUD_ADMIN_PASSWORD
