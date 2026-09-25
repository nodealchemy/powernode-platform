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
export { adminSettingsApi } from './services/adminSettingsApi';

// Settings
export { siteSettingsApi } from './settings/services/siteSettingsApi';
