# MCP Specialist Configuration

Task tool specialist spawning and delegation rules.

---

## Specialist Index

| Category | Specialist | Documentation |
|----------|------------|---------------|
| **Backend** | Rails Architect | [RAILS_ARCHITECT_SPECIALIST.md](../backend/RAILS_ARCHITECT_SPECIALIST.md) |
| | Data Modeler | [DATA_MODELER_SPECIALIST.md](../backend/DATA_MODELER_SPECIALIST.md) |
| | API Developer | [API_DEVELOPER_SPECIALIST.md](../backend/API_DEVELOPER_SPECIALIST.md) |
| | Payment Integration | [PAYMENT_INTEGRATION_SPECIALIST.md](../backend/PAYMENT_INTEGRATION_SPECIALIST.md) |
| | Billing Engine | [BILLING_ENGINE_DEVELOPER_SPECIALIST.md](../backend/BILLING_ENGINE_DEVELOPER_SPECIALIST.md) |
| | Background Jobs | [BACKGROUND_JOB_ENGINEER_SPECIALIST.md](../backend/BACKGROUND_JOB_ENGINEER_SPECIALIST.md) |
| **Frontend** | React Architect | [REACT_ARCHITECT_SPECIALIST.md](../frontend/REACT_ARCHITECT_SPECIALIST.md) |
| | UI Components | [UI_COMPONENT_DEVELOPER_SPECIALIST.md](../frontend/UI_COMPONENT_DEVELOPER_SPECIALIST.md) |
| | Dashboard | [DASHBOARD_SPECIALIST.md](../frontend/DASHBOARD_SPECIALIST.md) |
| | Admin Panel | [ADMIN_PANEL_DEVELOPER_SPECIALIST.md](../frontend/ADMIN_PANEL_DEVELOPER_SPECIALIST.md) |
| **Infrastructure** | DevOps Engineer | [DEVOPS_ENGINEER_SPECIALIST.md](../infrastructure/DEVOPS_ENGINEER_SPECIALIST.md) |
| | Security | [SECURITY_SPECIALIST.md](../infrastructure/SECURITY_SPECIALIST.md) |
| | Performance | [PERFORMANCE_OPTIMIZER.md](../infrastructure/PERFORMANCE_OPTIMIZER.md) |
| **Testing** | Backend Testing | [BACKEND_TEST_ENGINEER_SPECIALIST.md](../testing/BACKEND_TEST_ENGINEER_SPECIALIST.md) |
| | Frontend Testing | [FRONTEND_TEST_ENGINEER_SPECIALIST.md](../testing/FRONTEND_TEST_ENGINEER_SPECIALIST.md) |
| **Services** | Project Manager | [PROJECT_MANAGER_SPECIALIST.md](../services/PROJECT_MANAGER_SPECIALIST.md) |
| | Notifications | [NOTIFICATION_ENGINEER.md](../services/NOTIFICATION_ENGINEER.md) |
| | Documentation | [DOCUMENTATION_SPECIALIST.md](../services/DOCUMENTATION_SPECIALIST.md) |
| | Analytics | [ANALYTICS_ENGINEER.md](../services/ANALYTICS_ENGINEER.md) |

**All specialists use Opus 4.6 exclusively.**

---

## Task Tool Delegation

### Delegation Priority

| Priority | Trigger | Delegate To |
|----------|---------|-------------|
| **High** | Service failures | DevOps Engineer |
| | Database schema | Data Modeler |
| | Payment issues | Payment Integration |
| | Security vulnerabilities | Security Specialist |
| | Performance bottlenecks | Performance Optimizer |
| **Medium** | API endpoints | API Developer |
| | UI components | UI Component Developer |
| | Test failures | Respective Test Engineer |
| | Background jobs | Background Job Engineer |
| **Low** | Documentation | Documentation Specialist |
| | Analytics features | Analytics Engineer |
| | Admin interface | Admin Panel Developer |

### Trigger Keywords

| Specialist | Keywords | File Patterns |
|------------|----------|---------------|
| Rails Architect | Rails, API endpoint, controller, JWT | `server/app/controllers/`, `config/routes.rb` |
| Data Modeler | database, model, migration, schema | `server/db/migrate/`, `server/app/models/` |
| API Developer | REST, JSON, serialization | `server/app/controllers/api/` |
| Background Job | Sidekiq, queue, worker, async | `worker/app/jobs/`, `server/app/jobs/` |
| Payment Integration | payment, Stripe, PayPal, webhook | Payment models/controllers |
| React Architect | component architecture, routing, state | `frontend/src/` |
| UI Component | UI, design system, theme, styling | `frontend/src/shared/components/` |
| DevOps | deployment, Docker, CI/CD, monitoring | `.github/workflows/`, Docker files |
| Security | vulnerability, authentication, PCI | Security configurations |

---

## Spawning Specialists

### Template

```
Task({
  description: "Brief task description",
  subagent_type: "general-purpose",
  model: "opus",
  prompt: `You are a [Specialist Role] for Powernode.

Reference: [path/to/SPECIALIST.md]

Task: [specific task description]

Follow patterns in specialist documentation.`
})
```

### Examples

**Backend API work:**
```
Task({
  description: "Rails API architecture",
  subagent_type: "general-purpose",
  model: "opus",
  prompt: `You are a Rails 8 API architect for Powernode.

Reference: docs/backend/RAILS_ARCHITECT_SPECIALIST.md

Task: Review and optimize the subscription API endpoints.

Follow patterns in specialist documentation.`
})
```

**Payment implementation:**
```
Task({
  description: "Payment webhook handler",
  subagent_type: "general-purpose",
  model: "opus",
  prompt: `You are a payment integration specialist for Powernode.

Reference: docs/backend/PAYMENT_INTEGRATION_SPECIALIST.md

Task: Implement Stripe webhook signature validation.

Follow PCI DSS standards in specialist documentation.`
})
```

**UI component:**
```
Task({
  description: "Theme-aware button",
  subagent_type: "general-purpose",
  model: "opus",
  prompt: `You are a UI component developer for Powernode.

Reference: docs/frontend/UI_COMPONENT_DEVELOPER_SPECIALIST.md

Task: Create accessible button component with loading state.

Use theme classes (bg-theme-*, text-theme-*).`
})
```

### Parallel Spawning

For complex tasks, spawn multiple specialists in one message:

```
Task({ description: "Backend API", model: "opus", ... })
Task({ description: "Frontend components", model: "opus", ... })
Task({ description: "Integration tests", model: "opus", ... })
```

---

## Code Patterns

### Controller Pattern

```ruby
class Api::V1::[Resource]Controller < ApplicationController
  before_action :set_resource, only: [:show, :update, :destroy]
  before_action -> { require_permission('[resource].[action]') }, only: [actions]

  # Standard CRUD with render_success/render_error
end
```

### Permission Checks

```ruby
# Backend
def require_permission(permission)
  render_unauthorized unless current_user.has_permission?(permission)
end
```

```typescript
// Frontend
const hasPermission = (permission: string): boolean => {
  return currentUser?.permissions?.includes(permission) || false;
};
```

### Worker Job Pattern

```ruby
class MyJob < BaseJob
  sidekiq_options queue: 'default', retry: 3

  def execute(*args)
    # Implementation
  end
end
```

---

## Related Documentation

- [MCP_INTEGRATION_GUIDE.md](MCP_INTEGRATION_GUIDE.md) - Workflow execution architecture
- [WORKFLOW_IO_STANDARD.md](workflows/WORKFLOW_IO_STANDARD.md) - Node I/O specification
- [API_RESPONSE_STANDARDS.md](API_RESPONSE_STANDARDS.md) - API response format

---

**Document Status**: Complete (166 MCP tools registered)
**Consolidates**: MCP_MODEL_CONFIGURATION.md, MCP_DOCUMENTATION_ENHANCEMENT_PLAN.md, AUTOMATED_MCP_DELEGATION_CONFIG.md
**Tool Registry**: `server/app/services/ai/tools/platform_api_tool_registry.rb`
**Tool Catalog**: [MCP_TOOL_CATALOG.md](MCP_TOOL_CATALOG.md) (regenerate with `rails mcp:generate_tool_catalog`)
