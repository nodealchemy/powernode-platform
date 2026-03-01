import React, { useState } from 'react';

interface Task {
  id: string;
  title: string;
  risk_tier: string;
  status: 'pending' | 'in_progress' | 'completed' | 'failed';
  dependencies: string[];
}

interface Props {
  tasks?: Task[];
}

const statusIcons: Record<string, string> = {
  pending: '\u25CB',
  in_progress: '\u25CF',
  completed: '\u2713',
  failed: '\u2717',
};

const statusColors: Record<string, string> = {
  pending: 'text-theme-secondary',
  in_progress: 'text-theme-accent',
  completed: 'text-theme-success',
  failed: 'text-theme-error',
};

const tierColors: Record<string, string> = {
  low: 'bg-theme-secondary-bg text-theme-secondary',
  standard: 'bg-theme-info-bg text-theme-info',
  high: 'bg-theme-warning-bg text-theme-warning',
  critical: 'bg-theme-error-bg text-theme-error',
};

export const TaskListManager: React.FC<Props> = ({ tasks = [] }) => {
  const [filter, setFilter] = useState<string>('all');

  const filteredTasks = filter === 'all' ? tasks : tasks.filter((t) => t.status === filter);

  const completedCount = tasks.filter((t) => t.status === 'completed').length;
  const progress = tasks.length > 0 ? (completedCount / tasks.length) * 100 : 0;

  if (tasks.length === 0) {
    return (
      <div className="card-theme p-6 text-center text-theme-secondary text-sm">
        No tasks generated yet. Use the PRD Generator to create tasks.
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Progress Bar */}
      <div className="card-theme p-3">
        <div className="flex items-center justify-between mb-2">
          <span className="text-sm font-medium text-theme-primary">
            {completedCount}/{tasks.length} tasks completed
          </span>
          <span className="text-xs text-theme-secondary">{progress.toFixed(0)}%</span>
        </div>
        <div className="h-2 bg-theme-secondary-bg rounded-full overflow-hidden">
          <div
            className="h-full bg-theme-success rounded-full transition-all"
            style={{ width: `${progress}%` }}
          />
        </div>
      </div>

      {/* Filter */}
      <div className="flex gap-2">
        {['all', 'pending', 'in_progress', 'completed', 'failed'].map((f) => (
          <button
            key={f}
            onClick={() => setFilter(f)}
            className={`px-3 py-1 text-xs rounded-full transition-colors ${
              filter === f
                ? 'bg-theme-accent text-theme-on-primary'
                : 'bg-theme-secondary-bg text-theme-secondary hover:text-theme-primary'
            }`}
          >
            {f === 'all' ? 'All' : f.replace(/_/g, ' ')}
          </button>
        ))}
      </div>

      {/* Task List */}
      <div className="space-y-2">
        {filteredTasks.map((task) => (
          <div key={task.id} className="card-theme p-3 flex items-start gap-3">
            <span className={`text-lg ${statusColors[task.status] || ''}`}>
              {statusIcons[task.status]}
            </span>
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2">
                <span className="text-sm font-medium text-theme-primary">{task.title}</span>
                <span className={`px-1.5 py-0.5 rounded text-[10px] font-medium ${tierColors[task.risk_tier] || ''}`}>
                  {task.risk_tier}
                </span>
              </div>
              {task.dependencies.length > 0 && (
                <div className="text-xs text-theme-secondary mt-1">
                  Depends on: {task.dependencies.join(', ')}
                </div>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};
