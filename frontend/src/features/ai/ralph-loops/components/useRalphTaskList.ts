import { useState, useEffect, useCallback } from 'react';
import { ralphLoopsApi } from '@/shared/services/ai/RalphLoopsApiService';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { logger } from '@/shared/utils/logger';
import type {
  RalphTask,
  RalphTaskSummary,
  RalphTaskFilters,
  RalphTaskStatus,
  UpdateRalphTaskExecutorRequest,
  PrdTask,
} from '@/shared/services/ai/types/ralph-types';

interface UseRalphTaskListOptions {
  loopId: string;
  prdTasks: PrdTask[];
  onPrdTasksChange?: (tasks: PrdTask[]) => void;
  onSavePrd?: (tasks?: PrdTask[]) => Promise<void>;
  isRunning: boolean;
}

export function useRalphTaskList({
  loopId,
  prdTasks,
  onPrdTasksChange,
  onSavePrd,
  isRunning,
}: UseRalphTaskListOptions) {
  const { confirm, ConfirmationDialog } = useConfirmation();
  const [tasks, setTasks] = useState<RalphTaskSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [statusFilter, setStatusFilter] = useState<string>('');
  const [expandedTasks, setExpandedTasks] = useState<Set<string>>(new Set());
  const [taskDetails, setTaskDetails] = useState<Record<string, RalphTask>>({});
  const [loadingDetails, setLoadingDetails] = useState<Set<string>>(new Set());
  const [savingTasks, setSavingTasks] = useState<Set<string>>(new Set());
  const [showAddTask, setShowAddTask] = useState(false);
  const [newTask, setNewTask] = useState<PrdTask>({ key: '', description: '', dependencies: [] });
  const [configuringTask, setConfiguringTask] = useState<string | null>(null);
  const [savingConfig, setSavingConfig] = useState(false);
  const [deletingTask, setDeletingTask] = useState(false);

  const canEdit = !isRunning && !!onPrdTasksChange && !!onSavePrd;

  const loadTasks = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const filters: RalphTaskFilters = { per_page: 100 };
      if (statusFilter) filters.status = statusFilter as RalphTaskStatus;
      const response = await ralphLoopsApi.getTasks(loopId, filters);
      setTasks(response.items || []);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load tasks');
    } finally {
      setLoading(false);
    }
  }, [loopId, statusFilter]);

  useEffect(() => {
    loadTasks();
  }, [loadTasks]);

  const toggleTaskExpansion = useCallback(async (taskId: string) => {
    const isExpanding = !expandedTasks.has(taskId);
    setExpandedTasks(prev => {
      const next = new Set(prev);
      if (isExpanding) next.add(taskId);
      else next.delete(taskId);
      return next;
    });

    if (isExpanding && !taskDetails[taskId]) {
      setLoadingDetails(prev => new Set(prev).add(taskId));
      try {
        const response = await ralphLoopsApi.getTask(loopId, taskId);
        setTaskDetails(prev => ({ ...prev, [taskId]: response.task }));
      } catch (err) {
        logger.error('[RalphTaskList] Failed to load task details:', err);
      } finally {
        setLoadingDetails(prev => {
          const next = new Set(prev);
          next.delete(taskId);
          return next;
        });
      }
    }
  }, [expandedTasks, taskDetails, loopId]);

  const getPrdTask = (taskKey: string): PrdTask | undefined => {
    return prdTasks.find(t => t.key === taskKey);
  };

  const handleDeleteTask = (taskKey: string) => {
    if (!onPrdTasksChange || !onSavePrd) return;
    confirm({
      title: 'Delete Task',
      message: `Are you sure you want to delete task "${taskKey}"? This action cannot be undone.`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        setDeletingTask(true);
        const newTasks = prdTasks.filter(t => t.key !== taskKey);
        onPrdTasksChange(newTasks);
        try {
          await onSavePrd(newTasks);
          setConfiguringTask(null);
          loadTasks();
        } finally {
          setDeletingTask(false);
        }
      },
    });
  };

  const handleAddTask = async () => {
    if (!onPrdTasksChange || !onSavePrd || !newTask.key.trim()) return;
    const taskToAdd: PrdTask = {
      ...newTask,
      key: newTask.key.replace(/\s/g, '_'),
      priority: prdTasks.length + 1,
    };
    const newTasks = [...prdTasks, taskToAdd];
    onPrdTasksChange(newTasks);
    setSavingTasks(prev => new Set(prev).add('__new__'));
    try {
      await onSavePrd(newTasks);
      setNewTask({ key: '', description: '', dependencies: [] });
      setShowAddTask(false);
      loadTasks();
    } finally {
      setSavingTasks(prev => {
        const next = new Set(prev);
        next.delete('__new__');
        return next;
      });
    }
  };

  const handleSaveTaskConfig = async (
    taskId: string,
    originalTaskKey: string,
    taskDef: { key: string; description: string; dependencies: string[]; acceptance_criteria?: string },
    executorConfig: UpdateRalphTaskExecutorRequest
  ) => {
    if (!onPrdTasksChange || !onSavePrd) return;
    setSavingConfig(true);
    try {
      const updatedTasks = prdTasks.map(t =>
        t.key === originalTaskKey
          ? { ...t, key: taskDef.key, description: taskDef.description, dependencies: taskDef.dependencies, acceptance_criteria: taskDef.acceptance_criteria }
          : t
      );
      onPrdTasksChange(updatedTasks);
      await onSavePrd(updatedTasks);
      await ralphLoopsApi.updateTask(loopId, taskId, executorConfig);
      const response = await ralphLoopsApi.getTask(loopId, taskId);
      setTaskDetails(prev => ({ ...prev, [taskId]: response.task }));
      setConfiguringTask(null);
      loadTasks();
    } catch (err) {
      logger.error('[RalphTaskList] Failed to save task config:', err);
    } finally {
      setSavingConfig(false);
    }
  };

  const openTaskConfig = async (taskId: string) => {
    setConfiguringTask(taskId);
    if (!taskDetails[taskId]) {
      setLoadingDetails(prev => new Set(prev).add(taskId));
      try {
        const response = await ralphLoopsApi.getTask(loopId, taskId);
        setTaskDetails(prev => ({ ...prev, [taskId]: response.task }));
      } catch (err) {
        logger.error('[RalphTaskList] Failed to load task details:', err);
      } finally {
        setLoadingDetails(prev => {
          const next = new Set(prev);
          next.delete(taskId);
          return next;
        });
      }
    }
  };

  const getConfiguredTask = (): RalphTask | null => {
    if (!configuringTask) return null;
    return taskDetails[configuringTask] || null;
  };

  const isLoadingConfiguredTask = (): boolean => {
    if (!configuringTask) return false;
    return loadingDetails.has(configuringTask);
  };

  return {
    tasks,
    loading,
    error,
    statusFilter,
    setStatusFilter,
    expandedTasks,
    taskDetails,
    loadingDetails,
    savingTasks,
    showAddTask,
    setShowAddTask,
    newTask,
    setNewTask,
    configuringTask,
    setConfiguringTask,
    savingConfig,
    deletingTask,
    canEdit,
    loadTasks,
    toggleTaskExpansion,
    getPrdTask,
    handleDeleteTask,
    handleAddTask,
    handleSaveTaskConfig,
    openTaskConfig,
    getConfiguredTask,
    isLoadingConfiguredTask,
    ConfirmationDialog,
  };
}
