#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0
# Real WireGuard tunnel test in network namespaces. Nothing on the host's own
# interfaces, routes or DNS changes: both ends live in their own namespace,
# joined by a veth pair created inside them. Needs root (sudo), the kernel
# wireguard module, wireguard-tools (server side) and the helper built with
# tool/tunnel_helper/build.sh.
#
#   HELPER_DIR=/tmp/pp-tunnel-build tool/netns_test/run.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${HELPER_DIR:=/tmp/pp-tunnel-build}"
SRV=ppnet-srv CLI=ppnet-cli
WORK=$(mktemp -d); chmod 700 "$WORK"
cleanup() {
  local status=$?
  if [[ $status -ne 0 && -d "${WORK:-}" ]]; then
    [[ -n "${KEEP_DIR:-}" ]] && cp -r "$WORK"/. "$KEEP_DIR"/
    for f in "$WORK"/*.events "$WORK"/*.err; do [[ -f $f ]] && { echo "--- $f"; grep -iE 'error|fail|network|status|route|exit' "$f" | head -40; }; done
  fi
  [[ -n "${HELPER_PID:-}" ]] && sudo kill "$HELPER_PID" 2>/dev/null || true
  sudo ip netns del $SRV 2>/dev/null || true
  sudo ip netns del $CLI 2>/dev/null || true
  sudo rm -rf /etc/netns/$CLI
  sudo rm -f /etc/wireguard/ppnet-test-*.key
  rm -rf "$WORK"
}
trap cleanup EXIT
cleanup; WORK=$(mktemp -d); chmod 700 "$WORK"

sudo ip netns add $SRV
sudo ip netns add $CLI
# An empty resolv.conf for the client namespace, so nothing can reach the host's.
sudo mkdir -p /etc/netns/$CLI && echo "# netns test" | sudo tee /etc/netns/$CLI/resolv.conf >/dev/null
sudo ip -n $SRV link add veth-s type veth peer name veth-c netns $CLI
sudo ip -n $SRV addr add 10.99.0.1/24 dev veth-s
sudo ip -n $CLI addr add 10.99.0.2/24 dev veth-c
for ns in $SRV $CLI; do sudo ip -n $ns link set lo up; done
sudo ip -n $SRV link set veth-s up; sudo ip -n $CLI link set veth-c up
# Partout waits for a usable network (a default route) before it connects.
# The default route goes to a dummy device, a dead end: only the tunnel can
# reach 10.200.0.0/24, so a ping that answers went through WireGuard.
sudo ip -n $CLI link add dummy0 type dummy
sudo ip -n $CLI addr add 10.98.0.2/24 dev dummy0
sudo ip -n $CLI link set dummy0 up
sudo ip -n $CLI route add default via 10.98.0.1 dev dummy0

SRV_KEY=$(wg genkey); SRV_PUB=$(echo "$SRV_KEY" | wg pubkey)
CLI_KEY=$(wg genkey); CLI_PUB=$(echo "$CLI_KEY" | wg pubkey)
sudo ip -n $SRV link add wg0 type wireguard
# Ubuntu's AppArmor profile for wg only lets it read keys under /etc/wireguard.
KEYFILE=/etc/wireguard/ppnet-test-$$.key
sudo install -d -m 700 /etc/wireguard
echo "$SRV_KEY" | sudo install -m 600 /dev/stdin "$KEYFILE"
sudo ip netns exec $SRV wg set wg0 private-key "$KEYFILE" listen-port 51820 peer "$CLI_PUB" allowed-ips 10.200.0.2/32
sudo rm -f "$KEYFILE"
sudo ip -n $SRV addr add 10.200.0.1/24 dev wg0
sudo ip -n $SRV addr add 10.200.0.3/24 dev wg0
sudo ip -n $SRV link set wg0 up

cat > "$WORK/client.conf" <<CONF
[Interface]
PrivateKey = $CLI_KEY
Address = 10.200.0.2/32

[Peer]
PublicKey = $SRV_PUB
AllowedIPs = 10.200.0.0/24
Endpoint = 10.99.0.1:51820
PersistentKeepalive = 5
CONF

run_case() { # name, extra excluded CIDRs...
  local name=$1; shift
  dart run tool/netns_test/make_profile.dart "$WORK/client.conf" "$WORK/$name.json" "$@" >/dev/null 2>&1
  # The helper stops when its stdin closes, so keep a writer open.
  sleep 600 | sudo ip netns exec $CLI "$HELPER_DIR/partout-tunnel" "$WORK/$name.json" > "$WORK/$name.events" 2>"$WORK/$name.err" &
  HELPER_PID=$!
  for _ in $(seq 1 40); do grep -q '"status":"connected"' "$WORK/$name.events" && break; sleep 0.5; done
  echo "== $name: $(grep -o '"status":"[a-z]*"' "$WORK/$name.events" | tr '\n' ' ')"
}

stop_helper() {
  sudo pkill -TERM -P "$HELPER_PID" 2>/dev/null || true # the sudo child, by parent PID
  sudo kill -TERM "$HELPER_PID" 2>/dev/null || true
  for _ in $(seq 1 20); do grep -q '"type":"exit"' "$WORK/$1.events" && break; sleep 0.5; done
  pkill -P $$ sleep 2>/dev/null || true
  HELPER_PID=
  echo "helper exit: $(grep -o '"type":"exit","code":[0-9]*' "$WORK/$1.events")"
}

run_case plain
sleep 2
grep -q 'Received handshake response' "$WORK/plain.events" && echo "handshake: completed (engine log)"
echo "server latest handshake: $(sudo ip netns exec $SRV wg show wg0 latest-handshakes | awk '{print $2}') (unix time)"
if sudo ip -n $CLI -br addr show tun0 | grep -q 10.200.0.2; then
  echo "tun0 configured by the engine"
else
  # Partout's default Linux tun controller (ctrl_set_tunnel with no settings)
  # creates tun0 but applies no address or route. Do what a controller would,
  # inside the namespace only, to check the data path.
  echo "tun0 NOT configured by the engine (no address/route); configuring it by hand"
  sudo ip -n $CLI addr add 10.200.0.2/32 dev tun0
  sudo ip -n $CLI link set tun0 up
  sudo ip -n $CLI route add 10.200.0.0/24 dev tun0
fi
sudo ip netns exec $CLI ping -c 3 -W 2 10.200.0.1 | grep -E "transmitted"
echo "server transfer rx/tx: $(sudo ip netns exec $SRV wg show wg0 transfer | awk '{print $2"/"$3}') bytes"
sleep 2; echo "helper data event: $(grep '"type":"data"' "$WORK/plain.events" | tail -1)"
stop_helper plain
sudo ip -n $CLI link show tun0 >/dev/null 2>&1 && echo "tun0 still present" || echo "tun0 removed on stop"

# Rule groups: the profile the engine gets carries the excluded route.
dart run tool/netns_test/make_profile.dart "$WORK/client.conf" "$WORK/rulegroup.json" 10.200.0.3/32 >/dev/null 2>&1
grep -q '"excludedRoutes":\[{"destination":"10.200.0.3/32"}\]' "$WORK/rulegroup.json" \
  && echo "rule group: excluded route present in the engine profile" || echo "rule group: route MISSING"
echo "host default route: $(ip route show default)"
