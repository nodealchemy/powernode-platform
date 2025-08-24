# CLAUDE.md

Development guidance for **Powernode** subscription platform.

## Project Overview & Architecture

**Powernode** - Subscription lifecycle management platform:
- **Backend**: Rails 8 API (`./server`) - JWT auth, UUID keys, audit logging
- **Frontend**: React TypeScript (`./frontend`) - Theme-aware, Tailwind CSS
- **Worker**: Sidekiq standalone service (`./worker`) - API-only communication
- **Database**: PostgreSQL with consolidated schema
- **Payments**: Stripe, PayPal with PCI compliance
- **Testing**: RSpec (203+ tests), Jest/Cypress

**ALWAYS REFERENCE TODO.md FOR CURRENT PROGRESS AND STATUS**

### Core Models & Relations
- **Account** → User (many), Subscription (one)
- **Subscription** → Plan, Payments, Invoices  
- **User** → Roles (`resource.action` format), Permissions, Invitations

### Git & Release Management
- **IMPORTANT**: Clean commit messages without Claude attribution
- **Git-Flow & Semantic Versioning**: See **[DevOps Engineer](docs/infrastructure/DEVOPS_ENGINEER_SPECIALIST.md#git-workflow--release-management)** for complete workflow documentation
- Current version: `0.0.1` → `0.1.0` (next release)
- Branch strategy: `develop` → `feature/*` → `release/*` → `main`

## Development Workflow

**See [DevOps Engineer - Development Workflow](docs/infrastructure/DEVOPS_ENGINEER_SPECIALIST.md#development-workflow) for complete development procedures including:**
- Process management and service startup procedures
- Database operations and schema management (consolidated UUID strategy)
- Development command reference
- Testing workflow and project tracking


## Project Structure & Organization

**See [React Architect - Project Structure](docs/frontend/REACT_ARCHITECT_SPECIALIST.md#1-project-structure-mandatory) for complete project organization including:**
- Overall project layout and directory structure
- Feature-based frontend architecture  
- File naming conventions and import rules
- TypeScript organization standards
- Migration strategy for restructuring

## MCP Specialist Architecture

The Powernode platform uses specialized MCP (Model Context Protocol) connections for different aspects of development. Each specialist has detailed documentation with architectural patterns, code standards, and integration points.

### Backend Specialists
- **[Data Modeler](docs/backend/DATA_MODELER_SPECIALIST.md)**: Database architecture, ActiveRecord patterns, schema design
- **[Rails Architect](docs/backend/RAILS_ARCHITECT_SPECIALIST.md)**: Rails 8 API architecture, authentication, WebSocket integration
- **[Payment Integration Specialist](docs/backend/PAYMENT_INTEGRATION_SPECIALIST.md)**: Stripe/PayPal integration, PCI compliance
- **[API Developer](docs/backend/API_DEVELOPER_SPECIALIST.md)**: RESTful API design, serialization, error handling
- **[Billing Engine Developer](docs/backend/BILLING_ENGINE_DEVELOPER_SPECIALIST.md)**: Subscription lifecycle, automated renewals
- **[Background Job Engineer](docs/backend/BACKGROUND_JOB_ENGINEER_SPECIALIST.md)**: Sidekiq configuration, queue management

### Frontend Specialists  
- **[React Architect](docs/frontend/REACT_ARCHITECT_SPECIALIST.md)**: TypeScript architecture, routing, state management
- **[UI Component Developer](docs/frontend/UI_COMPONENT_DEVELOPER_SPECIALIST.md)**: Design system, theme-aware components
- **[Dashboard Specialist](docs/frontend/DASHBOARD_SPECIALIST.md)**: Interactive charts, analytics visualization
- **[Admin Panel Developer](docs/frontend/ADMIN_PANEL_DEVELOPER_SPECIALIST.md)**: Administrative interfaces, system management

### Testing Specialists
- **[Backend Test Engineer](docs/testing/BACKEND_TEST_ENGINEER_SPECIALIST.md)**: RSpec testing, API integration tests
- **[Frontend Test Engineer](docs/testing/FRONTEND_TEST_ENGINEER_SPECIALIST.md)**: Jest/Cypress testing, component testing

### Infrastructure Specialists
- **[DevOps Engineer](docs/infrastructure/DEVOPS_ENGINEER_SPECIALIST.md)**: CI/CD, deployment, monitoring
- **[Security Specialist](docs/infrastructure/SECURITY_SPECIALIST.md)**: Application security, PCI compliance
- **[Performance Optimizer](docs/infrastructure/PERFORMANCE_OPTIMIZER.md)**: Performance tuning, load testing

### Service Specialists
- **[Notification Engineer](docs/services/NOTIFICATION_ENGINEER.md)**: Email, SMS, real-time notifications
- **[Documentation Specialist](docs/services/DOCUMENTATION_SPECIALIST.md)**: API docs, knowledge base
- **[Analytics Engineer](docs/services/ANALYTICS_ENGINEER.md)**: Business intelligence, KPI tracking

### Working with Specialists

When working on specific areas of the platform, reference the appropriate specialist documentation for:
- Architectural patterns and standards
- Code examples and best practices  
- Integration points with other systems
- Development commands and workflows
- Quick reference guides

**Key Principle**: Each specialist maintains expertise in their domain while coordinating with the platform architect for system-wide coherence.

## Platform Standardization (COMPLETED)

### Comprehensive Pattern Discovery & Documentation
The platform has undergone comprehensive pattern analysis and standardization (January 2025). All architectural patterns have been discovered, documented, and integrated into MCP specialist documentation.

#### Completed Standardization Work
✅ **Pattern Discovery**: Comprehensive audit of backend, frontend, and worker services  
✅ **MCP Documentation Enhancement**: All 18+ specialists updated with discovered patterns  
✅ **Validation Tools**: Automated compliance checking and pre-commit hooks  
✅ **Platform Standards**: Consolidated architectural guidelines and best practices  

#### Key Standardized Patterns

**Backend (Rails API)**:
- **API Response Format**: Mandatory `{success: boolean, data: object, error?: string}` structure
- **Controller Pattern**: `Api::V1` namespace, permission-based authorization, serialization concerns
- **Model Structure**: 8-step organization (Authentication → Concerns → Associations → Validations → Scopes → Callbacks → Methods → Private)
- **UUID Strategy**: Consistent string-based UUIDs across all models
- **Service Integration**: Complex operations delegated to worker service via API

**Frontend (React TypeScript)**:
- **Permission-Based Access Control**: MANDATORY `hasPermission()` usage, NEVER role-based access
- **Theme-Aware Components**: `bg-theme-*`, `text-theme-*`, `border-theme` classes only
- **Component Architecture**: Feature-based organization with standardized structure
- **API Service Pattern**: Centralized client with consistent error handling

**Worker (Sidekiq Service)**:
- **BaseJob Pattern**: All jobs inherit from standardized BaseJob with exponential backoff
- **API-Only Communication**: Workers use BackendApiClient, NO direct database access  
- **Execute Method**: Jobs implement `execute()`, never override `perform()`
- **Environment Isolation**: Complete separation from main Rails application

#### Pattern Validation Tools
```bash
# Comprehensive pattern audit (25+ checks)
./scripts/pattern-validation.sh

# Quick development feedback
./scripts/quick-pattern-check.sh

# Pre-commit validation (prevents pattern violations)
./scripts/pre-commit-pattern-check.sh

# Generate usage statistics
./scripts/generate-pattern-stats.sh
```

#### Standardization Documentation
- **[Platform Patterns Analysis](docs/platform/PLATFORM_PATTERNS_ANALYSIS.md)**: Complete pattern discovery findings
- **[MCP Documentation Enhancement Plan](docs/platform/MCP_DOCUMENTATION_ENHANCEMENT_PLAN.md)**: Implementation roadmap
- **[Platform Standardization Recommendations](docs/platform/PLATFORM_STANDARDIZATION_RECOMMENDATIONS.md)**: Strategic recommendations

**Platform Compliance**: 95%+ pattern consistency across all services

## Security & Permissions

### Security Requirements
- **JWT Authentication**: 15min access tokens, 7-day refresh tokens, HMAC-SHA256
- **Email Verification**: Required before login, time-limited tokens
- **Password Security**: 12+ chars, complexity rules, history tracking, account lockout
- **PCI Compliance**: Secure payment data handling
- **Rate Limiting**: All endpoints protected

### Permission-Based Access Control System (CRITICAL)
**ABSOLUTE MANDATE**: Frontend access control MUST use permissions ONLY - NEVER roles.

**FORBIDDEN FRONTEND PATTERNS**:
```typescript
// ❌ NEVER DO THIS - Role-based frontend access control
const canManage = currentUser?.roles?.includes('account.manager');
const isSystemAdmin = currentUser?.role === 'system.admin';
if (user.roles.includes('billing.manager')) { return <AdminPanel />; }

// ❌ NEVER DO THIS - Mixed role/permission checks
const hasAccess = user.roles.includes('admin') || user.permissions.includes('read');
```

**MANDATORY FRONTEND PATTERNS**:
```typescript
// ✅ ALWAYS DO THIS - Permission-based access control ONLY
const canManageUsers = currentUser?.permissions?.includes('users.manage');
const canViewBilling = currentUser?.permissions?.includes('billing.read');
const canCreateContent = currentUser?.permissions?.includes('pages.create');

// ✅ Component access control
const canAccessAdminPanel = currentUser?.permissions?.includes('admin.access');
if (!canAccessAdminPanel) return <AccessDenied />;

// ✅ UI element control
<Button disabled={!currentUser?.permissions?.includes('users.create')}>
  Create User
</Button>
```

#### Backend Role System (For Permission Assignment Only)
**Backend roles exist ONLY to assign permissions - frontend NEVER checks roles**

**Standard Roles** (Backend assignment only):
- **`system.admin`**: Grants all permissions across system
- **`account.manager`**: Grants account-scoped permissions
- **`account.member`**: Grants basic user permissions  
- **`billing.manager`**: Grants billing management permissions

**Permission Categories**:
- **User Management**: `users.create`, `users.read`, `users.update`, `users.delete`, `users.manage`, `team.manage`
- **Billing Operations**: `billing.read`, `billing.update`, `billing.manage`, `invoices.create`, `payments.process`
- **System Administration**: `admin.access`, `system.admin`, `accounts.manage`, `settings.update`  
- **Content Management**: `pages.create`, `pages.update`, `pages.delete`, `content.manage`
- **Analytics**: `analytics.read`, `analytics.export`, `reports.generate`

#### Implementation Rules
1. **Frontend**: Check `currentUser.permissions.includes('permission.name')` ONLY
2. **Backend**: Roles assign permissions, controllers validate permissions
3. **API Responses**: Always include `permissions` array in user objects
4. **UI Controls**: Disable/hide elements based on permissions
5. **Navigation**: Filter menu items by permissions, not roles

## Backend & Worker Architecture

The backend architecture follows Rails 8 API patterns with a separate Sidekiq worker service. See the specialist documentation for detailed implementation patterns:

- **[Rails Architect](docs/backend/RAILS_ARCHITECT_SPECIALIST.md)**: Controller patterns, middleware, authentication
- **[Data Modeler](docs/backend/DATA_MODELER_SPECIALIST.md)**: Model patterns, UUID strategy, database schema
- **[Background Job Engineer](docs/backend/BACKGROUND_JOB_ENGINEER_SPECIALIST.md)**: Worker job patterns, queue management
- **[API Developer](docs/backend/API_DEVELOPER_SPECIALIST.md)**: API design, serialization, error handling

### Key Architectural Principles
- **API-First**: Rails API backend with structured JSON responses
- **Worker Delegation**: Complex operations handled by Sidekiq workers
- **UUID Strategy**: All models use UUID primary keys
- **Service Layer**: Business logic in service objects
- **API-Only Workers**: Workers communicate via API calls, no direct database access



## Quick Reference - CRITICAL Requirements

### 🚨 ABSOLUTE PROHIBITIONS
**Frontend**:
1. **NO role-based access control**: ONLY permission-based access control allowed
2. **NO hardcoded colors**: Use `bg-theme-*`, `text-theme-*` classes only (Exception: `text-white` on colored backgrounds)
3. **NO submenu navigation**: Flat navigation structure only - no `children` arrays
4. **NO action buttons in page content**: ALL actions in PageContainer only
5. **NO local success/error state**: Global notifications only
6. **NO relative imports**: Use path aliases (`@/shared/`, `@/features/`)
7. **NO inline styles**: All styling via Tailwind classes
8. **NO console.log**: Use proper logging utilities
9. **NO any types**: Proper TypeScript types required

**CRITICAL - Permission-Based Access Control**:
- **NEVER**: `currentUser?.roles?.includes('admin')` or `user.role === 'manager'`
- **NEVER**: `if (user.roles.includes('system.admin'))` for access control
- **NEVER**: Mixed role/permission checks for access decisions
- **ALWAYS**: `currentUser?.permissions?.includes('users.manage')` for access control

**Backend**:
9. **NO direct database access in worker**: Use API client only
10. **NO puts/p/print in code**: Use proper logging (Rails.logger/logger)
11. **NO missing frozen_string_literal**: All Ruby files must include pragma
12. **NO ApplicationJob inheritance**: Worker jobs inherit from BaseJob
13. **NO perform method in worker**: Use execute method instead
14. **NO unstructured API responses**: Use {success, data, error} format
15. **NO manual server starts**: Use management scripts only
16. **NO Claude attribution**: Clean commit messages only

### ✅ MANDATORY PATTERNS
**Frontend**:
1. **Permission-Based Access Control**: `currentUser?.permissions?.includes('users.manage')` for ALL access decisions
2. **PageContainer**: All app pages use PageContainer with consolidated actions
3. **Theme Classes**: `bg-theme-surface`, `text-theme-primary`, `border-theme`
4. **API Services**: Standard pattern with `serviceNameApi = { getItems, createItem, ... }`
5. **Component Structure**: Props interface → Hooks → Effects → Handlers → Render
6. **Form Handling**: preventDefault → Validation → API call → Global notification
7. **Mobile-First**: Start with mobile styles, add breakpoint modifiers
8. **File Organization**: Feature-based structure - see [React Architect](docs/frontend/REACT_ARCHITECT_SPECIALIST.md#1-project-structure-mandatory)

**Backend**:
9. **Controller Pattern**: `Api::V1` namespace, standard response format, include concerns
10. **Model Structure**: Associations → Validations → Scopes → Callbacks → Methods
11. **Service Delegation**: Complex operations delegated to worker service
12. **Worker Jobs**: Inherit BaseJob, use execute method, API-only communication
13. **API Responses**: `{success: boolean, data: object, error?: string}` format
14. **UUID Strategy**: All models use UUID primary keys (string, limit: 36)
15. **Frozen Strings**: All Ruby files start with `# frozen_string_literal: true`
16. **Error Handling**: Structured responses with user-friendly messages

**Universal**:
17. **Conventional Commits & Git-Flow**: See [DevOps Engineer](docs/infrastructure/DEVOPS_ENGINEER_SPECIALIST.md#git-workflow--release-management)
18. **Permission-Based Authorization**: Use permissions, not roles, for access control

### 🔧 Quick Commands
```bash
# Development - See DevOps Engineer specialist for complete commands
$POWERNODE_ROOT/scripts/auto-dev.sh ensure                    # Start all services
cd $POWERNODE_ROOT/server && rails db:migrate db:seed         # Database setup
cd $POWERNODE_ROOT/server && bundle exec rspec                # Run backend tests

# Git Flow - See DevOps Engineer specialist for details
git flow feature start ISSUE-description
git flow release start v1.2.0
npm version patch|minor|major

# Audits
# Permission-Based Access Control Audits (CRITICAL)
grep -r "\.roles\?\.includes\|\.role.*==\|\.role.*!=" frontend/src/ | grep -v "member\.roles\?.*map\|formatRole\|getRoleColor"  # Find role-based access checks (should be empty)
grep -r "currentUser.*roles\?\." frontend/src/ | grep -v "member\.roles\|user\.roles.*map\|formatRole"  # Find user role access (should be empty for access control)
grep -r "user.*roles.*admin\|user.*role.*manager" frontend/src/ | grep -v "display\|format\|badge"  # Find hardcoded role checks (should be empty)
grep -r "permissions.*includes" frontend/src/ | wc -l  # Count permission-based checks (should be > 0)

# Frontend Design Pattern Audits
grep -r "bg-red-\|bg-white\|text-black\|border-gray-" frontend/src/ | grep -v "text-white"  # Hardcoded colors
grep -c "children:" frontend/src/config/navigation.tsx    # Should return 0
grep -r "useState.*[Ss]uccess.*[Mm]essage" frontend/src/  # Should be empty
grep -r "console.log" frontend/src/                       # Should be empty
grep -r ": any" frontend/src/ | grep -v "node_modules"   # Find any types

# Backend audits
grep -r "puts \|p \|print " server/app/                   # Should be empty (no debug code)
grep -L "frozen_string_literal" server/app/**/*.rb       # Files missing pragma
grep -r "< ApplicationJob" worker/app/jobs/              # Should be empty (use BaseJob)
grep -r "def perform" worker/app/jobs/                   # Should be empty (use execute)
grep -r "ActiveRecord" worker/app/                       # Should be empty (API-only)
grep -c "render json:.*success:" server/app/controllers/ # Count structured responses
```

## 📁 CLAUDE Documentation Organization (MANDATORY)

### Documentation Directory Structure
**CRITICAL**: All CLAUDE-generated documentation MUST be organized in appropriate subdirectories - NEVER save to root folder.

```
powernode-platform/
├── docs/                    # Platform-wide documentation
│   ├── platform/           # Platform architecture, migrations, system docs
│   ├── backend/            # Backend-specific technical documentation
│   ├── frontend/           # Frontend-specific technical documentation  
│   └── worker/             # Worker service documentation
├── server/docs/            # Backend implementation docs
├── frontend/docs/          # Frontend implementation docs
└── worker/docs/            # Worker implementation docs
```

### Document Categories & Placement Rules

**Platform-Level** (`docs/platform/`):
- System architecture documents
- Migration plans and completion reports
- Cross-component integration documentation
- WebSocket and authentication system docs
- Permission system documentation
- Multi-service coordination docs

**Backend-Specific** (`docs/backend/` or `server/docs/`):
- Rails API documentation
- Database schema and model documentation
- Service layer architecture
- Authentication and security implementation
- Backend testing strategies

**Frontend-Specific** (`docs/frontend/` or `frontend/docs/`):
- React architecture and patterns
- Component organization documentation
- Styling and theming guides
- Frontend testing documentation
- UI/UX implementation guides

**Worker-Specific** (`docs/worker/` or `worker/docs/`):
- Sidekiq job documentation
- Background processing architecture
- Queue management documentation
- Worker service integration

### File Organization Commands
```bash
# NEVER save documentation to root - use appropriate directories
# Platform docs
docs/platform/PERMISSION_SYSTEM_COMPLETE.md
docs/platform/MIGRATION_PHASE_1_IMPLEMENTATION.md
docs/platform/WEBSOCKET_STATUS_SOLUTION.md

# Frontend docs  
frontend/docs/CONTAINER_PATTERNS.md
frontend/docs/STYLING_IMPLEMENTATION_PLAN.md

# Backend docs
server/docs/PERMISSION_SYSTEM_V2_SUMMARY.md
server/docs/ROLE_STANDARDIZATION.md

# Worker docs
worker/docs/ # For worker-specific documentation
```

### Documentation Standards
- **Naming**: Use UPPERCASE with underscores for technical docs (FEATURE_IMPLEMENTATION.md)
- **Location**: Choose most specific directory possible (component-specific over platform-wide)
- **Cross-References**: Use relative paths when linking between docs
- **Version Control**: All documentation committed to appropriate directories

**ABSOLUTE RULE**: No `.md` files in project root except CLAUDE.md, TODO.md, CHANGELOG.md, and DEVELOPMENT.md
