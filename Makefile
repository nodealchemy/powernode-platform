# Powernode Platform Development Makefile

.PHONY: help setup install test clean build deploy

# Default target
help:
	@echo "Powernode Platform Development Commands"
	@echo "======================================"
	@echo ""
	@echo "Setup Commands:"
	@echo "  make setup          - Full project setup (install dependencies)"
	@echo "  make install        - Install dependencies only"
	@echo "  make db-setup       - Setup databases"
	@echo ""
	@echo "Development Commands (All servers listen on 0.0.0.0 for external access):"
	@echo "  make dev            - Start all services via systemd"
	@echo "  make dev-api        - Start Rails API server only (0.0.0.0:3000)"
	@echo "  make dev-frontend   - Start React frontend server only (0.0.0.0:3001)"
	@echo "  make dev-stop       - Stop all services"
	@echo "  make dev-restart    - Restart all services"
	@echo "  make dev-status     - Show service status"
	@echo ""
	@echo "Testing Commands:"
	@echo "  make test           - Run all tests"
	@echo "  make test-backend   - Run backend tests"
	@echo "  make test-frontend  - Run frontend tests"
	@echo "  make test-e2e       - Run end-to-end tests"
	@echo "  make test-security  - Run security tests"
	@echo ""
	@echo "Quality Commands:"
	@echo "  make lint           - Run all linters"
	@echo "  make lint-backend   - Run backend linters"
	@echo "  make lint-frontend  - Run frontend linters"
	@echo "  make security       - Run security scans"
	@echo ""
	@echo "Build Commands:"
	@echo "  make build          - Build both applications"
	@echo "  make build-backend  - Build backend application"
	@echo "  make build-frontend - Build frontend application"
	@echo ""
	@echo "Utility Commands:"
	@echo "  make clean          - Clean build artifacts"
	@echo "  make logs           - Show development logs"
	@echo "  make db-reset       - Reset development database"

# Setup commands
setup: install db-setup
	@echo "✅ Full setup complete!"

install:
	@echo "📦 Installing dependencies..."
	@cd server && bundle install
	@cd frontend && npm install
	@echo "✅ Dependencies installed!"

db-setup:
	@echo "🗄️  Setting up databases..."
	@cd server && bundle exec rails db:create db:migrate db:seed
	@echo "✅ Database setup complete!"

db-reset:
	@echo "🗄️  Resetting development database..."
	@cd server && bundle exec rails db:drop db:create db:migrate db:seed
	@echo "✅ Database reset complete!"

# Development commands (systemd)
dev:
	@echo "🚀 Starting development servers..."
	@sudo systemctl start powernode.target

dev-api:
	@echo "🔧 Starting Rails API server..."
	@sudo systemctl start powernode-backend@default

dev-frontend:
	@echo "⚛️  Starting React frontend server..."
	@sudo systemctl start powernode-frontend@default

dev-stop:
	@echo "🛑 Stopping development servers..."
	@sudo systemctl stop powernode.target

dev-restart:
	@echo "🔄 Restarting development servers..."
	@sudo systemctl restart powernode.target

dev-status:
	@echo "📊 Development server status..."
	@sudo scripts/systemd/powernode-installer.sh status

# Testing commands
test: test-backend test-frontend
	@echo "✅ All tests completed!"

test-backend:
	@echo "🧪 Running backend tests..."
	@cd server && bundle exec rspec --format progress

test-frontend:
	@echo "🧪 Running frontend tests..."
	@cd frontend && npm test -- --coverage --watchAll=false

test-e2e:
	@echo "🧪 Running end-to-end tests..."
	@cd frontend && npm run cypress:run

test-security:
	@echo "🔒 Running security tests..."
	@cd server && bundle exec rails test:security
	@cd frontend && npm run lint:security

# Quality commands
lint: lint-backend lint-frontend
	@echo "✅ All linting completed!"

lint-backend:
	@echo "🔍 Running backend linters..."
	@cd server && bundle exec rubocop

lint-frontend:
	@echo "🔍 Running frontend linters..."
	@cd frontend && npm run lint

security:
	@echo "🔒 Running security scans..."
	@cd server && bundle exec bundle-audit check --update || true
	@cd server && bundle exec brakeman -q || true
	@cd frontend && npm audit --audit-level moderate || true

# Build commands
build: build-backend build-frontend
	@echo "✅ Build completed!"

build-backend:
	@echo "🏗️  Building backend application..."
	@cd server && bundle install --deployment --without development test
	@cd server && bundle exec rails assets:precompile RAILS_ENV=production

build-frontend:
	@echo "🏗️  Building frontend application..."
	@cd frontend && npm run build

# Utility commands
clean:
	@echo "🧹 Cleaning build artifacts..."
	@rm -rf server/public/assets/
	@rm -rf server/tmp/cache/
	@rm -rf frontend/build/
	@rm -rf frontend/node_modules/.cache/
	@echo "✅ Clean completed!"

logs:
	@echo "📜 Development logs:"
	@echo "Backend logs:"
	@tail -n 50 server/log/development.log || echo "No backend logs found"
	@echo ""
	@echo "Frontend logs available in terminal output"

# CI/CD helper commands
ci-setup:
	@echo "🔧 CI/CD Setup..."
	@make install
	@make db-setup

ci-test:
	@echo "🧪 CI/CD Testing..."
	@make test
	@make test-security
	@make lint
	@make security

ci-build:
	@echo "🏗️  CI/CD Build..."
	@make build

ci-deploy-staging:
	@echo "🚀 Deploying to staging..."
	@echo "Database migrations..."
	@cd server && bundle exec rails db:migrate RAILS_ENV=staging
	@echo "Deployment would happen here..."

ci-deploy-production:
	@echo "🚀 Deploying to production..."
	@echo "Database migrations..."
	@cd server && bundle exec rails db:migrate RAILS_ENV=production
	@echo "Deployment would happen here..."