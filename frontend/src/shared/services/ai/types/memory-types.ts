/**
 * Memory System Types
 * Types for the persistent memory system (factual, experiential, working)
 */

// ===================================================================
// Memory Entry Types
// ===================================================================

export type MemoryType = 'factual' | 'experiential' | 'working';

export type EntryType =
  | 'fact'
  | 'memory'
  | 'preference'
  | 'knowledge'
  | 'tool_result'
  | 'observation'
  | 'insight';

export type SourceType =
  | 'user_input'
  | 'agent_output'
  | 'workflow'
  | 'import'
  | 'api'
  | 'system';

export interface MemoryEntry {
  id: string;
  entry_key: string;
  entry_type?: EntryType;
  memory_type: MemoryType;
  content: MemoryContent;
  content_text?: string;
  metadata: Record<string, unknown>;

  // Scores
  importance_score: number;
  confidence_score: number;
  decay_rate: number;

  // Context
  context_tags: string[];
  task_context?: Record<string, unknown>;
  outcome_success?: boolean;

  // Source
  source_type?: SourceType;
  source_id?: string;
  ai_agent_id?: string;

  // Versioning
  version: number;
  previous_version_id?: string;

  // Usage
  access_count: number;
  last_accessed_at?: string;

  // Lifecycle
  expires_at?: string;
  archived_at?: string;

  // Timestamps
  created_at: string;
  updated_at: string;

  // Search result fields
  similarity?: number;
}

export type MemoryContent =
  | { text: string; value?: unknown }
  | { value: unknown }
  | { items: unknown[] }
  | Record<string, unknown>;

// ===================================================================
// Persistent Context Types
// ===================================================================

export interface PersistentContext {
  id: string;
  account_id: string;
  name: string;
  description?: string;
  context_type: 'agent_memory' | 'knowledge_base' | 'shared_context';
  scope_type: 'account' | 'agent' | 'team' | 'workflow';
  scope_id?: string;
  access_level: 'public' | 'private';
  version: number;
  entry_count: number;
  data_size_bytes: number;
  retention_policy: RetentionPolicy;
  expires_at?: string;
  archived_at?: string;
  created_at: string;
  updated_at: string;
}

export interface RetentionPolicy {
  max_entries?: number;
  max_age_days?: number;
  archive_before_delete?: boolean;
}

// ===================================================================
// Memory API Request/Response Types
// ===================================================================

export interface MemoryFilters {
  memory_type?: MemoryType;
  entry_type?: EntryType;
  source_type?: SourceType;
  tags?: string[];
  min_importance?: number;
  outcome_success?: boolean;
  limit?: number;
  offset?: number;
  [key: string]: string | number | boolean | string[] | Record<string, unknown> | undefined;
}

export interface CreateMemoryRequest {
  entry_key?: string;
  entry_type?: EntryType;
  memory_type?: MemoryType;
  content: MemoryContent | string;
  metadata?: Record<string, unknown>;
  importance?: number;
  confidence?: number;
  tags?: string[];
  task_context?: Record<string, unknown>;
  outcome_success?: boolean;
  source_type?: SourceType;
  source_id?: string;
  expires_at?: string;
}

export interface UpdateMemoryRequest {
  content?: MemoryContent | string;
  metadata?: Record<string, unknown>;
  importance?: number;
  tags?: string[];
  create_version?: boolean;
}

export interface MemorySearchRequest {
  query: string;
  memory_type?: MemoryType;
  tags?: string[];
  outcome_filter?: 'success' | 'failure';
  threshold?: number;
  limit?: number;
}

export interface MemorySearchResponse {
  results: MemoryEntry[];
  total: number;
  query: string;
  threshold: number;
}

export interface ContextInjectionRequest {
  task_id?: string;
  query?: string;
  token_budget?: number;
  include_types?: MemoryType[];
}

export interface ContextInjectionResponse {
  context: string;
  token_estimate: number;
  breakdown: {
    factual: number;
    working: number;
    experiential: number;
  };
}

export interface MemoryStatsResponse {
  total_entries: number;
  by_type: {
    factual: number;
    experiential: number;
    working: number;
  };
  by_outcome: {
    success: number;
    failure: number;
    unknown: number;
  };
  avg_importance: number;
  oldest_entry?: string;
  newest_entry?: string;
}

// ===================================================================
// Working Memory Types (Redis-backed)
// ===================================================================

export interface WorkingMemoryState {
  task_state?: Record<string, unknown>;
  conversation_context?: ConversationMessage[];
  intermediate_results?: Record<string, unknown>;
  scratch_pad?: string;
  [key: string]: unknown;
}

export interface ConversationMessage {
  role: 'user' | 'assistant' | 'system';
  content: string;
  timestamp: string;
}

export interface WorkingMemoryStats {
  key_count: number;
  total_size_bytes: number;
  context_id: string;
  agent_id: string;
  task_id?: string;
  workflow_run_id?: string;
}

// ===================================================================
// Memory Visualization Types
// ===================================================================

export interface MemoryTimelineEntry {
  id: string;
  entry_key: string;
  memory_type: MemoryType;
  content_preview: string;
  importance_score: number;
  outcome_success?: boolean;
  created_at: string;
  tags: string[];
}

export interface MemoryCluster {
  id: string;
  label: string;
  entries: string[];
  centroid?: number[];
  similarity_score: number;
}

export interface MemoryGraph {
  nodes: MemoryGraphNode[];
  edges: MemoryGraphEdge[];
}

export interface MemoryGraphNode {
  id: string;
  label: string;
  memory_type: MemoryType;
  importance: number;
}

export interface MemoryGraphEdge {
  source: string;
  target: string;
  similarity: number;
}
