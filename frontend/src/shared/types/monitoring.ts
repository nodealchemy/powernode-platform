export interface ConversationMetrics {
  id: string;
  title: string;
  status: 'active' | 'inactive' | 'archived';
  // Nothing measures a conversation's health today: null, never a literal 100.
  health_score: number | null;
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
  success_rate: number | null;
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
  // The server reports the pool's SIZE only. Used and available are not
  // measured, so they are null rather than the size repeated or a 0.
  connection_pool: {
    size: number | null;
    used: number | null;
    available: number | null;
  };
  query_performance: {
    avg_query_time: number;
    slow_queries: number;
    deadlocks: number;
  };
  // Not reported by the dashboard endpoint: null, never a fabricated figure.
  storage_usage: {
    total_size: number;
    used_size: number;
    free_size: number;
  } | null;
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
