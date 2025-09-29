#!/bin/bash
set -euo pipefail

# Colors (silence when DEBUG=false)
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
DEBUG="${DEBUG:-false}"
if [ "$DEBUG" = "true" ]; then
  log_info(){ echo -e "${GREEN}[INFO]${NC} $*"; }
  log_warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
  log_error(){ echo -e "${RED}[ERROR]${NC} $*"; }
else
  log_info(){ :; }; log_warn(){ :; }; log_error(){ :; }
fi

WG_INTERFACE="${WG_INTERFACE:-wg0}"
WG_SUBNET="${WG_SUBNET:-10.13.13.0/24}"
WG_ADDR="${WG_ADDR:-10.13.13.1/24}"
WG_HOST="${WG_HOST:-auto}"
WG_PORT="${WG_PORT:-51820}"
SOCKS_PORT="${SOCKS_PORT:-9050}"

mkdir -p /data /etc/wireguard /data/tor
chmod 700 /data

# Detect public endpoint if WG_HOST=auto
detect_public() {
  (curl -fsS https://ifconfig.me || curl -fsS https://api.ipify.org) 2>/dev/null || true
}

if [ "$WG_HOST" = "auto" ]; then
  IP=$(detect_public || true)
  if [ -n "${IP:-}" ]; then
    WG_ENDPOINT="$IP:$WG_PORT"
  else
    log_warn "Could not auto-detect public IP; WG endpoint will be ':$WG_PORT' until reachable."
    WG_ENDPOINT=":$WG_PORT"
  fi
else
  WG_ENDPOINT="$WG_HOST:$WG_PORT"
fi
log_info "WG endpoint: ${WG_ENDPOINT}"

# Keys
if [ ! -f /data/server_private.key ]; then
  log_info "Generating WireGuard server keys..."
  umask 077
  wg genkey | tee /data/server_private.key | wg pubkey > /data/server_public.key
fi
if [ ! -f /data/client_private.key ]; then
  log_info "Generating WireGuard client keys..."
  umask 077
  wg genkey | tee /data/client_private.key | wg pubkey > /data/client_public.key
fi

SERVER_PRIVATE_KEY=$(cat /data/server_private.key)
SERVER_PUBLIC_KEY=$(cat /data/server_public.key)
CLIENT_PUBLIC_KEY=$(cat /data/client_public.key)

# Server config
cat >/etc/wireguard/${WG_INTERFACE}.conf <<EOF
[Interface]
PrivateKey = ${SERVER_PRIVATE_KEY}
Address = ${WG_ADDR}
ListenPort = ${WG_PORT}
# We deliberately do NOT set PostUp/PostDown here; firewall set below.

[Peer]
# single allowed client; add more peers as needed
PublicKey = ${CLIENT_PUBLIC_KEY}
AllowedIPs = 10.13.13.2/32
PersistentKeepalive = 25
EOF

# Bring up WG
log_info "Bringing up ${WG_INTERFACE}..."
wg-quick up ${WG_INTERFACE} || (log_error "Failed to bring up ${WG_INTERFACE}"; ip a; exit 1)

# Tor config: SOCKS + DNSPort with no logs by default
if [ ! -f /data/torrc ]; then
  cat >/data/torrc <<'TORRC'
SocksPort 0.0.0.0:9050
DNSPort 127.0.0.1:5353
AvoidDiskWrites 1
Log notice file /dev/null
DataDirectory /data/tor
ExitRelay 0
TORRC
fi
# If DEBUG=true, switch Tor logs to stdout (optional)
if [ "$DEBUG" = "true" ]; then
  sed -i 's|^Log .*|Log notice stdout|' /data/torrc || true
fi

# Firewall: reset and lock down
# Accept only what we need; block everything else
log_info "Configuring iptables..."
iptables -F || true
iptables -t nat -F || true
iptables -X || true
iptables -t nat -X || true

# Base policies
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Accept loopback and established
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow WireGuard UDP port on INPUT
iptables -A INPUT -p udp --dport ${WG_PORT} -j ACCEPT

# Allow SOCKS5 on INPUT from WG subnet only
iptables -A INPUT -s ${WG_SUBNET} -p tcp --dport ${SOCKS_PORT} -j ACCEPT

# Redirect DNS (53) from wg0 to Tor DNSPort 5353 (both UDP and TCP)
iptables -t nat -A PREROUTING -i ${WG_INTERFACE} -p udp --dport 53 -j REDIRECT --to-ports 5353
iptables -t nat -A PREROUTING -i ${WG_INTERFACE} -p tcp --dport 53 -j REDIRECT --to-ports 5353

# (No FORWARD exceptions for SOCKS; traffic terminates locally.)

# Generate client config + QR
/usr/local/bin/generate-wireguard-config.sh "$(cat /data/client_private.key)" "${SERVER_PUBLIC_KEY}" "${WG_HOST}" "${WG_PORT}" "${SOCKS_PORT}" || true

# Launch Tor and keep container alive
log_info "Starting Tor..."
tor -f /data/torrc &

# If debug, show some status
if [ "$DEBUG" = "true" ]; then
  wg show
  ss -lntup || true
fi

# Stay running
trap 'log_info "Shutting down..."; wg-quick down ${WG_INTERFACE} || true; exit 0' SIGINT SIGTERM
while true; do sleep 3600; done
