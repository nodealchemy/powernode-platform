// Shared Services Exports
export { api } from '@/shared/services/api';

// Account services
export * from '@/shared/services/account/impersonationApi';
export * from '@/shared/services/account/invitationsApi';
export * from '@/shared/services/account/twoFactorApi';

// Billing services
export * from '@/shared/services/billing/invoicesApi';
export * from '@/shared/services/billing/paymentMethodsApi';
export * from '@/shared/services/billing/planFeaturesApi';
export * from '@/shared/services/billing/subscriptionHistoryApi';

// Settings services
export * from '@/shared/services/settings/emailSettingsApi';
export * from '@/shared/services/settings/settingsApi';

// Admin services
export * from '@/shared/services/admin/maintenanceApi';
export * from '@/shared/services/admin/performanceApi';
export * from '@/shared/services/admin/versionApi';

// Business services
export * from '@/shared/services/business/customersApi';

// Content services
export * from '@/shared/services/content/knowledgeBaseApi';