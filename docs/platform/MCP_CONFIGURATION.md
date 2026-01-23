# MCP Specialist Configuration

**Model selection, delegation rules, and Task tool specialist spawning**

---

## Quick Reference - Specialist Documentation

### Backend Specialists
| Specialist | Documentation | Model |
|------------|---------------|-------|
| Rails Architect | [RAILS_ARCHITECT_SPECIALIST.md](../backend/RAILS_ARCHITECT_SPECIALIST.md) | **opus** |
| Data Modeler | [DATA_MODELER_SPECIALIST.md](../backend/DATA_MODELER_SPECIALIST.md) | **opus** |
| API Developer | [API_DEVELOPER_SPECIALIST.md](../backend/API_DEVELOPER_SPECIALIST.md) | **opus** |
| Payment Integration | [PAYMENT_INTEGRATION_SPECIALIST.md](../backend/PAYMENT_INTEGRATION_SPECIALIST.md) | **opus** |
| Billing Engine | [BILLING_ENGINE_DEVELOPER_SPECIALIST.md](../backend/BILLING_ENGINE_DEVELOPER_SPECIALIST.md) | **opus** |
| Background Jobs | [BACKGROUND_JOB_ENGINEER_SPECIALIST.md](../backend/BACKGROUND_JOB_ENGINEER_SPECIALIST.md) | **opus** |

### Frontend Specialists
| Specialist | Documentation | Model |
|------------|---------------|-------|
| React Architect | [REACT_ARCHITECT_SPECIALIST.md](../frontend/REACT_ARCHITECT_SPECIALIST.md) | **opus** |
| UI Components | [UI_COMPONENT_DEVELOPER_SPECIALIST.md](../frontend/UI_COMPONENT_DEVELOPER_SPECIALIST.md) | **opus** |
| Dashboard | [DASHBOARD_SPECIALIST.md](../frontend/DASHBOARD_SPECIALIST.md) | **opus** |
| Admin Panel | [ADMIN_PANEL_DEVELOPER_SPECIALIST.md](../frontend/ADMIN_PANEL_DEVELOPER_SPECIALIST.md) | **opus** |

### Infrastructure Specialists
| Specialist | Documentation | Model |
|------------|---------------|-------|
| DevOps Engineer | [DEVOPS_ENGINEER_SPECIALIST.md](../infrastructure/DEVOPS_ENGINEER_SPECIALIST.md) | **opus** |
| Security | [SECURITY_SPECIALIST.md](../infrastructure/SECURITY_SPECIALIST.md) | **opus** |
| Performance | [PERFORMANCE_OPTIMIZER.md](../infrastructure/PERFORMANCE_OPTIMIZER.md) | **opus** |

### Testing Specialists
| Specialist | Documentation | Model |
|------------|---------------|-------|
| Backend Testing | [BACKEND_TEST_ENGINEER_SPECIALIST.md](../testing/BACKEND_TEST_ENGINEER_SPECIALIST.md) | **opus** |
| Frontend Testing | [FRONTEND_TEST_ENGINEER_SPECIALIST.md](../testing/FRONTEND_TEST_ENGINEER_SPECIALIST.md) | **opus** |

### Service Specialists
| Specialist | Documentation | Model |
|------------|---------------|-------|
| Project Manager | [PROJECT_MANAGER_SPECIALIST.md](../services/PROJECT_MANAGER_SPECIALIST.md) | **opus** |
| Notifications | [NOTIFICATION_ENGINEER.md](../services/NOTIFICATION_ENGINEER.md) | **opus** |
| Documentation | [DOCUMENTATION_SPECIALIST.md](../services/DOCUMENTATION_SPECIALIST.md) | **opus** |
| Analytics | [ANALYTICS_ENGINEER.md](../services/ANALYTICS_ENGINEER.md) | **opus** |

---

## Table of Contents

1. [Model Selection Strategy](#model-selection-strategy)
2. [Specialist Model Assignments](#specialist-model-assignments)
3. [Automated Delegation Rules](#automated-delegation-rules)
4. [Documentation Enhancement Patterns](#documentation-enhancement-patterns)
5. [Implementation Configuration](#implementation-configuration)

---

## Model Selection Strategy

### Opus 4.5 Exclusive Configuration

All Claude agents in this project use **Opus 4.5** exclusively for maximum reasoning capability across all tasks.

#### Opus 4.5 (Exclusive Model)
- **Strengths**: Highest reasoning capability, complex problem solving, extended thinking
- **Best For**: All development tasks - from architecture to implementation
- **Use Cases**: All specialist work, code generation, debugging, optimization
- **Model Parameter**: `"opus"`

### Thinking Budget Optimization

**"ultrathink"** - Reserved for:
- Production deployments and infrastructure changes
- Payment processing and financial calculations
- Security vulnerability analysis
- Complex performance optimization
- Business-critical decision making

**"think harder"** - Used for:
- Architectural decisions and system design
- Complex data modeling and relationships
- Integration planning and API design
- Advanced testing scenarios

**"think hard"** - Applied to:
- Feature implementation with complexity
- Component architecture decisions
- Integration development
- Quality assurance planning

**"think"** - Standard for:
- Routine development tasks
- Standard component creation
- Basic documentation
- Simple configurations

---

## Specialist Model Assignments

### All Specialists (Opus 4.5 Exclusive)

| Specialist | Model | Thinking Budget | Reasoning |
|------------|-------|-----------------|-----------|
| **DevOps Engineer** | Opus | ultrathink | Infrastructure, production troubleshooting |
| **Security Specialist** | Opus | ultrathink | Security analysis, vulnerability assessment |
| **Payment Integration** | Opus | ultrathink | PCI compliance, financial accuracy |
| **Billing Engine** | Opus | ultrathink | Complex billing logic, proration |
| **Analytics Engineer** | Opus | ultrathink | Statistical analysis, business intelligence |
| **Performance Optimizer** | Opus | ultrathink | Bottleneck resolution, optimization |
| **Rails Architect** | Opus | ultrathink | Rails conventions, API design |
| **React Architect** | Opus | ultrathink | Component architecture, state management |
| **Data Modeler** | Opus | ultrathink | Database design, relationships |
| **API Developer** | Opus | ultrathink | RESTful design, serialization |
| **Background Job Engineer** | Opus | ultrathink | Async patterns, queue management |
| **Dashboard Specialist** | Opus | ultrathink | Data visualization, interactive components |
| **Backend Test Engineer** | Opus | ultrathink | Test strategy, integration testing |
| **Notification Engineer** | Opus | ultrathink | Communication systems, integration |
| **Admin Panel Developer** | Opus | ultrathink | Admin workflows, permissions |
| **UI Component Developer** | Opus | ultrathink | Component creation, styling |
| **Frontend Test Engineer** | Opus | ultrathink | Component testing, E2E testing |
| **Documentation Specialist** | Opus | ultrathink | Documentation, technical writing |
| **Project Manager** | Opus | ultrathink | Project coordination, releases |

---

## Automated Delegation Rules

### Delegation Priority Matrix

**High Priority (Immediate Delegation)**:
1. **Service Management Issues** → DevOps Engineer
2. **Database Schema Changes** → Data Modeler
3. **Payment Integration** → Payment Integration Specialist
4. **Security Vulnerabilities** → Security Specialist
5. **Performance Bottlenecks** → Performance Optimizer

**Medium Priority (With Context)**:
1. **API Development** → API Developer (with requirements summary)
2. **UI Component Work** → UI Component Developer (with design requirements)
3. **Testing Tasks** → Respective Test Engineers (with scope definition)
4. **Background Jobs** → Background Job Engineer (with job specifications)

**Low Priority (User Choice)**:
1. **Documentation Updates** → Documentation Specialist
2. **Analytics Features** → Analytics Engineer
3. **Admin Interface** → Admin Panel Developer

### Trigger Conditions by Specialist

#### Backend Specialists

**Rails Architect**:
- **Keywords**: "Rails", "API endpoint", "controller", "middleware", "authentication", "JWT"
- **File Patterns**: `server/app/controllers/`, `server/config/routes.rb`
- **Task Types**: API architecture, Rails configuration, authentication setup

**Data Modeler**:
- **Keywords**: "database", "model", "migration", "ActiveRecord", "schema", "associations"
- **File Patterns**: `server/db/migrate/`, `server/app/models/`
- **Task Types**: Database schema design, model relationships, migrations

**API Developer**:
- **Keywords**: "API endpoint", "REST", "JSON", "serialization", "API response"
- **File Patterns**: `server/app/controllers/api/`, serializer files
- **Task Types**: API endpoint implementation, serialization, response formatting

**Background Job Engineer**:
- **Keywords**: "background job", "Sidekiq", "queue", "worker", "async", "scheduled"
- **File Patterns**: `worker/app/jobs/`, `server/app/jobs/`
- **Task Types**: Background job creation, queue management, scheduled tasks

**Payment Integration Specialist**:
- **Keywords**: "payment", "Stripe", "PayPal", "billing", "webhook", "invoice"
- **File Patterns**: Payment-related models, payment controllers
- **Task Types**: Payment gateway integration, webhook handling

**Billing Engine Developer**:
- **Keywords**: "subscription lifecycle", "billing cycle", "proration", "renewal"
- **File Patterns**: Subscription models, billing controllers
- **Task Types**: Subscription management, billing logic

#### Frontend Specialists

**React Architect**:
- **Keywords**: "React", "component architecture", "routing", "state management", "TypeScript"
- **File Patterns**: `frontend/src/`, React components, routing files
- **Task Types**: Component architecture, routing setup, state management

**UI Component Developer**:
- **Keywords**: "component", "UI", "design system", "theme", "styling", "responsive"
- **File Patterns**: `frontend/src/shared/components/`
- **Task Types**: UI component creation, design system implementation

**Dashboard Specialist**:
- **Keywords**: "dashboard", "analytics", "charts", "metrics", "visualization"
- **File Patterns**: Analytics components, dashboard pages
- **Task Types**: Dashboard development, data visualization

**Admin Panel Developer**:
- **Keywords**: "admin", "administration", "management panel", "system management"
- **File Patterns**: Admin-related components
- **Task Types**: Admin interface development, system management tools

#### Infrastructure Specialists

**DevOps Engineer**:
- **Keywords**: "deployment", "CI/CD", "Docker", "infrastructure", "monitoring", "production"
- **File Patterns**: `.github/workflows/`, Docker files, deployment scripts
- **Task Types**: Deployment automation, CI/CD setup, infrastructure management

**Security Specialist**:
- **Keywords**: "security", "vulnerability", "authentication", "authorization", "PCI compliance"
- **File Patterns**: Security configurations, authentication files
- **Task Types**: Security audits, vulnerability fixes, compliance implementation

**Performance Optimizer**:
- **Keywords**: "performance", "optimization", "slow", "bottleneck", "caching"
- **File Patterns**: Performance-related configurations
- **Task Types**: Performance analysis, optimization implementation

---

## Documentation Enhancement Patterns

### Controller Pattern Standardization

```ruby
## Standard Controller Pattern

class Api::V1::[Resource]Controller < ApplicationController
  include [Resource]Serialization

  before_action :set_resource, only: [:show, :update, :destroy]
  before_action -> { require_permission('[resource].[action]') }, only: [actions]

  # Standard CRUD operations with consistent response format
end

## Response Format Standards
{
  success: boolean,
  data: object|array,
  error?: string,
  details?: array,
  message?: string
}
```

### Authentication & Authorization Patterns

```ruby
## Authentication Concern Pattern
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_request
    attr_reader :current_user, :current_account
  end

  # JWT validation, permission checking, impersonation support
end

## Permission-Based Authorization
def require_permission(permission)
  render_unauthorized unless current_user.has_permission?(permission)
end
```

### Frontend Permission Patterns

```typescript
// Permission hook patterns
export const usePermissions = () => {
  const { currentUser } = useAuth();

  const hasPermission = (permission: string): boolean => {
    return currentUser?.permissions?.includes(permission) || false;
  };

  const hasAnyPermission = (permissions: string[]): boolean => {
    return permissions.some(permission => hasPermission(permission));
  };

  const hasAllPermissions = (permissions: string[]): boolean => {
    return permissions.every(permission => hasPermission(permission));
  };

  return { hasPermission, hasAnyPermission, hasAllPermissions };
};
```

### Worker Job Patterns

```ruby
## BaseJob Pattern
class BaseJob
  include Sidekiq::Job

  sidekiq_options retry: 3, dead: true, queue: 'default'

  # Exponential backoff with API error handling
  sidekiq_retry_in do |count, exception|
    case exception
    when BackendApiClient::ApiError
      [30, 60, 180][count - 1] || 300
    else
      (count ** 4) + 15 + (rand(30) * (count + 1))
    end
  end

  def perform(*args)
    @started_at = Time.current
    logger.info "Starting #{self.class.name} with args: #{args.inspect}"
    execute(*args)
  end

  private

  def execute(*args)
    raise NotImplementedError, "Subclasses must implement execute method"
  end
end
```

---

## Implementation Configuration

### Configuration Commands

```bash
# All Specialists (Opus 4.5 + ultrathink)
mcp__devops_engineer__task --thinking_budget "ultrathink" --model "opus"
mcp__payment_integration_specialist__task --thinking_budget "ultrathink" --model "opus"
mcp__billing_engine_developer__task --thinking_budget "ultrathink" --model "opus"
mcp__analytics_engineer__task --thinking_budget "ultrathink" --model "opus"
mcp__performance_optimizer__task --thinking_budget "ultrathink" --model "opus"
mcp__security_specialist__task --thinking_budget "ultrathink" --model "opus"
mcp__rails_architect__task --thinking_budget "ultrathink" --model "opus"
mcp__react_architect__task --thinking_budget "ultrathink" --model "opus"
mcp__data_modeler__task --thinking_budget "ultrathink" --model "opus"
mcp__api_developer__task --thinking_budget "ultrathink" --model "opus"
mcp__background_job_engineer__task --thinking_budget "ultrathink" --model "opus"
mcp__dashboard_specialist__task --thinking_budget "ultrathink" --model "opus"
mcp__ui_component_developer__task --thinking_budget "ultrathink" --model "opus"
mcp__frontend_test_engineer__task --thinking_budget "ultrathink" --model "opus"
mcp__documentation_specialist__task --thinking_budget "ultrathink" --model "opus"
mcp__backend_test_engineer__task --thinking_budget "ultrathink" --model "opus"
mcp__admin_panel_developer__task --thinking_budget "ultrathink" --model "opus"
mcp__notification_engineer__task --thinking_budget "ultrathink" --model "opus"
mcp__project_manager__task --thinking_budget "ultrathink" --model "opus"
```

### Implementation Configuration

**All specialists configured with Opus 4.5 + ultrathink:**
- DevOps Engineer, Security Specialist, Payment Integration
- Rails Architect, React Architect, Data Modeler
- Performance Optimizer, Analytics Engineer
- API Developer, Background Job Engineer
- Dashboard Specialist, Admin Panel Developer
- UI Component Developer, Frontend Test Engineer
- Backend Test Engineer, Documentation Specialist
- Notification Engineer, Project Manager

### Configuration Validation

Test each specialist configuration with sample tasks:
- Verify appropriate model selection for task complexity
- Confirm thinking budget matches reasoning requirements
- Validate output quality meets domain standards
- Ensure cost-effectiveness for task volume

---

## Quick Reference

### Model Selection by Task Type

| Task Type | Model | Thinking |
|-----------|-------|----------|
| All tasks | Opus | ultrathink |

### Delegation Response Templates

**Immediate Delegation (High Priority)**:
```
I'm delegating this [task type] to our [Specialist Name] who specializes in [area].
They have comprehensive expertise in [specific domain] and will handle this efficiently.
```

**Contextual Delegation (Medium Priority)**:
```
This [task type] aligns perfectly with our [Specialist Name]'s expertise.
Let me delegate to them with the context that [brief summary of requirements].
```

**Suggested Delegation (Low Priority)**:
```
I can handle this [task], or would you prefer me to delegate to our [Specialist Name]
who specializes in [area]? They might provide more specialized insights.
```

---

## Task Tool Specialist Delegation

Claude Code's Task tool enables spawning specialist agents for domain-specific work. This section documents how to delegate tasks to specialists using the Task tool with appropriate model selection.

### Specialist-to-Subagent Mapping

| Specialist | Subagent Type | Model | Documentation |
|------------|---------------|-------|---------------|
| **Platform Architect** | general-purpose | opus | Full system oversight |
| **Rails Architect** | general-purpose | opus | docs/backend/RAILS_ARCHITECT_SPECIALIST.md |
| **Data Modeler** | general-purpose | opus | docs/backend/DATA_MODELER_SPECIALIST.md |
| **Payment Integration** | general-purpose | opus | docs/backend/PAYMENT_INTEGRATION_SPECIALIST.md |
| **Billing Engine** | general-purpose | opus | docs/backend/BILLING_ENGINE_DEVELOPER_SPECIALIST.md |
| **API Developer** | general-purpose | opus | docs/backend/API_DEVELOPER_SPECIALIST.md |
| **Background Job Engineer** | general-purpose | opus | docs/backend/BACKGROUND_JOB_ENGINEER_SPECIALIST.md |
| **React Architect** | general-purpose | opus | docs/frontend/REACT_ARCHITECT_SPECIALIST.md |
| **UI Component Developer** | general-purpose | opus | docs/frontend/UI_COMPONENT_DEVELOPER_SPECIALIST.md |
| **Dashboard Specialist** | general-purpose | opus | docs/frontend/DASHBOARD_SPECIALIST.md |
| **Admin Panel Developer** | general-purpose | opus | docs/frontend/ADMIN_PANEL_DEVELOPER_SPECIALIST.md |
| **Backend Test Engineer** | general-purpose | opus | docs/testing/BACKEND_TEST_ENGINEER_SPECIALIST.md |
| **Frontend Test Engineer** | general-purpose | opus | docs/testing/FRONTEND_TEST_ENGINEER_SPECIALIST.md |
| **DevOps Engineer** | general-purpose | opus | docs/infrastructure/DEVOPS_ENGINEER_SPECIALIST.md |
| **Security Specialist** | general-purpose | opus | docs/infrastructure/SECURITY_SPECIALIST.md |
| **Performance Optimizer** | general-purpose | opus | docs/infrastructure/PERFORMANCE_OPTIMIZER.md |
| **Project Manager** | general-purpose | opus | docs/services/PROJECT_MANAGER_SPECIALIST.md |
| **Notification Engineer** | general-purpose | opus | docs/services/NOTIFICATION_ENGINEER.md |
| **Documentation Specialist** | general-purpose | opus | docs/services/DOCUMENTATION_SPECIALIST.md |
| **Analytics Engineer** | general-purpose | opus | docs/services/ANALYTICS_ENGINEER.md |

### Model Selection Guide

**All specialists use Opus 4.5 exclusively** for maximum reasoning capability across all development tasks.

### Task Tool Usage Examples

**Spawning a Backend Specialist:**

```
Task({
  description: "Rails API architecture review",
  subagent_type: "general-purpose",
  model: "opus",
  prompt: `You are a Rails 8 API architect for Powernode.

Reference: docs/backend/RAILS_ARCHITECT_SPECIALIST.md

Core Responsibilities:
- Rails 8 API-only application architecture
- JWT authentication and middleware configuration
- WebSocket integration with Action Cable
- API versioning and endpoint design
- Security configuration and best practices

Task: [specific task description]

Follow patterns in the specialist documentation. Reference docs/TODO.md for context.`
})
```

**Spawning a Payment Specialist:**

```
Task({
  description: "Payment webhook implementation",
  subagent_type: "general-purpose",
  model: "opus",
  prompt: `You are a payment integration specialist for Powernode.

Reference: docs/backend/PAYMENT_INTEGRATION_SPECIALIST.md

Core Responsibilities:
- Stripe and PayPal gateway integration
- Webhook processing and validation
- PCI DSS compliance implementation
- Payment retry logic and failure handling
- Secure payment method storage

Task: [specific task description]

Follow PCI DSS standards and patterns in specialist documentation.`
})
```

**Spawning a Frontend Specialist:**

```
Task({
  description: "React dashboard component",
  subagent_type: "general-purpose",
  model: "opus",
  prompt: `You are a dashboard specialist for Powernode.

Reference: docs/frontend/DASHBOARD_SPECIALIST.md

Core Responsibilities:
- Interactive dashboard development with Chart.js
- Real-time data visualization and updates
- KPI display and business metrics
- Dashboard performance optimization
- WebSocket integration for live data

Task: [specific task description]

Follow visualization patterns and theme-aware styling in specialist documentation.`
})
```

**Spawning a UI Task:**

```
Task({
  description: "Create button component",
  subagent_type: "general-purpose",
  model: "opus",
  prompt: `You are a UI component developer for Powernode.

Reference: docs/frontend/UI_COMPONENT_DEVELOPER_SPECIALIST.md

Core Responsibilities:
- Design system with theme-aware components
- Reusable React component library
- Responsive design with Tailwind CSS

Task: [simple component task]

Use theme classes (bg-theme-*, text-theme-*) and follow component patterns.`
})
```

### Parallel Specialist Spawning

For complex tasks requiring multiple specialists, spawn them in parallel:

```
// Single message with multiple Task calls
Task({ description: "Backend API", model: "opus", ... })
Task({ description: "Frontend components", model: "opus", ... })
Task({ description: "Integration tests", model: "opus", ... })
```

### Specialist Prompt Template

```
You are a [Specialist Role] for Powernode.

Reference: [path/to/SPECIALIST_DOCUMENTATION.md]

Core Responsibilities:
- [Responsibility 1]
- [Responsibility 2]
- [Responsibility 3]

Task: [Specific task description with requirements]

Follow patterns and standards in your specialist documentation.
Reference docs/TODO.md for project status and coordination points.
```

---

**Document Status**: ✅ Complete
**Consolidates**: MCP_MODEL_CONFIGURATION.md, MCP_DOCUMENTATION_ENHANCEMENT_PLAN.md, AUTOMATED_MCP_DELEGATION_CONFIG.md

