# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-02-28

### Added
- **AI Autonomy System**: Complete agent autonomy framework with kill switch, goals, proposals, escalations, feedback, intervention policies, observations, duty cycle, and sensors
- 7 new models: `Ai::KillSwitchEvent`, `Ai::AgentGoal`, `Ai::AgentProposal`, `Ai::AgentEscalation`, `Ai::AgentFeedback`, `Ai::InterventionPolicy`, `Ai::AgentObservation`
- 8 new API controllers for autonomy management (public + internal)
- 8 sensor classes for agent behavioral observation
- 10+ new services: kill switch, escalation, feedback loop, proposal, intervention policy, observation pipeline, duty cycle, work claim, session discovery, agent outreach
- 6 new Sidekiq jobs for autonomy maintenance (observation pipeline, goal maintenance, observation cleanup, escalation timeout, proposal expiry, intervention policy tuning)
- `AiSuspensionCheckConcern` for all AI execution jobs (kill switch compliance)
- 16 new MCP tool actions: 3 kill switch (`emergency_halt`, `emergency_resume`, `kill_switch_status`) + 13 agent autonomy (`create_agent_goal`, `list_agent_goals`, `update_agent_goal`, `agent_introspect`, `propose_feature`, `send_proactive_notification`, `discover_claude_sessions`, `request_code_change`, `create_proposal`, `escalate`, `request_feedback`, `report_issue`)
- Autonomy dashboard with 6 panel components (goals, proposals, escalations, feedback, intervention policies, kill switch)
- 10 database migrations for autonomy subsystem
- Autonomy permissions seed

## [0.2.0] - 2026-02-26

### Added
- **AI Orchestration System**: Complete AI workflow orchestration with database schema, models, services, API endpoints, and WebSocket channels
- **MCP Integration**: Model Context Protocol implementation with OAuth 2.1 and security hardening (2025-06-18 spec compliance)
- **Workflow Builder**: MCP nodes integration into visual workflow builder
- **GDPR Compliance**: Data privacy features including consent management and data export
- **Notification System**: Comprehensive notification infrastructure with email, in-app, and WebSocket delivery
- **Account Switcher**: UI component for managing multiple accounts
- **Privacy Features**: Enhanced user privacy controls and data management
- **Knowledge Base Enhancement**: Comprehensive knowledge base system with improved search and categorization
- **Security Scanning**: Added security scanning tools and infrastructure configurations
- **Compliance Jobs**: GDPR compliance, notification, and virus scan background jobs
- **MCP Browser**: Enhanced UI for browsing MCP servers and tools
- **Database-driven CORS**: Dynamic CORS and Vite allowed hosts management

### Changed
- **Build System**: Migrated frontend from Create React App to Vite for faster builds
- **Reverse Proxy**: Added reverse proxy configuration with smart port detection
- **Worker Authentication**: Unified worker authentication system across services
- **Database Schema**: Comprehensive consolidation and optimization
- **Service Naming**: Renamed AI orchestration services with `ai_` prefix for clarity

### Fixed
- Login persistence issues
- MCP streamable HTTP test assertions
- Zeitwerk autoloading conflicts for workflow services
- Non-deterministic worker test failures
- Frontend test assertions and expectations
- Hardcoded colors converted to theme classes

### Security
- Comprehensive JWT authentication system with enhanced security
- OAuth 2.1 integration for MCP
- Security hardening across all API endpoints

### Infrastructure
- Proxy host management scripts
- Development scripts and frontend tooling updates
- Package updates across all platform dependencies

## [0.0.2] - 2025-08-24

### Added
- **Marketplace Infrastructure**: Complete app marketplace with 13 database tables
- **App Management**: Full CRUD operations for apps, plans, subscriptions, and features
- **API Endpoints**: 7 new controllers with comprehensive marketplace operations
- **Frontend Components**: 40+ new components for marketplace UI and management
- **Webhook System**: Complete webhook management with delivery tracking
- **Endpoint Management**: API endpoint configuration and analytics
- **App Analytics**: Comprehensive metrics and performance tracking
- **Permission System**: 47 new marketplace-specific permissions with audit logging
- **Database Migrations**: 4 new migrations for marketplace infrastructure
- **Documentation**: Comprehensive marketplace implementation guides and API docs

### Changed
- **Code Quality**: Fixed 51 files with ESLint warnings (94 → 14 warnings)
- **Performance**: Added useCallback/useMemo optimizations across components
- **Navigation**: Updated structure with marketplace routes and improved UX
- **Component Architecture**: Enhanced PageContainer and TabContainer patterns
- **Database Schema**: Updated to version 2025_08_24_040830

### Fixed
- **TypeScript Compilation**: Resolved TS2554 and TS2304 errors in admin components
- **React Hooks**: Fixed no-use-before-define warnings by reordering function definitions
- **Template Strings**: Fixed expression warnings in fix-compilation-errors.ts
- **DateRangeFilter**: Major reorganization to resolve multiple hook dependency issues
- **AdminAPI**: Updated getUsers() method to accept optional filters parameter
- **Unused Variables**: Cleaned up unused imports and variables across codebase

### Technical Details
- **Files Changed**: 135 files with +23,580 insertions, -297 deletions
- **Test Coverage**: All tests passing (Frontend 19/19, Backend 921/921)
- **Code Quality**: Zero TypeScript compilation errors
- **Performance**: 84% reduction in ESLint warnings
- **Architecture**: Complete marketplace infrastructure ready for production

## [0.0.1] - 2025-08-15

### Added
- Initial platform foundation with Rails 8 API backend
- React TypeScript frontend with modern component architecture
- Sidekiq worker service for background job processing
- JWT authentication system with secure token handling
- Comprehensive subscription lifecycle management
- Payment gateway integrations (Stripe, PayPal)
- Money gem integration for precise financial calculations
- UUIDv7 primary keys for all database entities
- State machine implementations for subscription management
- Comprehensive audit logging system
- User management with role-based permissions
- Account delegation and impersonation capabilities
- Global notification system with theme-aware components
- Analytics dashboard with real-time metrics
- Admin panel with security settings and system management
- Email configuration and template management
- Comprehensive test suite (921+ backend, 45+ frontend tests)
- Git-Flow workflow with semantic versioning enforcement
- Development environment automation scripts
- Comprehensive documentation and setup guides

### Changed
- Renamed services to workers for architectural clarity
- Enhanced authentication and security features
- Improved API error handling and validation
- Database schema optimizations
- Theme-aware component styling throughout platform

### Fixed
- Analytics dashboard date range button functionality
- Component import/export consistency
- TypeScript compilation errors
- Security vulnerabilities in error handling

### Security
- Enhanced authentication flow validation
- Improved error message sanitization
- Rate limiting implementation
- Secure JWT token handling
- PCI-compliant payment processing
- Cross-origin request protection (CORS)
- Input validation and sanitization
- Secure email delivery system

### Infrastructure
- PostgreSQL database with optimized schema
- Redis for caching and session management
- Comprehensive development scripts
- Docker-ready configuration
- CI/CD pipeline foundation
- Automated testing and validation

---

## Version History

- `0.0.1` - Initial release with core platform features
- `0.0.2` - Marketplace infrastructure
- `0.2.0` - AI Orchestration, MCP integration, GDPR, notifications
- `0.3.0` - AI Autonomy System (kill switch, goals, proposals, escalations)
