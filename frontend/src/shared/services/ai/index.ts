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
import { modelRouterApi } from './ModelRouterApiService';
import { aiOpsApi } from './AiOpsApiService';
import { roiApi } from './RoiApiService';
import { creditsApi } from './CreditsApiService';
import { mcpHostingApi } from './McpHostingApiService';
import { outcomeBillingApi } from './OutcomeBillingApiService';
import { ragApi } from './RagApiService';
import { teamsApi } from './TeamsApiService';
import { agentMarketplaceApi } from './AgentMarketplaceApiService';
import { governanceApi } from './GovernanceApiService';
import { devopsApi } from './DevopsApiService';
import { sandboxApi } from './SandboxApiService';
import { agentCardsApiService } from './AgentCardsApiService';
import { a2aTasksApiService } from './A2aTasksApiService';
import { memoryApiService } from './MemoryApiService';
import { chatChannelsApi } from './ChatChannelsApiService';
import { communityAgentsApi } from './CommunityAgentsApiService';
import { containerExecutionApi } from './ContainerExecutionApiService';
import { ralphLoopsApi } from './RalphLoopsApiService';

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
  SendMessageResponse,
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

// Re-export Model Router service (Phase 1 - Intelligent Routing)
export { modelRouterApi };
export type {
  RoutingRuleFilters,
  DecisionFilters,
  RoutingRule,
  CreateRoutingRuleRequest,
  RouteRequest,
  RoutingResult,
  RoutingDecision,
  RoutingStatistics,
  CostAnalysis as RouterCostAnalysis,
  ProviderRanking,
  OptimizationRecommendation,
  CostOptimizationLog,
  OptimizationStats,
} from './ModelRouterApiService';

// Re-export AIOps service (Phase 1 - Real-Time Operations)
export { aiOpsApi };
export type {
  AiOpsFilters,
  AiOpsDashboard,
  SystemHealth,
  ComponentHealth,
  SystemOverview,
  ProviderMetrics,
  ProviderDetailMetrics,
  ProviderComparison,
  WorkflowMetrics,
  AgentMetrics,
  CostAnalysisData,
  Alert as AiOpsAlert,
  CircuitBreakerStatus,
  RealTimeMetrics,
  RecordMetricsRequest,
} from './AiOpsApiService';

// Re-export ROI service (Phase 1 - ROI Tracking)
export { roiApi };
export type {
  RoiFilters,
  AttributionFilters,
  MetricFilters,
  RoiDashboard,
  RoiSummary,
  RoiTrends,
  DailyMetrics,
  WorkflowRoi,
  AgentRoi,
  ProviderCost,
  CostBreakdown,
  CostAttribution,
  RoiMetric,
  RoiProjections,
  RoiRecommendation,
  PeriodComparison,
} from './RoiApiService';

// Re-export Credits service (Phase 2 - Credit System)
export { creditsApi };
export type {
  CreditBalance,
  CreditTransaction,
  CreditPack,
  CreditPurchase,
  CreditTransfer,
  UsageAnalytics,
  OperationCost,
  ResellerStats,
} from './CreditsApiService';

// Re-export MCP Hosting service (Phase 2 - MCP Hosting)
export { mcpHostingApi };
export type {
  McpHostedServer,
  McpServerDetailed,
  McpServerDeployment,
  McpServerMetric,
  McpServerSubscription,
  McpMarketplaceListing,
  ServerCreateParams,
} from './McpHostingApiService';

// Re-export Outcome Billing service (Phase 2 - Outcome Billing)
export { outcomeBillingApi };
export type {
  OutcomeDefinition,
  SlaContract,
  OutcomeBillingRecord,
  SlaViolation,
  BillingSummary,
  SlaPerformance,
} from './OutcomeBillingApiService';

// Re-export RAG service (Phase 3 - Knowledge-Augmented Agents)
export { ragApi };
export type {
  KnowledgeBase,
  Document,
  RagQuery,
  QueryResult,
  RetrievedChunk,
  DataConnector,
  RagAnalytics,
} from './RagApiService';

// Re-export Teams service (Phase 3 - Multi-Agent Team Orchestration)
export { teamsApi };
export type {
  Team,
  TeamRole,
  TeamChannel,
  TeamExecution,
  TeamTask,
  TeamMessage,
  TeamTemplate,
  TeamAnalytics,
} from './TeamsApiService';

// Re-export Agent Marketplace service (Phase 4 - Pre-Built Vertical AI Agents)
export { agentMarketplaceApi };
export type {
  AgentTemplate,
  AgentInstallation,
  AgentReview,
  MarketplaceCategory,
  Publisher,
  PublisherAnalytics,
  TemplateFilters as AgentTemplateFilters,
} from './AgentMarketplaceApiService';

// Re-export Governance service (Phase 4 - AI Workflow Governance & Compliance)
export { governanceApi };
export type {
  CompliancePolicy,
  PolicyViolation,
  ApprovalChain,
  ApprovalRequest,
  DataClassification,
  DataDetection,
  ComplianceReport,
  AuditEntry,
  ComplianceSummary,
  PolicyEvaluationResult,
} from './GovernanceApiService';

// Re-export DevOps service (Phase 4 - AI Pipeline Templates for CI/CD)
export { devopsApi };
export type {
  DevopsTemplate,
  DevopsInstallation,
  PipelineExecution,
  DeploymentRisk,
  CodeReview,
  DevopsAnalytics,
} from './DevopsApiService';

// Re-export Sandbox service (Phase 4 - Enterprise AI Agent Sandbox & Testing)
export { sandboxApi };
export type {
  Sandbox,
  TestScenario,
  MockResponse,
  TestRun,
  TestResult,
  PerformanceBenchmark,
  AbTest,
  AbTestResults,
  SandboxAnalytics,
} from './SandboxApiService';

// Re-export A2A Agent Cards service
export { agentCardsApiService };
export type {
  AgentCard,
  AgentCardFilters,
  CreateAgentCardRequest,
  UpdateAgentCardRequest,
  A2aAgentCardJson,
  DiscoverAgentsResponse,
  A2aTask,
  A2aTaskFilters,
  SubmitA2aTaskRequest,
  A2aTaskResponse,
  A2aTaskJson,
  A2aTaskEvent,
  A2aTaskEventsResponse,
  A2aArtifact,
  A2aMessage,
  A2aMessagePart,
  AgentAuthentication,
  AgentCapabilities,
  AgentSkill,
} from './types/a2a-types';

// Re-export A2A Tasks service
export { a2aTasksApiService };

// Re-export Memory service
export { memoryApiService };
export type {
  MemoryEntry,
  MemoryType,
  EntryType,
  SourceType,
  MemoryContent,
  MemoryFilters,
  CreateMemoryRequest,
  UpdateMemoryRequest,
  MemorySearchRequest,
  MemorySearchResponse,
  ContextInjectionRequest,
  ContextInjectionResponse,
  MemoryStatsResponse,
  PersistentContext,
  RetentionPolicy,
  WorkingMemoryState,
  ConversationMessage,
  WorkingMemoryStats,
  MemoryTimelineEntry,
  MemoryCluster,
  MemoryGraph,
  MemoryGraphNode,
  MemoryGraphEdge,
} from './types/memory-types';

// Re-export Chat Channels service (AI Agent Community Platform)
export { chatChannelsApi };
export type {
  ChatPlatform,
  ChannelStatus,
  SessionStatus,
  MessageDirection,
  MessageType,
  DeliveryStatus,
  ChatChannel,
  ChatChannelSummary,
  CreateChannelRequest,
  UpdateChannelRequest,
  ChannelFilters,
  ChatSession,
  ChatSessionSummary,
  SessionFilters,
  ChatMessage,
  ChatMessageSummary,
  ChatMessageAttachment,
  SendMessageRequest as ChatSendMessageRequest,
  MessageFilters,
  ChannelMetrics,
  SessionStats,
  PlatformInfo,
} from './types/chat-types';

// Re-export Community Agents service (AI Agent Community Platform)
export { communityAgentsApi };
export type {
  AgentVisibility,
  AgentStatus as CommunityAgentStatus,
  PricingModel,
  ReportReason,
  ReportStatus,
  CommunityAgent,
  CommunityAgentSummary,
  CreateCommunityAgentRequest,
  UpdateCommunityAgentRequest,
  CommunityAgentFilters,
  CommunityAgentRating,
  CreateRatingRequest,
  CommunityAgentReport,
  CreateReportRequest as CreateAgentReportRequest,
  DiscoverAgentsRequest,
  DiscoverAgentsResponse as CommunityDiscoverResponse,
  FederationStatus,
  TrustLevel,
  FederationPartner,
  FederationPartnerSummary,
  CreateFederationPartnerRequest,
  UpdateFederationPartnerRequest,
  FederationPartnerFilters,
  FederatedAgent,
  VerifyFederationKeyResponse,
} from './types/community-types';

// Re-export Container Execution service (AI Agent Community Platform)
export { containerExecutionApi };
export type {
  ContainerStatus,
  TemplateVisibility,
  TemplateStatus,
  ContainerInstance,
  ContainerInstanceSummary,
  SecurityViolation,
  ExecuteContainerRequest,
  ContainerFilters,
  ContainerTemplate,
  ContainerTemplateSummary,
  CreateContainerTemplateRequest,
  UpdateContainerTemplateRequest,
  TemplateFilters as ContainerTemplateFilters,
  TemplateStats,
  ResourceQuota,
  QuotaStatus,
  ResourceLimits,
  QuotaResponse,
  UpdateQuotaRequest,
  UsageHistory,
  OverageInfo,
  ContainerStats,
} from './types/container-types';

// Re-export Ralph Loops service (Autonomous AI Agent Loops)
export { ralphLoopsApi };
export type {
  RalphLoopStatus,
  RalphTaskStatus,
  RalphIterationStatus,
  RalphAiTool,
  PrdTask,
  RalphLoop,
  RalphLoopSummary,
  RalphTask,
  RalphTaskSummary,
  RalphIteration,
  RalphIterationSummary,
  CreateRalphLoopRequest,
  UpdateRalphLoopRequest,
  RalphLoopFilters,
  RalphTaskFilters,
  RalphIterationFilters,
  ParsePrdRequest,
  RalphStatistics,
  RalphProgress,
} from './types/ralph-types';

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
  // Phase 1 - New services
  modelRouter: modelRouterApi,
  aiOps: aiOpsApi,
  roi: roiApi,
  // Phase 2 - New services
  credits: creditsApi,
  mcpHosting: mcpHostingApi,
  outcomeBilling: outcomeBillingApi,
  // Phase 3 - New services
  rag: ragApi,
  teams: teamsApi,
  // Phase 4 - New services
  agentMarketplace: agentMarketplaceApi,
  governance: governanceApi,
  devops: devopsApi,
  sandbox: sandboxApi,
  // A2A & Memory services
  agentCards: agentCardsApiService,
  a2aTasks: a2aTasksApiService,
  memory: memoryApiService,
  // AI Agent Community Platform services
  chatChannels: chatChannelsApi,
  communityAgents: communityAgentsApi,
  containerExecution: containerExecutionApi,
  // Ralph Loops (Autonomous AI Agent Loops)
  ralphLoops: ralphLoopsApi,
} as const;

export default aiApi;
