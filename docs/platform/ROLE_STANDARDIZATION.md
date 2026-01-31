# Role Standardization Documentation

## Overview
The Powernode platform uses a standardized role-based access control system with permissions. All roles have been standardized to use consistent naming conventions.

## Standardized Role Names

### User Roles (role_type: 'user')
- **`member`** - Basic account member with standard access
- **`manager`** - Team manager with content and team management capabilities  
- **`billing_admin`** - Manages billing, subscriptions, and financial operations
- **`owner`** - Account owner with full account management capabilities

### Admin Roles (role_type: 'admin')
- **`admin`** - System administrator with full administrative access
- **`super_admin`** - Super administrator with full system access

### System Roles (role_type: 'system')
- **`system_worker`** - Automated worker with system-level access
- **`task_worker`** - Worker limited to specific task execution

## Migration from Old Role Names

The following role names have been deprecated and migrated:

| Old Name | New Name |
|----------|----------|
| `account.owner` | `owner` |
| `account.manager` | `manager` |
| `account.member` | `member` |
| `system.admin` | `super_admin` |
| `billing.admin` | `billing_admin` |

## Role Configuration

All roles are defined in `/config/permissions.rb` in the `Permissions` module:

```ruby
module Permissions
  ROLES = {
    'member' => { ... },
    'manager' => { ... },
    'billing_admin' => { ... },
    'owner' => { ... },
    'admin' => { ... },
    'super_admin' => { ... },
    'system_worker' => { ... },
    'task_worker' => { ... }
  }
end
```

## Permission System

Permissions follow the `resource.action` format:
- User Management: `user.view`, `user.edit_self`, `user.delete_self`
- Team Management: `team.view`, `team.invite`, `team.remove`, `team.assign_roles`
- Billing: `billing.view`, `billing.update`, `billing.cancel`
- Content: `page.create`, `page.edit`, `page.delete`, `page.publish`
- Analytics: `analytics.view`, `analytics.export`
- Admin: `admin.access`, `admin.users.*`, `admin.settings.*`
- System: `system.worker.*`, `system.database.*`, `system.jobs.*`

## Database Management

### Sync Roles from Configuration
```bash
bundle exec rake roles:standardize
```

### Check Role Status
```bash
bundle exec rake roles:status
```

## Code Usage

### Checking User Roles
```ruby
# Correct - Use standardized role names
user.has_role?('owner')
user.has_role?('admin')
user.has_role?('member')

# Incorrect - Don't use old dotted notation
# user.has_role?('account.owner')  # WRONG
# user.has_role?('system.admin')   # WRONG
```

### Role Predicates
```ruby
user.owner?        # Checks for 'owner' role
user.admin?        # Checks for 'admin' or 'super_admin' roles
user.super_admin?  # Checks for 'super_admin' role
user.manager?      # Checks for 'manager' role
user.member?       # Checks for 'member' role
user.billing_admin? # Checks for 'billing_admin' role
```

### Permission Checking
```ruby
# Check permissions (preferred over role checking)
user.has_permission?('team.invite')
user.has_permission?('billing.update')
user.can?('analytics.view')
```

## Testing

All test factories and specs have been updated to use standardized role names:

```ruby
# Factory usage
create(:user, :owner)     # Creates user with owner role
create(:user, :admin)      # Creates user with admin role
create(:user, :member)     # Creates user with member role

# Test setup
Role.sync_from_config!     # Syncs all roles from configuration
```

## Frontend Integration

The frontend should use permissions for access control, not roles:

```javascript
// Correct - Check permissions
currentUser.permissions.includes('users.manage')
currentUser.permissions.includes('billing.read')

// Incorrect - Don't check roles in frontend
// currentUser.roles.includes('admin')  // WRONG
```

## Maintenance

1. All role definitions are centralized in `/config/permissions.rb`
2. Use `Role.sync_from_config!` to sync database with configuration
3. Run `bundle exec rake roles:status` to check for discrepancies
4. Never create roles outside of the Permissions module configuration

## Changes Made

1. Renamed `PermissionsV2` module to `Permissions`
2. Removed duplicate `/app/lib/permissions.rb` file
3. Updated all model references from dotted notation to simple names
4. Created rake task for role standardization (`/lib/tasks/standardize_roles.rake`)
5. Updated test setup to use `Role.sync_from_config!`
6. Fixed password history validation messages
7. Corrected reset token field names in User model

## Testing Results

After standardization:
- Test failures reduced from 151 to 32
- All role-related functionality working correctly
- Permissions properly assigned to all roles
- Database seeding and test setup automated