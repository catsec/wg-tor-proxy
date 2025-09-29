FROM alpine:3.20

RUN apk add --no-cache \
    tor \
    wireguard-tools \
    iptables \
    ip6tables \
    bash \
    curl \
    openresolv \
    python3 \
    py3-pip \
    && rm -rf /var/cache/apk/* \
    && pip3 install --no-cache-dir qrcode[pil] --break-system-packages

RUN adduser -D -u 1000 -s /sbin/nologin toruser && \
    adduser -D -u 1001 -s /sbin/nologin wguser

RUN mkdir -p /var/lib/tor /etc/wireguard /data && \
    chown -R toruser:toruser /var/lib/tor && \
    chmod 700 /var/lib/tor && \
    chmod 755 /data

COPY --chmod=755 entrypoint.sh /entrypoint.sh
COPY --chmod=755 generate-wireguard-config.sh /usr/local/bin/generate-wireguard-config.sh

HEALTHCHECK --interval=60s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -x socks5h://10.13.13.1:9050 -s https://check.torproject.org/ | grep -q Congratulations || exit 1

WORKDIR /data

ENTRYPOINT ["/entrypoint.sh"]
