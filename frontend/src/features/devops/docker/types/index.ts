// Docker Host Management Types

// ==================== Enums / Unions ====================

export type HostEnvironment = 'staging' | 'production' | 'development' | 'custom';
export type HostStatus = 'pending' | 'connected' | 'disconnected' | 'error' | 'maintenance';

export type ContainerState = 'created' | 'running' | 'paused' | 'restarting' | 'exited' | 'removing' | 'dead';

export type EventSeverity = 'info' | 'warning' | 'error' | 'critical';
export type EventSourceType = 'host' | 'container' | 'image' | 'network' | 'volume';

export type ActivityType = 'create' | 'start' | 'stop' | 'restart' | 'remove' | 'pull' | 'image_remove' | 'image_tag';
export type ActivityStatus = 'pending' | 'running' | 'completed' | 'failed';

// ==================== Docker Host ====================

export interface DockerHostSummary {
  id: string;
  name: string;
  slug: string;
  api_endpoint: string;
  environment: HostEnvironment;
  status: HostStatus;
  container_count: number;
  image_count: number;
  last_synced_at?: string;
  auto_sync: boolean;
  tls_verify: boolean;
  has_tls_credentials: boolean;
}

export interface DockerHost extends DockerHostSummary {
  description?: string;
  api_version: string;
  docker_version?: string;
  os_type?: string;
  architecture?: string;
  kernel_version?: string;
  memory_bytes?: number;
  cpu_count?: number;
  storage_bytes?: number;
  sync_interval_seconds: number;
  consecutive_failures: number;
  metadata: Record<string, unknown>;
  created_at: string;
  updated_at: string;
}

export interface HostFormData {
  name: string;
  description?: string;
  api_endpoint: string;
  api_version?: string;
  environment: HostEnvironment;
  auto_sync?: boolean;
  tls_verify?: boolean;
  sync_interval_seconds?: number;
  tls_ca?: string;
  tls_cert?: string;
  tls_key?: string;
}

// ==================== Docker Container ====================

export interface DockerContainerSummary {
  id: string;
  docker_container_id: string;
  name: string;
  image: string;
  state: ContainerState;
  status_text?: string;
  ports: ContainerPort[];
  started_at?: string;
  created_at: string;
}

export interface DockerContainer extends DockerContainerSummary {
  image_id?: string;
  mounts: ContainerMount[];
  networks: Record<string, unknown>;
  labels: Record<string, string>;
  environment: string[];
  command?: string;
  restart_policy?: string;
  restart_count: number;
  size_rw?: number;
  finished_at?: string;
  last_seen_at?: string;
  docker_host_id: string;
  updated_at: string;
}

export interface ContainerPort {
  ip?: string;
  private_port: number;
  public_port?: number;
  type: string;
}

export interface ContainerMount {
  type: string;
  source: string;
  destination: string;
  mode: string;
  rw: boolean;
}

export interface ContainerCreateData {
  name: string;
  image: string;
  command?: string;
  environment?: Record<string, string>;
  ports?: Record<string, string>;
  volumes?: Record<string, string>;
  restart_policy?: string;
  labels?: Record<string, string>;
}

export interface ContainerStats {
  cpu_percentage: number;
  memory_usage: number;
  memory_limit: number;
  memory_percentage: number;
  network_rx: number;
  network_tx: number;
  block_read: number;
  block_write: number;
  pids: number;
}

// ==================== Docker Image ====================

export interface DockerImageSummary {
  id: string;
  docker_image_id: string;
  primary_tag: string;
  repo_tags: string[];
  size_bytes?: number;
  size_mb?: number;
  container_count: number;
  docker_created_at?: string;
  created_at: string;
}

export interface DockerImage extends DockerImageSummary {
  repo_digests: string[];
  virtual_size?: number;
  architecture?: string;
  os?: string;
  labels: Record<string, string>;
  last_seen_at?: string;
  docker_host_id: string;
  updated_at: string;
}

export interface ImagePullData {
  image: string;
  tag?: string;
  credential_id?: string;
}

export interface ImageTagData {
  repo: string;
  tag: string;
}

// ==================== Docker Event ====================

export interface DockerEventSummary {
  id: string;
  event_type: string;
  severity: EventSeverity;
  source_type: EventSourceType;
  source_name?: string;
  message: string;
  acknowledged: boolean;
  created_at: string;
}

export interface DockerEvent extends DockerEventSummary {
  source_id?: string;
  metadata: Record<string, unknown>;
  acknowledged_by?: string;
  acknowledged_at?: string;
  docker_host_id: string;
}

// ==================== Docker Activity ====================

export interface DockerActivitySummary {
  id: string;
  activity_type: ActivityType;
  status: ActivityStatus;
  container_id?: string;
  image_id?: string;
  triggered_by?: string;
  trigger_source?: string;
  started_at?: string;
  completed_at?: string;
  duration_ms?: number;
  created_at: string;
}

export interface DockerActivity extends DockerActivitySummary {
  params: Record<string, unknown>;
  result: Record<string, unknown>;
  docker_host_id: string;
}

// ==================== Docker Resources ====================

export interface DockerNetwork {
  id: string;
  name: string;
  driver: string;
  scope: string;
  internal: boolean;
  attachable: boolean;
  labels: Record<string, string>;
  created_at: string;
}

export interface DockerVolume {
  name: string;
  driver: string;
  mountpoint: string;
  scope: string;
  labels: Record<string, string>;
  created_at: string;
}

export interface NetworkFormData {
  name: string;
  driver?: string;
  internal?: boolean;
  attachable?: boolean;
  labels?: Record<string, string>;
  options?: Record<string, string>;
}

export interface VolumeFormData {
  name: string;
  driver?: string;
  labels?: Record<string, string>;
  options?: Record<string, string>;
}

// ==================== Available Resources (Import Pattern) ====================

export interface AvailableDockerContainer {
  docker_container_id: string;
  name: string;
  image: string;
  state: string;
  status_text?: string;
  ports: ContainerPort[];
  already_imported: boolean;
}

export interface AvailableDockerImage {
  docker_image_id: string;
  repo_tags: string[];
  size_bytes?: number;
  container_count: number;
  already_imported: boolean;
}

// ==================== Registry ====================

export interface RegistryInfo {
  credential_id: string;
  credential_name: string;
  provider_type: string;
  registry_url: string;
}

// ==================== Health ====================

export interface HostHealthSummary {
  host_id: string;
  status: HostStatus;
  container_health: {
    total: number;
    running: number;
    stopped: number;
    paused: number;
  };
  image_stats: {
    total: number;
    dangling: number;
  };
  recent_events: {
    critical: number;
    warning: number;
    unacknowledged: number;
  };
  resource_usage: {
    memory_bytes?: number;
    memory_total?: number;
    cpu_count?: number;
    storage_bytes?: number;
  };
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

// ==================== Filter Types ====================

export interface HostFilters {
  environment?: HostEnvironment;
  status?: HostStatus;
  q?: string;
}

export interface ContainerFilters {
  state?: ContainerState;
  q?: string;
}

export interface ImageFilters {
  dangling?: boolean;
  q?: string;
}

export interface ActivityFilters {
  activity_type?: ActivityType;
  status?: ActivityStatus;
}

export interface EventFilters {
  severity?: EventSeverity;
  source_type?: EventSourceType;
  acknowledged?: boolean;
  since?: string;
}

// ==================== Container Log Types ====================

export interface ContainerLogEntry {
  timestamp: string;
  message: string;
  stream: 'stdout' | 'stderr';
}

export interface ContainerLogOptions {
  tail?: number;
  since?: string;
  timestamps?: boolean;
}
