export interface SystemOverview {
  total_providers: number;
  total_agents: number;
  total_workflows: number;
  active_conversations: number;
  system_uptime: number;
  last_updated: string;
  // Extended operational metrics from monitoring dashboard
  total_executions_today?: number;
  total_cost_today?: number;
  avg_response_time?: number;
  success_rate?: number;
}

export interface SystemMetrics {
  executions_total: number;
  success_rate: number;
  avg_response_time: number;
  total_cost: number;
  error_count: number;
}

export interface SystemHealthData {
  overall_health: number;
  status: 'excellent' | 'good' | 'fair' | 'degraded' | 'critical';
  components: {
    providers: ComponentHealthStatus;
    agents: ComponentHealthStatus;
    workflows: ComponentHealthStatus;
    conversations: ComponentHealthStatus;
    infrastructure: ComponentHealthStatus;
  };
  alerts: AlertSummary;
  recommendations: HealthRecommendation[];
  last_updated: string;
}

export interface ComponentHealthStatus {
  health_score: number;
  status: 'healthy' | 'degraded' | 'unhealthy' | 'critical';
  active_count: number;
  issues: string[];
}

export interface ProviderMetrics {
  id: string;
  name: string;
  slug: string;
  status: 'healthy' | 'degraded' | 'unhealthy' | 'recovering';
  health_score: number;
  circuit_breaker: CircuitBreakerData;
  load_balancing: LoadBalancingData;
  performance: PerformanceMetrics;
  usage: UsageMetrics;
  alerts: Alert[];
  credentials: CredentialStatus[];
  last_execution: string | null;
}

export interface CircuitBreakerData {
  state: 'closed' | 'open' | 'half_open';
  failure_count: number;
  success_threshold: number;
  timeout: number;
  last_failure: string | null;
  stats: {
    total_requests: number;
    successful_requests: number;
    failed_requests: number;
    avg_response_time: number;
  };
}

export interface LoadBalancingData {
  current_load: number;
  weight: number;
  utilization: number;
}

export interface PerformanceMetrics {
  success_rate: number;
  avg_response_time: number;
  throughput: number;
  error_rate: number;
}

export interface UsageMetrics {
  executions_count: number;
  tokens_consumed: number;
  cost: number;
}

export interface CredentialStatus {
  id: string;
  name: string;
  is_active: boolean;
  last_tested: string | null;
  status: 'valid' | 'invalid' | 'expired' | 'unknown';
}

export interface AgentMetrics {
  id: string;
  name: string;
  status: 'active' | 'inactive' | 'error';
  health_score: number;
  performance: PerformanceMetrics;
  usage: UsageMetrics;
  executions: ExecutionSummary;
  provider_distribution: ProviderDistribution[];
  alerts: Alert[];
  last_execution: string | null;
  created_at: string;
  updated_at: string;
}

export interface ExecutionSummary {
  running: number;
  completed: number;
  failed: number;
  cancelled: number;
}

export interface ProviderDistribution {
  provider_id: string;
  provider_name: string;
  execution_count: number;
  success_rate: number;
  avg_cost: number;
}

export interface WorkflowMetrics {
  id: string;
  name: string;
  status: 'active' | 'draft' | 'inactive';
  version: string;
  health_score: number;
  performance: PerformanceMetrics;
  usage: WorkflowUsageMetrics;
  runs: WorkflowRunSummary;
  nodes: WorkflowNodeSummary;
  triggers: WorkflowTriggerSummary;
  alerts: Alert[];
  last_run: string | null;
  created_at: string;
  updated_at: string;
}

export interface WorkflowUsageMetrics extends UsageMetrics {
  runs_count: number;
  nodes_executed: number;
}

export interface WorkflowRunSummary {
  running: number;
  completed: number;
  failed: number;
  cancelled: number;
}

export interface WorkflowNodeSummary {
  total_nodes: number;
  node_performance: NodePerformance[];
}

export interface NodePerformance {
  node_id: string;
  node_type: string;
  node_name: string;
  avg_execution_time: number;
  success_rate: number;
  failure_rate: number;
}

export interface WorkflowTriggerSummary {
  manual: number;
  scheduled: number;
  webhook: number;
  api: number;
}

export interface ConversationMetrics {
  id: string;
  title: string;
  status: 'active' | 'inactive' | 'archived';
  health_score: number;
  performance: ConversationPerformanceMetrics;
  usage: ConversationUsageMetrics;
  participants: ConversationParticipants;
  agent_usage: AgentUsage[];
  alerts: Alert[];
  last_activity: string | null;
  created_at: string;
  updated_at: string;
}

export interface ConversationPerformanceMetrics {
  avg_response_time: number;
  message_throughput: number;
  success_rate: number;
}

export interface ConversationUsageMetrics {
  messages_count: number;
  total_tokens: number;
  total_cost: number;
}

export interface ConversationParticipants {
  human_messages: number;
  ai_messages: number;
  system_messages: number;
}

export interface AgentUsage {
  agent_id: string;
  agent_name: string;
  message_count: number;
  total_tokens: number;
  total_cost: number;
}

export interface Alert {
  id: string;
  severity: 'low' | 'medium' | 'high' | 'critical';
  component: string;
  title: string;
  message: string;
  metadata: Record<string, unknown>;
  acknowledged: boolean;
  acknowledged_at: string | null;
  acknowledged_by: string | null;
  resolved: boolean;
  resolved_at: string | null;
  resolved_by: string | null;
  created_at: string;
}

export interface AlertSummary {
  active: number;
  high_priority: number;
  medium_priority: number;
  low_priority: number;
  by_component: Record<string, number>;
  recent_count: number;
}

export interface HealthRecommendation {
  type: 'performance' | 'cost' | 'reliability' | 'security';
  priority: 'low' | 'medium' | 'high';
  component: string;
  message: string;
  action: string;
}

export interface ResourceUtilization {
  system: SystemResources;
  database: DatabaseResources;
  redis: RedisResources;
  sidekiq: SidekiqResources;
  actioncable: ActionCableResources;
}

export interface SystemResources {
  cpu_usage: number;
  memory_usage: number;
  disk_usage: number;
  network_usage: number;
}

export interface DatabaseResources {
  connection_pool: {
    size: number;
    used: number;
    available: number;
  };
  query_performance: {
    avg_query_time: number;
    slow_queries: number;
    deadlocks: number;
  };
  storage_usage: {
    total_size: number;
    used_size: number;
    free_size: number;
  };
}

export interface RedisResources {
  memory_usage: {
    used: number;
    peak: number;
    limit: number;
  };
  connection_count: number;
  hit_rate: number;
}

export interface SidekiqResources {
  queue_sizes: Record<string, number>;
  worker_utilization: {
    busy: number;
    idle: number;
    total: number;
  };
  failed_jobs: number;
}

export interface ActionCableResources {
  connection_count: number;
  subscription_count: number;
  message_throughput: number;
}

export interface CostAnalysis {
  total_cost: number;
  breakdown: CostBreakdown[];
  trends: CostTrend[];
  projections: CostProjection;
}

export interface CostBreakdown {
  category: string;
  amount: number;
  percentage: number;
  trend: 'up' | 'down' | 'stable';
}

export interface CostTrend {
  timestamp: string;
  amount: number;
}

export interface CostProjection {
  daily: number;
  weekly: number;
  monthly: number;
  confidence: number;
}

export interface MonitoringDashboardData {
  timestamp: string;
  overview: SystemOverview;
  health_score: number;
  components: {
    system?: SystemMetrics;
    providers?: ProvidersSummary;
    agents?: AgentsSummary;
    workflows?: WorkflowsSummary;
    conversations?: ConversationsSummary;
    costs?: CostsSummary;
    alerts?: AlertSummary;
    resources?: ResourcesSummary;
  };
}

export interface ProvidersSummary {
  active: number;
  healthy: number;
  degraded: number;
  unhealthy: number;
  circuit_breakers: {
    closed: number;
    open: number;
    half_open: number;
  };
  active_alerts: number;
}

export interface AgentsSummary {
  active: number;
  running_executions: number;
  completed_today: number;
  failed_today: number;
  healthy: number;
  degraded: number;
  unhealthy: number;
  active_alerts: number;
}

export interface WorkflowsSummary {
  active: number;
  running: number;
  completed_today: number;
  failed_today: number;
  healthy: number;
  degraded: number;
  unhealthy: number;
  active_alerts: number;
}

export interface ConversationsSummary {
  active: number;
  messages_today: number;
  avg_response_time: number;
  healthy: number;
  active_alerts: number;
}

export interface CostsSummary {
  total_today: number;
  by_provider: Record<string, number>;
  trending: 'up' | 'down' | 'stable';
}

export interface ResourcesSummary {
  cpu_usage: number;
  memory_usage: number;
  disk_usage: number;
  healthy: boolean;
}

// WebSocket event types
export interface MonitoringWebSocketMessage {
  type: string;
  data?: unknown;
  timestamp: string;
  [key: string]: unknown;
}

export interface ComponentTestResult {
  success: boolean;
  response_time: number;
  error?: string;
  details: Record<string, unknown>;
}

// Filter types
export interface AlertFilters {
  severity?: 'low' | 'medium' | 'high' | 'critical';
  component?: string;
  provider_id?: string;
  agent_id?: string;
  workflow_id?: string;
  status?: 'active' | 'acknowledged' | 'resolved' | 'all';
}

export interface TimeRange {
  duration: string;
  start_time: string;
  end_time: string;
}

export type MonitoringComponent =
  | 'system'
  | 'providers'
  | 'agents'
  | 'workflows'
  | 'conversations'
  | 'costs'
  | 'alerts'
  | 'resources';

export type MonitoringInterval = 'real-time' | 'fast' | 'normal' | 'slow';

export type HealthStatus = 'excellent' | 'good' | 'fair' | 'degraded' | 'critical';

export type ComponentStatus = 'healthy' | 'degraded' | 'unhealthy' | 'critical' | 'unknown';

// Callback interfaces for monitoring service
export interface MonitoringCallbacks {
  onConnect?: () => void;
  onDisconnect?: () => void;
  onError?: (error: unknown) => void;
  onDashboardUpdate?: (data: MonitoringDashboardData) => void;
  onSystemHealthUpdate?: (data: SystemHealthData) => void;
  onComponentUpdate?: (component: MonitoringComponent, data: unknown) => void;
  onAlertUpdate?: (alerts: Alert[]) => void;
  onAlertTriggered?: (alert: Alert) => void;
  onAlertAcknowledged?: (alertId: string, acknowledgedBy: string) => void;
  onAlertResolved?: (alertId: string, resolvedBy: string) => void;
  onPerformanceUpdate?: (component: MonitoringComponent, data: PerformanceMetrics) => void;
  onResourceUpdate?: (data: ResourceUtilization) => void;
  onComponentTested?: (componentType: string, componentId: string, result: ComponentTestResult) => void;
}