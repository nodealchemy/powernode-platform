import React, { useState, useEffect, useCallback } from 'react';
import {
  CheckCircle,
  XCircle,
  Clock,
  AlertTriangle,
  PlayCircle,
  SkipForward,
  RefreshCw,
  ChevronRight,
  ChevronDown,
  Bot,
  GitBranch,
  Target,
  Loader2,
  Edit3,
  X,
  Plus,
  Workflow,
  Container,
  Network,
  User,
  Globe,
  Settings,
  Calendar,
  Hash,
  Zap,
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Select } from '@/shared/components/ui/Select';
import { Loading } from '@/shared/components/ui/Loading';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Modal } from '@/shared/components/ui/Modal';
import { RalphTaskExecutorSelect } from './RalphTaskExecutorSelect';
import { ralphLoopsApi } from '@/shared/services/ai/RalphLoopsApiService';
import { cn } from '@/shared/utils/cn';
import type { RalphTask, RalphTaskSummary, RalphTaskFilters, RalphTaskStatus, RalphExecutionType, PrdTask, UpdateRalphTaskExecutorRequest } from '@/shared/services/ai/types/ralph-types';

interface RalphTaskListProps {
  loopId: string;
  prdTasks?: PrdTask[];
  onPrdTasksChange?: (tasks: PrdTask[]) => void;
  onSavePrd?: (tasks?: PrdTask[]) => Promise<void>;
  isRunning?: boolean;
  onSelectTask?: (task: RalphTaskSummary) => void;
  className?: string;
}

const statusConfig: Record<RalphTaskStatus, {
  variant: 'success' | 'warning' | 'danger' | 'info' | 'outline';
  label: string;
  icon: React.FC<{ className?: string }>;
}> = {
  pending: { variant: 'outline', label: 'Pending', icon: Clock },
  in_progress: { variant: 'info', label: 'In Progress', icon: PlayCircle },
  passed: { variant: 'success', label: 'Passed', icon: CheckCircle },
  failed: { variant: 'danger', label: 'Failed', icon: XCircle },
  blocked: { variant: 'warning', label: 'Blocked', icon: AlertTriangle },
  skipped: { variant: 'outline', label: 'Skipped', icon: SkipForward },
};

const statusOptions = [
  { value: '', label: 'All Tasks' },
  { value: 'pending', label: 'Pending' },
  { value: 'in_progress', label: 'In Progress' },
  { value: 'passed', label: 'Passed' },
  { value: 'failed', label: 'Failed' },
  { value: 'blocked', label: 'Blocked' },
  { value: 'skipped', label: 'Skipped' },
];

const executionTypeConfig: Record<RalphExecutionType, {
  label: string;
  icon: React.FC<{ className?: string }>;
}> = {
  agent: { label: 'AI Agent', icon: Bot },
  workflow: { label: 'Workflow', icon: Workflow },
  pipeline: { label: 'Pipeline', icon: GitBranch },
  a2a_task: { label: 'A2A Task', icon: Network },
  container: { label: 'Container', icon: Container },
  human: { label: 'Human Review', icon: User },
  community: { label: 'Community Agent', icon: Globe },
};

const matchStrategyLabels: Record<string, string> = {
  all: 'Match All',
  any: 'Match Any',
  weighted: 'Weighted',
};

const formatDate = (dateString?: string): string => {
  if (!dateString) return 'N/A';
  return new Date(dateString).toLocaleString();
};

export const RalphTaskList: React.FC<RalphTaskListProps> = ({
  loopId,
  prdTasks = [],
  onPrdTasksChange,
  onSavePrd,
  isRunning = false,
  onSelectTask,
  className,
}) => {
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

  const canEdit = !isRunning && onPrdTasksChange && onSavePrd;

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
      if (isExpanding) {
        next.add(taskId);
      } else {
        next.delete(taskId);
      }
      return next;
    });

    // Load task details if expanding and not already loaded
    if (isExpanding && !taskDetails[taskId]) {
      setLoadingDetails(prev => new Set(prev).add(taskId));
      try {
        const response = await ralphLoopsApi.getTask(loopId, taskId);
        setTaskDetails(prev => ({ ...prev, [taskId]: response.task }));
      } catch (err) {
        console.error('[RalphTaskList] Failed to load task details:', err);
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

  const handleDeleteTask = async (taskKey: string) => {
    if (!onPrdTasksChange || !onSavePrd) return;

    if (!window.confirm(`Are you sure you want to delete task "${taskKey}"? This action cannot be undone.`)) {
      return;
    }

    setDeletingTask(true);
    const newTasks = prdTasks.filter(t => t.key !== taskKey);
    onPrdTasksChange(newTasks);
    try {
      await onSavePrd(newTasks); // Pass tasks directly to avoid stale state
      setConfiguringTask(null);
      loadTasks(); // Refresh to reflect deletion
    } finally {
      setDeletingTask(false);
    }
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
      await onSavePrd(newTasks); // Pass tasks directly to avoid stale state
      setNewTask({ key: '', description: '', dependencies: [] });
      setShowAddTask(false);
      loadTasks(); // Refresh to show new task
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
      // Update PRD task definition
      const updatedTasks = prdTasks.map(t =>
        t.key === originalTaskKey
          ? { ...t, key: taskDef.key, description: taskDef.description, dependencies: taskDef.dependencies, acceptance_criteria: taskDef.acceptance_criteria }
          : t
      );
      onPrdTasksChange(updatedTasks);
      await onSavePrd(updatedTasks); // Pass tasks directly to avoid stale state

      // Update executor config via API
      await ralphLoopsApi.updateTask(loopId, taskId, executorConfig);

      // Refresh task details
      const response = await ralphLoopsApi.getTask(loopId, taskId);
      setTaskDetails(prev => ({ ...prev, [taskId]: response.task }));

      setConfiguringTask(null);
      loadTasks(); // Refresh to show updated task
    } catch (err) {
      console.error('[RalphTaskList] Failed to save task config:', err);
    } finally {
      setSavingConfig(false);
    }
  };

  const openTaskConfig = async (taskId: string) => {
    setConfiguringTask(taskId);
    // Load task details if not already loaded
    if (!taskDetails[taskId]) {
      setLoadingDetails(prev => new Set(prev).add(taskId));
      try {
        const response = await ralphLoopsApi.getTask(loopId, taskId);
        setTaskDetails(prev => ({ ...prev, [taskId]: response.task }));
      } catch (err) {
        console.error('[RalphTaskList] Failed to load task details:', err);
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

  if (loading && tasks.length === 0) {
    return (
      <div className="flex items-center justify-center p-8">
        <Loading size="lg" />
      </div>
    );
  }

  return (
    <div className={cn('space-y-4', className)}>
      {/* Header */}
      <div className="flex items-center justify-between">
        <h3 className="font-medium text-theme-text-primary">Tasks</h3>
        <div className="flex items-center gap-2">
          <Select
            value={statusFilter}
            onChange={(value) => setStatusFilter(value)}
            className="w-36"
          >
            {statusOptions.map((option) => (
              <option key={option.value} value={option.value}>
                {option.label}
              </option>
            ))}
          </Select>
          <Button variant="ghost" size="sm" onClick={loadTasks} disabled={loading}>
            <RefreshCw className={cn('w-4 h-4', loading && 'animate-spin')} />
          </Button>
          {canEdit && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => setShowAddTask(!showAddTask)}
              className={cn('min-w-[120px]', showAddTask && 'bg-theme-bg-secondary')}
            >
              <Plus className="w-4 h-4 mr-1" />
              Add Task
            </Button>
          )}
        </div>
      </div>

      {/* Error */}
      {error && (
        <div className="p-3 rounded-lg bg-theme-status-error/10 text-theme-status-error text-sm">
          {error}
        </div>
      )}

      {/* Add Task Form */}
      {showAddTask && canEdit && (
        <Card className="border-dashed border-2 border-theme-status-info/50">
          <CardContent className="p-4 space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-sm font-medium text-theme-text-primary">New Task</span>
              <Button variant="ghost" size="sm" onClick={() => setShowAddTask(false)}>
                <X className="w-4 h-4" />
              </Button>
            </div>
            <div className="grid grid-cols-[120px_1fr] gap-3 items-start">
              <label className="text-sm text-theme-text-secondary pt-2">Task Key</label>
              <Input
                value={newTask.key}
                onChange={(e) => setNewTask(prev => ({ ...prev, key: e.target.value }))}
                placeholder="task_key"
                className="font-mono"
              />
            </div>
            <div className="grid grid-cols-[120px_1fr] gap-3 items-start">
              <label className="text-sm text-theme-text-secondary pt-2">Description</label>
              <Textarea
                value={newTask.description}
                onChange={(e) => setNewTask(prev => ({ ...prev, description: e.target.value }))}
                placeholder="Task description..."
                rows={2}
              />
            </div>
            <div className="grid grid-cols-[120px_1fr] gap-3 items-start">
              <label className="text-sm text-theme-text-secondary pt-2">Dependencies</label>
              <Input
                value={newTask.dependencies?.join(', ') || ''}
                onChange={(e) => setNewTask(prev => ({
                  ...prev,
                  dependencies: e.target.value.split(',').map(d => d.trim()).filter(Boolean)
                }))}
                placeholder="task_1, task_2"
              />
            </div>
            <div className="grid grid-cols-[120px_1fr] gap-3 items-start">
              <label className="text-sm text-theme-text-secondary pt-2">Acceptance</label>
              <Input
                value={newTask.acceptance_criteria || ''}
                onChange={(e) => setNewTask(prev => ({ ...prev, acceptance_criteria: e.target.value }))}
                placeholder="Acceptance criteria..."
              />
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <Button variant="ghost" size="sm" onClick={() => setShowAddTask(false)}>
                Cancel
              </Button>
              <Button
                variant="primary"
                size="sm"
                onClick={handleAddTask}
                disabled={!newTask.key.trim() || savingTasks.has('__new__')}
              >
                {savingTasks.has('__new__') ? (
                  <Loader2 className="w-4 h-4 mr-1 animate-spin" />
                ) : (
                  <Plus className="w-4 h-4 mr-1" />
                )}
                Add Task
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      {/* Task Configuration Modal */}
      {configuringTask && (
        <Modal
          isOpen={true}
          onClose={() => setConfiguringTask(null)}
          title="Configure Task"
          icon={<Settings className="w-5 h-5 text-theme-brand-primary" />}
          size="lg"
        >
          {(() => {
            const configTask = getConfiguredTask();
            const isLoadingTask = isLoadingConfiguredTask();
            const prdTask = configTask ? getPrdTask(configTask.task_key) : null;

            if (isLoadingTask || !configTask) {
              return (
                <div className="flex items-center justify-center p-8">
                  <Loader2 className="w-6 h-6 animate-spin text-theme-brand-primary" />
                  <span className="ml-2 text-theme-text-secondary">
                    Loading task details...
                  </span>
                </div>
              );
            }
            return (
              <RalphTaskExecutorSelect
                taskId={configTask.id}
                taskKey={prdTask?.key || configTask.task_key}
                taskDescription={prdTask?.description || configTask.description}
                taskDependencies={prdTask?.dependencies || configTask.dependencies || []}
                taskAcceptanceCriteria={prdTask?.acceptance_criteria || configTask.acceptance_criteria}
                availableTaskKeys={tasks.map(t => t.task_key)}
                executionType={configTask.execution_type || 'agent'}
                executorId={configTask.executor_id}
                requiredCapabilities={configTask.required_capabilities}
                capabilityMatchStrategy={configTask.capability_match_strategy}
                delegationConfig={configTask.delegation_config}
                onSave={(taskDef, executorConfig) =>
                  handleSaveTaskConfig(configuringTask, configTask.task_key, taskDef, executorConfig)
                }
                onDelete={canEdit ? () => handleDeleteTask(configTask.task_key) : undefined}
                onCancel={() => setConfiguringTask(null)}
                isDeleting={deletingTask}
              />
            );
          })()}
          {savingConfig && (
            <div className="flex items-center justify-center p-4 border-t border-theme-border-primary">
              <Loader2 className="w-5 h-5 animate-spin text-theme-brand-primary" />
              <span className="ml-2 text-sm text-theme-text-secondary">
                Saving changes...
              </span>
            </div>
          )}
        </Modal>
      )}

      {tasks.length === 0 ? (
        <EmptyState
          icon={CheckCircle}
          title="No tasks found"
          description={
            statusFilter
              ? 'Try adjusting your filter'
              : 'Add tasks using the button above'
          }
        />
      ) : (
        <div className="space-y-2">
          {tasks.map((task) => {
            const status = statusConfig[task.status] || statusConfig.pending;
            const StatusIcon = status.icon;
            const isExpanded = expandedTasks.has(task.id);
            const details = taskDetails[task.id];
            const isLoadingDetails = loadingDetails.has(task.id);

            return (
              <Card
                key={task.id}
                className="transition-colors cursor-pointer hover:bg-theme-bg-secondary/50"
              >
                <CardContent className="p-3">
                  {/* Header row */}
                  <div
                    className="flex items-center justify-between"
                    onClick={() => toggleTaskExpansion(task.id)}
                  >
                    <div className="flex items-center gap-3 flex-1 min-w-0">
                      <StatusIcon className={cn(
                        'w-5 h-5 flex-shrink-0',
                        task.status === 'passed' && 'text-theme-status-success',
                        task.status === 'failed' && 'text-theme-status-error',
                        task.status === 'in_progress' && 'text-theme-status-info',
                        task.status === 'blocked' && 'text-theme-status-warning',
                        (task.status === 'pending' || task.status === 'skipped') && 'text-theme-text-secondary'
                      )} />
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <span className="font-mono text-xs text-theme-text-secondary">
                            {task.task_key}
                          </span>
                          <Badge variant={status.variant} size="sm">
                            {status.label}
                          </Badge>
                          {task.priority > 0 && (
                            <span className="text-xs text-theme-text-secondary">
                              P{task.priority}
                            </span>
                          )}
                        </div>
                        <p className={cn(
                          'text-sm text-theme-text-primary mt-1',
                          !isExpanded && 'truncate'
                        )}>
                          {task.description}
                        </p>
                      </div>
                    </div>
                    <div className="flex items-center gap-2 ml-2">
                      {task.iteration_count > 0 && (
                        <span className="text-xs text-theme-text-secondary">
                          {task.iteration_count} iteration{task.iteration_count !== 1 ? 's' : ''}
                        </span>
                      )}
                      {canEdit && (
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={(e) => {
                            e.stopPropagation();
                            openTaskConfig(task.id);
                          }}
                          title="Configure task"
                        >
                          <Edit3 className="w-4 h-4" />
                        </Button>
                      )}
                      {isExpanded ? (
                        <ChevronDown className="w-4 h-4 text-theme-text-secondary" />
                      ) : (
                        <ChevronRight className="w-4 h-4 text-theme-text-secondary" />
                      )}
                    </div>
                  </div>

                  {/* Expanded details */}
                  {isExpanded && (
                    <div className="mt-4 pt-3 border-t border-theme-border-primary space-y-4">
                      {isLoadingDetails ? (
                        <div className="flex items-center justify-center py-4">
                          <Loader2 className="w-5 h-5 animate-spin text-theme-text-secondary" />
                        </div>
                      ) : details ? (
                        <>
                          {/* Error Message - Show prominently if present */}
                          {details.error_message && (
                            <div className="p-3 rounded-lg bg-theme-status-error/10 border border-theme-status-error/30 text-theme-status-error text-sm">
                              <strong className="block mb-1">Error:</strong>
                              <span className="whitespace-pre-wrap">{details.error_message}</span>
                            </div>
                          )}

                          {/* Executor Configuration Section */}
                          <div className="p-3 rounded-lg bg-theme-bg-secondary space-y-3">
                            <h4 className="text-sm font-medium text-theme-text-primary flex items-center gap-2">
                              <Settings className="w-4 h-4" />
                              Executor Configuration
                            </h4>

                            <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
                              {/* Execution Type */}
                              <div>
                                <span className="text-theme-text-secondary block mb-1">Type</span>
                                {details.execution_type && (
                                  <div className="flex items-center gap-1.5">
                                    {(() => {
                                      const config = executionTypeConfig[details.execution_type];
                                      const Icon = config?.icon || Bot;
                                      return <Icon className="w-4 h-4 text-theme-brand-primary" />;
                                    })()}
                                    <span className="text-theme-text-primary font-medium">
                                      {executionTypeConfig[details.execution_type]?.label || details.execution_type}
                                    </span>
                                  </div>
                                )}
                              </div>

                              {/* Specific Executor */}
                              <div>
                                <span className="text-theme-text-secondary block mb-1">Executor ID</span>
                                <span className="text-theme-text-primary font-mono text-xs">
                                  {details.executor_id ? details.executor_id.slice(0, 8) + '...' : 'Auto-select'}
                                </span>
                              </div>

                              {/* Match Strategy */}
                              <div>
                                <span className="text-theme-text-secondary block mb-1">Match Strategy</span>
                                <span className="text-theme-text-primary">
                                  {matchStrategyLabels[details.capability_match_strategy || 'all'] || 'Match All'}
                                </span>
                              </div>

                              {/* Execution Attempts */}
                              <div>
                                <span className="text-theme-text-secondary block mb-1">Attempts</span>
                                <span className="text-theme-text-primary flex items-center gap-1">
                                  <Zap className="w-3 h-3" />
                                  {details.execution_attempts || 0}
                                </span>
                              </div>
                            </div>

                            {/* Required Capabilities */}
                            {details.required_capabilities && details.required_capabilities.length > 0 && (
                              <div>
                                <span className="text-theme-text-secondary text-sm block mb-1.5">Required Capabilities</span>
                                <div className="flex flex-wrap gap-1.5">
                                  {details.required_capabilities.map((cap) => (
                                    <Badge key={cap} variant="info" size="sm">
                                      {cap}
                                    </Badge>
                                  ))}
                                </div>
                              </div>
                            )}

                            {/* Delegation Config (if present) */}
                            {details.delegation_config && Object.keys(details.delegation_config).length > 0 && (
                              <div className="pt-2 border-t border-theme-border-primary">
                                <span className="text-theme-text-secondary text-sm block mb-2">Delegation Settings</span>
                                <div className="grid grid-cols-2 md:grid-cols-3 gap-2 text-xs">
                                  {details.delegation_config.timeout_seconds && (
                                    <div>
                                      <span className="text-theme-text-secondary">Timeout:</span>
                                      <span className="text-theme-text-primary ml-1">
                                        {details.delegation_config.timeout_seconds}s
                                      </span>
                                    </div>
                                  )}
                                  {details.delegation_config.max_delegation_depth && (
                                    <div>
                                      <span className="text-theme-text-secondary">Max Depth:</span>
                                      <span className="text-theme-text-primary ml-1">
                                        {details.delegation_config.max_delegation_depth}
                                      </span>
                                    </div>
                                  )}
                                  {details.delegation_config.retry_strategy && (
                                    <div>
                                      <span className="text-theme-text-secondary">Retry:</span>
                                      <span className="text-theme-text-primary ml-1 capitalize">
                                        {details.delegation_config.retry_strategy}
                                      </span>
                                    </div>
                                  )}
                                  {details.delegation_config.fallback_executor_type && (
                                    <div>
                                      <span className="text-theme-text-secondary">Fallback:</span>
                                      <span className="text-theme-text-primary ml-1">
                                        {executionTypeConfig[details.delegation_config.fallback_executor_type]?.label}
                                      </span>
                                    </div>
                                  )}
                                </div>
                              </div>
                            )}
                          </div>

                          {/* Task Details Section */}
                          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                            {/* Dependencies */}
                            <div>
                              <div className="flex items-center gap-1.5 text-sm mb-2">
                                <GitBranch className="w-4 h-4 text-theme-text-secondary" />
                                <span className="font-medium text-theme-text-primary">Dependencies</span>
                              </div>
                              {details.dependencies && details.dependencies.length > 0 ? (
                                <div className="flex flex-wrap gap-1.5">
                                  {details.dependencies.map((dep) => (
                                    <Badge key={dep} variant="outline" size="sm">
                                      {dep}
                                    </Badge>
                                  ))}
                                </div>
                              ) : (
                                <span className="text-sm text-theme-text-secondary">No dependencies</span>
                              )}
                            </div>

                            {/* Acceptance Criteria */}
                            <div>
                              <div className="flex items-center gap-1.5 text-sm mb-2">
                                <Target className="w-4 h-4 text-theme-text-secondary" />
                                <span className="font-medium text-theme-text-primary">Acceptance Criteria</span>
                              </div>
                              {details.acceptance_criteria ? (
                                <p className="text-sm text-theme-text-primary whitespace-pre-wrap bg-theme-bg-secondary p-2 rounded">
                                  {details.acceptance_criteria}
                                </p>
                              ) : (
                                <span className="text-sm text-theme-text-secondary">Not specified</span>
                              )}
                            </div>
                          </div>

                          {/* Timestamps & Iteration Info */}
                          <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-xs p-3 bg-theme-bg-secondary rounded-lg">
                            <div>
                              <div className="flex items-center gap-1 text-theme-text-secondary mb-1">
                                <Hash className="w-3 h-3" />
                                <span>Priority</span>
                              </div>
                              <span className="text-theme-text-primary font-medium">
                                {details.priority || 'Not set'}
                              </span>
                            </div>
                            <div>
                              <div className="flex items-center gap-1 text-theme-text-secondary mb-1">
                                <RefreshCw className="w-3 h-3" />
                                <span>Iterations</span>
                              </div>
                              <span className="text-theme-text-primary font-medium">
                                {details.iteration_count || 0}
                              </span>
                            </div>
                            <div>
                              <div className="flex items-center gap-1 text-theme-text-secondary mb-1">
                                <Calendar className="w-3 h-3" />
                                <span>Created</span>
                              </div>
                              <span className="text-theme-text-primary">
                                {formatDate(details.created_at)}
                              </span>
                            </div>
                            <div>
                              <div className="flex items-center gap-1 text-theme-text-secondary mb-1">
                                <Calendar className="w-3 h-3" />
                                <span>Last Iteration</span>
                              </div>
                              <span className="text-theme-text-primary">
                                {formatDate(details.iteration_completed_at)}
                              </span>
                            </div>
                          </div>

                          {/* Action Buttons */}
                          <div className="flex items-center gap-2 pt-2 border-t border-theme-border-primary">
                            {onSelectTask && (
                              <Button
                                variant="outline"
                                size="sm"
                                onClick={(e) => {
                                  e.stopPropagation();
                                  onSelectTask(task);
                                }}
                              >
                                <RefreshCw className="w-3 h-3 mr-1" />
                                View Iterations
                              </Button>
                            )}
                          </div>
                        </>
                      ) : (
                        <p className="text-sm text-theme-text-secondary">
                          Failed to load task details
                        </p>
                      )}
                    </div>
                  )}
                </CardContent>
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
};

export default RalphTaskList;
