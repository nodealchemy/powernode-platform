import { useState, useEffect, useCallback, useRef } from 'react';
import { missionsApi } from '../api/missionsApi';
import type { TaskGraph, TaskGraphNode } from '../types/mission';
import { logger } from '@/shared/utils/logger';

interface UseMissionTaskGraphResult {
  taskGraph: TaskGraph | null;
  loading: boolean;
  error: string | null;
  refetch: () => void;
  updateTaskStatus: (taskId: string, status: string) => void;
}

export function useMissionTaskGraph(missionId: string | null): UseMissionTaskGraphResult {
  const [taskGraph, setTaskGraph] = useState<TaskGraph | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const isMounted = useRef(true);

  const fetchGraph = useCallback(async () => {
    if (!missionId) return;
    setLoading(true);
    setError(null);
    try {
      const response = await missionsApi.getTaskGraph(missionId);
      if (isMounted.current) {
        setTaskGraph(response.data.task_graph);
      }
    } catch (err) {
      if (isMounted.current) {
        const message = err instanceof Error ? err.message : 'Failed to load task graph';
        setError(message);
        logger.error('Failed to fetch task graph', { missionId, error: message });
      }
    } finally {
      if (isMounted.current) {
        setLoading(false);
      }
    }
  }, [missionId]);

  useEffect(() => {
    isMounted.current = true;
    fetchGraph();
    return () => { isMounted.current = false; };
  }, [fetchGraph]);

  const updateTaskStatus = useCallback((taskId: string, status: string) => {
    setTaskGraph(prev => {
      if (!prev) return prev;
      const updatedNodes: TaskGraphNode[] = prev.nodes.map(node =>
        node.id === taskId ? { ...node, status: status as TaskGraphNode['status'] } : node
      );
      return { ...prev, nodes: updatedNodes };
    });
  }, []);

  return {
    taskGraph,
    loading,
    error,
    refetch: fetchGraph,
    updateTaskStatus,
  };
}
