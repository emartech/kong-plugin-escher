SHELL=/bin/bash
.PHONY: help publish test

help: ## Show this help
	@echo "Targets:"
	@fgrep -h "##" $(MAKEFILE_LIST) | fgrep -v fgrep | sed -e 's/\\$$//' | sed -e 's/\(.*\):.*##[ \t]*/    \1 ## /' | sort | column -t -s '##'

up: ## Start containers
	docker-compose up -d

down: ## Stops containers
	docker-compose down

restart: down up ## Restart containers

clear-db: ## Clears local db
	bash -c "rm -rf .docker"

build: ## Rebuild containers
	docker-compose build --no-cache

complete-restart: clear-db down up    ## Clear DB and restart containers

publish: ## Build and publish plugin to luarocks
	docker-compose run kong bash -c "cd /kong-plugins && chmod +x publish.sh && ./publish.sh"

test: ## Run tests
	docker-compose run kong bash -c "cd /kong && bin/kong migrations up && bin/busted /kong-plugins/spec"
	docker-compose down

unit: ## Run unit tests
	docker-compose run kong bash -c "cd /kong && bin/kong migrations up && bin/busted --exclude-tags='e2e' /kong-plugins/spec"
	docker-compose down

e2e: ## Run end to end tests
	docker-compose run kong bash -c "cd /kong && bin/kong migrations up && bin/busted -t 'e2e' /kong-plugins/spec"
	docker-compose down


dev-env: ## Creates API (testapi) and consumer (TestUser)
	bash -c "curl -i -X POST --url http://localhost:8001/services/ --data 'name=testapi' --data 'url=http://mockbin.org/request'"
	bash -c "curl -i -X POST --url http://localhost:8001/services/testapi/routes/ --data 'paths[]=/'"
	bash -c "curl -i -X POST --url http://localhost:8001/services/testapi/plugins/ --data 'name=escher' --data 'config.encryption_key_path=/secret.txt'"
	bash -c "curl -i -X POST --url http://localhost:8001/consumers/ --data 'username=TestUser'"
	bash -c "curl -i -X POST --url http://localhost:8001/consumers/TestUser/escher_key/ --data 'key=suite_test-integration_v1&secret=53cr37p455w0rd'"

ping: ## Pings kong on localhost:8000
	bash -c "curl -i http://localhost:8000"

ssh: ## Pings kong on localhost:8000
	docker-compose run kong bash

db: ## Access DB
	docker-compose run kong bash -c "psql -h kong-database -U kong"
