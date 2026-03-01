import React from 'react';
import { ListTodo } from 'lucide-react';
import { TeamExecution, TeamTask } from '@/shared/services/ai/TeamsApiService';

interface TasksTabProps {
  selectedExecution: TeamExecution | null;
  tasks: TeamTask[];
  getStatusColor: (status: string) => string;
}

export const TasksTab: React.FC<TasksTabProps> = ({ selectedExecution, tasks, getStatusColor }) => {
  if (!selectedExecution) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <ListTodo size={48} className="mx-auto text-theme-secondary mb-4" />
        <h3 className="text-lg font-semibold text-theme-primary mb-2">Select an execution</h3>
        <p className="text-theme-secondary">Go to the Executions tab and click on an execution to view its tasks</p>
      </div>
    );
  }

  if (tasks.length === 0) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <ListTodo size={48} className="mx-auto text-theme-secondary mb-4" />
        <h3 className="text-lg font-semibold text-theme-primary mb-2">No tasks</h3>
        <p className="text-theme-secondary">Tasks will appear as the execution progresses</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {tasks.map(task => (
        <div key={task.id} className="bg-theme-surface border border-theme rounded-lg p-4">
          <div className="flex items-center justify-between mb-2">
            <div className="flex items-center gap-3">
              <h3 className="font-medium text-theme-primary">{task.description || task.task_type || 'Task'}</h3>
              <span className={`px-2 py-1 text-xs rounded ${getStatusColor(task.status)}`}>{task.status}</span>
            </div>
          </div>
          <div className="flex gap-4 text-xs text-theme-secondary">
            {task.assigned_role_name && <span>Role: {task.assigned_role_name}</span>}
            {task.assigned_agent_id && <span>Agent: {task.assigned_agent_id.slice(0, 8)}</span>}
            {task.priority && <span>Priority: {task.priority}</span>}
            {task.tokens_used > 0 && <span>{task.tokens_used.toLocaleString()} tokens</span>}
            {task.duration_ms && <span>{(task.duration_ms / 1000).toFixed(1)}s</span>}
          </div>
        </div>
      ))}
    </div>
  );
};
