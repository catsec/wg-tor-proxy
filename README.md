# wg-tor-proxy
WireGuard → Tor SOCKS proxy tailored for **Molly (Signal)**. The client routes only to the server’s tunnel IP; inside the container, SOCKS and DNS are handled via Tor. No logs by default; enable `DEBUG=true` if you need to troubleshoot.

## Quick start
```bash
docker compose up -d
```
Client files (after first start):
- `./data/molly-tor.conf` — import into WireGuard mobile
- `./data/molly-tor.qr.txt` — ASCII QR (optional)
- `./data/molly-tor.txt` — quick Molly steps

## Synology DSM 7.2 (Intel/amd64) notes
- Ensure `/dev/net/tun` exists and `tun` module is loaded (DSM 7.2 usually is):
  ```sh
  lsmod | grep tun
  ls -l /dev/net/tun
  ```
- Compose already includes:
  ```yaml
  devices:
    - /dev/net/tun:/dev/net/tun
  cap_add:
    - NET_ADMIN
  ```
- Map your data folder to a Synology path, e.g. `/volume1/docker/wg-tor/data:/data`.

## Router
Forward **UDP 51820 → your NAS**. If behind dynamic IP, use a DNS name and set `WG_HOST` to it in `docker-compose.yml`.

## Debug
Set `DEBUG=true` in `docker-compose.yml` and restart. Tor logs switch to stdout; entrypoint prints status.

## Security
- Only SOCKS (`10.13.13.1:9050`) and DNS (redirected to Tor) are reachable over the tunnel.
- Keys live under `./data` — keep this folder private.


## GitHub Actions (GHCR) workflow
This repo includes `.github/workflows/build.yml` to build **linux/amd64 + linux/arm64** and push to **GHCR** on:
- pushes to `main`/`master` → tags `:latest` and `:<short-sha>`
- tags `v*` (e.g., `v0.1.0`) → tags `:latest` and `:v0.1.0`

No extra secrets are needed: the default `GITHUB_TOKEN` has `packages: write` permission.
To pull on Synology:
```bash
docker login ghcr.io -u catsec -p <a classic PAT or token>
docker pull ghcr.io/catsec/wg-tor-proxy:latest
```

**Compose example using the published image:**
```yaml
services:
  wg-tor:
    image: ghcr.io/catsec/wg-tor-proxy:latest
    devices:
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - NET_ADMIN
    volumes:
      - /volume1/docker/wg-tor/data:/data
    ports:
      - "51820:51820/udp"
    environment:
      - WG_HOST=auto
      - WG_PORT=51820
      - SOCKS_PORT=9050
      - DEBUG=false
    restart: unless-stopped
```

## Sanity fixes included
- Corrected client `Endpoint` when `WG_HOST=auto` by passing the detected IP to the generator.
- Adjusted `DNSPort` bind to `0.0.0.0:5353` to work with iptables REDIRECT from wg0.
