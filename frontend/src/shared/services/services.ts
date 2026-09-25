// Shared Services Exports
// Service clients only: the raw HTTP client (api/apiClient) is not
// re-exported, so a component cannot reach it through this barrel (fc-39).

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