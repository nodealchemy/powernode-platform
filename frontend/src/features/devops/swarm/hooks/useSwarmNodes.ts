import { useState, useEffect, useCallback } from 'react';
import { swarmApi } from '../services/swarmApi';
import type { SwarmNodeSummary, SwarmNode, NodeUpdateData, NodeFilters } from '../types';

interface UseSwarmNodesOptions {
  clusterId: string;
  filters?: NodeFilters;
  autoLoad?: boolean;
}

interface UseSwarmNodesResult {
  nodes: SwarmNodeSummary[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
  getNode: (nodeId: string) => Promise<SwarmNode | null>;
  updateNode: (nodeId: string, data: NodeUpdateData) => Promise<SwarmNode | null>;
  drainNode: (nodeId: string) => Promise<boolean>;
  removeNode: (nodeId: string) => Promise<boolean>;
}

export function useSwarmNodes(options: UseSwarmNodesOptions): UseSwarmNodesResult {
  const { clusterId, filters, autoLoad = true } = options;
  const [nodes, setNodes] = useState<SwarmNodeSummary[]>([]);
  const [isLoading, setIsLoading] = useState(autoLoad);
  const [error, setError] = useState<string | null>(null);

  const fetchNodes = useCallback(async () => {
    if (!clusterId) return;

    setIsLoading(true);
    setError(null);

    const response = await swarmApi.getNodes(clusterId, filters);

    if (response.success && response.data) {
      setNodes(response.data.items ?? []);
    } else {
      setError(response.error || 'Failed to fetch nodes');
    }

    setIsLoading(false);
  }, [clusterId, filters]);

  useEffect(() => {
    if (autoLoad) {
      fetchNodes();
    }
  }, [fetchNodes, autoLoad]);

  const getNode = useCallback(async (nodeId: string): Promise<SwarmNode | null> => {
    const response = await swarmApi.getNode(clusterId, nodeId);
    if (response.success && response.data) {
      return response.data.node;
    }
    setError(response.error || 'Failed to fetch node');
    return null;
  }, [clusterId]);

  const updateNode = useCallback(async (nodeId: string, data: NodeUpdateData): Promise<SwarmNode | null> => {
    const response = await swarmApi.updateNode(clusterId, nodeId, data);
    if (response.success && response.data) {
      await fetchNodes();
      return response.data.node;
    }
    setError(response.error || 'Failed to update node');
    return null;
  }, [clusterId, fetchNodes]);

  const drainNode = useCallback(async (nodeId: string): Promise<boolean> => {
    const response = await swarmApi.drainNode(clusterId, nodeId);
    if (response.success) {
      await fetchNodes();
      return true;
    }
    setError(response.error || 'Failed to drain node');
    return false;
  }, [clusterId, fetchNodes]);

  const removeNode = useCallback(async (nodeId: string): Promise<boolean> => {
    const response = await swarmApi.removeNode(clusterId, nodeId);
    if (response.success) {
      await fetchNodes();
      return true;
    }
    setError(response.error || 'Failed to remove node');
    return false;
  }, [clusterId, fetchNodes]);

  return {
    nodes,
    isLoading,
    error,
    refetch: fetchNodes,
    getNode,
    updateNode,
    drainNode,
    removeNode,
  };
}
