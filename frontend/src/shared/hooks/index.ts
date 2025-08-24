// Shared hooks exports
export { useNotification } from './useNotification';
export { usePermissions } from './usePermissions';
export { useThemeColors } from './useThemeColors';
export { useWebSocket } from './useWebSocket';
export { useAnalyticsWebSocket } from './useAnalyticsWebSocket';
export { useCustomerWebSocket } from './useCustomerWebSocket';
export { useSettingsWebSocket } from './useSettingsWebSocket';
export { useSubscriptionLifecycle } from './useSubscriptionLifecycle';
export { useSubscriptionWebSocket } from './useSubscriptionWebSocket';
export { useTabBreadcrumb } from './useTabBreadcrumb';

// Form handling
export { useForm } from './useForm';
export type { UseFormReturn, UseFormOptions, FormValidationRule, FormValidationRules } from './useForm';

// Context exports
export { BreadcrumbProvider, useBreadcrumb } from './BreadcrumbContext';
export { NavigationProvider, useNavigation } from './NavigationContext';
export { ThemeProvider, useTheme } from './ThemeContext';