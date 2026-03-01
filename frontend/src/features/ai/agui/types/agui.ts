// AG-UI Session Status
export type AguiSessionStatus = 'idle' | 'running' | 'completed' | 'error' | 'cancelled';

// AG-UI Event Types (19 total from AG-UI protocol)
export type AguiEventType =
  | 'TEXT_MESSAGE_START'
  | 'TEXT_MESSAGE_CONTENT'
  | 'TEXT_MESSAGE_END'
  | 'TOOL_CALL_START'
  | 'TOOL_CALL_ARGS'
  | 'TOOL_CALL_END'
  | 'TOOL_CALL_RESULT'
  | 'STATE_SNAPSHOT'
  | 'STATE_DELTA'
  | 'MESSAGES_SNAPSHOT'
  | 'ACTIVITY_SNAPSHOT'
  | 'ACTIVITY_DELTA'
  | 'RUN_STARTED'
  | 'RUN_FINISHED'
  | 'RUN_ERROR'
  | 'STEP_STARTED'
  | 'STEP_FINISHED'
  | 'CUSTOM'
  | 'RAW';

// Event type categories for filtering
export type AguiEventCategory = 'text' | 'tool' | 'state' | 'lifecycle' | 'step' | 'other';

export const EVENT_CATEGORIES: Record<AguiEventCategory, AguiEventType[]> = {
  text: ['TEXT_MESSAGE_START', 'TEXT_MESSAGE_CONTENT', 'TEXT_MESSAGE_END'],
  tool: ['TOOL_CALL_START', 'TOOL_CALL_ARGS', 'TOOL_CALL_END', 'TOOL_CALL_RESULT'],
  state: ['STATE_SNAPSHOT', 'STATE_DELTA', 'MESSAGES_SNAPSHOT', 'ACTIVITY_SNAPSHOT', 'ACTIVITY_DELTA'],
  lifecycle: ['RUN_STARTED', 'RUN_FINISHED', 'RUN_ERROR'],
  step: ['STEP_STARTED', 'STEP_FINISHED'],
  other: ['CUSTOM', 'RAW'],
};

// AG-UI Session
export interface AguiSession {
  id: string;
  account_id: string;
  user_id: string | null;
  agent_id: string | null;
  thread_id: string;
  run_id: string | null;
  parent_run_id: string | null;
  status: AguiSessionStatus;
  state: Record<string, unknown>;
  tools: string[];
  capabilities: Record<string, unknown>;
  sequence_number: number;
  started_at: string | null;
  completed_at: string | null;
  last_event_at: string | null;
  expires_at: string | null;
  created_at: string;
  updated_at: string;
}

// AG-UI Event (SSE data shape from to_sse_data)
export interface AguiEvent {
  type: AguiEventType;
  sequence: number;
  message_id?: string;
  tool_call_id?: string;
  role?: string;
  content?: string;
  delta?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
  run_id?: string;
  step_id?: string;
  timestamp: string;
}

// RFC 6902 JSON Patch operation
export interface JsonPatchOperation {
  op: 'add' | 'remove' | 'replace' | 'move' | 'copy' | 'test';
  path: string;
  value?: unknown;
  from?: string;
}

// State push result
export interface StatePushResult {
  sequence: number;
  snapshot: Record<string, unknown>;
}

// API params
export interface AguiSessionFilterParams {
  status?: AguiSessionStatus;
  thread_id?: string;
  agent_id?: string;
}

export interface CreateSessionParams {
  thread_id?: string;
  agent_id?: string;
  tools?: string[];
  capabilities?: Record<string, unknown>;
}

export interface AguiEventsParams {
  after_sequence?: number;
  limit?: number;
}

export interface PushStateParams {
  session_id: string;
  state_delta: JsonPatchOperation[];
}
