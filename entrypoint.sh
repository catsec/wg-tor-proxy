#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

WG_INTERFACE="wg0"
WG_SUBNET="10.13.13.0/24"
WG_PORT="${WG_PORT:-51820}"
SOCKS_PORT="${SOCKS_PORT:-9050}"

log_info "Starting Tor + WireGuard Privacy Proxy..."

if [ "$WG_HOST" = "auto" ]; then
    log_info "Detecting public IP address..."
    WG_HOST=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me || echo "localhost")
    log_info "Detected public IP: $WG_HOST"
fi

mkdir -p /data

if [ ! -f /data/server_private.key ]; then
    log_info "Generating WireGuard server keys..."
    wg genkey | tee /data/server_private.key | wg pubkey > /data/server_public.key
    chmod 600 /data/server_private.key
    log_info "Server keys generated"
fi

if [ ! -f /data/client_private.key ]; then
    log_info "Generating WireGuard client keys..."
    wg genkey | tee /data/client_private.key | wg pubkey > /data/client_public.key
    chmod 600 /data/client_private.key
    log_info "Client keys generated"
fi

if [ ! -f /data/torrc ]; then
    log_info "Creating Tor configuration..."
    cp /usr/share/tor/torrc.sample /data/torrc || cat > /data/torrc <<TOREOF
SocksPort 0.0.0.0:9050
CookieAuthentication 1
AvoidDiskWrites 1
Log notice file /dev/null
DataDirectory /var/lib/tor
ExitRelay 0
TOREOF
    log_info "Tor configuration created"
fi

SERVER_PRIVATE_KEY=$(cat /data/server_private.key)
SERVER_PUBLIC_KEY=$(cat /data/server_public.key)
CLIENT_PRIVATE_KEY=$(cat /data/client_private.key)
CLIENT_PUBLIC_KEY=$(cat /data/client_public.key)

log_info "Creating WireGuard server configuration..."
cat > /etc/wireguard/${WG_INTERFACE}.conf <<WGEOF
[Interface]
PrivateKey = ${SERVER_PRIVATE_KEY}
Address = 10.13.13.1/24
ListenPort = ${WG_PORT}
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT

[Peer]
PublicKey = ${CLIENT_PUBLIC_KEY}
AllowedIPs = 10.13.13.2/32
PersistentKeepalive = 25
WGEOF

chmod 600 /etc/wireguard/${WG_INTERFACE}.conf

log_info "Generating WireGuard client configuration..."
/usr/local/bin/generate-wireguard-config.sh \
    "$CLIENT_PRIVATE_KEY" \
    "$SERVER_PUBLIC_KEY" \
    "$WG_HOST" \
    "$WG_PORT" \
    "$SOCKS_PORT"

log_info "Starting WireGuard interface..."
wg-quick up ${WG_INTERFACE}

log_info "Configuring firewall rules..."

iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X

iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

iptables -A INPUT -p udp --dport ${WG_PORT} -j ACCEPT

iptables -A INPUT -s ${WG_SUBNET} -p tcp --dport ${SOCKS_PORT} -j ACCEPT
iptables -A FORWARD -s ${WG_SUBNET} -p tcp --dport ${SOCKS_PORT} -j ACCEPT

iptables -A FORWARD -i ${WG_INTERFACE} -j DROP

log_info "Firewall configured - Only SOCKS5 port accessible via WireGuard"

log_info "Starting Tor daemon..."
chown -R toruser:toruser /var/lib/tor
su -s /bin/sh toruser -c "tor -f /data/torrc" &
TOR_PID=$!

log_info "Waiting for Tor to establish circuits..."
sleep 15

if kill -0 $TOR_PID 2>/dev/null; then
    log_info "${GREEN}[OK]${NC} Tor is running (PID: $TOR_PID)"
else
    log_error "Tor failed to start"
    exit 1
fi

if curl -x socks5h://127.0.0.1:${SOCKS_PORT} -s https://check.torproject.org/ | grep -q Congratulations; then
    log_info "${GREEN}[OK]${NC} Tor connection verified"
else
    log_warn "Tor connection test inconclusive (may take longer to establish circuits)"
fi

log_info "============================================"
log_info "${GREEN}System Ready!${NC}"
log_info "============================================"
log_info "WireGuard config: /data/molly-tor.conf"
log_info "SOCKS5 Proxy: 10.13.13.1:${SOCKS_PORT}"
log_info "WireGuard Port: ${WG_PORT}/udp"
log_info "============================================"

cleanup() {
    log_info "Shutting down..."

    # Stop Tor daemon gracefully
    if [ ! -z "$TOR_PID" ]; then
        kill -TERM $TOR_PID 2>/dev/null || true
        sleep 5
        kill -KILL $TOR_PID 2>/dev/null || true
        wait $TOR_PID 2>/dev/null || true
    fi

    # Clean up WireGuard interface
    wg-quick down ${WG_INTERFACE} 2>/dev/null || true

    log_info "Shutdown complete"
    exit 0
}

trap cleanup SIGTERM SIGINT

while true; do
    # Check Tor process
    if ! kill -0 $TOR_PID 2>/dev/null; then
        log_error "Tor process died, restarting..."
        su -s /bin/sh toruser -c "tor -f /data/torrc" &
        TOR_PID=$!
    fi

    sleep 30
done
