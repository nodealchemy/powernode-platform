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

