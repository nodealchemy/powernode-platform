// Shared hooks exports
export { useNotifications } from './useNotifications';
export { usePermissions } from './usePermissions';
export { useThemeColors } from './useThemeColors';
export { useWebSocket } from './useWebSocket';
export { useAnalyticsWebSocket } from './useAnalyticsWebSocket';
export { useCustomerWebSocket } from './useCustomerWebSocket';
export { useSettingsWebSocket } from './useSettingsWebSocket';
export { useSubscriptionLifecycle } from './useSubscriptionLifecycle';
export { useSubscriptionWebSocket } from './useSubscriptionWebSocket';
export { useMcpWebSocket } from './useMcpWebSocket';
export { useAiOrchestrationWebSocket } from './useAiOrchestrationWebSocket';
export { useTabBreadcrumb } from './useTabBreadcrumb';

// Form handling
export { useForm } from './useForm';
export type { UseFormReturn, UseFormOptions, FormValidationRule, FormValidationRules } from './useForm';

// Context exports
export { BreadcrumbProvider, useBreadcrumb } from './BreadcrumbContext';
export { NavigationProvider, useNavigation } from './NavigationContext';
export { ThemeProvider, useTheme } from './ThemeContext';

// AI Orchestration WebSocket types
export type {
  WorkflowEvent,
  WorkflowRunEvent,
  AgentEvent,
  AgentTeamEvent,
  BatchEvent,
  CircuitBreakerEvent,
  ProviderEvent,
  AiOrchestrationEvent,
  WorkflowEventType,
  WorkflowRunEventType,
  AgentEventType,
  AgentTeamEventType,
  BatchEventType,
  CircuitBreakerEventType,
  ProviderEventType,
  AiOrchestrationEventType
} from './useAiOrchestrationWebSocket';