# Permissions Registry

> Status: active
>
> Authoritative reference for the permission strings recognised by Powernode access control.

## Table of Contents

- [Overview](#overview)
- [Forbidden Patterns](#forbidden-patterns)
- [Correct Patterns](#correct-patterns)
- [Permission Categories](#permission-categories)
- [AI Autonomy Permissions](#ai-autonomy-permissions)
- [Common Permission Patterns](#common-permission-patterns)
- [Backend Roles](#backend-roles)
- [API Response Format](#api-response-format)
- [Navigation Filtering](#navigation-filtering)

## Overview

Powernode uses **permission-based** access control. The frontend MUST check permissions only, never roles. The backend uses `current_user.has_permission?('name')` for authorization. Roles exist only as a backend convenience for grouping permissions; they are never inspected by frontend code. The canonical registry is the code-defined `Permissions` catalog in `server/config/permissions.rb` — there is no `permissions` table and no `Permission` model.

For the design rationale (why permissions instead of roles, ABAC vs RBAC trade-offs, etc.), see [../concepts/permissions.md](../concepts/permissions.md).

## Forbidden Patterns

### Frontend

```typescript
// FORBIDDEN — role-based access control
const canManage    = currentUser?.roles?.includes('account.manager');
const isSystemAdmin = currentUser?.role === 'system.admin';
if (user.roles.includes('billing.manager')) { return <AdminPanel />; }

// FORBIDDEN — mixed role / permission checks
const hasAccess = user.roles.includes('admin') || user.permissions.includes('read');

// FORBIDDEN — hardcoded role checks
if (currentUser?.roles?.some(r => r.includes('admin'))) { /* ... */ }
```

### Backend

```ruby
# FORBIDDEN — .include? on permissions collection (returns objects, not strings)
if current_user.permissions.include?('users.manage')

# FORBIDDEN — role-based authorization
if current_user.roles.any? { |r| r.name == 'admin' }
```

## Correct Patterns

### Frontend

```typescript
const canManageUsers   = currentUser?.permissions?.includes('users.manage');
const canViewBilling   = currentUser?.permissions?.includes('billing.read');
const canAccessAdmin   = currentUser?.permissions?.includes('admin.access');

if (!canAccessAdmin) return <AccessDenied />;

<Button disabled={!currentUser?.permissions?.includes('users.create')}>
  Create User
</Button>

{currentUser?.permissions?.includes('analytics.read') && <AnalyticsDashboard />}
```

### Backend

```ruby
# Correct — has_permission? helper
if current_user.has_permission?('users.manage')
  # allow
end

# Controller before_action
before_action -> { require_permission('users.read') },   only: %i[index show]
before_action -> { require_permission('users.manage') }, only: %i[create update destroy]

# Inline
def sensitive_action
  return render_forbidden("Access denied") unless current_user.has_permission?('admin.access')
  # proceed
end
```

## Permission Categories

Permissions are organised by prefix. The base platform ships a core-only set in `Permissions::CORE_PERMISSIONS`; the runtime total is the dynamic union `Permissions.all_permissions` (core ∪ every enabled extension's permissions, roughly ~687 in full mode). The total depends on which extensions are loaded, so never hardcode it — query the runtime registry (`GET /api/v1/permissions`, or `cd server && rails runner "puts Permissions.all_permissions.size"`) for the current count. The code catalog (`server/config/permissions.rb`) is the source of truth for the core set.

| Category | Description |
|----------|-------------|
| `admin.*` | Admin panel access — accounts, AI, audit, billing, DevOps, Docker, files, Git, marketplace |
| `ai.*` | AI features — agents, workflows, memory, knowledge, conversations, providers, autonomy |
| `system.*` | System-level — admin, monitoring, health, configuration |
| `supply_chain.*` | Supply chain management |
| `devops.*` | DevOps — pipelines, providers, repositories, templates |
| `swarm.*` | Docker Swarm operations |
| `git.*` | Git — approvals, credentials, pipelines, providers, repositories |
| `docker.*` | Docker container management |
| `marketing.*` | Marketing campaigns |
| `integrations.*` | Third-party integrations |
| `app.*` | App marketplace |
| `files.*` | File management |
| `kb.*` | Knowledge base articles |
| `mcp.*` | MCP protocol operations |
| `subscription.*` | Subscription lifecycle (extension-gated) |
| `page.*` | CMS pages |
| `review.*` | Code reviews |
| `storage.*` | Storage backends |
| `listing.*` | Marketplace listings |
| `team.*` | Team management |
| `webhook.*` | Webhook management |
| `api.*` | API key management |
| `audit.*` | Audit logs |
| `billing.*` | Billing operations (extension-gated) |
| `plans.*` | Plan management (extension-gated) |
| `report.*` | Reports |
| `user.*` | User management |
| `invoice.*` | Invoice management (extension-gated) |
| `marketplace.*` | Marketplace access |
| `users.*` | User listing |

## AI Autonomy Permissions

| Permission | Description |
|------------|-------------|
| `ai.kill_switch.manage` | Activate and deactivate the AI emergency kill switch |
| `ai.goals.manage` | Create, update, and delete AI agent goals |
| `ai.intervention_policies.manage` | Configure AI intervention policies and notification preferences |
| `ai.proposals.view` | View AI agent proposals |
| `ai.proposals.review` | Approve or reject AI agent proposals |
| `ai.escalations.view` | View AI agent escalations |
| `ai.escalations.resolve` | Acknowledge and resolve AI agent escalations |
| `ai.feedback.submit` | Submit feedback on AI agent performance |
| `ai.feedback.view` | View AI agent feedback history |
| `ai.autonomy.manage` | Manage AI agent autonomous behaviour and duty cycles |

**Role assignments:** `ai.kill_switch.manage` is automatically assigned to `owner` and `admin` roles.

> **Registration source:** The AI Autonomy permissions above are defined in the code catalog (`server/config/permissions.rb`, surfaced via `Permissions::CORE_PERMISSIONS` / `Permissions.all_permissions`) like every other core permission — there is no separate seed file.

## Common Permission Patterns

```
# CRUD pattern
resource.create
resource.read
resource.update
resource.delete

# Management shortcut
resource.manage     # implies full CRUD

# Admin-scoped
admin.resource.read
admin.resource.update
admin.resource.delete
```

## Backend Roles

Roles exist only for permission grouping in the backend. Frontend code NEVER checks roles.

| Role | Description | Typical Permissions |
|------|-------------|---------------------|
| `super_admin` | Full system access | All permissions |
| `owner` | Account owner | Account-scoped permissions |
| `admin` | Administrator | Admin-scoped permissions |
| `manager` | Account management | Management permissions |
| `member` | Basic access | Read-only permissions |
| `developer` | Developer access | DevOps / engineering permissions |
| `content_manager` | Content management | Content / CMS permissions |

Worker roles (`system_worker`, `task_worker`, `ci_worker`, `ai_specialist`) also exist for service-to-service authorization.

## API Response Format

User objects returned from API MUST include a permissions array:

```ruby
class UserSerializer
  def permission_names
    object.permissions.pluck(:name)
  end
end
```

```json
{
  "data": {
    "id": "uuid",
    "email": "user@example.com",
    "permissions": ["users.read", "billing.read", "analytics.read"]
  }
}
```

## Navigation Filtering

```typescript
const filteredNavItems = navigationItems.filter(item => {
  if (!item.permission) return true;
  return currentUser?.permissions?.includes(item.permission);
});
```

---

## Related docs

- [../concepts/permissions.md](../concepts/permissions.md) — Design rationale
- [../guides/backend.md](../guides/backend.md) — `has_permission?` patterns
- [../guides/frontend.md](../guides/frontend.md) — Permission-gated UI
- [api/overview.md](api/overview.md) — Endpoint-level permission requirements
- Source of truth: the code-defined `Permissions` catalog in `server/config/permissions.rb` — core permissions in `Permissions::CORE_PERMISSIONS`, the runtime union via `Permissions.all_permissions`. There is no seeder and no separate seed file; AI Autonomy permissions live in the catalog like every other core permission.

## Materials previously at

- `docs/platform/PERMISSION_SYSTEM_REFERENCE.md` (registry portions)

_Last verified: 2026-06-04_
