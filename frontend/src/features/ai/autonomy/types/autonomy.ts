export interface AgentLineageNode {
  id: string;
  name: string;
  type: string;
  status: string;
  trust_level?: string;
  depth: number;
  children: AgentLineageNode[];
}

export interface TrustScore {
  id: string;
  agent_id: string;
  agent_name: string;
  reliability: number;
  cost_efficiency: number;
  safety: number;
  quality: number;
  speed: number;
  overall_score: number;
  tier: 'supervised' | 'monitored' | 'trusted' | 'autonomous';
  evaluation_count: number;
  last_evaluated_at?: string;
  promotable: boolean;
  demotable: boolean;
}

export interface AgentBudget {
  id: string;
  agent_id: string;
  agent_name: string;
  total_budget_cents: number;
  spent_cents: number;
  reserved_cents: number;
  currency: string;
  period_type: string;
  utilization_percentage: number;
  remaining_cents: number;
}

export interface AutonomyStats {
  total_agents: number;
  supervised: number;
  monitored: number;
  trusted: number;
  autonomous: number;
  pending_promotions: number;
  pending_demotions: number;
}
