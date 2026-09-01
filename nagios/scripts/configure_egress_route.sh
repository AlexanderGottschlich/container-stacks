#!/usr/bin/env bash
set -euo pipefail

: "${NAGIOS_EGRESS_GATEWAY:=172.30.250.1}"

# The egress network uses a fixed gateway created by start-nagios.sh.
# Route replacement is idempotent and is required for legacy Docker engines
# which cannot assign a gateway priority to a network endpoint.
ip route replace default via "${NAGIOS_EGRESS_GATEWAY}"

echo "Default route: $(ip route show default)"
