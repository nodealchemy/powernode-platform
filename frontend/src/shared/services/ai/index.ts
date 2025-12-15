/**
 * AI Orchestration API Services
 *
 * Consolidated API services for the new AI Orchestration architecture.
 * These services replace 25+ old controllers with 6 RESTful consolidated controllers.
 *
 * Architecture Overview:
 * - Each service extends BaseApiService for consistent patterns
 * - Follows RESTful nested resource conventions
 * - Automatic response unwrapping and error handling
 * - Type-safe with comprehensive TypeScript interfaces
 *
 * Migration from old services:
 * - Old: aiAgentApi, aiAgentExecutionsApi, aiConversationsApi
 *   New: agentsApi (single consolidated service)
 *
 * - Old: workflowApi, workflowRunsApi, workflowSchedulesApi, workflowTriggersApi
 *   New: workflowsApi (single consolidated service)
 *
 * - Old: aiProviderApi, aiProviderCredentialsApi
 *   New: providersApi (single consolidated service)
 *
 * - Old: aiMonitoringService, circuitBreakersApi
 *   New: monitoringApi (single consolidated service)
 *
 * - Old: aiAnalyticsApi, reportsApi
 *   New: analyticsApi (single consolidated service)
 *
 * - Old: marketplaceApi, templatesApi
 *   New: marketplaceApi (single consolidated service)
 */

// Base service and types
// Import all service instances for local use
import { workflowsApi } from './WorkflowsApiService';
import { agentsApi } from './AgentsApiService';
import { providersApi } from './ProvidersApiService';
import { monitoringApi } from './MonitoringApiService';
import { analyticsApi } from './AnalyticsApiService';
import { marketplaceApi } from './MarketplaceApiService';
import { pluginsApi } from './PluginsApiService';
import { validationApi } from './ValidationApiService';
import { conversationsApi } from './ConversationsApiService';

export { BaseApiService } from './BaseApiService';
export type {
  ApiResponse,
  PaginatedResponse,
  QueryFilters,
} from './BaseApiService';

// Re-export Workflows service
export { workflowsApi };
export type {
  WorkflowFilters,
  WorkflowRunFilters,
  CreateWorkflowRequest,
  ExecuteWorkflowRequest,
  WorkflowStatistics,
  WorkflowValidationResult,
  WorkflowRunMetrics,
} from './types/workflow-api-types';

// Re-export Agents service
export { agentsApi };
export type {
  AgentFilters,
  AgentExecutionFilters,
  ConversationFilters,
  CreateAgentRequest,
  ExecuteAgentRequest,
  AgentStats,
  AgentAnalytics,
  AgentType,
  SendMessageRequest,
} from './types/agent-api-types';

// Re-export Conversations service (global conversations)
export { conversationsApi };
export type {
  GlobalConversationFilters,
  ConversationStats,
  DuplicateConversationRequest,
  UpdateConversationRequest,
  ConversationDetail,
  ConversationBase,
} from './ConversationsApiService';

// Re-export Providers service
export { providersApi };
export type {
  ProviderFilters,
  CreateProviderRequest,
  CreateCredentialRequest,
  ModelInfo,
  UsageSummary,
  ProviderStatistics,
  ConnectionTestResult,
} from './ProvidersApiService';

// Re-export Monitoring service
export { monitoringApi };
export type {
  MonitoringDashboard,
  HealthStatus,
  MetricsData,
  CircuitBreaker,
  Alert,
} from './MonitoringApiService';

// Re-export Analytics service
export { analyticsApi };
export type {
  AnalyticsFilters,
  AnalyticsDashboard,
  PerformanceMetrics,
  CostAnalytics,
  UsageMetrics,
  Insight,
  Recommendation,
  Trend,
  Report,
  ReportType,
  CreateReportRequest,
  ScheduleReportRequest,
  ExportRequest,
} from './AnalyticsApiService';

// Re-export Marketplace service
export { marketplaceApi };
export type {
  TemplateFilters,
  SearchFilters,
  Template,
  Installation,
  TemplateAnalytics,
  Rating,
  Category,
  TemplateStatistics,
  CreateTemplateRequest,
  InstallTemplateRequest,
  PublishWorkflowRequest,
  CompareRequest,
  UpdateCheck,
} from './MarketplaceApiService';

// Re-export Plugins service
export { pluginsApi };
export type {
  PluginMarketplace,
  Plugin,
  PluginInstallation,
  PluginType,
  PluginManifest,
  AiProviderConfig,
  WorkflowNodeConfig,
  CreatePluginMarketplaceRequest,
  CreatePluginRequest,
  InstallPluginRequest,
} from '@/shared/types/plugin';

// Re-export Validation service
export { validationApi };
export type {
  ValidationIssue,
  ValidationRule,
} from '@/shared/types/workflow';

/**
 * Convenience object for accessing all API services
 */
export const aiApi = {
  workflows: workflowsApi,
  agents: agentsApi,
  conversations: conversationsApi,
  providers: providersApi,
  monitoring: monitoringApi,
  analytics: analyticsApi,
  marketplace: marketplaceApi,
  plugins: pluginsApi,
  validation: validationApi,
} as const;

export default aiApi;
