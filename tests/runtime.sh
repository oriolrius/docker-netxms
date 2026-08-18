#!/usr/bin/env bash
#
# Runtime suite: starts a server and an agent from the given images and checks that
# they actually work -- the server initialises its database and listens, the agent
# renders its config from the environment, and the server can query the agent over
# NXCP. Works against locally built images or against images pulled from a registry.
#
# Usage: tests/runtime.sh <server-image> <agent-image> [expected-netxms-version]
set -uo pipefail

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trap cleanup EXIT
require_docker

if [ $# -lt 2 ]; then
    printf 'usage: %s <server-image> <agent-image> [expected-netxms-version]\n' "$0" >&2
    exit 2
fi

SERVER_IMAGE="$1"
AGENT_IMAGE="$2"
EXPECTED_VERSION="${3:-$(pinned_version Dockerfile.server)}"

NETWORK="netxms-test-net-$$"
SERVER_CT="netxms-test-server-$$"
AGENT_CT="netxms-test-agent-$$"
AGENT_DEFAULTS_CT="netxms-test-agent-defaults-$$"

log "Starting $SERVER_IMAGE"
docker network create "$NETWORK" >/dev/null
register_network "$NETWORK"
SUBNET="$(docker network inspect "$NETWORK" -f '{{ (index .IPAM.Config 0).Subnet }}')"

# -t mirrors `tty: true` in compose.yaml: netxmsd exits as soon as stdin closes, so
# the server only stays up with a TTY attached.
register_container "$SERVER_CT"
docker run -d -t --name "$SERVER_CT" --network "$NETWORK" "$SERVER_IMAGE" >/dev/null
SERVER_IP="$(docker inspect -f "{{ (index .NetworkSettings.Networks \"$NETWORK\").IPAddress }}" "$SERVER_CT")"
info "server at $SERVER_IP on $SUBNET"

if wait_for 120 docker exec "$SERVER_CT" sh -c 'netstat -ln | grep -q :4701'; then
    pass "server listens on 4701 (client port)"
else
    fail "server listens on 4701 (client port)" "$(docker logs "$SERVER_CT" 2>&1 | tail -5)"
fi

assert_ok "server listens on 4703 (agent tunnel port)" \
    docker exec "$SERVER_CT" sh -c 'netstat -ln | grep -q :4703'
assert_ok "server initialised its SQLite database" \
    docker exec "$SERVER_CT" test -s /var/lib/netxms/netxms.db
assert_ok "compose healthcheck command succeeds" \
    docker exec "$SERVER_CT" sh -c 'netstat -ln | grep :4701'
assert_ok "server stayed up" docker exec "$SERVER_CT" pgrep netxmsd

server_version="$(docker exec "$SERVER_CT" sh -c 'netxmsd -v 2>&1 | head -1' | tr -d '\r')"
assert_contains "server runs NetXMS $EXPECTED_VERSION" \
    "NetXMS Server Version $EXPECTED_VERSION" "$server_version"

log "Starting $AGENT_IMAGE against the server"
register_container "$AGENT_CT"
docker run -d --name "$AGENT_CT" --network "$NETWORK" \
    -e SERVER="$SERVER_IP" \
    -e MASTER_SERVERS="$SUBNET" \
    -e DEBUG_LEVEL=3 \
    -e PROXY_AGENT=yes \
    -e PROXY_SNMP=yes \
    "$AGENT_IMAGE" >/dev/null
AGENT_IP="$(docker inspect -f "{{ (index .NetworkSettings.Networks \"$NETWORK\").IPAddress }}" "$AGENT_CT")"
info "agent at $AGENT_IP"

if wait_for 90 docker exec "$SERVER_CT" nxget "$AGENT_IP" Agent.Version; then
    pass "agent answers NXCP requests from the server"
else
    fail "agent answers NXCP requests from the server" "$(docker logs "$AGENT_CT" 2>&1 | tail -5)"
fi

assert_ok "compose healthcheck command succeeds (agent)" docker exec "$AGENT_CT" pgrep nxagentd

agent_conf="$(docker exec "$AGENT_CT" cat /etc/netxms/nxagentd.conf | tr -d '\r')"
assert_contains "MASTER_SERVERS lands in nxagentd.conf" "MasterServers = $SUBNET" "$agent_conf"
assert_contains "DEBUG_LEVEL lands in nxagentd.conf" "DebugLevel = 3" "$agent_conf"
assert_contains "PROXY_AGENT enables the agent proxy" "EnableProxy = yes" "$agent_conf"
assert_contains "PROXY_SNMP enables the SNMP proxy" "EnableSNMPProxy = yes" "$agent_conf"

reported_version="$(docker exec "$SERVER_CT" nxget "$AGENT_IP" Agent.Version 2>&1 | tr -d '\r')"
assert_eq "agent reports NetXMS $EXPECTED_VERSION over NXCP" "$EXPECTED_VERSION" "$reported_version"

uptime="$(docker exec "$SERVER_CT" nxget "$AGENT_IP" System.Uptime 2>&1 | tr -d '\r')"
assert_matches "System.Uptime returns a number" '^[0-9]+$' "$uptime"

db_status="$(docker exec "$SERVER_CT" nxget "$AGENT_IP" Agent.LocalDatabase.Status 2>&1 | tr -d '\r')"
assert_eq "agent local database is healthy" "0" "$db_status"

log "Agent defaults with no proxy variables set"
register_container "$AGENT_DEFAULTS_CT"
docker run -d --name "$AGENT_DEFAULTS_CT" --network "$NETWORK" "$AGENT_IMAGE" >/dev/null
if wait_for 60 docker exec "$AGENT_DEFAULTS_CT" test -s /etc/netxms/nxagentd.conf; then
    defaults_conf="$(docker exec "$AGENT_DEFAULTS_CT" cat /etc/netxms/nxagentd.conf | tr -d '\r')"
    assert_contains "proxy is off by default" "EnableProxy = no" "$defaults_conf"
    assert_contains "SNMP proxy is off by default" "EnableSNMPProxy = no" "$defaults_conf"
    assert_contains "MasterServers falls back to the SERVER default" \
        "MasterServers = 172.20.0.2" "$defaults_conf"
else
    fail "agent renders a config with no environment overrides"
fi

summary "runtime suite"
