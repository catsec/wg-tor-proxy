#!/usr/bin/env bash
set -euo pipefail

CLIENT_PRIVATE_KEY="$1"
SERVER_PUBLIC_KEY="$2"
WG_HOST="$3"
WG_PORT="$4"
SOCKS_PORT="$5"

# Client uses only the server's tunnel IP (split tunnel)
# DNS is the server tunnel IP; container transparently forwards to Tor DNSPort.
WG_CONFIG="[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = 10.13.13.2/32
DNS = 10.13.13.1

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
AllowedIPs = 10.13.13.1/32
Endpoint = ${WG_HOST}:${WG_PORT}
PersistentKeepalive = 25
"

mkdir -p /data
echo "$WG_CONFIG" > /data/molly-tor.conf
chmod 0644 /data/molly-tor.conf

# Create a help text for Molly users
cat > /data/molly-tor.txt <<'EOH'
Molly (Signal) over WireGuard → Tor
===================================
1) Import / scan the QR of /data/molly-tor.conf into WireGuard mobile.
2) Connect the WireGuard tunnel.
3) In Molly: Settings → Advanced → Proxy → SOCKS5
   Host: 10.13.13.1     Port: 9050
4) All Molly traffic (including DNS) will route through Tor.
EOH
chmod 0644 /data/molly-tor.txt

# Try to produce an ASCII QR. Prefer python3+qrcode, fallback to qrencode, else skip.
QR_OUT="/data/molly-tor.qr.txt"
if command -v python3 >/dev/null 2>&1; then
  python3 - <<'PY' || true
try:
    import qrcode
    img = qrcode.make(open('/data/molly-tor.conf','r').read())
    # Render a coarse ASCII approximation
    import numpy as np
    m = np.array(img, dtype=bool)
    with open('/data/molly-tor.qr.txt','w') as f:
        for row in m:
            f.write(''.join('██' if v else '  ' for v in row) + '\n')
except Exception as e:
    pass
PY
elif command -v qrencode >/dev/null 2>&1; then
  qrencode -t ASCIIi -o "$QR_OUT" < /data/molly-tor.conf || true
fi
chmod 0644 "$QR_OUT" || true

echo "WireGuard client configuration generated:"
echo "  - /data/molly-tor.conf"
[ -s "$QR_OUT" ] && echo "  - /data/molly-tor.qr.txt (ASCII QR)"
