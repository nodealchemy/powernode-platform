# Powernode Platform Documentation

This directory contains comprehensive documentation for the Powernode subscription platform.

## Quick Access
- **[TODO.md](TODO.md)** - Project tracking and development status (auto-generated from MCP shared knowledge)
- **[CHANGELOG.md](CHANGELOG.md)** - Version history and release notes
- **[DEVELOPMENT.md](DEVELOPMENT.md)** - Development setup and workflow
- **[Backend Test Engineer](testing/BACKEND_TEST_ENGINEER_SPECIALIST.md)** - Rails testing specialist
- **[Frontend Test Engineer](testing/FRONTEND_TEST_ENGINEER_SPECIALIST.md)** - React testing specialist

## Directory Structure

### Platform Documentation (`platform/`)
System-wide architectural and integration documentation:
- **Permission System**: Permission-based access control
- **MCP Configuration**: Model Context Protocol setup + 305 tool actions across 50 tool classes
- **UUID System**: UUIDv7 implementation across all 423 tables
- **Accessibility Standards**: Platform accessibility compliance and guidelines
- **AI Orchestration**: 132 models, 88 controllers, 376 services across 52 subdirectories
- **Content Linking**: Wikilinks and backlinks on the knowledge graph
- **Daily Summaries**: Auto-generated operational summaries
- **Data Sources**: Managed external data API integration (NOAA, Open-Meteo, FRED, etc.)

### Backend Documentation (`backend/`)
Rails API specialist documentation:
- **[Rails Architect](backend/RAILS_ARCHITECT_SPECIALIST.md)** - Rails 8 API architecture and patterns
- **[Data Modeler](backend/DATA_MODELER_SPECIALIST.md)** - Database schema and ActiveRecord patterns
- **[Payment Integration](backend/PAYMENT_INTEGRATION_SPECIALIST.md)** - Stripe/PayPal integration
- **[API Developer](backend/API_DEVELOPER_SPECIALIST.md)** - RESTful API design patterns
- **[Billing Engine](backend/BILLING_ENGINE_DEVELOPER_SPECIALIST.md)** - Subscription lifecycle management
- **[Background Jobs](backend/BACKGROUND_JOB_ENGINEER_SPECIALIST.md)** - Sidekiq worker patterns

### Frontend Documentation (`frontend/`)
React TypeScript specialist documentation:
- **[React Architect](frontend/REACT_ARCHITECT_SPECIALIST.md)** - TypeScript architecture and state management
- **[UI Components](frontend/UI_COMPONENT_DEVELOPER_SPECIALIST.md)** - Design system and reusable components
- **[Dashboard Specialist](frontend/DASHBOARD_SPECIALIST.md)** - Interactive charts and analytics
- **[Admin Panel](frontend/ADMIN_PANEL_DEVELOPER_SPECIALIST.md)** - Administrative interface development

### Testing Documentation (`testing/`)
Comprehensive testing framework and methodologies:
- **[Backend Test Engineer](testing/BACKEND_TEST_ENGINEER_SPECIALIST.md)** - Rails testing specialist guide (RSpec patterns)
- **[Frontend Test Engineer](testing/FRONTEND_TEST_ENGINEER_SPECIALIST.md)** - React testing specialist guide (Jest/Cypress)

### Infrastructure Documentation (`infrastructure/`)
DevOps and system administration:
- **[DevOps Engineer](infrastructure/DEVOPS_ENGINEER_SPECIALIST.md)** - CI/CD, deployment, monitoring
- **[Security Specialist](infrastructure/SECURITY_SPECIALIST.md)** - Application security and compliance
- **[Performance Optimizer](infrastructure/PERFORMANCE_OPTIMIZER.md)** - Performance tuning and optimization

### Service Documentation (`services/`)
Specialized service implementations:
- **[Analytics Engineer](services/ANALYTICS_ENGINEER.md)** - Business intelligence and KPIs
- **[Documentation Specialist](services/DOCUMENTATION_SPECIALIST.md)** - API documentation and knowledge base
- **[Notification Engineer](services/NOTIFICATION_ENGINEER.md)** - Email, SMS, and real-time notifications

### Worker Documentation (`worker/`)
Background processing documentation:
- See **[Background Jobs Specialist](backend/BACKGROUND_JOB_ENGINEER_SPECIALIST.md)** for worker patterns

## Additional Documentation Files

### Quick Reference Guides
- **[QUICKSTART](QUICKSTART.md)** - Getting started guide
- **[DEVELOPMENT](DEVELOPMENT.md)** - Development setup and workflow

## Additional Documentation Locations

For service-specific implementation documentation:
- **Backend** (`../server/docs/`): Rails API, models, services, and backend architecture
- **Frontend** (`../frontend/docs/`): React components, styling, and UI patterns  
- **Worker** (`../worker/docs/`): Sidekiq jobs, background processing, and queue management

## Platform Status

The platform has achieved:
- ✅ **Comprehensive Test Coverage** - Tests passing across frontend and backend
- ✅ **Specialist Documentation** - 16 specialist role guides across backend, frontend, infrastructure, services, testing
- ✅ **Production Ready** - Full-stack subscription platform with payment integration
- ✅ **Documentation Hygiene** - Organized documentation structure with proper file organization

## Key Platform Documentation Files

### Platform Architecture & Standards
- **[Permission System Reference](platform/PERMISSION_SYSTEM_REFERENCE.md)** - Permission-based access control
- **[UUID System Implementation](platform/UUID_SYSTEM_IMPLEMENTATION.md)** - UUIDv7 system documentation
- **[MCP Configuration](platform/MCP_CONFIGURATION.md)** - Model Context Protocol setup and tools
- **[MCP Tool Catalog](platform/MCP_TOOL_CATALOG.md)** - All 305 MCP actions across 50 tool classes
- **[AI Orchestration Guide](platform/AI_ORCHESTRATION_GUIDE.md)** - Agents, missions, ralph loops, autonomy, codebase intelligence
- **[Missions Guide](platform/MISSIONS_GUIDE.md)** - End-to-end development pipeline with approval gates
- **[Agent Autonomy Guide](platform/AGENT_AUTONOMY_GUIDE.md)** - Trust tiers, goals, proposals, escalations
- **[Data Sources](platform/DATA_SOURCES.md)** - External data API integration
- **[Daily Summaries](platform/DAILY_SUMMARIES.md)** - Auto-generated operational summaries
- **[Content Linking](platform/CONTENT_LINKING.md)** - Wikilinks and backlinks
- **[Theme System Reference](platform/THEME_SYSTEM_REFERENCE.md)** - Theme system documentation
- **[API Response Standards](platform/API_RESPONSE_STANDARDS.md)** - API response format standards

### Compliance & Analysis
- **[Accessibility Compliance Standards](platform/ACCESSIBILITY_COMPLIANCE_STANDARDS.md)** - Platform accessibility standards

## Documentation Standards

All documentation follows the standardized organization:
- **Platform-Level**: Cross-component system documentation
- **Component-Level**: Service-specific implementation details
- **Feature-Level**: Individual feature documentation and guides

For development guidance, see the main [CLAUDE.md](../CLAUDE.md) configuration file.