export type EntityType = 'concept' | 'entity' | 'document' | 'agent' | 'skill' | 'context' | 'learning';
export type RelationType = 'related_to' | 'depends_on' | 'derived_from' | 'part_of' | 'uses' | 'produces' | 'contradicts' | 'supports';
export type SearchMode = 'hybrid' | 'vector' | 'keyword' | 'graph';

export interface KnowledgeNode {
  id: string;
  name: string;
  entity_type: EntityType;
  description: string;
  properties: Record<string, unknown>;
  embedding_status: 'pending' | 'complete' | 'failed';
  edge_count: number;
  created_at: string;
  updated_at: string;
}

export interface KnowledgeEdge {
  id: string;
  source_id: string;
  target_id: string;
  source_name?: string;
  target_name?: string;
  relation_type: RelationType;
  weight: number;
  properties: Record<string, unknown>;
  created_at: string;
}

export interface NodeDetail extends KnowledgeNode {
  neighbors: NeighborInfo[];
  incoming_edges: KnowledgeEdge[];
  outgoing_edges: KnowledgeEdge[];
}

export interface NeighborInfo {
  node: KnowledgeNode;
  edge: KnowledgeEdge;
  direction: 'incoming' | 'outgoing';
}

export interface SubgraphResult {
  nodes: KnowledgeNode[];
  edges: KnowledgeEdge[];
}

export interface ShortestPathResult {
  path: KnowledgeNode[];
  edges: KnowledgeEdge[];
  total_weight: number;
}

export interface HybridSearchResult {
  id: string;
  node: KnowledgeNode;
  score: number;
  match_type: SearchMode;
  highlights: string[];
}

export interface GraphStatistics {
  total_nodes: number;
  total_edges: number;
  by_entity_type: Record<EntityType, number>;
  by_relation_type: Record<RelationType, number>;
  avg_edges_per_node: number;
  most_connected: KnowledgeNode[];
}

export interface NodeListParams {
  page?: number;
  per_page?: number;
  entity_type?: EntityType;
  search?: string;
}

export interface EdgeListParams {
  page?: number;
  per_page?: number;
  relation_type?: RelationType;
  source_id?: string;
  target_id?: string;
}

export interface SearchParams {
  query: string;
  mode?: SearchMode;
  entity_type?: EntityType;
  limit?: number;
}

export interface SubgraphParams {
  node_ids: string[];
  depth?: number;
}

export interface ShortestPathParams {
  source_id: string;
  target_id: string;
}

export interface CreateNodeParams {
  name: string;
  entity_type: EntityType;
  description: string;
  properties?: Record<string, unknown>;
}

export interface CreateEdgeParams {
  source_id: string;
  target_id: string;
  relation_type: RelationType;
  weight?: number;
  properties?: Record<string, unknown>;
}

export interface PaginatedResponse<T> {
  data: T[];
  pagination: {
    current_page: number;
    total_pages: number;
    total_count: number;
    per_page: number;
  };
}
