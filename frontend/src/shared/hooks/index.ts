// Shared hooks exports
export { useNotifications } from '@/shared/hooks/useNotifications';
export { usePermissions } from '@/shared/hooks/usePermissions';
export { useThemeColors } from '@/shared/hooks/useThemeColors';
export { useWebSocket } from '@/shared/hooks/useWebSocket';
export { useAnalyticsWebSocket } from '@/shared/hooks/useAnalyticsWebSocket';
export { useCustomerWebSocket } from '@/shared/hooks/useCustomerWebSocket';
export { useSettingsWebSocket } from '@/shared/hooks/useSettingsWebSocket';
export { useMcpWebSocket } from '@/shared/hooks/useMcpWebSocket';
export { useAiOrchestrationWebSocket } from '@/shared/hooks/useAiOrchestrationWebSocket';
export { useAiMonitoringWebSocket } from '@/shared/hooks/useAiMonitoringWebSocket';
export { useAiStreamingWebSocket } from '@/shared/hooks/useAiStreamingWebSocket';
export { useNotificationWebSocket } from '@/shared/hooks/useNotificationWebSocket';
export { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
export { useTabBreadcrumb } from '@/shared/hooks/useTabBreadcrumb';

// Page WebSocket types
export type {
  PageType,
  ChannelType,
  WebSocketDataUpdate,
  PageWebSocketOptions,
  PageWebSocketReturn
} from '@/shared/hooks/usePageWebSocket';

// MCP Workflow Builder hooks
export { useMcpServersForWorkflow, useMcpServerForWorkflow } from '@/shared/hooks/useMcpServersForWorkflow';
export {
  useMcpToolsForWorkflow,
  useMcpResourcesForWorkflow,
  useMcpPromptsForWorkflow,
  useMcpToolForWorkflow,
  useAllMcpToolsForWorkflow,
  useAllMcpResourcesForWorkflow,
  useAllMcpPromptsForWorkflow,
} from '@/shared/hooks/useMcpToolsForWorkflow';
export { useWorkflowVariables, resolveVariablePath } from '@/shared/hooks/useWorkflowVariables';
export type { WorkflowVariable } from '@/shared/hooks/useWorkflowVariables';

// Form handling
export { useForm } from '@/shared/hooks/useForm';
export type { UseFormReturn, UseFormOptions, FormValidationRule, FormValidationRules } from '@/shared/hooks/useForm';

// Refresh action
export { useRefreshAction } from '@/shared/hooks/useRefreshAction';
export type { UseRefreshActionOptions, UseRefreshActionReturn } from '@/shared/hooks/useRefreshAction';

// Context exports
export { BreadcrumbProvider, useBreadcrumb } from '@/shared/hooks/BreadcrumbContext';
export { NavigationProvider, useNavigation } from '@/shared/hooks/NavigationContext';
export { ThemeProvider, useTheme } from '@/shared/hooks/ThemeContext';

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
} from '@/shared/hooks/useAiOrchestrationWebSocket';

// AI Monitoring WebSocket types
export type {
  DashboardStats,
  WorkflowExecution,
  SystemAlert,
  CostAlert
} from '@/shared/hooks/useAiMonitoringWebSocket';

// Notification WebSocket types
export type { WebSocketNotification } from '@/shared/hooks/useNotificationWebSocket';

// AI Streaming WebSocket types
export type {
  StreamEventType,
  StreamStartEvent,
  TokenEvent,
  StreamEndEvent,
  StreamErrorEvent,
  StreamEvent,
  StreamingState
} from '@/shared/hooks/useAiStreamingWebSocket';