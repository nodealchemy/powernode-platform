import React from 'react';
import { CheckCircle, Settings, Loader2 } from 'lucide-react';
import { Loading } from '@/shared/components/ui/Loading';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { Modal } from '@/shared/components/ui/Modal';
import { RalphTaskExecutorSelect } from './RalphTaskExecutorSelect';
import { RalphTaskCard } from './RalphTaskCard';
import { RalphTaskEditForm } from './RalphTaskEditForm';
import { RalphTaskFiltersBar } from './RalphTaskFiltersBar';
import { useRalphTaskList } from './useRalphTaskList';
import ErrorAlert from '@/shared/components/ui/ErrorAlert';
import { cn } from '@/shared/utils/cn';
import type { RalphTaskSummary, PrdTask } from '@/shared/services/ai/types/ralph-types';

interface RalphTaskListProps {
  loopId: string;
  prdTasks?: PrdTask[];
  onPrdTasksChange?: (tasks: PrdTask[]) => void;
  onSavePrd?: (tasks?: PrdTask[]) => Promise<void>;
  isRunning?: boolean;
  onSelectTask?: (task: RalphTaskSummary) => void;
  className?: string;
}

export const RalphTaskList: React.FC<RalphTaskListProps> = ({
  loopId,
  prdTasks = [],
  onPrdTasksChange,
  onSavePrd,
  isRunning = false,
  onSelectTask,
  className,
}) => {
  const {
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
  } = useRalphTaskList({ loopId, prdTasks, onPrdTasksChange, onSavePrd, isRunning });

  if (loading && tasks.length === 0) {
    return (
      <div className="flex items-center justify-center p-8">
        <Loading size="lg" />
      </div>
    );
  }

  return (
    <div className={cn('space-y-4', className)}>
      <RalphTaskFiltersBar
        statusFilter={statusFilter}
        onStatusFilterChange={setStatusFilter}
        loading={loading}
        onRefresh={loadTasks}
        canEdit={canEdit}
        showAddTask={showAddTask}
        onToggleAddTask={() => setShowAddTask(!showAddTask)}
      />

      {error && <ErrorAlert message={error} />}

      {showAddTask && canEdit && (
        <RalphTaskEditForm
          newTask={newTask}
          onNewTaskChange={setNewTask}
          onAddTask={handleAddTask}
          onClose={() => setShowAddTask(false)}
          isSaving={savingTasks.has('__new__')}
        />
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
                  <span className="ml-2 text-theme-text-secondary">Loading task details...</span>
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
              <span className="ml-2 text-sm text-theme-text-secondary">Saving changes...</span>
            </div>
          )}
        </Modal>
      )}

      {tasks.length === 0 ? (
        <EmptyState
          icon={CheckCircle}
          title="No tasks found"
          description={statusFilter ? 'Try adjusting your filter' : 'Add tasks using the button above'}
        />
      ) : (
        <div className="space-y-2">
          {tasks.map((task) => (
            <RalphTaskCard
              key={task.id}
              task={task}
              isExpanded={expandedTasks.has(task.id)}
              details={taskDetails[task.id]}
              isLoadingDetails={loadingDetails.has(task.id)}
              canEdit={canEdit}
              onToggleExpansion={toggleTaskExpansion}
              onOpenConfig={openTaskConfig}
              onSelectTask={onSelectTask}
            />
          ))}
        </div>
      )}
      {ConfirmationDialog}
    </div>
  );
};

export default RalphTaskList;
