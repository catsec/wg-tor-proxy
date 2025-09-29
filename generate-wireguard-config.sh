#!/bin/bash
set -e

CLIENT_PRIVATE_KEY="$1"
SERVER_PUBLIC_KEY="$2"
WG_HOST="$3"
WG_PORT="$4"
SOCKS_PORT="$5"

# Generate the WireGuard config content
WG_CONFIG="[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = 10.13.13.2/32
DNS = ${WG_DEFAULT_DNS:-1.1.1.1,1.0.0.1}

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
Endpoint = ${WG_HOST}:${WG_PORT}
AllowedIPs = 10.13.13.1/32
PersistentKeepalive = 25"

# Generate the full config file with instructions
cat > /data/molly-tor.conf <<CONFEOF
# Molly.im -> WireGuard -> SOCKS5 -> Tor Configuration
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
#
# SOCKS5 Proxy Settings for Molly.im:
# - Host: 10.13.13.1
# - Port: ${SOCKS_PORT}
# - Type: SOCKS5 (no authentication)

${WG_CONFIG}

# ============================================
# INSTRUCTIONS FOR MOLLY.IM
# ============================================
# 1. Import this config into your WireGuard app
# 2. Connect to the VPN
# 3. In Molly.im settings:
#    - Go to Settings > Advanced > Proxy
#    - Enable proxy
#    - Type: SOCKS5
#    - Host: 10.13.13.1
#    - Port: ${SOCKS_PORT}
# 4. Verify connection in Molly.im
# ============================================
CONFEOF

# Generate ASCII QR code for easy mobile import
echo "Generating ASCII QR code for mobile import..."
python3 -c "
import qrcode

config = '''${WG_CONFIG}'''

qr = qrcode.QRCode(border=1)
qr.add_data(config)
qr.make()
qr.print_ascii()
" > /data/molly-tor.qr.txt 2>/dev/null || echo "QR code generation failed" > /data/molly-tor.qr.txt

# Add QR code instructions to the main config file
cat >> /data/molly-tor.conf <<QREOF

# ============================================
# QR CODE FOR MOBILE IMPORT
# ============================================
# View the ASCII QR code with: cat molly-tor.qr.txt
# Or scan this QR code with your WireGuard mobile app
# for instant configuration import.
# ============================================
QREOF

chmod 644 /data/molly-tor.conf
chmod 644 /data/molly-tor.qr.txt

echo "WireGuard client configuration generated:"
echo "  Config file: /data/molly-tor.conf"
echo "  ASCII QR code: /data/molly-tor.qr.txt"
