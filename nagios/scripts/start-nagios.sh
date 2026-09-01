#!/usr/bin/env bash
set -euo pipefail

CONTAINER="nagios"
TRAEFIK_CONTAINER="${TRAEFIK_CONTAINER:-traefik}"
PROXY_NETWORK="proxy_net"
EGRESS_NETWORK="nagios_egress"
RULE_TAG="nagios-public-check"

# This deployment intentionally checks the host's public IP from Nagios.
# On this legacy Docker setup, Docker's own nat/DOCKER chain returns traffic
# arriving from a user-defined bridge before the published-port DNAT rule.
# Therefore we install a narrowly scoped, idempotent host DNAT/forwarding rule.

compose() {
  docker-compose "$@"
}

run_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

dotenv_value() {
  local key="$1"
  [[ -f .env ]] || return 0
  awk -v key="${key}" '
    $0 ~ "^[[:space:]]*" key "=" {
      sub("^[[:space:]]*" key "=", "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      gsub(/^\"|\"$/, "")
      print
      exit
    }' .env
}

network_attached() {
  docker inspect "${CONTAINER}" \
    --format '{{range $name, $cfg := .NetworkSettings.Networks}}{{println $name}}{{end}}' \
    | grep -qx "$1"
}

bridge_name() {
  local network="$1"
  local configured id
  configured="$(docker network inspect "${network}" --format '{{index .Options "com.docker.network.bridge.name"}}' 2>/dev/null || true)"
  if [[ -n "${configured}" && "${configured}" != "<no value>" ]]; then
    printf '%s\n' "${configured}"
    return
  fi
  id="$(docker network inspect "${network}" --format '{{.Id}}')"
  printf 'br-%s\n' "${id:0:12}"
}

iptables_chain_ensure() {
  local table="$1"
  local chain="$2"
  if ! run_root iptables -t "${table}" -nL "${chain}" >/dev/null 2>&1; then
    run_root iptables -t "${table}" -N "${chain}"
  fi
}

iptables_jump_ensure() {
  local table="$1"
  local parent="$2"
  local child="$3"
  local comment="$4"
  if ! run_root iptables -t "${table}" -C "${parent}" \
      -m comment --comment "${comment}" -j "${child}" >/dev/null 2>&1; then
    run_root iptables -t "${table}" -I "${parent}" 1 \
      -m comment --comment "${comment}" -j "${child}"
  fi
}

iptables_delete_all() {
  local table="$1"
  local chain="$2"
  shift 2
  while run_root iptables -t "${table}" -C "${chain}" "$@" >/dev/null 2>&1; do
    run_root iptables -t "${table}" -D "${chain}" "$@"
  done
}

EGRESS_SUBNET="${NAGIOS_EGRESS_SUBNET:-$(dotenv_value NAGIOS_EGRESS_SUBNET)}"
EGRESS_GATEWAY="${NAGIOS_EGRESS_GATEWAY:-$(dotenv_value NAGIOS_EGRESS_GATEWAY)}"
EGRESS_SUBNET="${EGRESS_SUBNET:-172.30.250.0/24}"
EGRESS_GATEWAY="${EGRESS_GATEWAY:-172.30.250.1}"
PUBLIC_IP="${NAGIOS_TEST_PUBLIC_IP:-152.53.46.232}"
PUBLIC_HOST="${NAGIOS_TEST_HOST:-nc2.elastic2ls.com}"

# Traefik owns this external network.
if ! docker network inspect "${PROXY_NETWORK}" >/dev/null 2>&1; then
  echo >&2 "ERROR: required external network '${PROXY_NETWORK}' does not exist."
  exit 1
fi

if ! docker inspect "${TRAEFIK_CONTAINER}" >/dev/null 2>&1; then
  echo >&2 "ERROR: Traefik container '${TRAEFIK_CONTAINER}' does not exist."
  exit 1
fi

# Create the dedicated egress bridge with stable IPAM.
if ! docker network inspect "${EGRESS_NETWORK}" >/dev/null 2>&1; then
  docker network create \
    --driver bridge \
    --subnet "${EGRESS_SUBNET}" \
    --gateway "${EGRESS_GATEWAY}" \
    "${EGRESS_NETWORK}" >/dev/null
else
  ACTUAL_SUBNET="$(docker network inspect "${EGRESS_NETWORK}" --format '{{(index .IPAM.Config 0).Subnet}}')"
  ACTUAL_GATEWAY="$(docker network inspect "${EGRESS_NETWORK}" --format '{{(index .IPAM.Config 0).Gateway}}')"
  if [[ "${ACTUAL_SUBNET}" != "${EGRESS_SUBNET}" || "${ACTUAL_GATEWAY}" != "${EGRESS_GATEWAY}" ]]; then
    echo >&2 "ERROR: '${EGRESS_NETWORK}' exists with unexpected IPAM settings."
    echo >&2 "Expected: subnet=${EGRESS_SUBNET} gateway=${EGRESS_GATEWAY}"
    echo >&2 "Actual:   subnet=${ACTUAL_SUBNET} gateway=${ACTUAL_GATEWAY}"
    exit 1
  fi
fi

# Compose creates/recreates Nagios on egress first.
compose up -d --build "${CONTAINER}"

# Attach proxy_net idempotently. Legacy Compose cannot express gateway priority.
if ! network_attached "${PROXY_NETWORK}"; then
  docker network connect "${PROXY_NETWORK}" "${CONTAINER}"
fi

# Restore the dedicated egress bridge as default route.
docker exec \
  -e NAGIOS_EGRESS_GATEWAY="${EGRESS_GATEWAY}" \
  "${CONTAINER}" /usr/local/bin/configure_egress_route.sh

EGRESS_BRIDGE="$(bridge_name "${EGRESS_NETWORK}")"
PROXY_BRIDGE="$(bridge_name "${PROXY_NETWORK}")"
TRAEFIK_IP="$(docker inspect "${TRAEFIK_CONTAINER}" \
  --format "{{(index .NetworkSettings.Networks \"${PROXY_NETWORK}\").IPAddress}}")"

if [[ -z "${TRAEFIK_IP}" || "${TRAEFIK_IP}" == "<no value>" ]]; then
  echo >&2 "ERROR: could not determine Traefik IP on '${PROXY_NETWORK}'."
  exit 1
fi

# Verify bridge devices exist before modifying firewall rules.
for bridge in "${EGRESS_BRIDGE}" "${PROXY_BRIDGE}"; do
  if [[ ! -e "/sys/class/net/${bridge}" ]]; then
    echo >&2 "ERROR: expected Docker bridge '${bridge}' does not exist."
    exit 1
  fi
done

# Remove the exact temporary rules used while diagnosing this host. These
# existed only in the development path before the managed chains below.
iptables_delete_all nat PREROUTING \
  -i "${EGRESS_BRIDGE}" -d "${PUBLIC_IP}/32" \
  -p tcp --dport 443 \
  -j DNAT --to-destination "${TRAEFIK_IP}:443"

iptables_delete_all filter DOCKER-USER \
  -i "${EGRESS_BRIDGE}" -o "${PROXY_BRIDGE}" \
  -s "${EGRESS_SUBNET}" -d "${TRAEFIK_IP}/32" \
  -p tcp --dport 443 \
  -m conntrack --ctorigdst "${PUBLIC_IP}" --ctorigdstport 443 \
  -j ACCEPT

# This broad rule was also used only for diagnosis. Remove it so the final
# deployment does not leave a wider-than-required forwarding exception behind.
iptables_delete_all filter DOCKER-USER \
  -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Dedicated managed chains avoid stale Docker bridge IDs or Traefik IPs. The
# hooks are stable; chain contents are rebuilt from current Docker state on
# every deployment.
NAT_CHAIN="NAGIOS-PUBLIC-DNAT"
FWD_CHAIN="NAGIOS-PUBLIC-FWD"

iptables_chain_ensure nat "${NAT_CHAIN}"
iptables_chain_ensure filter "${FWD_CHAIN}"
iptables_jump_ensure nat PREROUTING "${NAT_CHAIN}" "${RULE_TAG}-hook"
iptables_jump_ensure filter DOCKER-USER "${FWD_CHAIN}" "${RULE_TAG}-hook"

run_root iptables -t nat -F "${NAT_CHAIN}"
run_root iptables -t filter -F "${FWD_CHAIN}"

# DNAT must happen before Docker's own nat/DOCKER bridge RETURN rule.
run_root iptables -t nat -A "${NAT_CHAIN}" \
  -i "${EGRESS_BRIDGE}" \
  -d "${PUBLIC_IP}/32" \
  -p tcp --dport 443 \
  -m comment --comment "${RULE_TAG}-dnat" \
  -j DNAT --to-destination "${TRAEFIK_IP}:443"

# Permit only the DNATed public-IP check across the two Docker bridges.
run_root iptables -t filter -A "${FWD_CHAIN}" \
  -i "${EGRESS_BRIDGE}" \
  -o "${PROXY_BRIDGE}" \
  -s "${EGRESS_SUBNET}" \
  -d "${TRAEFIK_IP}/32" \
  -p tcp --dport 443 \
  -m conntrack --ctstate NEW,ESTABLISHED \
  --ctorigdst "${PUBLIC_IP}" --ctorigdstport 443 \
  -m comment --comment "${RULE_TAG}-forward" \
  -j ACCEPT

run_root iptables -t filter -A "${FWD_CHAIN}" \
  -i "${PROXY_BRIDGE}" \
  -o "${EGRESS_BRIDGE}" \
  -s "${TRAEFIK_IP}/32" \
  -d "${EGRESS_SUBNET}" \
  -p tcp --sport 443 \
  -m conntrack --ctstate RELATED,ESTABLISHED \
  -m comment --comment "${RULE_TAG}-return" \
  -j ACCEPT

echo
echo "Nagios network attachments:"
docker inspect "${CONTAINER}" \
  --format '{{range $name, $cfg := .NetworkSettings.Networks}}{{$name}} -> {{$cfg.IPAddress}} gateway={{$cfg.Gateway}}{{println}}{{end}}'

echo "Default route:"
docker exec "${CONTAINER}" ip route show default

echo
echo "Public-check path:"
echo "  ${CONTAINER} --${EGRESS_BRIDGE}--> ${PUBLIC_IP}:443 --DNAT--> ${TRAEFIK_IP}:443 (${TRAEFIK_CONTAINER}/${PROXY_NETWORK})"

echo
echo "Testing public TCP endpoint ${PUBLIC_IP}:443 from Nagios ..."
if ! docker exec "${CONTAINER}" \
  bash -c "timeout 5 bash -c '</dev/tcp/${PUBLIC_IP}/443'"; then
  echo >&2 "ERROR: ${PUBLIC_IP}:443 is not reachable from the Nagios container."
  exit 1
fi
echo "${PUBLIC_IP}:443 OK"

echo
echo "Testing Nextcloud through public IP with Host/SNI ${PUBLIC_HOST} ..."
docker exec "${CONTAINER}" \
  /usr/local/nagios/libexec/check_http \
  -4 \
  -I "${PUBLIC_IP}" \
  -H "${PUBLIC_HOST}" \
  -S \
  --sni \
  --verify-host \
  -u /status.php \
  -e 200 \
  -s '"installed":true' \
  -w 5 \
  -c 10 \
  -t 15
