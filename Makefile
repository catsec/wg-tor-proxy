# Minimal Makefile for building & running the WireGuard+Tor SOCKS gateway
# Targets:
#   make build   - build the container image
#   make up      - start the service
#   make down    - stop the service
#   make logs    - follow logs (temporarily enable DEBUG=true first if needed)
#   make clean   - remove containers (keeps ./data)
#   make nuke    - remove containers and ./data

IMAGE ?= wg-tor-gateway
COMPOSE ?= docker compose

.PHONY: build up down logs clean nuke

build:
	$(COMPOSE) build

up:
	$(COMPOSE) up -d

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f

clean:
	$(COMPOSE) down --remove-orphans

nuke:
	$(COMPOSE) down --remove-orphans -v || true
	rm -rf ./data
