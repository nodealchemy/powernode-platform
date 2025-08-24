# Permission Naming Convention

## Overview
All permissions in the Powernode platform follow a consistent singular resource naming convention.

## Standard Format
`namespace.resource.action`

Where:
- **namespace**: Optional prefix (e.g., `admin`, `system`)
- **resource**: Singular resource name
- **action**: Operation being performed

## Examples

### Regular Resource Permissions (Singular)
- `user.view`, `user.edit_self`, `user.delete_self`
- `team.view`, `team.invite`, `team.remove`, `team.assign_roles`
- `billing.view`, `billing.update`, `billing.cancel`
- `invoice.view`, `invoice.download`
- `page.create`, `page.view`, `page.edit`, `page.delete`, `page.publish`
- `webhook.view`, `webhook.create`, `webhook.edit`, `webhook.delete`
- `report.view`, `report.generate`, `report.export`
- `audit.view`, `audit.export`

### Admin Permissions (Singular Resources)
- `admin.user.view`, `admin.user.create`, `admin.user.edit`, `admin.user.delete`, `admin.user.impersonate`
- `admin.role.view`, `admin.role.create`, `admin.role.edit`, `admin.role.delete`, `admin.role.assign`
- `admin.account.view`, `admin.account.create`, `admin.account.edit`, `admin.account.delete`
- `admin.worker.view`, `admin.worker.create`, `admin.worker.edit`, `admin.worker.delete`
- `admin.billing.view`, `admin.billing.override`, `admin.billing.refund`
- `admin.audit.view`, `admin.audit.export`, `admin.audit.delete`

### Special Cases (Plural)
- `admin.settings.*` - Settings remain plural as they represent a collection of configuration options
  - `admin.settings.view`, `admin.settings.edit`, `admin.settings.email`, `admin.settings.security`

### System Permissions (Singular)
- `system.worker.register`, `system.worker.heartbeat`, `system.worker.execute`
- `system.webhook.process`, `system.webhook.retry`
- `system.cache.read`, `system.cache.write`, `system.cache.clear`

## Migration History
- **2025-08-22**: Standardized all permissions to use singular resource naming
- Previously mixed plural/singular (e.g., `users.manage`, `webhooks.create`)
- Now consistent singular throughout (e.g., `user.manage`, `webhook.create`)

## Benefits
1. **Consistency**: All resources follow the same pattern
2. **Clarity**: Singular clearly indicates operation on a resource type
3. **Predictability**: Developers can guess permission names
4. **RESTful Alignment**: Matches REST singular resource conventions

## Testing
All permission changes have been validated:
- ✅ 921 RSpec tests passing
- ✅ All API endpoints tested and working
- ✅ Frontend permission checks updated
- ✅ Database permissions migrated