// Hook for managing workflow detail data loading and state

import { useState, useCallback, useEffect } from 'react';
import { workflowsApi } from '@/shared/services/ai';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { AiWorkflow } from '@/shared/types/workflow';

interface UseWorkflowDetailOptions {
  workflowId: string;
  isOpen: boolean;
}

interface UseWorkflowDetailReturn {
  workflow: AiWorkflow | null;
  loading: boolean;
  error: string | null;
  lastUpdateTime: Date;
  loadWorkflow: () => Promise<void>;
  setWorkflow: React.Dispatch<React.SetStateAction<AiWorkflow | null>>;
  setLastUpdateTime: React.Dispatch<React.SetStateAction<Date>>;
}

export const useWorkflowDetail = ({
  workflowId,
  isOpen
}: UseWorkflowDetailOptions): UseWorkflowDetailReturn => {
  const { addNotification } = useNotifications();

  const [workflow, setWorkflow] = useState<AiWorkflow | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [lastUpdateTime, setLastUpdateTime] = useState(new Date());

  const loadWorkflow = useCallback(async () => {
    if (!workflowId || !isOpen) return;

    try {
      setLoading(true);
      setError(null);
      const response = await workflowsApi.getWorkflow(workflowId);
      setWorkflow(response);
      setLastUpdateTime(new Date());
    } catch (_error) {
      setError('Failed to load workflow details. Please try again.');
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to load workflow details'
      });
    } finally {
      setLoading(false);
    }
  }, [workflowId, isOpen, addNotification]);

  // Reset and load when modal opens
  useEffect(() => {
    if (isOpen && workflowId) {
      setLoading(true);
      setWorkflow(null);
      setError(null);
      loadWorkflow();
    }
  }, [isOpen, workflowId, loadWorkflow]);

  return {
    workflow,
    loading,
    error,
    lastUpdateTime,
    loadWorkflow,
    setWorkflow,
    setLastUpdateTime
  };
};
