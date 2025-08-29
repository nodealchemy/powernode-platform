# Permission-Based Access Control Migration Plan

## Executive Summary

This document outlines the migration from role-based access control (RBAC) to a comprehensive permission-based access control (PBAC) system for the Powernode platform. The migration will provide granular access control, better security, and more flexible user management.

## Current State Analysis

### Current Role System
- **Roles**: `admin`, `owner`, `member` (hardcoded in User model validation)
- **New Role Format**: `system.admin`, `account.manager` (partially implemented)
- **Permission Infrastructure**: Exists but underutilized (Permission, Role, RolePermission models)

### Current Issues
1. **Hardcoded Role Checks**: 63+ files using role-based access (`role == 'admin'`, `.admin?`, `.owner?`)
2. **Inconsistent Patterns**: Mix of old roles (`admin`) and new format (`system.admin`)
3. **Limited Granularity**: Binary admin/non-admin access for most features
4. **Frontend/Backend Mismatch**: Frontend uses permissions arrays, backend uses role checks

### Existing Infrastructure ✅
- ✅ `Permission` model with `resource.action` format
- ✅ `Role` model with many-to-many permissions
- ✅ `RolePermission` join table
- ✅ User permission checking methods (`has_permission?`, `all_permissions`)
- ✅ Controller helper methods (`require_permission`)
- ✅ Frontend permission arrays in navigation

## Migration Strategy

### Phase 1: Foundation & Standards (Week 1-2)
**Goal**: Establish permission standards and update core infrastructure

#### Backend Tasks
1. **Define Permission Matrix**
   ```ruby
   # Standard permissions format: resource.action
   PERMISSIONS = {
     'users' => ['create', 'read', 'update', 'delete', 'suspend', 'impersonate'],
     'accounts' => ['create', 'read', 'update', 'delete', 'manage'],
     'billing' => ['read', 'update', 'manage', 'export'],
     'analytics' => ['read', 'export', 'manage'],
     'system' => ['admin', 'settings', 'workers', 'maintenance'],
     'audit_logs' => ['read', 'export', 'manage'],
     'webhooks' => ['create', 'read', 'update', 'delete', 'manage'],
     'api_keys' => ['create', 'read', 'update', 'delete'],
     'plans' => ['create', 'read', 'update', 'delete', 'manage'],
     'reports' => ['create', 'read', 'export', 'schedule'],
     'pages' => ['create', 'read', 'update', 'delete', 'publish'],
     'payments' => ['read', 'process', 'refund', 'manage']
   }
   ```

2. **Update Role Definitions**
   ```ruby
   # New standardized roles with explicit permissions
   STANDARD_ROLES = {
     'system.admin' => ['system.*', 'accounts.*', 'users.*', 'billing.*', 'analytics.*'],
     'account.manager' => ['accounts.manage', 'users.*', 'billing.read', 'analytics.read'],
     'account.member' => ['users.read', 'billing.read', 'analytics.read'],
     'billing.manager' => ['billing.*', 'payments.*', 'plans.read'],
     'support.agent' => ['users.read', 'users.suspend', 'accounts.read', 'audit_logs.read'],
     'content_manager' => ['pages.*', 'reports.create', 'reports.read'],
     'analytics.viewer' => ['analytics.read', 'reports.read', 'reports.export']
   }
   ```

3. **Create Migration Infrastructure**
   ```ruby
   # db/migrate/add_permission_migration_support.rb
   class AddPermissionMigrationSupport < ActiveRecord::Migration[7.1]
     def change
       # Track migration status
       add_column :users, :migrated_to_permissions, :boolean, default: false
       add_column :roles, :migration_source_role, :string # Track original role
       
       # Add indexes for performance
       add_index :role_permissions, [:role_id, :permission_id], unique: true
       add_index :permissions, [:resource, :action], unique: true
     end
   end
   ```

4. **Create Permission Seeder**
   ```ruby
   # db/seeds/permissions.rb
   class PermissionSeeder
     def self.seed
       # Create all permissions from matrix
       # Create standard roles with permissions
       # Migrate existing users to new roles
     end
   end
   ```

#### Frontend Tasks
1. **Standardize Permission Checking Hook**
   ```typescript
   // hooks/usePermissions.ts
   export const usePermissions = () => {
     const { user } = useSelector((state: RootState) => state.auth);
     
     const hasPermission = (permission: string): boolean => {
       return user?.permissions?.includes(permission) || false;
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

2. **Update ProtectedRoute Component**
   ```typescript
   // Support both role and permission checking during transition
   interface ProtectedRouteProps {
     requiredPermissions?: string[];
     requiredRoles?: string[]; // Deprecated, for backward compatibility
     fallbackToRoles?: boolean; // During migration period
   }
   ```

### Phase 2: Backend Migration (Week 3-4)
**Goal**: Replace all role checks with permission checks in backend

#### Controller Migration Pattern
```ruby
# Before (role-based)
before_action :require_admin!

# After (permission-based)
before_action :require_permissions, only: [:index, :show]
before_action :require_permissions, only: [:create, :update, :destroy]

private

def require_permissions
  case action_name
  when 'index', 'show'
    require_permission('users.read')
  when 'create'
    require_permission('users.create')
  when 'update'
    require_permission('users.update')
  when 'destroy'
    require_permission('users.delete')
  end
end
```

#### Service Migration Pattern
```ruby
# Before
def can_manage_billing?
  user.admin? || user.owner?
end

# After
def can_manage_billing?
  user.has_permission?('billing.manage')
end
```

#### Model Migration Pattern
```ruby
# Before
def viewable_by?(user)
  user.admin? || user.owner? || user.id == self.user_id
end

# After
def viewable_by?(user)
  user.has_permission?('analytics.read') || user.id == self.user_id
end
```

### Phase 3: Frontend Migration (Week 5-6)
**Goal**: Replace all role checks with permission checks in frontend

#### Navigation Migration
```typescript
// Before
roles: ['admin', 'manager']

// After
permissions: ['users.read', 'users.create']
```

#### Component Migration Pattern
```typescript
// Before
const canManageUsers = user?.role === 'admin' || user?.role === 'owner';

// After
const { hasPermission } = usePermissions();
const canManageUsers = hasPermission('users.manage');
```

#### Page Action Migration
```typescript
// Before
{
  id: 'create-user',
  permission: 'admin', // Role check
}

// After
{
  id: 'create-user',
  requiredPermissions: ['users.create'], // Permission check
}
```

### Phase 4: Testing & Validation (Week 7)
**Goal**: Comprehensive testing and validation of permission system

#### Test Strategy
1. **Permission Matrix Tests**
   ```ruby
   RSpec.describe 'Permission System' do
     it 'enforces correct permissions for each role' do
       STANDARD_ROLES.each do |role_name, permissions|
         user = create(:user, role: role_name)
         permissions.each do |permission|
           expect(user.has_permission?(permission)).to be_truthy
         end
       end
     end
   end
   ```

2. **Controller Permission Tests**
   ```ruby
   RSpec.describe Api::V1::UsersController do
     describe 'GET #index' do
       it 'requires users.read permission' do
         user = create(:user) # No permissions
         sign_in(user)
         get :index
         expect(response).to have_http_status(:forbidden)
       end
     end
   end
   ```

3. **Frontend Permission Tests**
   ```typescript
   describe('usePermissions', () => {
     it('correctly checks user permissions', () => {
       const user = { permissions: ['users.read', 'billing.read'] };
       const { result } = renderHook(() => usePermissions(), {
         wrapper: ({ children }) => (
           <Provider store={mockStore({ auth: { user } })}>
             {children}
           </Provider>
         )
       });
       
       expect(result.current.hasPermission('users.read')).toBe(true);
       expect(result.current.hasPermission('users.delete')).toBe(false);
     });
   });
   ```

### Phase 5: Cleanup & Optimization (Week 8)
**Goal**: Remove deprecated role checks and optimize permission system

#### Cleanup Tasks
1. **Remove Deprecated Methods**
   ```ruby
   # Remove from User model
   # def admin? ... end
   # def owner? ... end
   # def member? ... end
   ```

2. **Update Database Constraints**
   ```ruby
   # Remove old role validation
   # validates :role, inclusion: { in: %w[admin owner member] }
   
   # Add new role validation
   validates :role, presence: true
   validate :role_exists_in_system
   ```

3. **Remove Legacy Frontend Code**
   ```typescript
   // Remove role-based checks
   // const isAdmin = user?.role === 'admin';
   // roles: ['admin', 'manager']
   ```

## Implementation Details

### Permission Naming Convention
```
Format: resource.action
Examples:
- users.create
- users.read
- users.update
- users.delete
- users.suspend
- users.impersonate
- billing.read
- billing.manage
- system.admin
- analytics.export
```

### Role Definition Standard
```ruby
class StandardRoles
  ROLES = {
    # System Level
    'system.admin' => {
      description: 'Full system administration access',
      permissions: ['system.*']
    },
    
    # Account Level
    'account.manager' => {
      description: 'Full account management access',
      permissions: ['accounts.manage', 'users.*', 'billing.read', 'analytics.read']
    },
    
    'account.member' => {
      description: 'Basic account member access',
      permissions: ['users.read', 'billing.read', 'analytics.read']
    },
    
    # Specialized Roles
    'billing.manager' => {
      description: 'Billing and payment management',
      permissions: ['billing.*', 'payments.*', 'plans.read']
    },
    
    'support.agent' => {
      description: 'Customer support access',
      permissions: ['users.read', 'users.suspend', 'accounts.read', 'audit_logs.read']
    }
  }
end
```

### Migration Utilities
```ruby
class PermissionMigrationService
  def self.migrate_user_roles
    User.where(migrated_to_permissions: false).find_each do |user|
      new_role = map_old_role_to_new(user.role)
      user.update!(role: new_role, migrated_to_permissions: true)
    end
  end
  
  private
  
  def self.map_old_role_to_new(old_role)
    case old_role
    when 'admin' then 'system.admin'
    when 'owner' then 'account.manager'
    when 'member' then 'account.member'
    else old_role # Already in new format
    end
  end
end
```

## Risk Mitigation

### Backward Compatibility
- Keep role-based methods during transition period
- Use feature flags to toggle between systems
- Gradual rollout with ability to rollback

### Data Safety
- Database backups before migration
- Rollback procedures for each phase
- Permission validation before deployment

### Security Considerations
- Default to most restrictive permissions
- Audit all permission changes
- Monitor for privilege escalation

## Success Metrics

### Technical Metrics
- Zero role-based checks in codebase
- 100% permission coverage for all features
- Performance: <50ms for permission checks
- Test coverage: >95% for permission logic

### Business Metrics
- Reduced security incidents
- Faster user onboarding with granular roles
- Improved compliance reporting
- Enhanced audit capabilities

## Timeline

| Phase | Duration | Key Deliverables |
|-------|----------|------------------|
| Phase 1 | Week 1-2 | Permission matrix, infrastructure, standards |
| Phase 2 | Week 3-4 | Backend migration complete |
| Phase 3 | Week 5-6 | Frontend migration complete |
| Phase 4 | Week 7 | Testing and validation |
| Phase 5 | Week 8 | Cleanup and optimization |

## Rollback Plan

### Phase Rollback Procedures
1. **Database Rollback**: Revert migrations, restore role-based checks
2. **Code Rollback**: Feature flags to disable permission system
3. **User Impact**: Zero downtime rollback capability

### Emergency Procedures
- Immediate role-based fallback for critical functions
- Emergency admin access bypass
- Audit trail of all rollback actions

---

*This migration plan ensures a smooth transition from role-based to permission-based access control while maintaining security, performance, and user experience.*