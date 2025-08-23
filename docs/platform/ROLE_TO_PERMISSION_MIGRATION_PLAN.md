# Role-Based to Permission-Based Access Control Migration Plan

## 🎯 **Migration Objective**
Completely eliminate role-based access control from frontend and replace with permission-based access control. Backend role system remains for permission assignment only.

## 📊 **Current State Audit Results**

### Frontend Issues Found
- **43 existing permission-based checks** - Good foundation
- **11 files** with role-based access patterns requiring migration
- **Critical files** with hardcoded role checks identified

### Files Requiring Migration

#### High Priority Frontend Files
1. `frontend/src/shared/components/layout/Header.tsx` - Admin access check
2. `frontend/src/features/admin/components/users/SystemUserManagement.tsx` - User filtering by role
3. `frontend/src/features/admin/components/SystemUserManagement.tsx` - Duplicate patterns
4. `frontend/src/shared/hooks/usePermissions.ts` - Role-based utility functions
5. `frontend/src/shared/utils/permissionUtils.ts` - Mixed role/permission logic
6. `frontend/src/pages/app/UsersPage.tsx` - User management access
7. `frontend/src/pages/admin/AdminUsersPage.tsx` - Admin user management
8. `frontend/src/pages/admin/workers/WorkersPage.tsx` - Worker management

#### Medium Priority Frontend Files
9. `frontend/src/features/account/components/InviteTeamMemberModal.tsx` - Role selection forms
10. `frontend/src/features/roles/components/RoleUsersModal.tsx` - Role display logic

#### Low Priority (Display Only)
11. `frontend/src/features/account/components/TeamMembersManagement.tsx` - Already migrated ✅

### Backend Controller Issues
- **Authentication concern** uses `has_role?` methods
- **Admin controllers** check user roles directly
- **Permission validation** mixed with role checks

## 🗺️ **Migration Strategy**

### Phase 1: Permission Mapping (Week 1)
**Define comprehensive permission system based on current role usage**

#### 1.1 Create Permission Categories
```typescript
// User & Team Management
'users.read', 'users.create', 'users.update', 'users.delete', 'users.manage'
'team.invite', 'team.remove', 'team.manage'

// Admin & System Management  
'admin.access', 'admin.users', 'admin.system'
'system.admin', 'system.maintenance'

// Content Management
'pages.create', 'pages.update', 'pages.delete'
'content.manage', 'content.publish'

// Analytics & Reports
'analytics.read', 'analytics.export'
'reports.generate', 'reports.download'

// Billing & Payments
'billing.read', 'billing.update', 'billing.manage'
'invoices.create', 'payments.process'

// Workers & Infrastructure
'workers.read', 'workers.create', 'workers.manage'
'volumes.read', 'volumes.manage'
```

#### 1.2 Map Existing Roles to Permissions
```ruby
# Backend role -> permission mapping
system.admin -> [all permissions]
account.manager -> [users.*, team.*, billing.*, analytics.read, reports.*]
account.member -> [users.read, analytics.read, content.create]
billing.manager -> [billing.*, invoices.*, payments.*]
```

### Phase 2: Backend Permission Infrastructure (Week 1-2)
**Ensure backend properly assigns permissions based on roles**

#### 2.1 Update User Model Methods ✅ (Completed)
- [x] `has_permission?(permission_name)` method exists
- [x] `all_permissions` method exists  
- [x] Role-based permission assignment working

#### 2.2 Update Controllers to Use Permissions
```ruby
# Replace this pattern:
require_role('admin')

# With this pattern:  
require_permission('admin.access')
```

#### 2.3 Update API Responses
```ruby
# Ensure user serialization includes permissions
def user_data(user)
  {
    id: user.id,
    email: user.email,
    roles: user.role_names,           # Keep for display
    permissions: user.all_permissions.pluck(:name)  # Add for access control
  }
end
```

### Phase 3: Frontend Utility Migration (Week 2)
**Create permission-based utility functions**

#### 3.1 Update `usePermissions` Hook
```typescript
// Replace role-based methods with permission-based
export const usePermissions = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  
  return {
    hasPermission: (permission: string) => user?.permissions?.includes(permission) ?? false,
    hasAnyPermission: (permissions: string[]) => permissions.some(p => user?.permissions?.includes(p)),
    // Remove hasRole, hasAnyRole methods
  };
};
```

#### 3.2 Update `permissionUtils.ts`
```typescript
// Remove role-based functions, keep only permission-based
export const hasPermissions = (user: User | null, permissions: string[]): boolean => {
  if (!user?.permissions) return false;
  return permissions.every(permission => user.permissions.includes(permission));
};
```

### Phase 4: Critical Component Migration (Week 2-3)
**High-impact components affecting navigation and core functionality**

#### 4.1 Header.tsx Migration
```typescript
// Current (role-based):
const hasAdminAccess = user?.role === 'manager' || user?.role === 'admin';

// Target (permission-based):
const hasAdminAccess = user?.permissions?.includes('admin.access');
```

#### 4.2 SystemUserManagement.tsx Migration
```typescript
// Current (role-based filtering):
if (filters.role && user.role !== filters.role) return false;
users.filter(u => u.role === 'admin' || u.role === 'manager').length

// Target (permission-based display):
// Keep role display for UI, use permissions for access control
const canManageUsers = currentUser?.permissions?.includes('users.manage');
```

#### 4.3 Navigation & Menu Systems
- Update all menu visibility checks to use permissions
- Replace role-based route guards with permission guards

### Phase 5: Admin & Management Pages (Week 3-4)
**Admin interfaces and user management systems**

#### 5.1 AdminUsersPage.tsx
- Replace role-based user filtering with permission-based access control
- Keep role display for informational purposes
- Update bulk operations permissions

#### 5.2 WorkersPage.tsx  
- Update worker management access checks
- Replace permission filter role checks with proper permission validation

#### 5.3 UsersPage.tsx
- Update user management interface
- Replace role-based feature access with permissions

### Phase 6: Form & Modal Migration (Week 4)
**User-facing forms and role selection interfaces**

#### 6.1 InviteTeamMemberModal.tsx
- Keep role selection for backend assignment
- Update form validation to check user permissions for inviting
- Update available role options based on current user permissions

#### 6.2 Role Management Components  
- Update RoleUsersModal to show roles for display only
- Access control based on permissions not roles

### Phase 7: Testing & Validation (Week 4-5)
**Comprehensive testing of permission-based system**

#### 7.1 Automated Testing
```bash
# Permission-based audit commands
grep -r "\.roles\?\.includes\|\.role.*==\|\.role.*!=" frontend/src/ | grep -v "display\|format\|badge\|map"
grep -r "currentUser.*roles\?\." frontend/src/ | grep -v "display\|format"
grep -r "user.*roles.*admin\|user.*role.*manager" frontend/src/ | grep -v "display\|format"
grep -r "permissions.*includes" frontend/src/ | wc -l  # Should increase significantly
```

#### 7.2 Manual Testing Scenarios
- [ ] Login as different role types and verify access
- [ ] Test admin panel access with permission-based checks
- [ ] Verify user management operations work correctly  
- [ ] Test navigation menu filtering
- [ ] Verify form validations use permissions

#### 7.3 Edge Case Testing
- [ ] Users with no permissions
- [ ] Users with mixed permissions
- [ ] Permission changes requiring logout/login
- [ ] API error handling for permission failures

## 📋 **Migration Checklist**

### Week 1: Foundation & Planning
- [ ] Create comprehensive permission mapping
- [ ] Update backend permission assignment
- [ ] Verify API responses include permissions array
- [ ] Create migration utility functions

### Week 2: Core Infrastructure  
- [ ] Migrate usePermissions hook
- [ ] Update permissionUtils completely
- [ ] Migrate Header.tsx admin access
- [ ] Update authentication guards

### Week 3: Major Components
- [ ] Migrate SystemUserManagement.tsx
- [ ] Update AdminUsersPage.tsx  
- [ ] Migrate UsersPage.tsx
- [ ] Update navigation components

### Week 4: Forms & Final Components
- [ ] Migrate WorkersPage.tsx
- [ ] Update InviteTeamMemberModal.tsx
- [ ] Migrate remaining role components
- [ ] Update all form validations

### Week 5: Testing & Validation
- [ ] Run automated audit commands
- [ ] Execute manual test scenarios
- [ ] Fix any discovered issues
- [ ] Performance testing
- [ ] Security validation

## 🚨 **Critical Success Factors**

### Must Have
1. **Zero role-based access control** in frontend code
2. **100% permission-based** access decisions
3. **Backward compatibility** during migration
4. **No security regressions** during transition
5. **Comprehensive test coverage**

### Risk Mitigation
- **Feature flags** for gradual rollout
- **Rollback plan** for each migration phase
- **Monitoring** for permission failures
- **User communication** about potential access changes

## 📊 **Success Metrics**

### Technical Metrics
- **0 role-based access checks** in frontend audit
- **100+ permission-based checks** (target: 80+ current 43)
- **All critical paths** use permission validation
- **Zero test failures** after migration

### User Experience Metrics
- **No downtime** during migration
- **Same functionality** post-migration
- **Improved access control granularity**
- **Better error messages** for access denied scenarios

## 🔄 **Post-Migration Maintenance**

### Ongoing Requirements
1. **New features** must use permission-based access control only
2. **Code reviews** must check for role-based access patterns  
3. **Automated linting** to prevent role-based access code
4. **Regular audits** using provided commands
5. **Developer training** on permission-based patterns

### Long-term Benefits
- **Granular access control** beyond simple role hierarchies
- **Dynamic permission assignment** without role changes
- **Better security** through principle of least privilege
- **Easier compliance** with access control requirements
- **More flexible user management**

---

**Next Steps**: Begin Phase 1 permission mapping and backend infrastructure validation.