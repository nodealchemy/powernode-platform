/**
 * A2A Protocol Types
 * Types for Agent-to-Agent communication following A2A spec v0.3
 */

// ===================================================================
// Agent Card Types
// ===================================================================

export interface AgentCard {
  id: string;
  ai_agent_id?: string;
  account_id: string;
  name: string;
  description?: string;
  protocol_version: string;
  visibility: 'private' | 'internal' | 'public';
  status: 'active' | 'inactive' | 'deprecated';
  card_version: string;

  // A2A Capabilities
  capabilities: AgentCapabilities;
  authentication: AgentAuthentication;
  default_input_modes: string[];
  default_output_modes: string[];

  // Discovery
  endpoint_url?: string;
  provider_name?: string;
  provider_url?: string;
  documentation_url?: string;
  tags: string[];

  // Metrics
  task_count: number;
  success_count: number;
  failure_count: number;
  avg_response_time_ms?: number;

  // Timestamps
  published_at?: string;
  deprecated_at?: string;
  created_at: string;
  updated_at: string;
}

export interface AgentCapabilities {
  skills?: AgentSkill[];
  streaming?: boolean;
  push_notifications?: boolean;
  state_transition_history?: boolean;
  [key: string]: unknown;
}

export interface AgentSkill {
  id: string;
  name?: string;
  description?: string;
  inputSchema?: Record<string, unknown>;
  outputSchema?: Record<string, unknown>;
}

export interface AgentAuthentication {
  schemes?: ('bearer' | 'api_key' | 'oauth2' | 'basic' | 'none')[];
  credentials_url?: string;
}

export interface A2aAgentCardJson {
  name: string;
  description?: string;
  url?: string;
  provider?: {
    organization: string;
    url?: string;
  };
  version: string;
  documentationUrl?: string;
  capabilities: {
    streaming: boolean;
    pushNotifications: boolean;
    stateTransitionHistory: boolean;
    [key: string]: unknown;
  };
  authentication?: {
    schemes: string[];
    credentials?: string;
  };
  defaultInputModes: string[];
  defaultOutputModes: string[];
  skills: AgentSkill[];
}

// ===================================================================
// A2A Task Types
// ===================================================================

export interface A2aTask {
  id: string;
  task_id: string;
  account_id: string;
  status: A2aTaskStatus;

  // Agent relationships
  from_agent_id?: string;
  to_agent_id?: string;
  from_agent_card_id?: string;
  to_agent_card_id?: string;
  workflow_run_id?: string;
  parent_task_id?: string;

  // A2A Message
  message: A2aMessage;
  input: Record<string, unknown>;
  output: Record<string, unknown>;
  artifacts: A2aArtifact[];
  history: A2aMessage[];

  // Error handling
  error_message?: string;
  error_code?: string;
  error_details?: Record<string, unknown>;

  // Execution tracking
  sequence_number?: number;
  retry_count: number;
  max_retries: number;
  duration_ms?: number;
  cost?: number;
  tokens_used?: number;

  // External
  is_external: boolean;
  external_endpoint_url?: string;

  // Timestamps
  started_at?: string;
  completed_at?: string;
  created_at: string;
  updated_at: string;
}

export type A2aTaskStatus =
  | 'pending'
  | 'active'
  | 'completed'
  | 'failed'
  | 'cancelled'
  | 'input_required';

export interface A2aMessage {
  role: 'user' | 'agent';
  parts: A2aMessagePart[];
  timestamp?: string;
}

export type A2aMessagePart =
  | A2aTextPart
  | A2aFilePart
  | A2aDataPart;

export interface A2aTextPart {
  type: 'text';
  text: string;
}

export interface A2aFilePart {
  type: 'file';
  mimeType: string;
  uri?: string;
  data?: string; // base64
}

export interface A2aDataPart {
  type: 'data';
  mimeType?: string;
  data: Record<string, unknown>;
}

export interface A2aArtifact {
  id: string;
  name: string;
  mimeType?: string;
  uri?: string;
  parts: A2aMessagePart[];
  created_at?: string;
}

// ===================================================================
// A2A Task Event Types
// ===================================================================

export interface A2aTaskEvent {
  id: string;
  event_id: string;
  ai_a2a_task_id: string;
  event_type: A2aEventType;
  data: Record<string, unknown>;
  message?: string;

  // Status change
  previous_status?: A2aTaskStatus;
  new_status?: A2aTaskStatus;

  // Progress
  progress_current?: number;
  progress_total?: number;
  progress_message?: string;

  // Artifact
  artifact_id?: string;
  artifact_name?: string;
  artifact_mime_type?: string;

  created_at: string;
}

export type A2aEventType =
  | 'status_change'
  | 'artifact_added'
  | 'message'
  | 'progress'
  | 'error'
  | 'cancelled';

// ===================================================================
// A2A API Request/Response Types
// ===================================================================

export interface AgentCardFilters {
  skill?: string;
  tag?: string;
  query?: string;
  visibility?: 'private' | 'internal' | 'public';
  status?: 'active' | 'inactive' | 'deprecated';
  sort?: 'name' | 'created_at' | 'task_count' | 'success_rate';
  page?: number;
  per_page?: number;
}

export interface CreateAgentCardRequest {
  ai_agent_id?: string;
  name: string;
  description?: string;
  visibility?: 'private' | 'internal' | 'public';
  endpoint_url?: string;
  provider_name?: string;
  provider_url?: string;
  documentation_url?: string;
  capabilities?: AgentCapabilities;
  authentication?: AgentAuthentication;
  default_input_modes?: string[];
  default_output_modes?: string[];
  tags?: string[];
}

export interface UpdateAgentCardRequest extends Partial<CreateAgentCardRequest> {
  status?: 'active' | 'inactive' | 'deprecated';
}

export interface A2aTaskFilters {
  status?: A2aTaskStatus;
  from_agent_id?: string;
  to_agent_id?: string;
  workflow_run_id?: string;
  external?: boolean;
  since?: string;
  page?: number;
  per_page?: number;
}

export interface SubmitA2aTaskRequest {
  to_agent_card_id?: string;
  external_endpoint?: string;
  from_agent_id?: string;
  workflow_run_id?: string;
  message?: A2aMessage;
  text?: string; // Simplified input
  metadata?: Record<string, unknown>;
  authentication?: {
    type: 'bearer' | 'api_key' | 'basic';
    token?: string;
    key?: string;
    username?: string;
    password?: string;
  };
  subscribe?: boolean;
}

export interface A2aTaskResponse {
  task: A2aTaskJson;
  subscription?: {
    channel: string;
    events_url: string;
  };
}

export interface A2aTaskJson {
  id: string;
  sessionId?: string;
  status: {
    state: 'submitted' | 'working' | 'completed' | 'failed' | 'canceled' | 'input-required';
  };
  artifacts: {
    id: string;
    name: string;
    mimeType?: string;
    uri?: string;
    parts: A2aMessagePart[];
  }[];
  history: A2aMessage[];
  message?: A2aMessage;
  error?: {
    code: string;
    message: string;
    details?: Record<string, unknown>;
  };
  metadata?: Record<string, unknown>;
}

export interface DiscoverAgentsResponse {
  agents: A2aAgentCardJson[];
  total: number;
  page: number;
  per_page: number;
}

export interface A2aTaskEventsResponse {
  events: A2aTaskEvent[];
  task_status: {
    state: string;
  };
}

// ===================================================================
// SSE Event Types (for streaming)
// ===================================================================

export interface A2aSseEvent {
  id: string;
  type: string;
  data: string;
}

export interface A2aTaskStatusEvent {
  type: 'task.status';
  task: A2aTaskJson;
}

export interface A2aTaskProgressEvent {
  type: 'task.progress';
  taskId: string;
  current: number;
  total: number;
  message?: string;
}

export interface A2aTaskArtifactEvent {
  type: 'task.artifact';
  taskId: string;
  artifactId: string;
  name: string;
  mimeType?: string;
}

export interface A2aTaskCompleteEvent {
  type: 'task.complete';
  status: A2aTaskStatus;
}
