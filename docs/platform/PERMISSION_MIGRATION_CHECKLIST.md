# Permission Migration Implementation Checklist

## Pre-Migration Audit

### Current State Analysis ✅
- [x] Identified 63+ files using role-based access control
- [x] Confirmed existing Permission/Role infrastructure
- [x] Documented current role patterns (`admin`, `owner`, `member` vs `system.admin`, `account.manager`)
- [x] Identified mixed frontend/backend permission patterns

### Files Requiring Migration

#### Backend Controllers (18 files)
- [ ] `/server/app/controllers/api/v1/admin/users_controller.rb` (✅ Partially migrated)
- [ ] `/server/app/controllers/api/v1/admin/workers_controller.rb`
- [ ] `/server/app/controllers/api/v1/admin_settings_controller.rb`
- [ ] `/server/app/controllers/api/v1/audit_logs_controller.rb`
- [ ] `/server/app/controllers/api/v1/customers_controller.rb`
- [ ] `/server/app/controllers/api/v1/delegations_controller.rb`
- [ ] `/server/app/controllers/api/v1/email_settings_controller.rb`
- [ ] `/server/app/controllers/api/v1/impersonations_controller.rb`
- [ ] `/server/app/controllers/api/v1/payment_gateways_controller.rb`
- [ ] `/server/app/controllers/api/v1/plans_controller.rb`
- [ ] `/server/app/controllers/api/v1/webhooks_controller.rb`
- [ ] `/server/app/controllers/api/v1/api_keys_controller.rb`
- [ ] `/server/app/controllers/concerns/authentication.rb`

#### Backend Models (8 files)
- [ ] `/server/app/models/user.rb` (Update role validation)
- [ ] `/server/app/models/account.rb`
- [ ] `/server/app/models/audit_log.rb`
- [ ] `/server/app/models/impersonation_session.rb`
- [ ] `/server/app/models/invitation.rb`
- [ ] `/server/app/models/worker.rb`
- [ ] `/server/app/models/account_delegation.rb`

#### Backend Services (4 files)
- [ ] `/server/app/services/delegation_service.rb`
- [ ] `/server/app/services/impersonation_service.rb`
- [ ] `/server/app/services/audit_logging_service.rb`
- [ ] `/server/app/services/admin_settings_update_service.rb`

#### Frontend Components (12 files)
- [ ] `/frontend/src/shared/components/ui/ProtectedRoute.tsx` (✅ Partially migrated)
- [ ] `/frontend/src/shared/utils/navigation.tsx`
- [ ] `/frontend/src/features/account/components/PermissionSelector.tsx`
- [ ] `/frontend/src/features/account/components/TeamMembersManagement.tsx`
- [ ] `/frontend/src/features/account/components/InviteTeamMemberModal.tsx`
- [ ] `/frontend/src/features/admin/components/SystemUserManagement.tsx`
- [ ] `/frontend/src/shared/hooks/NavigationContext.tsx`
- [ ] `/frontend/src/shared/components/layout/Header.tsx`
- [ ] `/frontend/src/pages/admin/AdminUsersPage.tsx`
- [ ] `/frontend/src/pages/admin/workers/WorkersPage.tsx`
- [ ] `/frontend/src/pages/admin/AdminSettingsOverviewPage.tsx`

## Phase 1: Foundation & Standards (Week 1-2)

### Backend Infrastructure
- [ ] **Create Permission Matrix Service**
  ```ruby
  # app/services/permission_matrix_service.rb
  class PermissionMatrixService
    PERMISSIONS = { ... }
    STANDARD_ROLES = { ... }
  end
  ```

- [ ] **Create Migration Script**
  ```bash
  rails generate migration AddPermissionMigrationSupport
  ```
  
- [ ] **Seed Permissions and Roles**
  ```ruby
  # db/seeds/permissions.rb
  rake db:seed:permissions
  ```

- [ ] **Update User Model**
  ```ruby
  # Add new role validation
  # Remove hardcoded role constraints
  # Enhance permission checking methods
  ```

### Frontend Infrastructure  
- [ ] **Create usePermissions Hook**
  ```typescript
  # src/shared/hooks/usePermissions.ts
  export const usePermissions = () => { ... }
  ```

- [ ] **Update Auth Slice**
  ```typescript
  # Add permissions array to user state
  # Update login/user fetch to include permissions
  ```

- [ ] **Create Permission Helper Components**
  ```typescript
  # src/shared/components/PermissionGate.tsx
  # src/shared/components/PermissionGuard.tsx
  ```

### Documentation
- [ ] **API Documentation**
  - Permission endpoints documentation
  - Role management API docs
  - Migration procedure docs

## Phase 2: Backend Migration (Week 3-4)

### Controller Migration Priority

#### High Priority (Security Critical)
- [ ] **Admin Controllers**
  - [ ] `admin/users_controller.rb` (✅ Started)
  - [ ] `admin/workers_controller.rb`
  - [ ] `admin_settings_controller.rb`

- [ ] **Authentication & Authorization**
  - [ ] `concerns/authentication.rb`
  - [ ] `impersonations_controller.rb`

#### Medium Priority (Business Logic)
- [ ] **Financial Controllers**
  - [ ] `payment_gateways_controller.rb`
  - [ ] `plans_controller.rb`

- [ ] **User Management**
  - [ ] `customers_controller.rb`
  - [ ] `delegations_controller.rb`

#### Lower Priority (Operational)
- [ ] **System Features**
  - [ ] `audit_logs_controller.rb`
  - [ ] `webhooks_controller.rb`
  - [ ] `api_keys_controller.rb`
  - [ ] `email_settings_controller.rb`

### Migration Pattern Checklist

For each controller:
- [ ] **Replace `before_action :require_admin!`**
  ```ruby
  # Before
  before_action :require_admin!
  
  # After
  before_action :require_permission_for_action
  ```

- [ ] **Add permission checking method**
  ```ruby
  private
  
  def require_permission_for_action
    case action_name
    when 'index', 'show'
      require_permission('resource.read')
    when 'create'
      require_permission('resource.create')
    # etc.
    end
  end
  ```

- [ ] **Update role checks in actions**
  ```ruby
  # Before
  if current_user.admin?
  
  # After
  if current_user.has_permission?('specific.permission')
  ```

### Model Migration
- [ ] **User Model Updates**
  - [ ] Remove hardcoded role validation
  - [ ] Add role existence validation
  - [ ] Update role-based methods
  - [ ] Add permission caching

- [ ] **Other Models**
  - [ ] Replace role checks with permission checks
  - [ ] Update ownership/access methods
  - [ ] Add permission-based scopes

### Service Migration
- [ ] **Service Classes**
  - [ ] Replace role checks with permission checks
  - [ ] Update authorization logic
  - [ ] Add permission validation

## Phase 3: Frontend Migration (Week 5-6)

### Navigation System
- [ ] **Update Navigation Config**
  ```typescript
  // Replace roles with permissions
  roles: ['admin'] → permissions: ['users.read']
  ```

- [ ] **Update Navigation Context**
  ```typescript
  // Add permission checking logic
  // Remove role-based filtering
  ```

### Protected Routes
- [ ] **Update ProtectedRoute Component**
  ```typescript
  interface ProtectedRouteProps {
    requiredPermissions?: string[];
    children: React.ReactNode;
  }
  ```

- [ ] **Update Route Definitions**
  ```typescript
  // App.tsx route updates
  // Remove requireAdminRole
  // Add permission checks
  ```

### Component Migration

#### High Priority Components
- [ ] **AdminUsersPage**
  - [ ] Replace role checks with permission checks
  - [ ] Update action button permissions
  - [ ] Update user creation logic

- [ ] **Navigation Components**
  - [ ] Header.tsx
  - [ ] Sidebar navigation
  - [ ] User menu

#### Medium Priority Components
- [ ] **Account Management**
  - [ ] TeamMembersManagement.tsx
  - [ ] InviteTeamMemberModal.tsx
  - [ ] PermissionSelector.tsx

- [ ] **Admin Components**
  - [ ] SystemUserManagement.tsx
  - [ ] AdminSettingsOverviewPage.tsx
  - [ ] WorkersPage.tsx

### Page Action Updates
- [ ] **PageContainer Actions**
  ```typescript
  // Before
  permission: 'admin'
  
  // After
  requiredPermissions: ['resource.action']
  ```

## Phase 4: Testing & Validation (Week 7)

### Backend Testing
- [ ] **Permission System Tests**
  ```ruby
  # spec/models/permission_spec.rb
  # spec/models/role_spec.rb
  # spec/services/permission_matrix_service_spec.rb
  ```

- [ ] **Controller Permission Tests**
  ```ruby
  # Test each controller action requires correct permission
  # Test permission denied scenarios
  # Test edge cases
  ```

- [ ] **Integration Tests**
  ```ruby
  # End-to-end permission flows
  # Role assignment scenarios
  # Permission inheritance tests
  ```

### Frontend Testing
- [ ] **Permission Hook Tests**
  ```typescript
  # Test usePermissions hook
  # Test permission checking logic
  # Test edge cases
  ```

- [ ] **Component Permission Tests**
  ```typescript
  # Test ProtectedRoute with permissions
  # Test navigation permission filtering
  # Test action button permissions
  ```

- [ ] **Integration Tests**
  ```typescript
  # E2E permission flows
  # User journey tests
  # Permission UI tests
  ```

### Manual Testing Checklist
- [ ] **Admin User Flows**
  - [ ] System admin can access all features
  - [ ] Account manager has appropriate access
  - [ ] Permission denied works correctly

- [ ] **Regular User Flows**
  - [ ] Basic users can access allowed features
  - [ ] Users cannot access restricted features
  - [ ] Error messages are user-friendly

- [ ] **Edge Cases**
  - [ ] Users with no permissions
  - [ ] Users with custom roles
  - [ ] Permission changes take effect immediately

## Phase 5: Cleanup & Optimization (Week 8)

### Code Cleanup
- [ ] **Remove Deprecated Methods**
  ```ruby
  # User model
  # def admin? ... end
  # def owner? ... end
  # def member? ... end
  ```

- [ ] **Remove Legacy Constants**
  ```ruby
  # Remove hardcoded role arrays
  # Remove role-based validations
  ```

- [ ] **Clean Frontend Code**
  ```typescript
  // Remove role-based checks
  // Remove deprecated props
  ```

### Database Optimization
- [ ] **Add Performance Indexes**
  ```sql
  -- Permission lookup optimization
  -- Role permission joins
  -- User permission caching
  ```

- [ ] **Remove Migration Columns**
  ```ruby
  # Remove migrated_to_permissions column
  # Remove migration_source_role column
  ```

### Documentation Updates
- [ ] **API Documentation**
  - [ ] Update permission endpoints
  - [ ] Document new authentication patterns
  - [ ] Update example requests

- [ ] **Developer Documentation**
  - [ ] Permission checking guidelines
  - [ ] New role creation process
  - [ ] Testing patterns

## Validation Checklist

### Security Validation
- [ ] **No privilege escalation possible**
- [ ] **Default permissions are restrictive**
- [ ] **All sensitive actions require permissions**
- [ ] **Permission changes are audited**

### Performance Validation
- [ ] **Permission checks are cached**
- [ ] **Database queries are optimized**
- [ ] **Page load times unchanged**
- [ ] **API response times <50ms**

### User Experience Validation
- [ ] **Clear error messages for permission denied**
- [ ] **Intuitive permission descriptions**
- [ ] **Smooth user onboarding**
- [ ] **No broken functionality**

## Success Criteria

### Technical Success
- [ ] Zero role-based checks in codebase
- [ ] 100% permission coverage
- [ ] All tests passing
- [ ] Performance benchmarks met

### Business Success
- [ ] No user access issues
- [ ] Improved security audit results
- [ ] Faster user provisioning
- [ ] Enhanced compliance reporting

## Rollback Procedures

### Emergency Rollback
- [ ] **Feature Flag Disable**
  ```ruby
  # Disable permission system
  # Fall back to role-based checks
  ```

- [ ] **Database Rollback**
  ```bash
  # Restore user roles
  # Revert permission tables
  ```

### Staged Rollback
- [ ] **Phase-by-phase rollback**
- [ ] **Component-level rollback**
- [ ] **User-group rollback**

---

**Migration Status**: Planning Complete ✅ | Ready for Implementation

*Use this checklist to track progress and ensure nothing is missed during the migration to permission-based access control.*