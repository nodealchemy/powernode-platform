import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { apiClient } from '@/shared/services/apiClient';
import type {
  McpApp,
  McpAppDetailed,
  McpAppRenderResult,
  McpAppProcessResult,
  McpAppFilterParams,
  CreateMcpAppParams,
  UpdateMcpAppParams,
  RenderMcpAppParams,
  ProcessMcpAppInputParams,
} from '../types/mcpApps';

const MCP_APPS_KEYS = {
  all: ['mcp-apps'] as const,
  list: (params?: McpAppFilterParams) => [...MCP_APPS_KEYS.all, 'list', params] as const,
  detail: (id: string) => [...MCP_APPS_KEYS.all, 'detail', id] as const,
};

export function useListMcpApps(params?: McpAppFilterParams) {
  return useQuery({
    queryKey: MCP_APPS_KEYS.list(params),
    queryFn: async () => {
      const response = await apiClient.get('/ai/mcp_apps', { params });
      return response.data?.data?.apps as McpApp[];
    },
  });
}

export function useGetMcpApp(id: string) {
  return useQuery({
    queryKey: MCP_APPS_KEYS.detail(id),
    queryFn: async () => {
      const response = await apiClient.get(`/ai/mcp_apps/${id}`);
      return response.data?.data?.app as McpAppDetailed;
    },
    enabled: !!id,
  });
}

export function useCreateMcpApp() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (params: CreateMcpAppParams) => {
      const response = await apiClient.post('/ai/mcp_apps', params);
      return response.data?.data?.app as McpApp;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: MCP_APPS_KEYS.list() });
    },
  });
}

export function useUpdateMcpApp() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async ({ id, ...params }: UpdateMcpAppParams) => {
      const response = await apiClient.patch(`/ai/mcp_apps/${id}`, params);
      return response.data?.data?.app as McpApp;
    },
    onSuccess: (_data, variables) => {
      queryClient.invalidateQueries({ queryKey: MCP_APPS_KEYS.list() });
      queryClient.invalidateQueries({ queryKey: MCP_APPS_KEYS.detail(variables.id) });
    },
  });
}

export function useDeleteMcpApp() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: async (id: string) => {
      const response = await apiClient.delete(`/ai/mcp_apps/${id}`);
      return response.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: MCP_APPS_KEYS.list() });
    },
  });
}

export function useRenderMcpApp() {
  return useMutation({
    mutationFn: async ({ id, ...params }: RenderMcpAppParams) => {
      const response = await apiClient.post(`/ai/mcp_apps/${id}/render`, params);
      return response.data?.data as McpAppRenderResult;
    },
  });
}

export function useProcessMcpAppInput() {
  return useMutation({
    mutationFn: async ({ id, ...params }: ProcessMcpAppInputParams) => {
      const response = await apiClient.post(`/ai/mcp_apps/${id}/process`, params);
      return response.data?.data as McpAppProcessResult;
    },
  });
}

export { MCP_APPS_KEYS };
