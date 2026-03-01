/**
 * Agent API Types
 *
 * Type definitions for the Agents API service.
 * Extracted from AgentsApiService.ts for better modularity.
 */

import type { QueryFilters } from '@/shared/services/ai/BaseApiService';

// ===================================================================
// Filter Types
// ===================================================================

export interface AgentFilters extends QueryFilters {
  provider_id?: string;
  agent_type?: string;
  status?: 'active' | 'paused' | 'archived';
  visibility?: 'private' | 'account' | 'public';
  sort?: string;
  order?: 'asc' | 'desc';
  my_agents?: boolean;
}

export interface AgentExecutionFilters extends QueryFilters {
  status?: 'pending' | 'running' | 'completed' | 'failed' | 'cancelled';
  date_range?: {
    start?: string;
    end?: string;
  };
}

export interface ConversationFilters extends QueryFilters {
  status?: 'active' | 'paused' | 'completed' | 'archived';
}

// ===================================================================
// Request Types
// ===================================================================

export interface CreateAgentRequest {
  name: string;
  description?: string;
  agent_type: string;
  ai_provider_id: string;
  model_name?: string;
  system_instructions?: string;
  configuration?: Record<string, unknown>;
  input_schema?: Record<string, unknown>;
  output_schema?: Record<string, unknown>;
  max_iterations?: number;
  timeout_seconds?: number;
  visibility?: 'private' | 'account' | 'public';
  tags?: string[];
}

export interface ExecuteAgentRequest {
  input_parameters: Record<string, unknown>;
  ai_provider_id?: string;
  execution_options?: Record<string, unknown>;
}

export interface SendMessageRequest {
  message: {
    content: string;
    message_type?: string;
    metadata?: Record<string, unknown>;
  };
}

export interface SendMessageResponse {
  user_message: {
    id: string;
    conversation_id: string;
    role: string;
    content: string;
    content_preview: string;
    message_type: string;
    status: string;
    user: string | null;
    sequence_number: number;
    token_count: number;
    cost_usd: string;
    has_attachments: boolean;
    attachment_count: number;
    is_edited: boolean;
    created_at: string;
    processed_at: string | null;
    parent_message_id: string | null;
  };
  assistant_message: {
    id: string;
    conversation_id: string;
    role: string;
    content: string;
    content_preview: string;
    message_type: string;
    status: string;
    user: string | null;
    sequence_number: number;
    token_count: number;
    cost_usd: string;
    has_attachments: boolean;
    attachment_count: number;
    is_edited: boolean;
    created_at: string;
    processed_at: string | null;
    parent_message_id: string | null;
  } | null;
  error?: string;
  concierge_routed?: boolean;
  conversation: {
    id: string;
    message_count: number;
    total_tokens?: number;
    total_cost?: number;
  };
}

// ===================================================================
// Response Types
// ===================================================================

export interface AgentStats {
  total_executions: number;
  successful_executions: number;
  failed_executions: number;
  success_rate: number;
  avg_execution_time: number;
  estimated_total_cost: string;
  last_execution_at?: string;
  created_at: string;
}

export interface AgentAnalytics {
  execution_trends: Array<{
    date: string;
    count: number;
    success_rate: number;
  }>;
  performance_metrics: {
    avg_duration_ms: number;
    p50_duration_ms: number;
    p95_duration_ms: number;
    p99_duration_ms: number;
  };
  cost_analysis: {
    total_cost_usd: number;
    avg_cost_per_execution: number;
    cost_by_provider: Record<string, number>;
  };
}

export interface AgentType {
  value: string;
  label: string;
  description: string;
}

// ===================================================================
// Agent Skill Types
// ===================================================================

export interface AiAgentSkill {
  id: string;
  name: string;
  slug: string;
  category: string;
  is_active: boolean;
  priority: number;
  command_count: number;
}
