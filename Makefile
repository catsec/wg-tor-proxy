.PHONY: help setup build up down restart logs shell test-tor test-wg clean regenerate-keys status

help:
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

setup: ## Initial setup
	@mkdir -p data/configs data/wireguard-configs
	@[ -f .env ] || cp .env.example .env
	@echo "Setup complete"

build: ## Build the Docker image
	docker-compose build --no-cache

up: ## Start the container
	docker-compose up -d
	@sleep 5
	@make status

down: ## Stop the container
	docker-compose down

restart: ## Restart the container
	docker-compose restart
	@sleep 3
	@make status

logs: ## View logs
	docker-compose logs -f

shell: ## Open shell in container
	docker-compose exec tor-wireguard sh

test-tor: ## Test Tor connectivity
	@docker-compose exec tor-wireguard curl -x socks5h://127.0.0.1:9050 -s https://check.torproject.org/ | grep -q "Congratulations" && echo "Tor is working" || echo "Tor connection failed"

test-wg: ## Show WireGuard status
	@docker-compose exec tor-wireguard wg show

status: ## Show system status
	@echo "System Status:"
	@docker-compose ps
	@[ -f data/wireguard-configs/molly-tor.conf ] && echo "Config: data/wireguard-configs/molly-tor.conf" || echo "Config not found"

clean: ## Remove all data
	@read -p "Remove all keys and configs? (y/N) " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		docker-compose down -v; \
		rm -rf data/*; \
		echo "Cleaned"; \
	fi

regenerate-keys: ## Regenerate WireGuard keys
	@rm -f data/configs/client_*.key data/configs/server_*.key
	@docker-compose restart
	@sleep 5
	@echo "Keys regenerated"
