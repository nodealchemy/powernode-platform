# MCP Specialist Configuration

**Model selection, delegation rules, and Task tool specialist spawning**

---

## Quick Reference - Specialist Documentation

### Backend Specialists
| Specialist | Documentation | Model |
|------------|---------------|-------|
| Rails Architect | [RAILS_ARCHITECT_SPECIALIST.md](../backend/RAILS_ARCHITECT_SPECIALIST.md) | sonnet |
| Data Modeler | [DATA_MODELER_SPECIALIST.md](../backend/DATA_MODELER_SPECIALIST.md) | sonnet |
| API Developer | [API_DEVELOPER_SPECIALIST.md](../backend/API_DEVELOPER_SPECIALIST.md) | sonnet |
| Payment Integration | [PAYMENT_INTEGRATION_SPECIALIST.md](../backend/PAYMENT_INTEGRATION_SPECIALIST.md) | **opus** |
| Billing Engine | [BILLING_ENGINE_DEVELOPER_SPECIALIST.md](../backend/BILLING_ENGINE_DEVELOPER_SPECIALIST.md) | **opus** |
| Background Jobs | [BACKGROUND_JOB_ENGINEER_SPECIALIST.md](../backend/BACKGROUND_JOB_ENGINEER_SPECIALIST.md) | sonnet |

### Frontend Specialists
| Specialist | Documentation | Model |
|------------|---------------|-------|
| React Architect | [REACT_ARCHITECT_SPECIALIST.md](../frontend/REACT_ARCHITECT_SPECIALIST.md) | sonnet |
| UI Components | [UI_COMPONENT_DEVELOPER_SPECIALIST.md](../frontend/UI_COMPONENT_DEVELOPER_SPECIALIST.md) | haiku |
| Dashboard | [DASHBOARD_SPECIALIST.md](../frontend/DASHBOARD_SPECIALIST.md) | sonnet |
| Admin Panel | [ADMIN_PANEL_DEVELOPER_SPECIALIST.md](../frontend/ADMIN_PANEL_DEVELOPER_SPECIALIST.md) | sonnet |

### Infrastructure Specialists
| Specialist | Documentation | Model |
|------------|---------------|-------|
| DevOps Engineer | [DEVOPS_ENGINEER_SPECIALIST.md](../infrastructure/DEVOPS_ENGINEER_SPECIALIST.md) | **opus** |
| Security | [SECURITY_SPECIALIST.md](../infrastructure/SECURITY_SPECIALIST.md) | **opus** |
| Performance | [PERFORMANCE_OPTIMIZER.md](../infrastructure/PERFORMANCE_OPTIMIZER.md) | **opus** |

### Testing Specialists
| Specialist | Documentation | Model |
|------------|---------------|-------|
| Backend Testing | [BACKEND_TEST_ENGINEER_SPECIALIST.md](../testing/BACKEND_TEST_ENGINEER_SPECIALIST.md) | sonnet |
| Frontend Testing | [FRONTEND_TEST_ENGINEER_SPECIALIST.md](../testing/FRONTEND_TEST_ENGINEER_SPECIALIST.md) | haiku |

### Service Specialists
| Specialist | Documentation | Model |
|------------|---------------|-------|
| Project Manager | [PROJECT_MANAGER_SPECIALIST.md](../services/PROJECT_MANAGER_SPECIALIST.md) | sonnet |
| Notifications | [NOTIFICATION_ENGINEER.md](../services/NOTIFICATION_ENGINEER.md) | sonnet |
| Documentation | [DOCUMENTATION_SPECIALIST.md](../services/DOCUMENTATION_SPECIALIST.md) | haiku |
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

### Available Claude Models & Capabilities

#### Sonnet 4.5 (Current Default)
- **Strengths**: Enhanced reasoning, superior code generation, advanced problem-solving
- **Best For**: General development tasks, architectural decisions, complex integrations
- **Use Cases**: Multi-step planning, code architecture, system design, complex business logic
- **Model Parameter**: `"sonnet"` or `"claude-sonnet-4-5"`

#### Haiku
- **Strengths**: Fast response, cost-effective, good for routine tasks
- **Best For**: Simple code generation, documentation, straightforward implementations
- **Use Cases**: CRUD operations, basic configurations, simple fixes
- **Model Parameter**: `"haiku"`

#### Opus
- **Strengths**: Highest reasoning capability, complex problem solving, extended thinking
- **Best For**: Mission-critical systems, complex debugging, system optimization
- **Use Cases**: Performance analysis, payment processing, security analysis, infrastructure decisions
- **Model Parameter**: `"opus"` or `"claude-3-opus"`

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

### Architecture & System Design (Opus/Sonnet)

| Specialist | Model | Thinking Budget | Reasoning |
|------------|-------|-----------------|-----------|
| **DevOps Engineer** | Opus | ultrathink | Infrastructure, production troubleshooting |
| **Security Specialist** | Opus | ultrathink | Security analysis, vulnerability assessment |
| **Payment Integration** | Opus | ultrathink | PCI compliance, financial accuracy |
| **Billing Engine** | Opus | ultrathink | Complex billing logic, proration |
| **Analytics Engineer** | Opus | ultrathink | Statistical analysis, business intelligence |
| **Performance Optimizer** | Opus | ultrathink | Bottleneck resolution, optimization |
| **Rails Architect** | Sonnet 4.5 | think harder | Rails conventions, API design |
| **React Architect** | Sonnet 4.5 | think harder | Component architecture, state management |
| **Data Modeler** | Sonnet 4.5 | think harder | Database design, relationships |

### Implementation Specialists (Sonnet/Haiku)

| Specialist | Model | Thinking Budget | Reasoning |
|------------|-------|-----------------|-----------|
| **API Developer** | Sonnet 4.5 | think hard | RESTful design, serialization |
| **Background Job Engineer** | Sonnet 4.5 | think hard | Async patterns, queue management |
| **Dashboard Specialist** | Sonnet 4.5 | think hard | Data visualization, interactive components |
| **Backend Test Engineer** | Sonnet 4.5 | think hard | Test strategy, integration testing |
| **Notification Engineer** | Sonnet 4.5 | think hard | Communication systems, integration |
| **Admin Panel Developer** | Sonnet 4.5 | think hard | Admin workflows, permissions |
| **UI Component Developer** | Haiku | think | Component creation, styling |
| **Frontend Test Engineer** | Haiku | think | Component testing, E2E testing |
| **Documentation Specialist** | Haiku | think | Documentation, technical writing |

### Dynamic Model Selection

For specialists handling varying complexity:

```
UI Component Developer:
- Simple components → Haiku + "think"
- Complex interactive components → Sonnet 4.5 + "think hard"

Frontend Test Engineer:
- Unit tests → Haiku + "think"
- Complex E2E scenarios → Sonnet 4.5 + "think hard"

Documentation Specialist:
- Standard docs → Haiku + "think"
- Complex technical architecture docs → Sonnet 4.5 + "think hard"
```

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
# High Complexity Specialists (Opus + ultrathink)
mcp__devops_engineer__task --thinking_budget "ultrathink" --model "opus"
mcp__payment_integration_specialist__task --thinking_budget "ultrathink" --model "opus"
mcp__billing_engine_developer__task --thinking_budget "ultrathink" --model "opus"
mcp__analytics_engineer__task --thinking_budget "ultrathink" --model "opus"
mcp__performance_optimizer__task --thinking_budget "ultrathink" --model "opus"
mcp__security_specialist__task --thinking_budget "ultrathink" --model "opus"

# Medium-High Complexity (Sonnet 4.5 + think harder)
mcp__rails_architect__task --thinking_budget "think harder" --model "sonnet"
mcp__react_architect__task --thinking_budget "think harder" --model "sonnet"
mcp__data_modeler__task --thinking_budget "think harder" --model "sonnet"
mcp__api_developer__task --thinking_budget "think hard" --model "sonnet"
mcp__background_job_engineer__task --thinking_budget "think hard" --model "sonnet"
mcp__dashboard_specialist__task --thinking_budget "think hard" --model "sonnet"

# Standard Complexity (Haiku + think)
mcp__ui_component_developer__task --thinking_budget "think" --model "haiku"
mcp__frontend_test_engineer__task --thinking_budget "think" --model "haiku"
mcp__documentation_specialist__task --thinking_budget "think" --model "haiku"
```

### Implementation Phases

**Phase 1: Core Specialist Configuration**
1. DevOps Engineer (Opus + ultrathink)
2. Security Specialist (Opus + ultrathink)
3. Payment Integration Specialist (Opus + ultrathink)
4. Rails Architect (Sonnet 4.5 + think harder)
5. React Architect (Sonnet 4.5 + think harder)

**Phase 2: Specialized Domain Configuration**
1. Data Modeler (Sonnet 4.5 + think harder)
2. Performance Optimizer (Opus + ultrathink)
3. Analytics Engineer (Opus + ultrathink)
4. API Developer (Sonnet 4.5 + think hard)
5. Background Job Engineer (Sonnet 4.5 + think hard)

**Phase 3: Support Specialist Configuration**
1. UI Component Developer (Haiku + think)
2. Frontend Test Engineer (Haiku + think)
3. Documentation Specialist (Haiku + think)
4. Backend Test Engineer (Sonnet 4.5 + think hard)

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
| Production deployment | Opus | ultrathink |
| Payment processing | Opus | ultrathink |
| Security analysis | Opus | ultrathink |
| Architecture design | Sonnet | think harder |
| Database modeling | Sonnet | think harder |
| API implementation | Sonnet | think hard |
| UI components | Haiku | think |
| Documentation | Haiku | think |

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
| **Rails Architect** | general-purpose | sonnet | docs/backend/RAILS_ARCHITECT_SPECIALIST.md |
| **Data Modeler** | general-purpose | sonnet | docs/backend/DATA_MODELER_SPECIALIST.md |
| **Payment Integration** | general-purpose | opus | docs/backend/PAYMENT_INTEGRATION_SPECIALIST.md |
| **Billing Engine** | general-purpose | opus | docs/backend/BILLING_ENGINE_DEVELOPER_SPECIALIST.md |
| **API Developer** | general-purpose | sonnet | docs/backend/API_DEVELOPER_SPECIALIST.md |
| **Background Job Engineer** | general-purpose | sonnet | docs/backend/BACKGROUND_JOB_ENGINEER_SPECIALIST.md |
| **React Architect** | general-purpose | sonnet | docs/frontend/REACT_ARCHITECT_SPECIALIST.md |
| **UI Component Developer** | general-purpose | haiku | docs/frontend/UI_COMPONENT_DEVELOPER_SPECIALIST.md |
| **Dashboard Specialist** | general-purpose | sonnet | docs/frontend/DASHBOARD_SPECIALIST.md |
| **Admin Panel Developer** | general-purpose | sonnet | docs/frontend/ADMIN_PANEL_DEVELOPER_SPECIALIST.md |
| **Backend Test Engineer** | general-purpose | sonnet | docs/testing/BACKEND_TEST_ENGINEER_SPECIALIST.md |
| **Frontend Test Engineer** | general-purpose | haiku | docs/testing/FRONTEND_TEST_ENGINEER_SPECIALIST.md |
| **DevOps Engineer** | general-purpose | opus | docs/infrastructure/DEVOPS_ENGINEER_SPECIALIST.md |
| **Security Specialist** | general-purpose | opus | docs/infrastructure/SECURITY_SPECIALIST.md |
| **Performance Optimizer** | general-purpose | opus | docs/infrastructure/PERFORMANCE_OPTIMIZER.md |
| **Project Manager** | general-purpose | sonnet | docs/services/PROJECT_MANAGER_SPECIALIST.md |
| **Notification Engineer** | general-purpose | sonnet | docs/services/NOTIFICATION_ENGINEER.md |
| **Documentation Specialist** | general-purpose | haiku | docs/services/DOCUMENTATION_SPECIALIST.md |
| **Analytics Engineer** | general-purpose | opus | docs/services/ANALYTICS_ENGINEER.md |

### Model Selection Guide

**Use Opus for:**
- Payment processing and PCI compliance (Payment Integration, Billing Engine)
- Security analysis and vulnerability assessment (Security Specialist)
- Infrastructure and production deployments (DevOps Engineer)
- Performance optimization and bottleneck resolution (Performance Optimizer)
- Complex analytics and business intelligence (Analytics Engineer)

**Use Sonnet for:**
- Rails API architecture and authentication (Rails Architect)
- React component architecture and state management (React Architect)
- Database modeling and schema design (Data Modeler)
- API endpoint implementation (API Developer)
- Background job patterns (Background Job Engineer)
- Dashboard development (Dashboard Specialist)
- Admin interface development (Admin Panel Developer)
- Backend testing (Backend Test Engineer)
- Project coordination, git workflow, releases (Project Manager)
- Notification systems (Notification Engineer)

**Use Haiku for:**
- Simple UI component creation (UI Component Developer)
- Documentation writing (Documentation Specialist)
- Frontend unit testing (Frontend Test Engineer)

### Task Tool Usage Examples

**Spawning a Backend Specialist:**

```
Task({
  description: "Rails API architecture review",
  subagent_type: "general-purpose",
  model: "sonnet",
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

**Spawning a Payment Specialist (Opus):**

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
  model: "sonnet",
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

**Spawning a Quick UI Task (Haiku):**

```
Task({
  description: "Create button component",
  subagent_type: "general-purpose",
  model: "haiku",
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
Task({ description: "Backend API", model: "sonnet", ... })
Task({ description: "Frontend components", model: "sonnet", ... })
Task({ description: "Integration tests", model: "sonnet", ... })
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

