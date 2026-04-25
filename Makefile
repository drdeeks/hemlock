# =============================================================================
# OpenClaw Enterprise Framework - Makefile
# 
# Docker management commands for building, testing, and deploying
# 
# Usage:
#   make help                   # Show available commands
#   make build                  # Build all Docker images
#   make up                     # Start all services
#   make down                  # Stop all services
#   make clean                 # Remove containers and volumes
#   make export                # Export all agents as Docker images
#   make push                  # Build and push all images to registry
# =============================================================================

.PHONY: help build up down clean test export import push pull logs shell

# =============================================================================
# Configuration
# =============================================================================
DOCKER_COMPOSE ?= docker compose
DOCKER ?= docker

# =============================================================================
# Help
# =============================================================================
help:
	@echo "OpenClaw Enterprise Framework - Docker Management"
	@echo ""
	@echo "Available commands:"
	@echo ""
	@echo "  build                    # Build all Docker images"
	@echo "  up                      # Start all services (daemon mode)"
	@echo "  up-logs                 # Start all services with logs"
	@echo "  down                    # Stop all services"
	@echo "  restart                 # Restart all services"
	@echo "  clean                   # Remove containers, networks, volumes"
	@echo ""
	@echo "  build-framework         # Build only framework image"
	@echo "  build-agents            # Build all agent images"
	@echo "  build-agent AGENT_ID    # Build specific agent image"
	@echo ""
	@echo "  export                  # Export all agents as Docker images"
	@echo "  export-agent AGENT_ID   # Export specific agent"
	@echo "  import IMAGE             # Import agent from Docker image"
	@echo ""
	@echo "  export-crews            # Export all crews as Docker images"
	@echo "  export-crew CREW        # Export specific crew"
	@echo "  import-crew IMAGE       # Import crew from Docker image"
	@echo "  build-crew CREW         # Build crew Docker image"
	@echo "  push-crew IMAGE         # Push crew image to registry"
	@echo ""
	@echo "  push                    # Build and push all images to registry"
	@echo "  pull                    # Pull all images from registry"
	@echo ""
	@echo "  logs                    # Show all service logs"
	@echo "  logs-service SERVICE    # Show logs for specific service"
	@echo "  shell-service SERVICE   # Open shell in running service"
	@echo "  ps                      # List running containers"
	@echo "  images                  # List Docker images"
	@echo ""
	@echo "  test                    # Run health checks"
	@echo ""

# =============================================================================
# Build Commands
# =============================================================================

build:
	@echo "Building all Docker images..."
	@docker compose -f docker-compose.yml build

build-framework:
	@echo "Building framework image..."
	@docker build --target framework -t openclaw/enterprise-framework:latest -t openclaw/enterprise-framework:1.0.0 -f Dockerfile .

build-agents:
	@echo "Building all agent images..."
	@./scripts/docker/build-images.sh agents

build-agent:
	@echo "Building agent image: $@"
	@./scripts/docker/build-images.sh agent $@

build-crew:
	@echo "Building crew image: $@"
	@docker build -t "crew-$@:1.0.0" -t "crew-$@:latest" -f Dockerfile.crew --build-arg CREW_ID=$@ .

# =============================================================================
# Docker Compose Commands
# =============================================================================

up:
	@echo "Starting all services..."
	@$(DOCKER_COMPOSE) -f docker-compose.yml up -d

up-logs:
	@echo "Starting all services with logs..."
	@$(DOCKER_COMPOSE) -f docker-compose.yml up

down:
	@echo "Stopping all services..."
	@$(DOCKER_COMPOSE) -f docker-compose.yml down

restart:
	@echo "Restarting all services..."
	@$(DOCKER_COMPOSE) -f docker-compose.yml restart

# =============================================================================
# Cleanup Commands
# =============================================================================

clean:
	@echo "Cleaning up containers, networks, and volumes..."
	@$(DOCKER_COMPOSE) -f docker-compose.yml down -v --rmi local

clean-all:
	@echo "Removing ALL stopped containers, unused networks, dangling images..."
	@docker system prune -f

# =============================================================================
# Export/Import Commands
# =============================================================================

export:
	@echo "Exporting all agents as Docker images..."
	@./scripts/docker/export-agent.sh -a

export-agent:
	@echo "Exporting agent: $@"
	@./scripts/docker/export-agent.sh $@

import:
	@echo "Importing agent from image: $@"
	@./scripts/docker/import-agent.sh $@

export-crews:
	@echo "Exporting all crews as Docker images..."
	@./scripts/docker/export-crew.sh -a

export-crew:
	@echo "Exporting crew: $@"
	@./scripts/docker/export-crew.sh $@

import-crew:
	@echo "Importing crew from image: $@"
	@./scripts/docker/import-crew.sh $@

# =============================================================================
# Registry Commands
# =============================================================================

push:
	@echo "Building and pushing all images to registry..."
	@./scripts/docker/build-images.sh push

push-crew:
	@echo "Pushing crew image: $@"
	@docker push $@

pull:
	@echo "Pulling all images from registry..."
	@docker pull openclaw/enterprise-framework:latest
	@docker pull openclaw/agent:latest
	@docker pull openclaw/gateway:latest

# =============================================================================
# Logging and Debugging
# =============================================================================

logs:
	@echo "Showing logs for all services..."
	@$(DOCKER_COMPOSE) -f docker-compose.yml logs -f

logs-service:
	@echo "Showing logs for service: $@"
	@$(DOCKER_COMPOSE) -f docker-compose.yml logs -f $@

shell-service:
	@echo "Opening shell in service: $@"
	@$(DOCKER_COMPOSE) -f docker-compose.yml exec $@ sh

ps:
	@echo "Running containers:"
	@$(DOCKER_COMPOSE) -f docker-compose.yml ps

images:
	@echo "Docker images:"
	@docker images | grep openclaw

# =============================================================================
# Testing Commands
# =============================================================================

test:
	@echo "Running health checks..."
	@$(DOCKER_COMPOSE) -f docker-compose.yml ps -q | xargs -I {} docker inspect -f '{{.Name}}: {{.State.Health.Status}}' {} || true
