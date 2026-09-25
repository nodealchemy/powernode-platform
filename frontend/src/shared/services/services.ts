// Shared Services Exports
export { api } from '@/shared/services/api';

// Account services
export * from '@/shared/services/account/impersonationApi';
export * from '@/shared/services/account/invitationsApi';
export * from '@/shared/services/account/twoFactorApi';

// Settings services
export * from '@/shared/services/settings/emailSettingsApi';
export * from '@/shared/services/settings/settingsApi';

// Admin services
export * from '@/shared/services/admin/maintenanceApi';
export * from '@/shared/services/admin/versionApi';

// Content services
export * from '@/shared/services/content/knowledgeBaseApi';