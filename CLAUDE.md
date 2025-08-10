# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is **Powernode** built with:
- **Backend**: Ruby on Rails 8 API-only application (located in `./server` directory)
- **Frontend**: ReactJS with TypeScript (located in `./frontend` directory)
- **Database**: PostgreSQL
- **Payments**: Stripe (primary), PayPal (secondary)
- **Background Jobs**: Sidekiq (standalone worker agent with API-only connectivity)
- **Testing**: RSpec (backend), Jest/Testing Library/Cypress (frontend)

The platform handles subscription lifecycle management, automated billing, payment processing, proration calculations, dunning management, and comprehensive analytics.

## Architecture Overview

### Backend Structure (Rails 8 API)
- **Models**: Account, User, Role, Permission, Invitation, AccountDelegation, Subscription, Plan, Invoice, Payment, AuditLog with complex associations
  - Users are associated with an Account (accounts may have multiple users)
  - **Account-Subscription Relationship**: Each Account `has_one :subscription` (one-to-one relationship)
    - Enforced at application level with validation: `validates :account, uniqueness: { message: "can only have one subscription" }`
    - Enforced at database level with unique constraint on `subscriptions.account_id`
  - Role-based access control with Users having Roles and Permissions
  - Subscriptions `belongs_to` an Account and a Plan
  - Plans have configurable default roles
  - Plans include features and limits stored as hash
  - Default roles from plan are assigned to user on account creation
  - First created user becomes account owner
  - Invitations for new user invitees
  - Account Delegation support to allow existing users from different accounts
  - State machine functionality for subscription and payment states
  - Audit logging for all model changes and user actions
- **Primary Keys**: Use application-generated UUIDv7 for all primary keys
- **Authentication**: JWT authentication for API access
- **Services**: Payment processing, billing calculations, dunning management
- **Jobs**: Automated renewals, payment retries, notification sending
- **Controllers**: RESTful API endpoints with proper serialization
- **Webhooks**: Payment gateway event handling (Stripe, PayPal)

### Frontend Structure (React + TypeScript)
- **Pages**: Customer dashboard, admin panel, billing management, application settings, user management, account management, subscription management, invitations management, delegations management, payment processor management
- **Components**: Reusable UI components with accessibility
- **Store**: Redux/Context for state management
- **Services**: API integration and data fetching
- **Application Settings**: All application settings manageable from within the frontend

### Key Business Logic Areas
- **Subscription Lifecycle**: Creation, upgrades/downgrades, pausing, cancellation
- **Billing Engine**: Automated renewals, proration calculations, invoice generation
- **Payment Processing**: Gateway integrations, retry logic, webhook handling
- **Dunning Management**: Failed payment recovery, account suspension
- **Analytics**: MRR/ARR calculations, churn analysis, customer lifetime value

## CRITICAL: Process Management Configuration

### ALWAYS Use Individual Process Manager Scripts

**NEVER** manually start Rails or React servers. **ALWAYS** use the dedicated process manager scripts:

#### Backend Management
- **Script**: `./scripts/backend-manager.sh`
- **Commands**: `start|stop|restart|status|logs|follow`
- **Usage**: 
  - Start: `./scripts/backend-manager.sh start`
  - Stop: `./scripts/backend-manager.sh stop`
  - Restart: `./scripts/backend-manager.sh restart`
  - Status: `./scripts/backend-manager.sh status`
  - Logs: `./scripts/backend-manager.sh logs [lines]`
  - Follow logs: `./scripts/backend-manager.sh follow`

#### Frontend Management
- **Script**: `./scripts/frontend-manager.sh`
- **Commands**: `start|stop|restart|status|logs|follow|clear-cache`
- **Usage**:
  - Start: `./scripts/frontend-manager.sh start`
  - Stop: `./scripts/frontend-manager.sh stop`
  - Restart: `./scripts/frontend-manager.sh restart`
  - Status: `./scripts/frontend-manager.sh status`
  - Logs: `./scripts/frontend-manager.sh logs [lines]`
  - Follow logs: `./scripts/frontend-manager.sh follow`
  - Clear cache: `./scripts/frontend-manager.sh clear-cache`

#### Orchestration (Both Services)
- **Script**: `./dev-manager.sh`
- **Usage**:
  - Start both: `./dev-manager.sh start`
  - Stop both: `./dev-manager.sh stop`
  - Restart both: `./dev-manager.sh restart`
  - Status both: `./dev-manager.sh status`
  - Backend only: `./dev-manager.sh backend [command]`
  - Frontend only: `./dev-manager.sh frontend [command]`

### Process Management Rules

1. **ALWAYS** run services as background processes using the scripts
2. **ALWAYS** check for existing processes and kill them thoroughly
3. **NEVER** use manual `rails server` or `npm start` commands
4. **AUTOMATICALLY** start servers when needed for development tasks
5. **ALWAYS** use the scripts when:
   - Starting backend or frontend
   - Stopping backend or frontend
   - Restarting backend or frontend
   - Checking server status
   - Viewing logs

### Tmux-Based Server Management

**Modern Approach**: Both backend and frontend servers now run in detached tmux sessions to completely isolate them from the Bash tool and provide persistent, manageable sessions.

**Backend (Rails)**:
- Session name: `powernode-backend`
- Command: `./scripts/backend-manager.sh start`
- Attach: `./scripts/backend-manager.sh tmux`
- Logs streamed to: `/home/rett/Projects/powernode-platform/logs/backend.log`

**Frontend (React)**:
- Session name: `powernode-frontend` 
- Command: `./scripts/frontend-manager.sh start`
- Attach: `./scripts/frontend-manager.sh tmux`
- Logs streamed to: `/home/rett/Projects/powernode-platform/logs/frontend.log`

### Important: Bash Tool Timeout Behavior

**CONFIRMED LIMITATION**: The Bash tool will ALWAYS show "Command timed out after 2m 0.0s" when starting Rails servers, regardless of the implementation approach (daemon mode, tmux sessions, ultra-simple scripts). This is a fundamental limitation of how the Bash tool handles processes related to Rails/tmux and is NOT an indication of failure.

**Key Facts**:
- ✅ **Scripts execute successfully** within 1-2 seconds
- ✅ **Servers start properly** and become healthy immediately
- ✅ **All functionality works** as expected
- ⚠️ **Timeout message is cosmetic** and should be ignored
- ✅ **Multiple approaches tested**: All show same timeout behavior

**Benefits of Tmux Approach**:
- ✅ Complete isolation from Bash tool limitations
- ✅ Persistent sessions that survive terminal disconnection
- ✅ Interactive access via `tmux attach-session`
- ✅ Clean process management and cleanup
- ✅ Real-time log streaming to both session and log files

**Recommended workflow**:
1. Run `./scripts/backend-manager.sh start` (ignore any timeout message)
2. Run `./scripts/backend-manager.sh status` to verify success
3. Use `./scripts/backend-manager.sh tmux` to attach and view live output
4. Detach with `Ctrl+B, D` to leave session running

### Automatic Background Server Management

**CRITICAL**: Claude should automatically manage development servers as follows:

#### **When to Start Servers Automatically**
- When user asks to test functionality that requires running servers
- When user asks to work on frontend or backend code that needs live testing
- When user asks to restart servers
- When user asks to check application status
- When user asks to view the application in browser

#### **Server Startup Priority**
1. **Backend First**: Always start `./scripts/backend-manager.sh start` first
2. **Frontend Second**: Then start `./scripts/frontend-manager.sh start`
3. **Health Check**: Verify both are running with `./dev-manager.sh status`

#### **Background Process Requirements**
- **Always Background**: Never run servers in foreground that would block Claude
- **Process Validation**: Always check if servers are already running before starting
- **Health Verification**: Confirm servers are responding before proceeding
- **Graceful Handling**: Handle server startup failures gracefully with error reporting

#### **Auto-Development Script** 
**PREFERRED METHOD**: Use `./scripts/auto-dev.sh` for automatic server management:

- **Auto Start**: `./scripts/auto-dev.sh ensure` - Starts both servers only if needed
- **Quick Status**: `./scripts/auto-dev.sh status` - Fast health check of both servers
- **Backend Only**: `./scripts/auto-dev.sh backend` - Ensure backend is running
- **Frontend Only**: `./scripts/auto-dev.sh frontend` - Ensure frontend is running
- **Health Check**: `./scripts/auto-dev.sh check` - Silent health check (exit code based)

**Claude Usage Pattern**:
1. Before any development task: `./scripts/auto-dev.sh ensure`
2. Quick status check: `./scripts/auto-dev.sh status`
3. If issues detected: Use individual managers for debugging

### Script Features
- **Comprehensive Process Detection**: Multiple methods to find all related processes
- **Graceful + Force Kill**: SIGTERM first, then SIGKILL after timeout
- **Health Checking**: Waits for services to be ready before confirming startup
- **Logging**: Centralized logging with structured output
- **PID Management**: Proper PID file tracking and cleanup
- **Port Management**: Automatic port conflict resolution

## Development Workflow

### Project Status Tracking
- Main task tracking should be maintained in a TODO.md file with development tasks
- Tasks use status indicators: `[ ]` PENDING, `[🔄]` IN_PROGRESS, `[✅]` COMPLETED, `[❌]` BLOCKED, `[⚠️]` NEEDS_REVIEW
- Always update task status when working on related features

### Development Commands

**CRITICAL: Process Management Protocol**
- **ALWAYS kill old processes before starting new ones** to prevent port conflicts and resource issues
- **Required before ANY server startup**: Run `./scripts/process-manager.sh stop` or `make dev-stop`
- **Use automated scripts**: `./scripts/dev-start.sh` handles full cleanup + startup sequence
- **Never start servers without first stopping existing processes**
- **For Claude Code automation**: Use `./scripts/process-manager.sh` for reliable process control

**Process Management Scripts:**
- `./scripts/dev-stop.sh` - Interactive process cleanup with verification
- `./scripts/dev-start.sh` - Full development environment startup
- `./scripts/process-manager.sh` - Automation-friendly process control utility
- `make dev-stop` / `make dev-start` / `make dev-restart` - Makefile shortcuts

**Standard Commands:**
- **Database**: Standard Rails commands from server directory (`cd server && rails db:create`, `rails db:migrate`, `rails db:seed`)
- **Testing**: `cd server && bundle exec rspec` for backend tests
- **Development Servers** (All configured for external access on 0.0.0.0): 
  - Backend: `cd server && bundle exec rails server -p 3000 -b 0.0.0.0`
  - Frontend: `cd frontend && HOST=0.0.0.0 npm run dev` (starts on port 3001, listens on all IPs)
- **Money Gem**: Configured with USD default currency and proper localization (see `config/initializers/money.rb`)
- **Background Jobs**: Standalone worker agent approach - see Background Jobs Architecture section below

### Multi-Agent Coordination
The project uses a sophisticated agent-based development approach defined in `claude-swarm.yml`:
- **Backend Agents**: Rails architect, data modeler, payment specialist, billing engine developer
- **Frontend Agents**: React architect, UI developer, dashboard specialist, admin panel developer
- **Quality Agents**: Backend/frontend test engineers
- **Infrastructure Agents**: DevOps engineer, security specialist, performance optimizer

## Key Implementation Patterns

### Payment Integration
- Use service objects for payment gateway interactions
- Implement comprehensive webhook handling for payment events
- Store payment methods securely with PCI compliance considerations
- Handle payment retries with exponential backoff
- **Money Gem Configuration**: 
  - Default currency set to USD (`Money.default_currency = "USD"`)
  - Rounding mode configured (`Money.rounding_mode = BigDecimal::ROUND_HALF_UP`)
  - I18n locale backend for proper formatting (`Money.locale_backend = :i18n`)

### Subscription Management
- Model subscription states as state machines
- Implement proration calculations for mid-cycle changes
- Use background jobs for automated renewal processing
- Track subscription history for audit purposes

### Security Considerations
- **JWT Authentication**: Stateless token-based authentication for API access
  - **Development Configuration**: Uses persistent JWT secret key to prevent token invalidation on server restart
  - **Production Configuration**: Uses encrypted credentials for JWT secret key
  - **Token Management**: Access tokens expire in 15 minutes, refresh tokens expire in 7 days
  - **Token Blacklisting**: Implements token blacklisting on logout to prevent token reuse
  - **Signature Verification**: All tokens verified with HMAC-SHA256 for security
- **Email Verification Required**: Users must verify their email address before login is allowed
  - Registration creates unverified accounts but login is blocked until email verification
  - Email verification tokens must be time-limited and single-use
  - Resend verification email functionality should be rate-limited
- **Password Security**: Strong password complexity requirements enforced
  - Minimum 12 characters length
  - Must contain uppercase, lowercase, numbers, and special characters
  - Password strength validation with entropy scoring
  - Password history tracking to prevent reuse of last 12 passwords
  - Account lockout after 5 failed attempts with exponential backoff
  - Secure password reset with time-limited tokens
- Rate limiting on all endpoints
- PCI DSS compliance for payment data
- Proper input validation and sanitization
- Environment-specific configuration management

### Background Jobs Architecture
- **Standalone Worker Agent**: Background jobs run as a separate worker service located in `./worker` directory with no direct database connectivity
- **API-Only Communication**: All data access must go through the Rails API backend via HTTP requests using service-to-service authentication
- **Sidekiq Processing**: Worker agent uses current Sidekiq version with built-in web interface for monitoring
- **Web Interface Authentication**: Sidekiq web interface integrates with Rails backend authentication system via API calls
- **Job Processing**: Sidekiq workers make authenticated API calls to the main Rails 8 backend for all data operations
- **Service Authentication**: Dedicated service-to-service authentication mechanism using secure tokens for worker-to-backend communication
- **Complete API Isolation**: Worker agent has zero direct database or model access, relying entirely on HTTP API endpoints
- **Scalability**: This architecture allows independent scaling of job processing and API backend components

### Testing Strategy
- Comprehensive model tests with FactoryBot (all factories fixed and validated)
- **Factory Validation**: All FactoryBot factories use valid data instead of placeholder "MyString" values
- **Money Gem Integration**: Tests properly handle Money objects and currency validation
- **Association Testing**: Proper shoulda-matchers usage with correct subject declarations for complex validations
- **One-to-One Relationship Testing**: Account-Subscription uniqueness validation at both application and database levels
- **Password Security Testing**: Comprehensive test coverage for password requirements
  - Password complexity validation tests
  - Password strength scoring tests
  - Account lockout behavior tests
  - Password history and reuse prevention tests
  - Password reset security flow tests
- API endpoint testing with proper fixtures
- Payment processing tests using VCR or stubs
- **Test Status**: Major model tests now passing (AuditLog: 42/42, Plan: 38/38, Payment: 62/62, Account: 41/41)
- Frontend component testing with Testing Library
- E2E tests for critical user flows

## Development Phases

The project follows a structured 6-phase approach:
1. **Backend Foundation** - Rails API setup, authentication, core models
2. **Payment Integration** - Gateway integrations, billing logic, webhooks
3. **Analytics & Reporting** - Business intelligence, KPI calculations
4. **Frontend Development** - React app, customer/admin interfaces
5. **Quality Assurance** - Comprehensive testing suite
6. **DevOps & Production** - CI/CD, monitoring, performance optimization

## Important Notes

- This is a greenfield project - no existing codebase yet
- Prioritize security and PCI compliance from the start
- Focus on scalable architecture for subscription growth
- Implement comprehensive error handling and logging
- Plan for multi-tenant capabilities if needed
- Consider regulatory compliance (tax calculations, reporting)

## Current Project Status

**Phase 1 - Backend Foundation**: ✅ **COMPLETED**
- Rails 8 API application fully set up in `./server` directory
- Core models implemented: Account, User, Subscription, Plan, Invoice, Payment, AuditLog
- **Account-Subscription One-to-One Relationship**: Implemented with validation and database constraints
- Money gem properly configured with USD defaults and I18n localization
- Authentication system with JWT tokens
- Database schema with UUIDv7 primary keys
- **Testing Suite**: Major model tests passing (203+ tests across key models)
  - AuditLog: 42/42 tests ✅
  - Plan: 38/38 tests ✅ 
  - Payment: 62/62 tests ✅
  - Account: 41/41 tests ✅
  - Subscription: Uniqueness validation working ✅
- **Factory Bot**: All factories validated and using proper test data
- State machines implemented for subscriptions and payments
- Multi-agent development approach defined in `claude-swarm.yml`
- 17 specialized agents for different aspects of development
- Payment gateway initializers configured (Stripe, PayPal)

**Next Phase**: Payment Integration - Gateway integrations, billing logic, webhooks

- Always update TODO.md when tasks are completed or changes to CLAUDE.md are made.

## Process Management Protocol for Claude Code

**RECOMMENDED SCREEN-BASED SERVER MANAGEMENT:**

Claude Code should use the modern screen-based individual manager scripts:

1. **Automatic environment management (preferred)**:
   ```bash
   ./scripts/auto-dev.sh ensure    # Start servers if needed
   ./scripts/auto-dev.sh status    # Check health
   ```

2. **Individual server control**:
   ```bash
   ./scripts/backend-manager.sh start    # Start Rails in screen session
   ./scripts/frontend-manager.sh start   # Start React in screen session
   ```

3. **Health checking and status**:
   ```bash
   ./scripts/auto-dev.sh status           # Quick environment check
   ./scripts/backend-manager.sh status    # Detailed backend status
   ./scripts/frontend-manager.sh status   # Detailed frontend status
   ```

**Benefits of screen-based approach:**
- **No timeout issues** - Clean detachment from Bash tool
- **Reliable process management** - Comprehensive detection methods
- **Interactive debugging** - Screen session attachment capabilities
- **Persistent sessions** - Servers survive shell disconnection

**This approach prevents:**
- Bash tool timeout errors
- Port conflicts (3000, 3001)
- Resource conflicts
- Orphaned background processes
- Failed server startups

**All development server management should use these screen-based scripts rather than direct Rails/NPM commands.**

**External Access Configuration:**
- All servers are configured to listen on 0.0.0.0 (all network interfaces)
- Backend accessible at: `http://localhost:3000` and `http://[HOST_IP]:3000`
- Frontend accessible at: `http://localhost:3001` and `http://[HOST_IP]:3001`
- This enables access from remote machines, containers, and networks
- WebSocket connections work with external IPs for real-time features

## Screen-Based Server Management

**RESOLVED**: Both backend and frontend server timeout issues have been resolved by switching from tmux to GNU screen.

**Backend Server Management**:
- `./scripts/backend-manager.sh start` - starts Rails in screen session 'powernode-backend' (no timeout)
- `./scripts/backend-manager.sh status` - check server health and running status
- `./scripts/backend-manager.sh screen` - attach to interactive screen session
- `./scripts/backend-manager.sh logs` - view server logs

**Frontend Server Management**:
- `./scripts/frontend-manager.sh start` - starts React in screen session 'powernode-frontend' (no timeout)
- `./scripts/frontend-manager.sh status` - check server health and running status  
- `./scripts/frontend-manager.sh screen` - attach to interactive screen session
- `./scripts/frontend-manager.sh logs` - view server logs

**Solution**: Screen sessions detach more cleanly from the Bash tool, eliminating the timeout issues that affected all tmux-based approaches for both Rails and React server startup. Both servers now use consistent screen-based process management.