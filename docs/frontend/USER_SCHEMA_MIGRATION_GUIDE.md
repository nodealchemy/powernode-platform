# User Schema Migration Guide - Frontend Updates

## Overview

**Context**: Backend migration `20250926073024_consolidate_user_name_fields.rb` consolidated User model from `first_name`/`last_name` to a single `name` field.

**Current Status**:
- ✅ Backend: Using `name` field (consolidated)
- ❌ Frontend: Still using `first_name`/`last_name` (131 references, 62+ TypeScript errors)

**Impact**: 62+ TypeScript errors across 27 files

## Updated User Type Definition

**Location**: `src/shared/services/slices/authSlice.ts`

```typescript
export interface User {
  id: string;
  email: string;
  name: string;              // ✅ PRIMARY field - full name
  full_name?: string;        // ✅ OPTIONAL - backend may return this
  // ❌ first_name - REMOVED
  // ❌ last_name - REMOVED
  roles: string[];
  permissions?: string[];
  status: string;
  email_verified: boolean;
  account: { id: string; name: string; };
}
```

## Migration Patterns

### Pattern 1: Simple Display (JSX)

**❌ Before**:
```tsx
<div>{user.first_name} {user.last_name}</div>
```

**✅ After**:
```tsx
<div>{user.name}</div>
```

**Files Affected**: 40+ instances
- `UserMenu.tsx`
- `SystemUserManagement.tsx`
- `ImpersonationBanner.tsx`
- Many others

---

### Pattern 2: Avatar Initials

**❌ Before**:
```tsx
// Get initials from first and last name
const getInitials = () => {
  if (!user?.first_name || !user?.last_name) return 'U';
  return `${user.first_name[0]}${user.last_name[0]}`.toUpperCase();
};

// Or inline:
<Avatar>{user.first_name?.[0]}{user.last_name?.[0]}</Avatar>
```

**✅ After**:
```tsx
// Get initials from full name
const getInitials = () => {
  if (!user?.name) return 'U';
  const parts = user.name.split(' ');
  if (parts.length === 1) return parts[0][0].toUpperCase();
  return `${parts[0][0]}${parts[parts.length - 1][0]}`.toUpperCase();
};

// Or use utility function:
import { getUserInitials } from '@/shared/utils/userUtils';
<Avatar>{getUserInitials(user)}</Avatar>
```

**Files Affected**: 8+ instances
- `UserMenu.tsx` (line 37-38)
- `SystemUserManagement.tsx` (line 295, 300)

**New Utility** (create if doesn't exist):
```typescript
// src/shared/utils/userUtils.ts
export const getUserInitials = (user?: { name?: string }): string => {
  if (!user?.name) return 'U';
  const parts = user.name.trim().split(/\s+/);
  if (parts.length === 1) return parts[0][0].toUpperCase();
  return `${parts[0][0]}${parts[parts.length - 1][0]}`.toUpperCase();
};

export const getFirstName = (user?: { name?: string }): string => {
  return user?.name?.split(' ')[0] || '';
};

export const getLastName = (user?: { name?: string }): string => {
  const parts = user?.name?.split(' ') || [];
  return parts.length > 1 ? parts[parts.length - 1] : '';
};
```

---

### Pattern 3: Form Inputs (Create/Edit User)

**❌ Before**:
```tsx
interface UserFormData {
  first_name: string;
  last_name: string;
  email: string;
}

const [formData, setFormData] = useState<UserFormData>({
  first_name: '',
  last_name: '',
  email: ''
});

<Input
  label="First Name"
  name="first_name"
  value={formData.first_name}
  onChange={(e) => handleInputChange('first_name', e.target.value)}
/>
<Input
  label="Last Name"
  name="last_name"
  value={formData.last_name}
  onChange={(e) => handleInputChange('last_name', e.target.value)}
/>
```

**✅ After**:
```tsx
interface UserFormData {
  name: string;  // Full name
  email: string;
}

const [formData, setFormData] = useState<UserFormData>({
  name: '',
  email: ''
});

<Input
  label="Full Name"
  name="name"
  placeholder="John Doe"
  value={formData.name}
  onChange={(e) => handleInputChange('name', e.target.value)}
/>
```

**Files Affected**: 6+ instances
- `CreateUserModal.tsx` (lines 18-19, 79-80, 100-101, 170-171, 183-184)
- `AcceptInvitationPage.tsx`
- `RegisterPage.tsx`

**Note**: Backend API now expects `{ name: "John Doe" }` instead of `{ first_name: "John", last_name: "Doe" }`

---

### Pattern 4: API Request/Response Mapping

**❌ Before**:
```typescript
// API request
const createUser = async (userData: {
  first_name: string;
  last_name: string;
  email: string;
}) => {
  return api.post('/users', userData);
};

// API response mapping
const user = {
  ...response.data,
  full_name: `${response.data.first_name} ${response.data.last_name}`
};
```

**✅ After**:
```typescript
// API request
const createUser = async (userData: {
  name: string;  // Full name
  email: string;
}) => {
  return api.post('/users', userData);
};

// API response - backend already returns 'name'
const user = response.data;  // Already has 'name' field
```

**Files Affected**: 10+ instances
- `pagesApi.ts`
- `delegationApi.ts`
- `adminSettingsApi.ts`
- `customersApi.ts`
- `invitationsApi.ts`

---

### Pattern 5: Conditional Logic

**❌ Before**:
```tsx
if (!user?.first_name || !user?.last_name) {
  return <div>Incomplete profile</div>;
}

const isValid = user.first_name?.trim() && user.last_name?.trim();
```

**✅ After**:
```tsx
if (!user?.name) {
  return <div>Incomplete profile</div>;
}

const isValid = user.name?.trim();
```

---

### Pattern 6: Search/Filter Logic

**❌ Before**:
```tsx
const filteredUsers = users.filter(user =>
  user.first_name.toLowerCase().includes(searchTerm.toLowerCase()) ||
  user.last_name.toLowerCase().includes(searchTerm.toLowerCase())
);
```

**✅ After**:
```tsx
const filteredUsers = users.filter(user =>
  user.name.toLowerCase().includes(searchTerm.toLowerCase())
);
```

---

### Pattern 7: Table Columns/Display Lists

**❌ Before**:
```tsx
const columns = [
  { key: 'first_name', label: 'First Name' },
  { key: 'last_name', label: 'Last Name' },
  { key: 'email', label: 'Email' }
];

// Or
<td>{user.first_name}</td>
<td>{user.last_name}</td>
```

**✅ After**:
```tsx
const columns = [
  { key: 'name', label: 'Name' },
  { key: 'email', label: 'Email' }
];

// Or
<td>{user.name}</td>
```

---

## File-by-File Migration Checklist

### High Priority (Direct User Type Access - TypeScript Errors)

1. **features/account/components/TeamMembersManagement.tsx** (6 errors)
   - Lines 163, 168, 252: Display patterns
   - Fix: `{member.first_name} {member.last_name}` → `{member.name}`

2. **features/admin/components/ImpersonationBanner.tsx** (2 errors)
   - Line 52: Display pattern
   - Fix: Template literal → `{user.name}`

3. **features/admin/components/users/ImpersonationBanner.tsx** (2 errors)
   - Line 46: Display pattern

4. **features/admin/components/users/SystemUserManagement.tsx** (12 errors)
   - Lines 295, 300: Initials pattern
   - Line 401: Display pattern
   - Fix: Create `getUserInitials()` utility

5. **features/admin/components/users/CreateUserModal.tsx** (10+ errors)
   - Lines 18-19, 79-80, 100-101: Form state
   - Lines 170-171, 183-184: Form inputs
   - Fix: Complete form refactor (Pattern 3)

6. **shared/components/navigation/UserMenu.tsx** (4 errors)
   - Lines 37-38: Initials check
   - Lines 72, 103: Display
   - Fix: Use `getUserInitials()` utility

7. **features/admin/components/UserManagement.tsx**
8. **pages/app/UsersPage.tsx**
9. **pages/app/business/CustomersPage.tsx**
10. **pages/app/admin/AdminUsersPage.tsx**

### Medium Priority (Form Data - No TypeScript Errors but Runtime Issues)

11. **pages/public/AcceptInvitationPage.tsx**
    - Form field refactor

12. **pages/public/RegisterPage.tsx**
    - Registration form refactor

13. **features/delegations/components/DelegationRequestModal.tsx**
14. **features/delegations/components/DelegationDetailsModal.tsx**

### Low Priority (API Layer - String Literals, Not Type Errors)

15. **features/pages/services/pagesApi.ts**
16. **features/delegations/services/delegationApi.ts**
17. **features/admin/services/adminSettingsApi.ts**
18. **shared/services/customersApi.ts**
19. **shared/services/invitationsApi.ts**

### Test Files (Fix After Production Code)

20. **shared/utils/test-utils.tsx**
21. **test-utils.tsx**

### Layout/UI Components

22. **shared/components/layout/Header.tsx**
23. **shared/components/layout/PublicPageContainer.tsx**
24. **shared/components/ai/AuthenticationCheck.tsx**
25. **shared/components/ai/AIPermissionsDebug.tsx**
26. **features/ai/components/AgentConversationComponent.tsx**
27. **pages/app/admin/AdminSettingsOverviewPage.tsx**

## Migration Strategy

### Phase 1: Create Utilities (15 min)
```bash
# Create utility functions
touch frontend/src/shared/utils/userUtils.ts
# Add getUserInitials, getFirstName, getLastName functions
```

### Phase 2: Fix High-Impact Display Components (1-2 hours)
1. UserMenu.tsx - Most visible (header component)
2. SystemUserManagement.tsx - Admin interface
3. TeamMembersManagement.tsx - Account management
4. ImpersonationBanner.tsx - Security critical

**Goal**: Fix 24+ TypeScript errors

### Phase 3: Fix Forms (2-3 hours)
1. CreateUserModal.tsx - Complex form refactor
2. AcceptInvitationPage.tsx - Registration flow
3. RegisterPage.tsx - New user signup

**Goal**: Fix 10+ TypeScript errors, prevent runtime bugs

### Phase 4: Fix API Layer (1-2 hours)
Update API request/response mappings in service files.

**Goal**: Clean up remaining references

### Phase 5: Testing & Verification (1 hour)
- Run full test suite
- Manual testing of user flows:
  - User creation
  - Profile display
  - User listing/search
  - Impersonation
- TypeScript verification: Should go from 62+ errors → 0 errors

## Testing Checklist

After each file fix:
```bash
# TypeScript check
npm run typecheck

# Run tests
npm test

# Check specific file
npm run typecheck -- --noEmit src/path/to/file.tsx
```

After all fixes:
- [ ] User creation flow works
- [ ] User profile displays correctly
- [ ] Avatar initials show correctly
- [ ] User search/filter works
- [ ] Impersonation displays target user correctly
- [ ] All TypeScript errors resolved
- [ ] All tests pass

## Rollback Plan

If issues arise:
```bash
# Revert specific file
git checkout HEAD -- frontend/src/path/to/file.tsx

# Revert all changes
git checkout HEAD -- frontend/src/
```

## Success Metrics

**Before**:
- TypeScript errors: 62+
- Code references: 131
- Affected files: 27

**After** (Target):
- TypeScript errors: 0
- Code references: 0 (all migrated to 'name')
- Tests passing: 100%
- User flows: All functional

## Common Pitfalls

1. **Forgetting Backend Change**: Backend expects `{ name }`, not `{ first_name, last_name }`
2. **Initials Logic**: Need to handle single-word names gracefully
3. **Empty Names**: Always check `if (!user?.name)` before accessing
4. **Form Validation**: Update validation rules to check `name` field
5. **Test Fixtures**: Update test data to use `name` instead of `first_name`/`last_name`

## Questions & Answers

**Q**: What if user only has one name (no space)?
**A**: `getUserInitials()` handles this - uses first character twice or shows single letter

**Q**: Do we need to support splitting name back to first/last?
**A**: Only for display purposes (e.g., "First name: John"). Use utility functions.

**Q**: What about legacy data with first_name/last_name in backend?
**A**: Backend migration already handled this - all data consolidated to `name` field

**Q**: Should we keep backward compatibility?
**A**: No - backend no longer returns these fields, so frontend must update

## Related Documentation

- Backend Migration: `server/db/migrate/20250926073024_consolidate_user_name_fields.rb`
- TypeScript Health Report: `docs/frontend/TYPESCRIPT_HEALTH_REPORT_2025_01_29.md`
- User Type Definition: `frontend/src/shared/services/slices/authSlice.ts`

---

**Last Updated**: January 29, 2025
**Status**: Ready for implementation
**Estimated Effort**: 4-6 hours total
**Expected Impact**: Fixes 62+ TypeScript errors, prevents runtime bugs
