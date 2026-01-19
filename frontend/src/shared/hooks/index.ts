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
export { useAiMonitoringWebSocket } from './useAiMonitoringWebSocket';
export { useNotificationWebSocket } from './useNotificationWebSocket';
export { usePageWebSocket } from './usePageWebSocket';
export { useTabBreadcrumb } from './useTabBreadcrumb';

// Page WebSocket types
export type {
  PageType,
  ChannelType,
  WebSocketDataUpdate,
  PageWebSocketOptions,
  PageWebSocketReturn
} from './usePageWebSocket';

// MCP Workflow Builder hooks
export { useMcpServersForWorkflow, useMcpServerForWorkflow } from './useMcpServersForWorkflow';
export {
  useMcpToolsForWorkflow,
  useMcpResourcesForWorkflow,
  useMcpPromptsForWorkflow,
  useMcpToolForWorkflow,
  useAllMcpToolsForWorkflow,
  useAllMcpResourcesForWorkflow,
  useAllMcpPromptsForWorkflow,
} from './useMcpToolsForWorkflow';
export { useWorkflowVariables, resolveVariablePath } from './useWorkflowVariables';
export type { WorkflowVariable } from './useWorkflowVariables';

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

// AI Monitoring WebSocket types
export type {
  DashboardStats,
  WorkflowExecution,
  SystemAlert,
  CostAlert
} from './useAiMonitoringWebSocket';

// Notification WebSocket types
export type { WebSocketNotification } from './useNotificationWebSocket';