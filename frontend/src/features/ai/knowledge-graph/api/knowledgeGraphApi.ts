import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { apiClient } from '@/shared/services/apiClient';
import type {
  KnowledgeNode,
  KnowledgeEdge,
  NodeDetail,
  SubgraphResult,
  ShortestPathResult,
  HybridSearchResult,
  GraphStatistics,
  NodeListParams,
  EdgeListParams,
  SearchParams,
  SubgraphParams,
  ShortestPathParams,
  CreateNodeParams,
  CreateEdgeParams,
  PaginatedResponse,
} from '../types/knowledgeGraph';

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

export function useKnowledgeNodes(params?: NodeListParams) {
  return useQuery({
    queryKey: KG_KEYS.nodes(params),
    queryFn: async (): Promise<PaginatedResponse<KnowledgeNode>> => {
      const response = await apiClient.get('/ai/knowledge_graph/nodes', { params });
      const nodes = response.data?.nodes || [];
      const totalCount = response.data?.total_count || nodes.length;
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
  });
}

export function useKnowledgeNodeDetail(id: string, enabled = true) {
  return useQuery({
    queryKey: KG_KEYS.nodeDetail(id),
    queryFn: async () => {
      const response = await apiClient.get(`/ai/knowledge_graph/nodes/${id}`);
      return response.data?.data as NodeDetail;
    },
    enabled: enabled && !!id,
  });
}

export function useKnowledgeEdges(params?: EdgeListParams) {
  return useQuery({
    queryKey: KG_KEYS.edges(params),
    queryFn: async (): Promise<PaginatedResponse<KnowledgeEdge>> => {
      const response = await apiClient.get('/ai/knowledge_graph/edges', { params });
      const edges = response.data?.edges || [];
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
  });
}

export function useNodeNeighbors(id: string, enabled = true) {
  return useQuery({
    queryKey: KG_KEYS.neighbors(id),
    queryFn: async () => {
      const response = await apiClient.get(`/ai/knowledge_graph/nodes/${id}/neighbors`);
      return response.data?.data as KnowledgeNode[];
    },
    enabled: enabled && !!id,
  });
}

export function useSubgraph(params: SubgraphParams, enabled = true) {
  return useQuery({
    queryKey: KG_KEYS.subgraph(params),
    queryFn: async () => {
      const response = await apiClient.post('/ai/knowledge_graph/subgraph', params);
      return response.data?.data as SubgraphResult;
    },
    enabled: enabled && params.node_ids.length > 0,
  });
}

export function useShortestPath(params: ShortestPathParams, enabled = true) {
  return useQuery({
    queryKey: KG_KEYS.shortestPath(params),
    queryFn: async () => {
      const response = await apiClient.get('/ai/knowledge_graph/shortest_path', { params });
      return response.data?.data as ShortestPathResult;
    },
    enabled: enabled && !!params.source_id && !!params.target_id,
  });
}

export function useHybridSearch(params: SearchParams, enabled = true) {
  return useQuery({
    queryKey: KG_KEYS.search(params),
    queryFn: async () => {
      const response = await apiClient.get('/ai/knowledge_graph/nodes', {
        params: {
          search: params.query,
          mode: params.mode,
          entity_type: params.entity_type,
          per_page: params.limit,
        },
      });
      return response.data?.data as HybridSearchResult[];
    },
    enabled: enabled && !!params.query && params.query.length >= 2,
  });
}

export function useGraphStatistics() {
  return useQuery({
    queryKey: KG_KEYS.statistics(),
    queryFn: async () => {
      const response = await apiClient.get('/ai/knowledge_graph/statistics');
      return response.data as GraphStatistics;
    },
  });
}

export function useCreateNode() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (params: CreateNodeParams) => {
      const response = await apiClient.post('/ai/knowledge_graph/nodes', { node: params });
      return response.data?.data as KnowledgeNode;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: KG_KEYS.nodes() });
      queryClient.invalidateQueries({ queryKey: KG_KEYS.statistics() });
    },
  });
}

export function useCreateEdge() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (params: CreateEdgeParams) => {
      const response = await apiClient.post('/ai/knowledge_graph/edges', { edge: params });
      return response.data?.data as KnowledgeEdge;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: KG_KEYS.edges() });
      queryClient.invalidateQueries({ queryKey: KG_KEYS.statistics() });
      queryClient.invalidateQueries({ queryKey: KG_KEYS.nodes() });
    },
  });
}
