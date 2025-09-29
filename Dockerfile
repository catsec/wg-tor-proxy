# Minimal Debian-based image with WireGuard, Tor, and tools we need
FROM debian:bookworm-slim

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      iproute2 iptables curl ca-certificates \
      wireguard-tools tor python3 python3-pip \
    && pip3 install --no-cache-dir qrcode[pil] numpy \
    && rm -rf /var/lib/apt/lists/*

# Ensure /dev/net/tun exists (runtime requires --device /dev/net/tun from host)
RUN mkdir -p /etc/wireguard /data /data/tor

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY generate-wireguard-config.sh /usr/local/bin/generate-wireguard-config.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/generate-wireguard-config.sh

EXPOSE 51820/udp 9050/tcp

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
