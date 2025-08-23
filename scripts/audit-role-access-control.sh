#!/bin/bash

# Role-Based to Permission-Based Access Control Audit Script
# Run from project root: ./scripts/audit-role-access-control.sh

echo "🔍 ROLE-BASED ACCESS CONTROL AUDIT"
echo "================================="
echo

cd "$(dirname "$0")/.."

echo "📊 CURRENT STATE ANALYSIS"
echo "-------------------------"

echo "1. Role-based access patterns (should be 0 after migration):"
echo "   Frontend role checks:"
role_checks=$(grep -r "\.roles\?\.includes\|\.role.*==\|\.role.*!=" frontend/src/ 2>/dev/null | grep -v "member\.roles\?.*map\|formatRole\|getRoleColor\|roles.*map\|display\|format\|badge" | wc -l)
echo "   → Found: $role_checks instances"

echo "   CurrentUser role access:"  
user_role_access=$(grep -r "currentUser.*roles\?\." frontend/src/ 2>/dev/null | grep -v "member\.roles\|user\.roles.*map\|formatRole\|display\|format" | wc -l)
echo "   → Found: $user_role_access instances"

echo "   Hardcoded admin/manager checks:"
hardcoded_roles=$(grep -r "user.*roles.*admin\|user.*role.*manager" frontend/src/ 2>/dev/null | grep -v "display\|format\|badge\|map" | wc -l)
echo "   → Found: $hardcoded_roles instances"

echo
echo "2. Permission-based access patterns (should increase after migration):"
permission_checks=$(grep -r "permissions.*includes" frontend/src/ 2>/dev/null | wc -l)
echo "   → Found: $permission_checks instances"

echo
echo "🎯 FILES REQUIRING MIGRATION"
echo "----------------------------"

echo "HIGH PRIORITY - Critical access control:"
grep -l "\.role.*=\|\.roles.*includes\|hasRole\|user.*role.*admin\|user.*role.*manager" frontend/src/shared/components/layout/Header.tsx frontend/src/features/admin/components/users/SystemUserManagement.tsx frontend/src/features/admin/components/SystemUserManagement.tsx frontend/src/shared/hooks/usePermissions.ts frontend/src/shared/utils/permissionUtils.ts 2>/dev/null | head -5

echo
echo "MEDIUM PRIORITY - User management:"
grep -l "\.role.*=\|\.roles.*includes" frontend/src/pages/app/UsersPage.tsx frontend/src/pages/admin/AdminUsersPage.tsx frontend/src/pages/admin/workers/WorkersPage.tsx 2>/dev/null | head -3

echo
echo "LOW PRIORITY - Forms and modals:"
grep -l "\.role.*=\|role.*option" frontend/src/features/account/components/InviteTeamMemberModal.tsx frontend/src/features/roles/components/RoleUsersModal.tsx 2>/dev/null | head -2

echo
echo "🔍 DETAILED ROLE-BASED ACCESS PATTERNS"
echo "--------------------------------------"

echo "Role-based access control patterns found:"
echo "(These should all be converted to permission-based)"
echo
grep -r "\.roles\?\.includes\|\.role.*==\|\.role.*!=" frontend/src/ 2>/dev/null | grep -v "member\.roles\?.*map\|formatRole\|getRoleColor\|roles.*map\|display\|format\|badge" | head -10

echo
echo "🚨 CRITICAL PATTERNS TO FIX"
echo "---------------------------"

echo "Admin access checks (should use permissions):"
grep -r "role.*admin\|role.*manager" frontend/src/ 2>/dev/null | grep -v "display\|format\|badge\|map" | head -5

echo
echo "📋 MIGRATION PROGRESS TRACKING"
echo "------------------------------"

total_role_checks=$((role_checks + user_role_access + hardcoded_roles))
echo "Total role-based access patterns: $total_role_checks"
echo "Permission-based access patterns: $permission_checks"

if [ $total_role_checks -eq 0 ]; then
    echo "✅ SUCCESS: No role-based access control found!"
    echo "✅ All access control is permission-based"
else
    echo "⚠️  MIGRATION NEEDED: $total_role_checks role-based patterns remaining"
    echo "🎯 Target: 0 role-based patterns, 80+ permission-based patterns"
fi

echo
echo "🔧 NEXT STEPS"
echo "-------------"
if [ $total_role_checks -gt 0 ]; then
    echo "1. Review ROLE_TO_PERMISSION_MIGRATION_PLAN.md"
    echo "2. Start with HIGH PRIORITY files listed above"
    echo "3. Use pattern: currentUser?.permissions?.includes('permission.name')"
    echo "4. Re-run this audit script to track progress"
else
    echo "1. Run comprehensive testing suite"
    echo "2. Verify all functionality works with permissions"
    echo "3. Update documentation"
    echo "4. Set up automated linting to prevent role-based access"
fi

echo
echo "Audit completed: $(date)"