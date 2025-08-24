# Phase 1 Implementation Guide: Permission Mapping & Backend Updates

## 🎯 **Current Audit Results** 
- **20 role-based access patterns** requiring migration
- **12 permission-based patterns** already implemented
- **Target**: 0 role-based, 80+ permission-based patterns

## 🚀 **Phase 1 Tasks (Week 1)**

### Task 1.1: Define Comprehensive Permission System

Based on audit findings, create these permission categories:

#### **User & Team Management Permissions**
```typescript
// User CRUD operations
'users.create'     // Create new users
'users.read'       // View user information  
'users.update'     // Edit user details
'users.delete'     // Remove users
'users.manage'     // Full user management (includes all above)

// Team-specific operations
'team.invite'      // Send team invitations
'team.remove'      // Remove team members
'team.manage'      // Full team management
'team.roles'       // Change team member roles
```

#### **Administrative Permissions** 
```typescript
// Admin panel access
'admin.access'     // Access admin sections
'admin.users'      // Admin user management
'admin.system'     // System administration
'admin.settings'   // Admin settings management

// System-level operations  
'system.admin'     // System administrator access
'system.maintenance' // System maintenance access
'accounts.manage'  // Manage accounts (system admin)
```

#### **Content & Resource Permissions**
```typescript
// Content management
'pages.create'     // Create new pages
'pages.update'     // Edit existing pages  
'pages.delete'     // Remove pages
'content.manage'   // Full content management

// Infrastructure management
'workers.read'     // View workers
'workers.create'   // Create new workers
'workers.manage'   // Full worker management
'volumes.read'     // View volumes
'volumes.manage'   // Manage storage volumes
```

#### **Business Operations Permissions**
```typescript
// Billing & Financial
'billing.read'     // View billing information
'billing.update'   // Update billing details
'billing.manage'   // Full billing management
'invoices.create'  // Generate invoices
'payments.process' // Process payments

// Analytics & Reports  
'analytics.read'   // View analytics data
'analytics.export' // Export analytics reports
'reports.generate' // Generate reports
'reports.download' // Download generated reports
```

### Task 1.2: Create Role → Permission Mapping

#### **Backend Role Definitions** (server/config/permissions.rb)
```ruby
# Create comprehensive role-permission mapping
ROLE_PERMISSIONS = {
  'system.admin' => [
    # Full system access - all permissions
    'users.manage', 'team.manage', 'admin.access', 'admin.users', 'admin.system', 'admin.settings',
    'system.admin', 'system.maintenance', 'accounts.manage', 'pages.manage', 'content.manage',
    'workers.manage', 'volumes.manage', 'billing.manage', 'invoices.create', 'payments.process',
    'analytics.read', 'analytics.export', 'reports.generate', 'reports.download'
  ].freeze,
  
  'account.manager' => [
    # Account-level management
    'users.manage', 'team.manage', 'admin.access', 'admin.users', 'pages.manage', 'content.manage',
    'billing.read', 'billing.update', 'analytics.read', 'reports.generate'
  ].freeze,
  
  'account.member' => [
    # Basic user access
    'users.read', 'team.invite', 'pages.create', 'pages.update', 'analytics.read'
  ].freeze,
  
  'billing.manager' => [
    # Billing specialist
    'users.read', 'billing.manage', 'invoices.create', 'payments.process', 
    'analytics.read', 'reports.generate'
  ].freeze,
  
  'volume.manager' => [
    # Infrastructure management
    'users.read', 'workers.manage', 'volumes.manage', 'analytics.read'
  ].freeze
}.freeze
```

### Task 1.3: Update Backend API Responses

#### **Update User Serialization** (server/app/controllers/concerns/user_serialization.rb)
```ruby
module UserSerialization
  private
  
  def user_data(user)
    {
      id: user.id,
      first_name: user.first_name,
      last_name: user.last_name,
      full_name: user.full_name,
      email: user.email,
      email_verified: user.email_verified?,
      phone: user.phone,
      
      # Keep roles for display and backend processing
      roles: user.role_names,
      
      # ADD: permissions array for frontend access control
      permissions: user_permissions(user),
      
      status: user.status,
      locked: user.locked?,
      failed_login_attempts: user.failed_login_attempts,
      last_login_at: user.last_login_at,
      created_at: user.created_at,
      updated_at: user.updated_at,
      preferences: user.preferences,
      account: user.account ? {
        id: user.account.id,
        name: user.account.name,
        status: user.account.status
      } : nil
    }
  end
  
  # NEW: Generate permissions array based on user roles
  def user_permissions(user)
    permissions = []
    user.role_names.each do |role_name|
      role_permissions = ROLE_PERMISSIONS[role_name] || []
      permissions.concat(role_permissions)
    end
    permissions.uniq.sort
  end
end
```

#### **Update Authentication Controller** (server/app/controllers/api/v1/auth_controller.rb)
```ruby
def login_success_response(user)
  render json: {
    success: true,
    data: {
      user: user_data(user),  # Now includes permissions array
      access_token: @access_token,
      refresh_token: @refresh_token,
      expires_at: @expires_at
    },
    message: "Login successful"
  }, status: :ok
end
```

### Task 1.4: Update Frontend User Interface

#### **Update User Type Definition** (frontend/src/features/users/services/usersApi.ts)
```typescript
export interface User {
  id: string;
  first_name: string;
  last_name: string;
  full_name: string;
  email: string;
  email_verified: boolean;
  phone?: string;
  
  // Keep roles for display purposes
  roles: string[];
  
  // ADD: permissions array for access control  
  permissions: string[];
  
  status: 'active' | 'suspended' | 'inactive';
  locked: boolean;
  failed_login_attempts: number;
  last_login_at: string | null;
  created_at: string;
  updated_at: string;
  preferences: Record<string, any>;
  account: {
    id: string;
    name: string;
    status: string;
  };
}
```

#### **Update Auth Slice** (frontend/src/shared/services/slices/authSlice.ts)
```typescript
interface AuthState {
  isAuthenticated: boolean;
  user: User | null;  // User now includes permissions array
  token: string | null;
  refreshToken: string | null;
  loading: boolean;
  error: string | null;
}
```

### Task 1.5: Create Permission Constants

#### **Frontend Permission Constants** (frontend/src/shared/constants/permissions.ts)
```typescript
// User & Team Management
export const USER_PERMISSIONS = {
  CREATE: 'users.create',
  READ: 'users.read', 
  UPDATE: 'users.update',
  DELETE: 'users.delete',
  MANAGE: 'users.manage'
} as const;

export const TEAM_PERMISSIONS = {
  INVITE: 'team.invite',
  REMOVE: 'team.remove', 
  MANAGE: 'team.manage',
  ROLES: 'team.roles'
} as const;

// Administrative
export const ADMIN_PERMISSIONS = {
  ACCESS: 'admin.access',
  USERS: 'admin.users',
  SYSTEM: 'admin.system', 
  SETTINGS: 'admin.settings'
} as const;

export const SYSTEM_PERMISSIONS = {
  ADMIN: 'system.admin',
  MAINTENANCE: 'system.maintenance',
  ACCOUNTS: 'accounts.manage'
} as const;

// Content & Resources
export const CONTENT_PERMISSIONS = {
  PAGES_CREATE: 'pages.create',
  PAGES_UPDATE: 'pages.update',
  PAGES_DELETE: 'pages.delete',
  CONTENT_MANAGE: 'content.manage'
} as const;

export const INFRASTRUCTURE_PERMISSIONS = {
  WORKERS_READ: 'workers.read',
  WORKERS_CREATE: 'workers.create', 
  WORKERS_MANAGE: 'workers.manage',
  VOLUMES_READ: 'volumes.read',
  VOLUMES_MANAGE: 'volumes.manage'
} as const;

// Business Operations
export const BILLING_PERMISSIONS = {
  READ: 'billing.read',
  UPDATE: 'billing.update',
  MANAGE: 'billing.manage',
  INVOICES: 'invoices.create',
  PAYMENTS: 'payments.process'
} as const;

export const ANALYTICS_PERMISSIONS = {
  READ: 'analytics.read',
  EXPORT: 'analytics.export', 
  REPORTS_GENERATE: 'reports.generate',
  REPORTS_DOWNLOAD: 'reports.download'
} as const;

// Utility type for all permissions
export type Permission = 
  | typeof USER_PERMISSIONS[keyof typeof USER_PERMISSIONS]
  | typeof TEAM_PERMISSIONS[keyof typeof TEAM_PERMISSIONS]
  | typeof ADMIN_PERMISSIONS[keyof typeof ADMIN_PERMISSIONS]
  | typeof SYSTEM_PERMISSIONS[keyof typeof SYSTEM_PERMISSIONS]
  | typeof CONTENT_PERMISSIONS[keyof typeof CONTENT_PERMISSIONS]
  | typeof INFRASTRUCTURE_PERMISSIONS[keyof typeof INFRASTRUCTURE_PERMISSIONS]
  | typeof BILLING_PERMISSIONS[keyof typeof BILLING_PERMISSIONS]
  | typeof ANALYTICS_PERMISSIONS[keyof typeof ANALYTICS_PERMISSIONS];
```

## ✅ **Phase 1 Validation Checklist**

### Backend Validation
- [ ] `ROLE_PERMISSIONS` mapping created and comprehensive
- [ ] User serialization includes `permissions` array
- [ ] API responses include permissions in user objects
- [ ] Authentication endpoints return permissions
- [ ] All role assignments properly map to permissions

### Frontend Validation  
- [ ] `User` interface updated with `permissions: string[]`
- [ ] Auth state properly typed with new User interface
- [ ] Permission constants file created and comprehensive
- [ ] TypeScript compilation succeeds without errors

### Integration Testing
- [ ] Login response includes permissions array
- [ ] User objects throughout app include permissions
- [ ] Backend role changes reflect in frontend permissions
- [ ] Permission arrays are correctly populated

### Audit Progress
Run audit script to verify:
```bash
./scripts/audit-role-access-control.sh
```

**Expected after Phase 1**: 
- Same number of role-based patterns (20) - not changed yet
- Permission infrastructure in place for Phase 2 migration
- All API responses include permissions array

## 🔄 **Phase 1 Completion Criteria**

1. ✅ **Backend Permission System**: Complete role-to-permission mapping implemented
2. ✅ **API Enhancement**: All user responses include permissions array  
3. ✅ **Frontend Types**: User interface updated with permissions field
4. ✅ **Constants**: Permission constants available for frontend use
5. ✅ **Testing**: No regressions in existing functionality
6. ✅ **Documentation**: Permission system documented for developers

**Ready for Phase 2**: Core utility function migration (usePermissions, permissionUtils)

---

**Estimated Effort**: 8-12 hours for experienced developer
**Risk Level**: Low - additive changes, no breaking modifications
**Dependencies**: None - pure infrastructure enhancement