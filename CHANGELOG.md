# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **UUIDv7 primary keys** across all tables — time-ordered v7 IDs via a portable `uuidv7()` SQL function
  (PG16-compatible, named to match the PG18 native function; self-bootstrapping in `schema.rb`).
- **Public/private schema isolation** — the committed `schema.rb` now contains only core + public-extension
  tables; private-extension tables are excluded via a dynamic prefix registry (`ExtensionRegistry`), with a
  leak-guard backstop in `scripts/pattern-validation.sh`.
- **Extension registry seams** — extensions contribute permissions (`register_catalog`), roles
  (`register_roles`), and audit actions/sources (`register_actions`/`register_sources`) into core at boot;
  core no longer hardcodes any extension. New conventions: `migrations-and-seeds.md`,
  `extension-db-contributions.md`.
- **Three-tier seeds** — `core` / `baseline` (global foundational content) / `demo` gates, with a per-extension
  `seed_orchestrator` contract.

### Changed
- **Migrations squashed** 616 → 7 baselines (one bootstrap + one per owner), with uniform `<ext>_` table
  prefixes (e.g. `system_`, `system_sdwan_`) and standardized Rails index names.
- **Permissions are code-defined** — the catalog is the source of truth; the `permissions` table was removed.
  Roles are global (read-only, code) or account-scoped (custom), with a no-escalation guard.
- **Billing** confirmed keep-separate (distinct billing surfaces; no consolidation).
- `db:seed` is now strictly idempotent (complete on first run, no-op on re-run).

### Fixed
- **supply-chain extension dedup** — removed core's stale duplicate tree that shadowed the canonical
  extension on the autoload path, restoring the `supply_chain.signing_keys.manage` separation-of-duties check.
- **`pattern-validation.sh`** — leak-guard always-FAIL bug (`grep -c || echo 0` double-emit) and a stale
  UUID-PK check (matched the discarded string-PK form); both now reflect the 0.4.0 schema.

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

## [0.0.1-dev] - 2024-12-XX

### Added
- Initial platform foundation
- Rails 8 API backend with core models
- React TypeScript frontend
- Sidekiq worker service
- JWT authentication system
- UUIDv7 primary keys
- Money gem integration
- State machine implementations
- Comprehensive test suite (203+ backend, 45+ frontend tests)

### Infrastructure
- PostgreSQL database setup
- Development environment automation
- Docker configuration
- CI/CD pipeline foundation

---

## Version History

- `0.0.1-dev` - Initial development version
- `0.1.0` - Planned first minor release

## Release Notes Template

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- New features

### Changed
- Changes in existing functionality

### Deprecated
- Soon-to-be removed features

### Removed
- Now removed features

### Fixed
- Bug fixes

### Security
- Security improvements
```

## Migration Guides

### Upgrading to 0.1.0 (Planned)
- Migration steps will be documented here
- Breaking changes and how to address them
- Updated API endpoints and parameters