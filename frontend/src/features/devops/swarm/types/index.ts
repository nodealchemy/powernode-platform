// Docker Swarm Management Types

// ==================== Enums / Unions ====================

export type ClusterEnvironment = 'staging' | 'production' | 'development' | 'custom';
export type ClusterStatus = 'pending' | 'connected' | 'disconnected' | 'error' | 'maintenance';

export type NodeRole = 'manager' | 'worker';
export type NodeAvailability = 'active' | 'pause' | 'drain';
export type NodeStatus = 'ready' | 'down' | 'disconnected' | 'unknown';

export type ServiceMode = 'replicated' | 'global';

export type StackStatus = 'draft' | 'deploying' | 'deployed' | 'failed' | 'removing' | 'removed';

export type DeploymentType = 'deploy' | 'update' | 'scale' | 'rollback' | 'remove' | 'stack_deploy' | 'stack_remove';
export type DeploymentStatus = 'pending' | 'running' | 'completed' | 'failed' | 'cancelled';

export type EventSeverity = 'info' | 'warning' | 'error' | 'critical';
export type EventSourceType = 'node' | 'service' | 'task' | 'cluster' | 'stack';

// ==================== Cluster ====================

export interface SwarmClusterSummary {
  id: string;
  name: string;
  slug: string;
  api_endpoint: string;
  environment: ClusterEnvironment;
  status: ClusterStatus;
  node_count: number;
  service_count: number;
  last_synced_at?: string;
  auto_sync: boolean;
  tls_verify: boolean;
  has_tls_credentials: boolean;
}

export interface SwarmCluster extends SwarmClusterSummary {
  description?: string;
  api_version: string;
  swarm_id?: string;
  sync_interval_seconds: number;
  consecutive_failures: number;
  metadata: Record<string, unknown>;
  created_at: string;
  updated_at: string;
}

export interface ClusterFormData {
  name: string;
  description?: string;
  api_endpoint: string;
  api_version?: string;
  environment: ClusterEnvironment;
  auto_sync?: boolean;
  sync_interval_seconds?: number;
  tls_verify?: boolean;
  tls_ca?: string;
  tls_cert?: string;
  tls_key?: string;
}

// ==================== Node ====================

export interface SwarmNodeSummary {
  id: string;
  docker_node_id: string;
  hostname: string;
  role: NodeRole;
  availability: NodeAvailability;
  status: NodeStatus;
  manager_status?: string;
  ip_address?: string;
  memory_gb?: number;
  cpu_count?: number;
  labels: Record<string, string>;
}

export interface SwarmNode extends SwarmNodeSummary {
  engine_version?: string;
  os?: string;
  architecture?: string;
  memory_bytes?: number;
  last_seen_at?: string;
  created_at: string;
  updated_at: string;
}

export interface NodeUpdateData {
  availability?: NodeAvailability;
  role?: NodeRole;
  labels?: Record<string, string>;
}

// ==================== Service ====================

export interface SwarmServiceSummary {
  id: string;
  docker_service_id: string;
  service_name: string;
  image: string;
  mode: ServiceMode;
  desired_replicas: number;
  running_replicas: number;
  health_percentage: number;
  ports: ServicePort[];
  stack_id?: string;
}

export interface SwarmService extends SwarmServiceSummary {
  constraints: string[];
  resource_limits: ResourceConfig;
  resource_reservations: ResourceConfig;
  update_config: UpdateConfig;
  rollback_config: UpdateConfig;
  labels: Record<string, string>;
  environment: string[];
  version?: number;
  created_at: string;
  updated_at: string;
}

export interface ServicePort {
  target: number;
  published: number;
  protocol?: string;
  mode?: string;
}

export interface ResourceConfig {
  memory_bytes?: number;
  nano_cpus?: number;
}

export interface UpdateConfig {
  parallelism?: number;
  delay?: string;
  failure_action?: string;
  monitor?: string;
  max_failure_ratio?: number;
  order?: string;
}

export interface ServiceFormData {
  service_name: string;
  image: string;
  mode?: ServiceMode;
  replicas?: number;
  ports?: ServicePort[];
  constraints?: string[];
  resource_limits?: ResourceConfig;
  resource_reservations?: ResourceConfig;
  environment?: string[];
  labels?: Record<string, string>;
  update_config?: UpdateConfig;
  rollback_config?: UpdateConfig;
}

export interface ServiceScaleData {
  replicas: number;
}

// ==================== Stack ====================

export interface SwarmStackSummary {
  id: string;
  name: string;
  slug: string;
  status: StackStatus;
  service_count: number;
  last_deployed_at?: string;
  deploy_count: number;
}

export interface SwarmStack extends SwarmStackSummary {
  compose_file?: string;
  compose_variables: Record<string, string>;
  cluster_id: string;
  created_at: string;
  updated_at: string;
}

export interface StackFormData {
  name: string;
  compose_file: string;
  compose_variables?: Record<string, string>;
}

// ==================== Deployment ====================

export interface SwarmDeploymentSummary {
  id: string;
  deployment_type: DeploymentType;
  status: DeploymentStatus;
  service_id?: string;
  stack_id?: string;
  triggered_by?: string;
  trigger_source?: string;
  started_at?: string;
  completed_at?: string;
  duration_ms?: number;
  created_at: string;
}

export interface SwarmDeployment extends SwarmDeploymentSummary {
  previous_state: Record<string, unknown>;
  desired_state: Record<string, unknown>;
  result: Record<string, unknown>;
  git_sha?: string;
  cluster_id: string;
}

// ==================== Event ====================

export interface SwarmEventSummary {
  id: string;
  event_type: string;
  severity: EventSeverity;
  source_type: EventSourceType;
  source_name?: string;
  message: string;
  acknowledged: boolean;
  created_at: string;
}

export interface SwarmEvent extends SwarmEventSummary {
  source_id?: string;
  metadata: Record<string, unknown>;
  acknowledged_by?: string;
  acknowledged_at?: string;
  cluster_id: string;
}

// ==================== Docker Resources ====================

export interface SwarmNetwork {
  id: string;
  name: string;
  driver: string;
  scope: string;
  internal: boolean;
  attachable: boolean;
  ingress: boolean;
  labels: Record<string, string>;
  created_at: string;
}

export interface SwarmVolume {
  name: string;
  driver: string;
  mountpoint: string;
  scope: string;
  labels: Record<string, string>;
  created_at: string;
}

export interface SwarmSecret {
  id: string;
  name: string;
  created_at: string;
  updated_at: string;
}

export interface SwarmConfig {
  id: string;
  name: string;
  created_at: string;
  updated_at: string;
}

export interface SecretFormData {
  name: string;
  data: string;
  labels?: Record<string, string>;
}

export interface ConfigFormData {
  name: string;
  data: string;
  labels?: Record<string, string>;
}

export interface NetworkFormData {
  name: string;
  driver?: string;
  internal?: boolean;
  attachable?: boolean;
  labels?: Record<string, string>;
  options?: Record<string, string>;
}

// ==================== Available Resources (Import Pattern) ====================

export interface AvailableSwarmService {
  docker_service_id: string;
  service_name: string;
  image: string;
  mode: string;
  desired_replicas: number;
  ports: ServicePort[];
  labels: Record<string, string>;
  already_imported: boolean;
}

// ==================== Task (Docker task, not project task) ====================

export interface SwarmTask {
  id: string;
  docker_task_id: string;
  service_id: string;
  node_id?: string;
  status: string;
  desired_state: string;
  image: string;
  slot?: number;
  error?: string;
  created_at: string;
  updated_at: string;
}

// ==================== Health ====================

export interface ClusterHealthSummary {
  cluster_id: string;
  status: ClusterStatus;
  node_health: {
    total: number;
    ready: number;
    down: number;
    managers: number;
    workers: number;
  };
  service_health: {
    total: number;
    healthy: number;
    unhealthy: number;
    avg_health_percentage: number;
  };
  recent_events: {
    critical: number;
    warning: number;
    unacknowledged: number;
  };
  alerts: HealthAlert[];
}

export interface HealthAlert {
  severity: EventSeverity;
  message: string;
  source_type: EventSourceType;
  source_name?: string;
  timestamp: string;
}

// ==================== API Response Types ====================

export interface Pagination {
  current_page: number;
  per_page: number;
  total_pages: number;
  total_count: number;
}

export interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
}

export interface PaginatedApiResponse<T> {
  success: boolean;
  data?: T;
  pagination?: Pagination;
  error?: string;
}

// ==================== Filter Types ====================

export interface ClusterFilters {
  environment?: ClusterEnvironment;
  status?: ClusterStatus;
  q?: string;
}

export interface NodeFilters {
  role?: NodeRole;
  status?: NodeStatus;
  availability?: NodeAvailability;
}

export interface ServiceFilters {
  mode?: ServiceMode;
  stack_id?: string;
  q?: string;
}

export interface DeploymentFilters {
  deployment_type?: DeploymentType;
  status?: DeploymentStatus;
  service_id?: string;
  stack_id?: string;
}

export interface EventFilters {
  severity?: EventSeverity;
  source_type?: EventSourceType;
  acknowledged?: boolean;
  since?: string;
}

// ==================== Service Log Types ====================

export interface ServiceLogEntry {
  timestamp: string;
  message: string;
  stream: 'stdout' | 'stderr';
}

export interface ServiceLogOptions {
  tail?: number;
  since?: string;
  timestamps?: boolean;
  follow?: boolean;
}
