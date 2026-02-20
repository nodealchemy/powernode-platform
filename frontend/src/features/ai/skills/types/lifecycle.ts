import type { SkillCategory, SkillCommand } from './index';

// === Proposal Types ===

export type ProposalStatus = 'draft' | 'proposed' | 'approved' | 'created' | 'rejected';

export interface SkillProposal {
  id: string;
  name: string;
  slug: string;
  description: string;
  category: SkillCategory;
  system_prompt: string;
  commands: SkillCommand[];
  tags: string[];
  metadata: Record<string, unknown>;
  status: ProposalStatus;
  trust_tier_at_proposal: string | null;
  auto_approved: boolean;
  rejection_reason: string | null;
  research_report: ResearchReport;
  suggested_dependencies: SuggestedDependency[];
  overlap_analysis: OverlapAnalysis;
  confidence_score: number;
  proposed_by_agent: { id: string; name: string } | null;
  proposed_by_user: { id: string; name: string; email: string } | null;
  reviewed_by: { id: string; name: string; email: string } | null;
  created_skill_id: string | null;
  parent_proposal_id: string | null;
  proposed_at: string | null;
  reviewed_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface SuggestedDependency {
  skill_id?: string;
  name: string;
  relation_type: string;
  confidence: number;
}

export interface OverlapAnalysis {
  overlapping_skills?: OverlappingSkill[];
  max_similarity?: number;
  recommendation?: string;
}

export interface OverlappingSkill {
  id: string;
  name: string;
  similarity: number;
  category: string;
}

// === Research Types ===

export interface ResearchRequest {
  topic: string;
  sources?: string[];
  agent_id?: string;
}

export interface ResearchReport {
  topic?: string;
  knowledge_graph_results?: KGResult[];
  knowledge_base_results?: KBResult[];
  mcp_tool_results?: McpToolResult[];
  federation_results?: FederationResult[];
  web_results?: WebResult[];
  suggested_name?: string;
  suggested_description?: string;
  suggested_category?: string;
  suggested_system_prompt?: string;
  suggested_commands?: SkillCommand[];
  suggested_tags?: string[];
  overlap_warnings?: OverlappingSkill[];
  confidence_score?: number;
}

export interface KGResult {
  node_id: string;
  name: string;
  similarity: number;
  node_type: string;
}

export interface KBResult {
  id: string;
  content: string;
  similarity: number;
  source: string;
}

export interface McpToolResult {
  server_name: string;
  tool_name: string;
  description: string;
  relevance: number;
}

export interface FederationResult {
  agent_name: string;
  capabilities: string[];
  endpoint: string;
}

export interface WebResult {
  title: string;
  summary: string;
  relevance: number;
}

// === Version Types ===

export type ChangeType = 'manual' | 'evolution' | 'consolidation' | 'ab_test';

export interface SkillVersion {
  id: string;
  ai_skill_id: string;
  version: string;
  system_prompt: string;
  commands: SkillCommand[];
  tags: string[];
  metadata: Record<string, unknown>;
  effectiveness_score: number;
  usage_count: number;
  success_count: number;
  failure_count: number;
  change_reason: string | null;
  change_type: ChangeType;
  is_active: boolean;
  is_ab_variant: boolean;
  ab_traffic_pct: number;
  created_by_agent: { id: string; name: string } | null;
  created_by_user: { id: string; name: string } | null;
  created_at: string;
}

// === Conflict Types ===

export type ConflictType = 'duplicate' | 'overlapping' | 'circular_dependency' | 'stale' | 'orphan' | 'version_drift';
export type ConflictSeverity = 'critical' | 'high' | 'medium' | 'low';
export type ConflictStatus = 'detected' | 'reviewing' | 'auto_resolved' | 'resolved' | 'dismissed';

export interface SkillConflict {
  id: string;
  conflict_type: ConflictType;
  severity: ConflictSeverity;
  status: ConflictStatus;
  skill_a: { id: string; name: string };
  skill_b: { id: string; name: string } | null;
  similarity_score: number | null;
  priority_score: number | null;
  resolution_strategy: string | null;
  resolution_details: Record<string, unknown>;
  auto_resolvable: boolean;
  detected_at: string | null;
  resolved_at: string | null;
  resolved_by: { id: string; name: string } | null;
  created_at: string;
}

// === Health & Optimization Types ===

export interface SkillHealthMetricsData {
  score: number;
  grade: 'A' | 'B' | 'C' | 'D' | 'F';
  components: {
    coverage: number;
    connectivity: number;
    freshness: number;
    effectiveness: number;
    conflict_penalty: number;
  };
  stats?: {
    total_skills: number;
    active_skills: number;
    total_nodes: number;
    total_edges: number;
    active_conflicts: number;
  };
  top_skills?: SkillMetricsSummary[];
  bottom_skills?: SkillMetricsSummary[];
}

export interface SkillMetricsSummary {
  id: string;
  name: string;
  effectiveness_score: number;
  usage_count: number;
}

export interface SkillMetrics {
  skill_id: string;
  name: string;
  effectiveness_score: number;
  positive_usage_count: number;
  negative_usage_count: number;
  success_rate: number;
  version_count: number;
  active_version: string | null;
  active_conflicts: number;
  last_used_at: string | null;
  last_optimized_at: string | null;
  usage_trend: 'rising' | 'stable' | 'declining' | 'new';
}

export interface OptimizationResult {
  operation: string;
  status: string;
  results: Record<string, unknown>;
  duration_ms: number;
}

// === API Response Wrappers ===

export interface ProposalsListResponse {
  success: boolean;
  data?: {
    proposals: SkillProposal[];
    pagination: {
      current_page: number;
      total_pages: number;
      total_count: number;
      per_page: number;
    };
  };
  error?: string;
}

export interface ProposalResponse {
  success: boolean;
  data?: { proposal: SkillProposal };
  error?: string;
}

export interface ResearchResponse {
  success: boolean;
  data?: { research: ResearchReport };
  error?: string;
}

export interface ConflictsListResponse {
  success: boolean;
  data?: { conflicts: SkillConflict[] };
  error?: string;
}

export interface HealthResponse {
  success: boolean;
  data?: { health: SkillHealthMetricsData };
  error?: string;
}

export interface SkillMetricsResponse {
  success: boolean;
  data?: { metrics: SkillMetrics };
  error?: string;
}

export interface VersionsListResponse {
  success: boolean;
  data?: { versions: SkillVersion[] };
  error?: string;
}

export interface OptimizationResponse {
  success: boolean;
  data?: { result: OptimizationResult };
  error?: string;
}
