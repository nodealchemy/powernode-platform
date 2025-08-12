# CLAUDE.md

Development guidance for **Powernode** subscription platform.

## Git Commit Configuration

- **IMPORTANT**: Git commit messages should NOT include "Generated with [Claude Code]" or "Co-Authored-By: Claude" notes
- Use clean, conventional commit messages without Claude attribution

## Project Overview

**Powernode** - Subscription lifecycle management platform:
- **Backend**: Rails 8 API (`./server`)
- **Frontend**: React TypeScript (`./frontend`) 
- **Worker**: Sidekiq standalone service (`./worker`)
- **Database**: PostgreSQL
- **Payments**: Stripe, PayPal
- **Testing**: RSpec, Jest/Cypress

## Architecture

### Core Models
- **Account** → User (many), Subscription (one)
- **Subscription** → Plan, Payments, Invoices
- **User** → Roles, Permissions, Invitations
- Primary keys: UUIDv7
- Authentication: JWT tokens
- Audit logging: All changes tracked

### Frontend (React + TypeScript)
- Theme-aware components (light/dark)
- Tailwind CSS with consistent patterns
- API services with standardized patterns
- Responsive design (mobile-first)

### Worker Service (Sidekiq)
- API-only communication (no DB access)
- Background job processing
- Payment webhooks, billing automation
- Screen-based process management

## Process Management

**CRITICAL**: Always use management scripts, never start servers manually.

### Quick Commands
```bash
# Auto-detect project root
POWERNODE_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

# Essential commands
$POWERNODE_ROOT/scripts/auto-dev.sh ensure    # Start all services
$POWERNODE_ROOT/scripts/auto-dev.sh status    # Check health
```

### Service Management Scripts

#### Auto-Development (Preferred)
- `auto-dev.sh ensure` - Start all services if needed
- `auto-dev.sh status` - Health check all services
- `auto-dev.sh backend|worker|frontend` - Manage individual services

#### Individual Services
- **Backend**: `backend-manager.sh start|stop|status|logs`
- **Worker**: `worker-manager.sh start|stop|status|start-web|stop-web`
- **Frontend**: `frontend-manager.sh start|stop|status|logs`

#### Service Endpoints
- Backend: `http://localhost:3000`
- Worker Web: `http://localhost:4567/sidekiq`
- Frontend: `http://localhost:3001`

### Process Rules
- **NEVER** start servers manually (`rails server`, `npm start`, `bundle exec sidekiq`)
- **ALWAYS** use management scripts
- Services run in detached screen sessions
- Screen sessions: `powernode-backend`, `powernode-worker`, `powernode-frontend`

### Claude Automation
**Auto-start servers when:**
- User requests testing/development work
- User wants to view application
- User needs background jobs

**Startup sequence:**
1. Backend first
2. Worker second  
3. Frontend third
4. Health check all

## Development Commands

### Database
```bash
cd server
rails db:create db:migrate db:seed
```

### Testing
```bash
cd server && bundle exec rspec        # Backend tests
cd frontend && npm test              # Frontend tests
```

### Project Tracking
- Use TODO.md with status indicators: `[ ]` `[🔄]` `[✅]` `[❌]` `[⚠️]`

### Git Workflow

**Pre-Commit Cleanup (MANDATORY)**:
```bash
# Quick cleanup before commits
find . -name "*.tmp" -o -name ".DS_Store" -o -name "Thumbs.db" -o -name "*.swp" -o -name "*.swo" -o -name "*~" | xargs rm -f 2>/dev/null; cd frontend && rm -rf .next/ dist/ build/ coverage/ .nyc_output/ node_modules/.cache/ && cd ../server && rm -rf tmp/cache/ tmp/pids/ tmp/sessions/ tmp/sockets/ coverage/ && find log/ -name "*.log" -exec truncate -s 0 {} \; 2>/dev/null; cd ../worker && rm -rf tmp/ coverage/ && find log/ -name "*.log" -exec truncate -s 0 {} \; 2>/dev/null; cd .. && git status --porcelain
```

**Commit Pattern**:
1. Complete work
2. Run cleanup (above)
3. Test/lint
4. `git add . && git commit -m "message"`

## Versioning & Git Flow

### Versions
- **Current**: `0.0.1-dev` (develop branch)
- **Format**: `MAJOR.MINOR.PATCH[-alpha|-beta|-rc]`
- **Branching**: Git-Flow (main, develop, feature/*, release/*, hotfix/*)

### Commit Format (Conventional)
```
<type>(<scope>): <description>
```
**Types**: feat, fix, docs, style, refactor, test, chore, ci

**Examples**:
- `feat(auth): implement JWT authentication`
- `fix(billing): resolve renewal issue`

### Multi-Agent Development
**18 Specialized Agents**:
- **Platform**: architect (coordinator)
- **Backend**: rails_architect, data_modeler, payment_specialist, billing_engine, api_developer, background_jobs, analytics
- **Frontend**: react_architect, ui_components, dashboard, admin_panel  
- **QA**: backend_test, frontend_test
- **Ops**: devops, security, performance, notifications, docs

## Key Development Patterns

### Frontend Styling Standards

**CRITICAL: Theme-Aware Components**

**MANDATORY**: All components must use theme-aware styling.

#### Theme Requirements
1. **NEVER** use hardcoded colors (`bg-red-500`, `text-blue-600`)
2. **ALWAYS** use theme classes (`bg-theme-*`, `text-theme-*`)
3. **AUDIT** existing components for hardcoded styles
4. **TEST** in both light and dark themes

#### Forbidden vs Required Patterns
```typescript
// ❌ FORBIDDEN
'bg-red-50', 'text-green-600', 'bg-white', 'text-black'

// ✅ REQUIRED  
'bg-theme-error-background', 'text-theme-success'
'bg-theme-surface', 'text-theme-primary'
```

#### Theme Class Reference

**Status Colors**:
- Success: `text-theme-success`, `bg-theme-success-background`, `border-theme-success-border`
- Warning: `text-theme-warning`, `bg-theme-warning-background`, `border-theme-warning-border`  
- Error: `text-theme-error`, `bg-theme-error-background`, `border-theme-error-border`
- Info: `text-theme-info`, `bg-theme-info-background`, `border-theme-info-border`

**Base Colors**:
- Backgrounds: `bg-theme-background`, `bg-theme-surface`
- Text: `text-theme-primary`, `text-theme-secondary`, `text-theme-tertiary`
- Interactive: `bg-theme-interactive-primary`, `text-theme-link`
- Borders: `border-theme`, `border-theme-focus`

#### Theme Management
- **Logged out**: Light theme only
- **Logged in**: User can toggle light/dark
- **Responsive**: Use `px-4 sm:px-6 lg:px-8` patterns

#### Standards
- **Layout**: Headers use `h-16`, responsive padding `px-4 sm:px-6 lg:px-8`
- **Accessibility**: ARIA labels, keyboard navigation, WCAG AA contrast
- **Components**: Reusable with TypeScript interfaces
- **Animations**: Standard durations (`duration-150/200/300`), respect `prefers-reduced-motion`

#### Component Checklist
1. **Color Audit**: No hardcoded colors (`bg-red-`, `text-blue-`, etc.)
2. **Theme Testing**: Works in both light and dark themes
3. **Responsive**: Test mobile/tablet/desktop breakpoints
4. **Accessibility**: ARIA labels, keyboard nav, contrast ratios
5. **Integration**: Harmonizes with existing components

#### Theme Audit Commands
```bash
# Find hardcoded colors
grep -r "bg-red-\|bg-green-\|bg-blue-\|bg-white\|text-black" frontend/src/

# Verify theme usage
grep -r "bg-theme-\|text-theme-" frontend/src/
```

#### Example: Status Badge
```typescript
// ✅ CORRECT
const getStatusClasses = (status: string) => {
  switch (status) {
    case 'success': return 'bg-theme-success-background text-theme-success';
    case 'error': return 'bg-theme-error-background text-theme-error';
    default: return 'bg-theme-surface text-theme-secondary';
  }
};

// ❌ WRONG
return 'bg-green-100 text-green-700';  // Hardcoded colors
```

### API Service Pattern (MANDATORY)

**Standardized pattern for all API services:**

```typescript
import { api } from './api';

export interface ServiceItem {
  id: string;
  name: string;
}

export const serviceNameApi = {
  async getItems(page = 1, perPage = 20): Promise<ServiceItem[]> {
    const response = await api.get(`/items?page=${page}&per_page=${perPage}`);
    return response.data;
  },

  async getItem(id: string): Promise<ServiceItem> {
    const response = await api.get(`/items/${id}`);
    return response.data;
  },

  async createItem(data: Partial<ServiceItem>): Promise<ServiceItem> {
    const response = await api.post('/items', data);
    return response.data;
  },

  async updateItem(id: string, data: Partial<ServiceItem>): Promise<ServiceItem> {
    const response = await api.put(`/items/${id}`, data);
    return response.data;
  },

  async deleteItem(id: string): Promise<void> {
    await api.delete(`/items/${id}`);
  }
};
```

**Requirements:**
- Import: `import { api } from './api'`
- Export: `export const serviceNameApi = { ... }`
- Direct API calls: `api.get()`, `api.post()`, etc.
- Return: `response.data`
- TypeScript: Proper interfaces and return types

### Security Requirements
- **JWT Authentication**: 15min access tokens, 7-day refresh tokens, HMAC-SHA256
- **Email Verification**: Required before login, time-limited tokens
- **Password Security**: 12+ chars, complexity rules, history tracking, account lockout
- **PCI Compliance**: Secure payment data handling
- **Rate Limiting**: All endpoints protected

### Business Logic
- **Subscriptions**: State machines, proration calculations, audit trails
- **Payments**: Gateway integrations, retry logic, webhook handling
- **Money Gem**: USD default, proper rounding, i18n formatting

### Worker Service Architecture

**CRITICAL**: All background jobs in standalone worker service (`./worker`)

#### Job Creation Rules
- **Jobs Location**: `./worker/app/jobs/` (NOT in Rails backend)
- **Communication**: API-only, no direct database access
- **Backend Role**: Simple operations, enqueue jobs only
- **Worker Role**: Complex operations (billing, emails, reports, analytics)

#### Service Delegation
- **Backend**: Simple calculations, validations, formatting
- **Worker**: Complex operations (>100ms), external APIs, file generation
- **MUST use worker**: Email, payments, reports, analytics

#### Worker Job Pattern
```ruby
class SomeJob < BaseJob
  sidekiq_options queue: 'default', retry: 3

  def execute(args)
    # Use API client, not ActiveRecord
    data = api_client.get("/api/v1/resource/#{args['id']}")
    # Process...
  end
end
```

**Requirements**:
- Inherit from `BaseJob` (not `ApplicationJob`)
- Use `execute` method (not `perform`)
- Use `api_client` for data access
- No Rails dependencies (`Rails.cache`, `Rails.logger`, etc.)

#### Worker Management
- **Start**: `worker-manager.sh start` (creates screen session)
- **Web Interface**: `worker-manager.sh start-web`
- **Monitoring**: `http://localhost:4567/sidekiq`
- **Authentication**: Service-to-service JWT tokens
- **Scaling**: Independent from Rails backend

### Testing Strategy
- **Backend**: RSpec with FactoryBot, shoulda-matchers, VCR for payments
- **Frontend**: Jest, Testing Library, Cypress for E2E
- **Models**: Money gem integration, association testing, security flows
- **Status**: 203+ tests passing across key models

## Project Status

**Phase 1 - Backend Foundation**: ✅ COMPLETED
- Rails 8 API with core models (Account, User, Subscription, Plan, etc.)
- JWT authentication, UUIDv7 primary keys
- Money gem configuration, state machines
- 203+ tests passing, FactoryBot validated
- Worker service architecture implemented

**Current Phase**: Payment Integration - Stripe/PayPal, billing logic, webhooks

**Development Phases**:
1. Backend Foundation ✅
2. Payment Integration 🔄
3. Analytics & Reporting
4. Frontend Development  
5. Quality Assurance
6. DevOps & Production

**Focus**: Security-first, PCI compliance, scalable subscription platform

---

**Always update TODO.md when tasks are completed.**

