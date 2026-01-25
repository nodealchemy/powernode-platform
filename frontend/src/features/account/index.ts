/**
 * Account Feature Module
 *
 * User account management, authentication, notifications, and team features
 */

// Auth submodule
export * from './auth';

// Notifications submodule
export * from './notifications';

// Account switcher submodule
export * from './switcher';

// Account components
export { InviteTeamMemberModal } from './components/InviteTeamMemberModal';
export { PermissionSelector } from './components/PermissionSelector';
export { TeamMembersManagement } from './components/TeamMembersManagement';
export { TwoFactorSettings } from './components/TwoFactorSettings';

// Users
export { UserRolesModal } from './users/components/UserRolesModal';
export { usersApi } from './users/services/usersApi';

// Services
export { accountsApi } from './services/accountsApi';
