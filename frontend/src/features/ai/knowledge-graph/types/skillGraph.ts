export type SkillEdgeRelation = 'requires' | 'enhances' | 'composes' | 'succeeds';

export const SKILL_EDGE_DISPLAY: Record<SkillEdgeRelation, { label: string; strokeColor: string; animated: boolean; description: string }> = {
  requires: { label: 'Requires', strokeColor: 'var(--color-warning)', animated: true, description: 'Must have this skill first' },
  enhances: { label: 'Enhances', strokeColor: 'var(--color-info)', animated: false, description: 'Improves this skill' },
  composes: { label: 'Composes', strokeColor: 'var(--color-success)', animated: false, description: 'Part of a composed skill' },
  succeeds: { label: 'Succeeds', strokeColor: 'var(--color-interactive-primary)', animated: false, description: 'Follows this skill' },
};

export interface SkillGraphNode {
  id: string;
  name: string;
  category: string;
  status: string;
  command_count: number;
  connector_count: number;
  skill_id: string;
  dependency_count: number;
}

export interface SkillGraphEdge {
  id: string;
  source_skill_id: string;
  target_skill_id: string;
  source_skill_name?: string;
  target_skill_name?: string;
  relation_type: SkillEdgeRelation;
  weight: number;
  confidence: number;
}

export interface SkillGraphResult {
  nodes: SkillGraphNode[];
  edges: SkillGraphEdge[];
}

export interface SkillGraphNodeData {
  label: string;
  category: string;
  status: string;
  commandCount: number;
  connectorCount: number;
  skillId: string;
  coverageStatus?: 'covered' | 'uncovered' | 'partial';
  dependencyCount: number;
  [key: string]: unknown;
}

export interface SkillCoverageResult {
  total_skill_nodes: number;
  covered_count: number;
  uncovered_count: number;
  coverage_ratio: number;
  category_coverage: Record<string, { covered: number; total: number }>;
  uncovered_skills: Array<{ id: string; name: string; category: string }>;
  agent_skill_mapping: AgentSkillMapping[];
  connectivity_score: number;
}

export interface SkillRecommendation {
  agent_id: string;
  agent_name: string;
  fills_skills: Array<{ id: string; name: string }>;
  fills_count: number;
}

export interface AgentSkillMapping {
  agent_id: string;
  agent_name: string;
  role: string;
  skills: Array<{ id: string; name: string; category: string }>;
}

export interface SkillEdgeCreationState {
  sourceId: string;
  targetId: string;
  sourceName: string;
  targetName: string;
}

export interface AutoDetectSuggestion {
  target_skill_id: string;
  target_skill_name: string;
  suggested_relation: SkillEdgeRelation;
  confidence: number;
  similarity: number;
}

export interface AgentSkillContext {
  agent_id: string;
  agent_name: string;
  skills: SkillGraphNode[];
  edges: SkillGraphEdge[];
  total_skills: number;
  total_dependencies: number;
}

export interface SkillDiscoveryResult {
  traversal_path: SkillGraphNode[];
  discovered_skills: SkillGraphNode[];
  recommended_edges: SkillGraphEdge[];
}
