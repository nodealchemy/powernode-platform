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

## Permission Categories

### User Management
| Permission | Description |
|------------|-------------|
| `users.create` | Create new users |
| `users.read` | View user information |
| `users.update` | Update user details |
| `users.delete` | Delete users |
| `users.manage` | Full user management |
| `team.manage` | Manage team settings |

### Billing Operations
| Permission | Description |
|------------|-------------|
| `billing.read` | View billing information |
| `billing.update` | Update billing settings |
| `billing.manage` | Full billing management |
| `invoices.create` | Create invoices |
| `payments.process` | Process payments |

### System Administration
| Permission | Description |
|------------|-------------|
| `admin.access` | Access admin panel |
| `system.admin` | Full system access |
| `accounts.manage` | Manage accounts |
| `settings.update` | Update system settings |

### Content Management
| Permission | Description |
|------------|-------------|
| `pages.create` | Create pages |
| `pages.update` | Update pages |
| `pages.delete` | Delete pages |
| `content.manage` | Full content management |

### Analytics
| Permission | Description |
|------------|-------------|
| `analytics.read` | View analytics |
| `analytics.export` | Export analytics data |
| `reports.generate` | Generate reports |

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
