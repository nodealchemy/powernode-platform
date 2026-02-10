import { useMemo } from 'react';
import { useMcpServersForWorkflow } from '@/shared/hooks/useMcpServersForWorkflow';
import {
  McpToolForWorkflowBuilder,
  McpResourceForWorkflowBuilder,
  McpPromptForWorkflowBuilder
} from '@/shared/types/workflow';

interface UseMcpToolsForWorkflowResult {
  tools: McpToolForWorkflowBuilder[];
  loading: boolean;
  error: string | null;
}

interface UseMcpResourcesForWorkflowResult {
  resources: McpResourceForWorkflowBuilder[];
  loading: boolean;
  error: string | null;
}

interface UseMcpPromptsForWorkflowResult {
  prompts: McpPromptForWorkflowBuilder[];
  loading: boolean;
  error: string | null;
}

/**
 * Hook to get MCP tools for a specific server for use in the workflow builder
 */
export function useMcpToolsForWorkflow(serverId: string | undefined): UseMcpToolsForWorkflowResult {
  const { servers, loading, error } = useMcpServersForWorkflow();

  const tools = useMemo(() => {
    if (!serverId) return [];
    const server = servers.find(s => s.id === serverId);
    return server?.tools || [];
  }, [servers, serverId]);

  return { tools, loading, error };
}

/**
 * Hook to get MCP resources for a specific server for use in the workflow builder
 */
export function useMcpResourcesForWorkflow(serverId: string | undefined): UseMcpResourcesForWorkflowResult {
  const { servers, loading, error } = useMcpServersForWorkflow();

  const resources = useMemo(() => {
    if (!serverId) return [];
    const server = servers.find(s => s.id === serverId);
    return server?.resources || [];
  }, [servers, serverId]);

  return { resources, loading, error };
}

/**
 * Hook to get MCP prompts for a specific server for use in the workflow builder
 */
export function useMcpPromptsForWorkflow(serverId: string | undefined): UseMcpPromptsForWorkflowResult {
  const { servers, loading, error } = useMcpServersForWorkflow();

  const prompts = useMemo(() => {
    if (!serverId) return [];
    const server = servers.find(s => s.id === serverId);
    return server?.prompts || [];
  }, [servers, serverId]);

  return { prompts, loading, error };
}

/**
 * Hook to get a specific MCP tool by ID for use in the workflow builder
 */
export function useMcpToolForWorkflow(serverId: string | undefined, toolId: string | undefined): {
  tool: McpToolForWorkflowBuilder | null;
  loading: boolean;
  error: string | null;
} {
  const { tools, loading, error } = useMcpToolsForWorkflow(serverId);

  const tool = useMemo(() => {
    if (!toolId) return null;
    return tools.find(t => t.id === toolId) || null;
  }, [tools, toolId]);

  return { tool, loading, error };
}

/**
 * Hook to get all tools from all connected servers
 */
export function useAllMcpToolsForWorkflow(): {
  tools: Array<McpToolForWorkflowBuilder & { serverId: string; serverName: string }>;
  loading: boolean;
  error: string | null;
} {
  const { servers, loading, error } = useMcpServersForWorkflow();

  const tools = useMemo(() => {
    return servers.flatMap(server =>
      server.tools.map(tool => ({
        ...tool,
        serverId: server.id,
        serverName: server.name,
      }))
    );
  }, [servers]);

  return { tools, loading, error };
}

/**
 * Hook to get all resources from all connected servers
 */
export function useAllMcpResourcesForWorkflow(): {
  resources: Array<McpResourceForWorkflowBuilder & { serverId: string; serverName: string }>;
  loading: boolean;
  error: string | null;
} {
  const { servers, loading, error } = useMcpServersForWorkflow();

  const resources = useMemo(() => {
    return servers.flatMap(server =>
      server.resources.map(resource => ({
        ...resource,
        serverId: server.id,
        serverName: server.name,
      }))
    );
  }, [servers]);

  return { resources, loading, error };
}

/**
 * Hook to get all prompts from all connected servers
 */
export function useAllMcpPromptsForWorkflow(): {
  prompts: Array<McpPromptForWorkflowBuilder & { serverId: string; serverName: string }>;
  loading: boolean;
  error: string | null;
} {
  const { servers, loading, error } = useMcpServersForWorkflow();

  const prompts = useMemo(() => {
    return servers.flatMap(server =>
      server.prompts.map(prompt => ({
        ...prompt,
        serverId: server.id,
        serverName: server.name,
      }))
    );
  }, [servers]);

  return { prompts, loading, error };
}
