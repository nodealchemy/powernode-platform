import { useQuery } from '@tanstack/react-query';
import { apiClient } from '@/shared/services/apiClient';
import type { KnowledgeNode, KnowledgeEdge, NodeDetail, HybridSearchResult, HybridSearchRawResult, GraphStatistics, NodeListParams, EdgeListParams, SearchParams, SubgraphParams, ShortestPathParams, PaginatedResponse } from '../types/knowledgeGraph';

const KG_KEYS = {
  all: ['knowledge-graph'] as const,
  nodes: (params?: NodeListParams) => [...KG_KEYS.all, 'nodes', params] as const,
  nodeDetail: (id: string) => [...KG_KEYS.all, 'node', id] as const,
  edges: (params?: EdgeListParams) => [...KG_KEYS.all, 'edges', params] as const,
  neighbors: (id: string) => [...KG_KEYS.all, 'neighbors', id] as const,
  subgraph: (params?: SubgraphParams) => [...KG_KEYS.all, 'subgraph', params] as const,
  shortestPath: (params?: ShortestPathParams) => [...KG_KEYS.all, 'shortest-path', params] as const,
  search: (params?: SearchParams) => [...KG_KEYS.all, 'search', params] as const,
  statistics: () => [...KG_KEYS.all, 'statistics'] as const,
};

// Unwrap the { success, data } envelope from render_success responses. Returns
// `unknown`; each caller asserts the concrete body shape it expects.
function unwrap(responseData: unknown): unknown {
  return (responseData as { data?: unknown } | null)?.data ?? responseData;
}

export function useKnowledgeNodes(params?: NodeListParams, enabled = true) {
  return useQuery({
    queryKey: KG_KEYS.nodes(params),
    queryFn: async (): Promise<PaginatedResponse<KnowledgeNode>> => {
      const response = await apiClient.get('/ai/knowledge_graph/nodes', { params });
      const body = unwrap(response.data) as { nodes?: KnowledgeNode[]; total_count?: number };
      const nodes = body?.nodes || [];
      const totalCount = body?.total_count || nodes.length;
      return {
        data: nodes,
        pagination: {
          current_page: params?.page || 1,
          total_pages: Math.ceil(totalCount / (params?.per_page || 100)),
          total_count: totalCount,
          per_page: params?.per_page || 100,
        },
      };
    },
    enabled,
  });
}

export function useKnowledgeNodeDetail(id: string, enabled = true) {
  return useQuery({
    queryKey: KG_KEYS.nodeDetail(id),
    queryFn: async () => {
      const response = await apiClient.get(`/ai/knowledge_graph/nodes/${id}`);
      const body = unwrap(response.data) as { node?: NodeDetail };
      return (body?.node || body) as NodeDetail;
    },
    enabled: enabled && !!id,
  });
}

export function useKnowledgeEdges(params?: EdgeListParams, enabled = true) {
  return useQuery({
    queryKey: KG_KEYS.edges(params),
    queryFn: async (): Promise<PaginatedResponse<KnowledgeEdge>> => {
      const response = await apiClient.get('/ai/knowledge_graph/edges', { params });
      const body = unwrap(response.data) as { edges?: KnowledgeEdge[] };
      const edges = body?.edges || [];
      return {
        data: edges,
        pagination: {
          current_page: params?.page || 1,
          total_pages: Math.ceil(edges.length / (params?.per_page || 500)),
          total_count: edges.length,
          per_page: params?.per_page || 500,
        },
      };
    },
    enabled,
  });
}

export function useHybridSearch(params: SearchParams, enabled = true) {
  return useQuery({
    queryKey: KG_KEYS.search(params),
    queryFn: async () => {
      const response = await apiClient.post('/ai/knowledge_graph/search', {
        query: params.query,
        mode: params.mode || 'hybrid',
        top_k: params.limit || 20,
        entity_type: params.entity_type,
      });
      const body = unwrap(response.data) as { results?: HybridSearchRawResult[] };
      const rawResults: HybridSearchRawResult[] = body?.results || [];

      return rawResults.map((r): HybridSearchResult => ({
        id: r.id,
        node: {
          id: r.id,
          name: r.metadata?.name as string || r.content.slice(0, 60),
          node_type: r.type || 'chunk',
          entity_type: (r.metadata?.entity_type as HybridSearchResult['node']['entity_type']) || 'document',
          description: r.content,
          confidence: r.score,
          mention_count: 0,
          status: 'active',
          created_at: '',
        },
        score: r.rrf_score ?? r.score,
        match_type: (r.source as HybridSearchResult['match_type']) || 'hybrid',
        highlights: r.content ? [r.content.slice(0, 200)] : [],
      }));
    },
    enabled: enabled && !!params.query && params.query.length >= 2,
  });
}

export function useGraphStatistics() {
  return useQuery({
    queryKey: KG_KEYS.statistics(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/knowledge_graph/statistics');
      return unwrap(response.data) as GraphStatistics;
    },
  });
}

