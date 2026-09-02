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

### Syncing role grants to the database

**Nothing has to be run by hand.** Grants reconcile automatically:
`Permissions::RoleGrantReconciler`
(`server/app/services/permissions/role_grant_reconciler.rb`) runs on **every
boot** of the Rails service, invoked from the `powernode-hub-backend` module's
`rails-start.sh:356-357` (`rails runner /usr/local/bin/role-grants-reconcile.rb`).

It is **absence-only**: it creates a declared global role that does not exist and
adds a declared grant that is missing, and it never updates a role and never
deletes a grant (`role_grant_reconciler.rb:121-164`). So a grant added to the
permission catalog reaches an already-installed deployment **at its next boot**,
not at deploy time.

Two caveats on "every boot". The reconcile is **advisory, never fatal**:
`rails-start.sh:357` ends in `|| true`, and the runner warns and skips if the
class is not loaded (`role-grants-reconcile.rb:28-31`) — so a boot can produce no
reconcile and no failure. And that is the **only** invocation site, so a Rails
install started by any other path never gets it.

The same reconcile can be run by hand, with the same absence-only behaviour:

```bash
bundle exec rails permissions:reconcile_role_grants
```

### Check grant drift (read-only)

```bash
bundle exec rails permissions:role_grant_drift
```

Reports the declared roles and grants this database lacks; `EXTRA` lines —
grants present in the database that the catalog does not declare, which a
destructive full sync **would delete**; and `ORPHAN GRANT KEY` lines — grants
registered against a role name the catalog does not declare, which are
permanently inert and which the reconcile cannot fix. It writes nothing, and it
**exits 1** when it finds drift (`server/lib/tasks/permissions.rake:234-272`).

### Revoking a grant

Remove it from the catalog (`config/permissions.rb` / the catalog DSL). Do not
reach for a full sync: `Role.sync_from_config!` calls `Role#sync_permissions!`,
which is full destructive reconciliation (`server/app/models/role.rb:179-180` —
`to_remove = current - desired`, then `delete_all`), and its desired set is
filtered through `Permissions.permission_exists?`, i.e. `CORE_PERMISSIONS`
merged with the extensions **loaded in this process**
(`config/permissions.rb:1170-1176`). On a module-composed instance that booted
without an extension, that silently deletes every grant belonging to that
extension from every global role the process still declares — which includes the
core roles (`admin`, `owner`, …) that most extension grants are registered
against. The unloaded extension's *own* roles are not in
`Permissions.all_roles`, so they are never iterated and their grants survive;
that is the only part of the blast radius this spares. Deliberate revocation
stays an explicit operator action; read `permissions:role_grant_drift`'s `EXTRA`
lines before running one.

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

`Role.sync_from_config!` is destructive (see [Revoking a grant](#revoking-a-grant)),
but it is the correct call **here**: the suite starts from an empty,
catalog-owned database, so there is nothing for its `delete_all` to lose
(`server/spec/rails_helper.rb:170`). Do not copy the call to a running deployment.

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
2. Nothing needs to be run to apply a catalog change — `Permissions::RoleGrantReconciler`
   creates the missing roles and grants at the next boot (see
   [Database Management](#database-management) above)
3. Run `bundle exec rails permissions:role_grant_drift` to check for discrepancies
   (read-only)
4. Never create roles outside of the Permissions module configuration
5. `Role.sync_from_config!` is destructive and is an explicit operator action, not
   maintenance — see [Revoking a grant](#revoking-a-grant)

## Changes Made

1. Renamed `PermissionsV2` module to `Permissions`
2. Removed duplicate `/app/lib/permissions.rb` file
3. Updated all model references from dotted notation to simple names
4. Created a `roles` rake namespace (`roles:standardize` and `roles:status`) —
   **both since removed** (IMP-6477865679f4). `roles:standardize` was destructive in
   two ways: it passed `config[:permissions]` to `Role#sync_permissions!` instead of
   `Permissions.permissions_for_role`, dropping every grant contributed by
   `register_role_permissions` or a catalog-DSL `grant:`; and its "clean up
   non-standard roles" pass ran `Role.where.not(name: …).destroy!` with **no
   `account_id` scope**, so it destroyed unused account-scoped custom roles created
   through the API. No code path ever invoked it — the only prescription was this
   document's own Database Management section, rewritten above. `roles:status` was a
   read-only reporter, superseded by `permissions:role_grant_drift`; the one thing it
   printed that the drift task does not is per-role user/worker counts.
5. Updated test setup to use `Role.sync_from_config!`
6. Fixed password history validation messages
7. Corrected reset token field names in User model

## Testing Results

After standardization:
- Test failures reduced from 151 to 32
- All role-related functionality working correctly
- Permissions properly assigned to all roles
- Database seeding and test setup automated