// AI Context Types

export type ContextType = 'agent_memory' | 'knowledge_base' | 'shared_context';
export type ContextScope = 'account' | 'agent' | 'team' | 'workflow';
export type EntryType = 'fact' | 'preference' | 'interaction' | 'knowledge' | 'skill' | 'relationship' | 'goal' | 'constraint';
export type AccessType = 'read' | 'write' | 'search' | 'export' | 'delete';

// AI Persistent Context
export interface AiPersistentContext {
  id: string;
  account_id: string;
  ai_agent_id?: string;
  name: string;
  description?: string;
  context_type: ContextType;
  scope: ContextScope;
  context_data: Record<string, unknown>;
  access_control: AccessControl;
  retention_policy: RetentionPolicy;
  version: number;
  data_size_bytes: number;
  entry_count: number;
  is_archived: boolean;
  expires_at?: string;
  archived_at?: string;
  last_accessed_at?: string;
  created_at: string;
  updated_at: string;
  ai_agent?: AiAgentSummary;
}

export interface AiPersistentContextSummary {
  id: string;
  name: string;
  context_type: ContextType;
  scope: ContextScope;
  entry_count: number;
  data_size_bytes: number;
  is_archived: boolean;
  last_accessed_at?: string;
  ai_agent?: AiAgentSummary;
}

export interface AiAgentSummary {
  id: string;
  name: string;
  agent_type?: string;
}

export interface AccessControl {
  owner_id?: string;
  allowed_agents?: string[];
  allowed_users?: string[];
  public_read?: boolean;
}

export interface RetentionPolicy {
  max_entries?: number;
  max_age_days?: number;
  auto_archive_days?: number;
  auto_delete_days?: number;
  importance_threshold?: number;
}

// AI Context Entry
export interface AiContextEntry {
  id: string;
  ai_persistent_context_id: string;
  entry_type: EntryType;
  key: string;
  content: Record<string, unknown>;
  content_text?: string;
  source?: string;
  importance_score: number;
  confidence_score: number;
  access_count: number;
  embedding?: number[];
  metadata: Record<string, unknown>;
  tags: string[];
  related_entry_ids: string[];
  expires_at?: string;
  embedding_updated_at?: string;
  last_accessed_at?: string;
  created_at: string;
  updated_at: string;
}

export interface AiContextEntrySummary {
  id: string;
  entry_type: EntryType;
  key: string;
  content_text?: string;
  importance_score: number;
  access_count: number;
  tags: string[];
  created_at: string;
}

// AI Context Access Log
export interface AiContextAccessLog {
  id: string;
  ai_persistent_context_id: string;
  ai_context_entry_id?: string;
  accessor_type: string;
  accessor_id: string;
  access_type: AccessType;
  query_text?: string;
  results_count?: number;
  response_time_ms?: number;
  metadata: Record<string, unknown>;
  created_at: string;
}

// API Response Types
export interface Pagination {
  current_page: number;
  per_page: number;
  total_pages: number;
  total_count: number;
}

export interface ContextsResponse {
  success: boolean;
  data?: {
    contexts: AiPersistentContextSummary[];
    pagination: Pagination;
  };
  error?: string;
}

export interface ContextResponse {
  success: boolean;
  data?: {
    context: AiPersistentContext;
  };
  error?: string;
}

export interface EntriesResponse {
  success: boolean;
  data?: {
    entries: AiContextEntrySummary[];
    pagination: Pagination;
  };
  error?: string;
}

export interface EntryResponse {
  success: boolean;
  data?: {
    entry: AiContextEntry;
  };
  error?: string;
}

export interface SearchResponse {
  success: boolean;
  data?: {
    results: SearchResult[];
    query: string;
    search_type: 'keyword' | 'semantic' | 'hybrid';
    total_results: number;
  };
  error?: string;
}

export interface SearchResult {
  entry: AiContextEntrySummary;
  score: number;
  highlights?: string[];
  context?: AiPersistentContextSummary;
}

export interface AgentMemoryResponse {
  success: boolean;
  data?: {
    memories: AiContextEntrySummary[];
    agent: AiAgentSummary;
    context: AiPersistentContextSummary;
    pagination: Pagination;
  };
  error?: string;
}

export interface ContextStatsResponse {
  success: boolean;
  data?: {
    stats: {
      total_entries: number;
      entries_by_type: Record<string, number>;
      data_size_bytes: number;
      avg_importance_score: number;
      access_count_total: number;
      entries_with_embeddings: number;
      recent_accesses: number;
    };
  };
  error?: string;
}

export interface ExportResponse {
  success: boolean;
  data?: {
    export_url: string;
    format: 'json' | 'csv';
    entry_count: number;
    expires_at: string;
  };
  error?: string;
}

export interface ImportResponse {
  success: boolean;
  data?: {
    imported: number;
    skipped: number;
    errors: string[];
  };
  error?: string;
}

// Form Data Types
export interface ContextFormData {
  name: string;
  description?: string;
  context_type: ContextType;
  scope: ContextScope;
  ai_agent_id?: string;
  retention_policy?: RetentionPolicy;
  access_control?: AccessControl;
}

export interface EntryFormData {
  entry_type: EntryType;
  key: string;
  content: Record<string, unknown>;
  content_text?: string;
  source?: string;
  importance_score?: number;
  confidence_score?: number;
  tags?: string[];
  metadata?: Record<string, unknown>;
  expires_at?: string;
}

// Filter Types
export interface ContextFilters {
  context_type?: ContextType;
  scope?: ContextScope;
  ai_agent_id?: string;
  is_archived?: boolean;
}

export interface EntryFilters {
  entry_type?: EntryType;
  min_importance?: number;
  tags?: string[];
  has_embedding?: boolean;
  q?: string;
}

export interface SearchParams {
  query: string;
  context_id?: string;
  search_type?: 'keyword' | 'semantic' | 'hybrid';
  entry_types?: EntryType[];
  min_score?: number;
  limit?: number;
}
