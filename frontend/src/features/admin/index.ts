/**
 * Admin Feature Module
 *
 * System administration, user management, settings, and audit functionality
 */

// Components barrel
export * from './components';

// Roles
export { RoleFormModal } from './roles/components/RoleFormModal';
export { RoleUsersModal } from './roles/components/RoleUsersModal';
export { rolesApi } from './roles/services/rolesApi';

// Services
export { adminApi } from './services/adminApi';
export { adminSettingsApi } from './services/adminSettingsApi';
export { servicesApi } from './services/servicesApi';

// Settings
export { siteSettingsApi } from './settings/services/siteSettingsApi';
