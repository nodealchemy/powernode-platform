# Permission System Reference

Unified permission-based access control documentation for backend and frontend.

## Core Principle

**ABSOLUTE MANDATE**: Access control MUST use permissions ONLY - NEVER roles.

- Roles exist in the backend ONLY for assigning groups of permissions
- Frontend NEVER checks roles - only permissions
- Backend authorization uses `has_permission?()` method

## FORBIDDEN Patterns

### Frontend - NEVER Do This

```typescript
// FORBIDDEN - Role-based access control
const canManage = currentUser?.roles?.includes('account.manager');
const isSystemAdmin = currentUser?.role === 'system.admin';
if (user.roles.includes('billing.manager')) { return <AdminPanel />; }

// FORBIDDEN - Mixed role/permission checks
const hasAccess = user.roles.includes('admin') || user.permissions.includes('read');

// FORBIDDEN - Hardcoded role checks
if (currentUser?.roles?.some(r => r.includes('admin'))) { ... }
```

### Backend - NEVER Do This

```ruby
# FORBIDDEN - Using .include? on permissions collection (returns objects not strings)
if current_user.permissions.include?('users.manage')  # WRONG - won't work

# FORBIDDEN - Role-based authorization
if current_user.roles.any? { |r| r.name == 'admin' }  # WRONG
```

## CORRECT Patterns

### Frontend - Permission-Based Access

```typescript
// Check single permission
const canManageUsers = currentUser?.permissions?.includes('users.manage');
const canViewBilling = currentUser?.permissions?.includes('billing.read');

// Component access control
const canAccessAdminPanel = currentUser?.permissions?.includes('admin.access');
if (!canAccessAdminPanel) return <AccessDenied />;

// UI element control
<Button disabled={!currentUser?.permissions?.includes('users.create')}>
  Create User
</Button>

// Conditional rendering
{currentUser?.permissions?.includes('analytics.read') && (
  <AnalyticsDashboard />
)}
```

### Backend - Permission-Based Authorization

```ruby
# CORRECT - Using has_permission? method
if current_user.has_permission?('users.manage')
  # Allow access
end

# Controller before_action
before_action -> { require_permission('users.read') }, only: [:index, :show]
before_action -> { require_permission('users.manage') }, only: [:create, :update, :destroy]

# In action
def sensitive_action
  unless current_user.has_permission?('admin.access')
    return render_forbidden("Access denied")
  end
  # Proceed with action
end
```

## Permission Categories (533 Total)

Permissions are organized by prefix. Major categories:

| Category | Count | Description |
|----------|-------|-------------|
| `admin.*` | 152 | Admin panel access — accounts, AI, audit, billing, DevOps, Docker, files, Git, marketplace |
| `ai.*` | 80 | AI features — agents, workflows, memory, knowledge, conversations, providers |
| `system.*` | 61 | System-level — admin, monitoring, health, configuration |
| `supply_chain.*` | 34 | Supply chain management |
| `devops.*` | 29 | DevOps — pipelines, providers, repositories, templates |
| `swarm.*` | 27 | Docker Swarm operations |
| `git.*` | 25 | Git — approvals, credentials, pipelines, providers, repositories |
| `docker.*` | 19 | Docker container management |
| `marketing.*` | 11 | Marketing campaigns |
| `integrations.*` | 9 | Third-party integrations |
| `app.*` | 8 | App marketplace |
| `files.*` | 8 | File management |
| `kb.*` | 7 | Knowledge base articles |
| `mcp.*` | 6 | MCP protocol operations |
| `subscription.*` | 6 | Subscription lifecycle |
| `page.*` | 5 | CMS pages |
| `review.*` | 5 | Code reviews |
| `storage.*` | 5 | Storage backends |
| `listing.*` | 4 | Marketplace listings |
| `team.*` | 4 | Team management |
| `webhook.*` | 4 | Webhook management |
| `api.*` | 3 | API key management |
| `audit.*` | 3 | Audit logs |
| `billing.*` | 3 | Billing operations |
| `plans.*` | 3 | Plan management |
| `report.*` | 3 | Reports |
| `user.*` | 3 | User management |
| `invoice.*` | 2 | Invoice management |
| `marketplace.*` | 3 | Marketplace access |
| `users.*` | 1 | User listing |

### Common Permission Patterns

```
# CRUD pattern
resource.create, resource.read, resource.update, resource.delete

# Management shortcut
resource.manage  (implies full CRUD)

# Admin scoped
admin.resource.read, admin.resource.update, admin.resource.delete
```

## Backend Roles (For Permission Assignment Only)

Roles exist in the backend to group permissions. Frontend NEVER checks roles.

| Role | Description | Typical Permissions |
|------|-------------|---------------------|
| `system.admin` | Full system access | All permissions |
| `account.manager` | Account management | Account-scoped permissions |
| `account.member` | Basic access | Read-only permissions |
| `billing.manager` | Billing operations | Billing-related permissions |

## API Response Format

User objects returned from API MUST include permissions array:

```ruby
# In UserSerializer
def permission_names
  object.permissions.pluck(:name)
end

# Response includes permissions
{
  "data": {
    "id": "...",
    "email": "user@example.com",
    "permissions": ["users.read", "billing.read", "analytics.read"]
  }
}
```

## Navigation Filtering

Filter navigation items by permissions:

```typescript
const filteredNavItems = navigationItems.filter(item => {
  if (!item.permission) return true;
  return currentUser?.permissions?.includes(item.permission);
});
```

## See Also

- [React Architect Specialist](../frontend/REACT_ARCHITECT_SPECIALIST.md)
- [Rails Architect Specialist](../backend/RAILS_ARCHITECT_SPECIALIST.md)
- [Admin Panel Developer](../frontend/ADMIN_PANEL_DEVELOPER_SPECIALIST.md)
