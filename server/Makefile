# Powernode Platform Makefile
# Provides convenient commands for development and deployment

.PHONY: help setup dev prod test clean logs security
.DEFAULT_GOAL := help

# Colors for output
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
RESET := \033[0m

help: ## Show this help message
	@echo "$(GREEN)Powernode Platform Development Commands$(RESET)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-20s$(RESET) %s\n", $$1, $$2}'

# Development Commands
setup: ## Set up development environment
	@echo "$(YELLOW)Setting up development environment...$(RESET)"
	bundle install
	cd ../frontend && npm install
	bin/rails db:create db:migrate db:seed
	@echo "$(GREEN)✅ Development environment ready$(RESET)"

dev: ## Start development servers
	@echo "$(YELLOW)Starting development servers...$(RESET)"
	docker-compose -f docker-compose.dev.yml up --build

dev-bg: ## Start development servers in background
	@echo "$(YELLOW)Starting development servers in background...$(RESET)"
	docker-compose -f docker-compose.dev.yml up -d --build

dev-stop: ## Stop development servers
	@echo "$(YELLOW)Stopping development servers...$(RESET)"
	docker-compose -f docker-compose.dev.yml down

dev-api: ## Start only API server for development
	@echo "$(YELLOW)Starting Rails API server...$(RESET)"
	bin/rails server -b 0.0.0.0 -p 3000

dev-frontend: ## Start only frontend server for development
	@echo "$(YELLOW)Starting React frontend server...$(RESET)"
	cd ../frontend && npm start

# Production Commands
prod: ## Start production environment
	@echo "$(YELLOW)Starting production environment...$(RESET)"
	docker-compose up -d --build

prod-stop: ## Stop production environment
	@echo "$(YELLOW)Stopping production environment...$(RESET)"
	docker-compose down

prod-logs: ## View production logs
	docker-compose logs -f

# Database Commands
db-create: ## Create database
	bin/rails db:create

db-migrate: ## Run database migrations
	bin/rails db:migrate

db-seed: ## Seed database with initial data
	bin/rails db:seed

db-reset: ## Reset database (drop, create, migrate, seed)
	@echo "$(RED)⚠️  This will destroy all data!$(RESET)"
	@read -p "Continue? (y/N) " confirm && [ "$$confirm" = "y" ]
	bin/rails db:drop db:create db:migrate db:seed

db-console: ## Open database console
	bin/rails db:console

# Testing Commands
test: ## Run all tests
	@echo "$(YELLOW)Running test suite...$(RESET)"
	bundle exec rspec

test-models: ## Run model tests only
	bundle exec rspec spec/models

test-controllers: ## Run controller tests only
	bundle exec rspec spec/requests

test-security: ## Run security tests only
	bundle exec rspec spec/security

test-coverage: ## Run tests with coverage report
	COVERAGE=true bundle exec rspec

# Security Commands
security: ## Run security analysis
	@echo "$(YELLOW)Running security analysis...$(RESET)"
	bundle exec brakeman -q --no-progress
	bundle audit check --update

security-update: ## Update security gems
	bundle audit update

# Code Quality Commands
lint: ## Run linters
	@echo "$(YELLOW)Running linters...$(RESET)"
	bundle exec rubocop
	cd ../frontend && npm run lint

lint-fix: ## Auto-fix linting issues
	@echo "$(YELLOW)Auto-fixing linting issues...$(RESET)"
	bundle exec rubocop -a
	cd ../frontend && npm run lint:fix

# Utility Commands
logs: ## View application logs
	tail -f log/development.log

logs-test: ## View test logs
	tail -f log/test.log

console: ## Open Rails console
	bin/rails console

clean: ## Clean up temporary files and caches
	@echo "$(YELLOW)Cleaning up...$(RESET)"
	bin/rails tmp:clear
	bin/rails log:clear
	docker system prune -f
	cd ../frontend && rm -rf node_modules/.cache

install: ## Install dependencies
	bundle install
	cd ../frontend && npm install

update: ## Update dependencies
	bundle update
	cd ../frontend && npm update

# Health check
health: ## Check application health
	@echo "$(YELLOW)Checking application health...$(RESET)"
	@curl -s -o /dev/null -w "API Health: %{http_code}\n" http://localhost:3000/api/v1/health || echo "API: $(RED)Down$(RESET)"
	@curl -s -o /dev/null -w "Frontend: %{http_code}\n" http://localhost:3001 || echo "Frontend: $(RED)Down$(RESET)"

# Deployment commands
deploy-staging: ## Deploy to staging
	@echo "$(YELLOW)Deploying to staging...$(RESET)"
	# Add staging deployment commands here

deploy-prod: ## Deploy to production
	@echo "$(RED)⚠️  Production deployment!$(RESET)"
	@read -p "Continue? (y/N) " confirm && [ "$$confirm" = "y" ]
	# Add production deployment commands here