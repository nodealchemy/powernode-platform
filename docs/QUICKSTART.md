# Powernode Platform - Developer Quick Start Guide

Get the Powernode platform running locally in under 10 minutes.

## Prerequisites

| Requirement | Version | Verify Command |
|-------------|---------|----------------|
| Node.js | 20+ | `node --version` |
| Ruby | 3.3+ | `ruby --version` |
| PostgreSQL | 16+ | `psql --version` |
| Redis | 7+ | `redis-server --version` |
| Docker | 24+ | `docker --version` |

## Quick Setup

### 1. Clone and Install Dependencies

```bash
# Clone the repository
git clone https://github.com/your-org/powernode-platform.git
cd powernode-platform

# Install dependencies
cd server && bundle install
cd ../frontend && npm install
cd ../worker && bundle install
cd ..

# Setup database
cd server && bundle exec rails db:create db:migrate db:seed
```

### 2. Install and Start All Services

```bash
# Install systemd services (one-time)
sudo scripts/systemd/powernode-installer.sh install

# Start everything
sudo systemctl start powernode.target

# Check status
sudo scripts/systemd/powernode-installer.sh status
```

### 3. Access the Application

| Service | URL |
|---------|-----|
| Frontend | http://localhost:5173 |
| Backend API | http://localhost:3000 |
| API Health | http://localhost:3000/api/v1/health |

### 4. Default Credentials

Create a test user:
```bash
cd server && bundle exec rails c
User.create!(email: 'dev@example.com', password: 'DevPassword123!', name: 'Developer')
```

## Running Tests

```bash
# Backend tests
cd server && pkill -f rspec 2>/dev/null; bundle exec rspec --format progress

# Frontend tests
cd frontend && CI=true npm test

# E2E tests (Playwright)
cd frontend && npx playwright test

# Type checking
cd frontend && npx tsc --noEmit
```

## Key Files to Know

### Backend (`/server`)

| File | Purpose |
|------|---------|
| `config/routes.rb` | API route definitions |
| `app/controllers/api/v1/` | API controllers |
| `app/models/` | ActiveRecord models |
| `app/services/` | Business logic services |
| `spec/` | RSpec test files |

### Frontend (`/frontend`)

| File | Purpose |
|------|---------|
| `src/App.tsx` | Main application entry |
| `src/pages/app/` | Application pages |
| `src/features/` | Feature modules |
| `src/shared/` | Shared components and utilities |
| `tailwind.config.js` | Tailwind CSS configuration |

### Worker (`/worker`)

| File | Purpose |
|------|---------|
| `app/jobs/` | Background job classes |
| `config/sidekiq.yml` | Sidekiq configuration |

## Common Development Tasks

### Add a New API Endpoint

1. Add route in `server/config/routes.rb`
2. Create controller in `server/app/controllers/api/v1/`
3. Use standard response helpers:
   ```ruby
   render_success(data: { ... })
   render_error(message: 'Error', status: :bad_request)
   ```
4. Add tests in `server/spec/requests/`

### Add a New Frontend Page

1. Create page in `frontend/src/pages/app/`
2. Add route in `frontend/src/App.tsx`
3. Use PageContainer for consistent layout:
   ```tsx
   <PageContainer title="Page Title" breadcrumbs={[...]}>
     {/* Page content */}
   </PageContainer>
   ```

### Add a Background Job

1. Create job in `worker/app/jobs/`
2. Inherit from `BaseJob` and implement `execute`:
   ```ruby
   class MyJob < BaseJob
     sidekiq_options queue: 'default'
     def execute(param)
       # Job logic
     end
   end
   ```
3. Queue from backend via API call

## Code Quality

Run before committing:

```bash
# Full quality check
./scripts/pre-commit-quality-check.sh

# Individual checks
./scripts/quick-pattern-check.sh      # Fast pattern validation
./scripts/fix-hardcoded-colors.sh     # Fix theme violations
./scripts/cleanup-all-console-logs.sh # Remove console.log
```

## Architecture Overview

```
powernode-platform/
├── server/          # Rails 8 API backend
│   ├── app/
│   │   ├── controllers/api/v1/  # API endpoints
│   │   ├── models/              # ActiveRecord models
│   │   └── services/            # Business logic
│   └── spec/                    # RSpec tests
│
├── frontend/        # React TypeScript frontend
│   ├── src/
│   │   ├── features/    # Feature modules
│   │   ├── pages/       # Page components
│   │   └── shared/      # Shared utilities
│   └── e2e/             # E2E tests (Playwright)
│
├── worker/          # Sidekiq background jobs
│   └── app/jobs/        # Job classes
│
├── docs/            # Documentation
├── scripts/         # Development scripts
└── docker/          # Docker configurations
```

## Troubleshooting

### Services Won't Start

```bash
# Check logs for errors
journalctl -u powernode-backend@default --since "5 min ago" --no-pager

# Reset failed state and restart
sudo systemctl reset-failed 'powernode-*'
sudo systemctl start powernode.target
```

### Database Issues

```bash
cd server
bundle exec rails db:reset   # WARNING: Drops and recreates DB
bundle exec rails db:migrate
```

### Frontend Build Errors

```bash
cd frontend
rm -rf node_modules
npm install
npm run typecheck
```

### Redis Connection Issues

```bash
# Check Redis is running
redis-cli ping
# Should return: PONG
```

## Getting Help

- **Internal docs**: See `/docs/` directory
- **Specialist guides**: See `/docs/backend/`, `/docs/frontend/`
- **Architecture decisions**: See `/docs/platform/`

## Next Steps

- Review [DEVELOPMENT.md](DEVELOPMENT.md) for detailed development guidelines
- Check [PERMISSION_SYSTEM_REFERENCE.md](platform/PERMISSION_SYSTEM_REFERENCE.md) for access control
- Read [THEME_SYSTEM_REFERENCE.md](platform/THEME_SYSTEM_REFERENCE.md) for styling guidelines
