import React from 'react';
import { Card } from '@/shared/components/ui/Card';
import type { SwarmTask } from '../types';

interface ServiceTaskListProps {
  tasks: SwarmTask[];
}

export const ServiceTaskList: React.FC<ServiceTaskListProps> = ({ tasks }) => {
  if (tasks.length === 0) {
    return (
      <Card variant="default" padding="lg" className="text-center">
        <p className="text-theme-secondary">No tasks found for this service.</p>
      </Card>
    );
  }

  const getStatusColor = (status: string): string => {
    switch (status) {
      case 'running': return 'bg-theme-success bg-opacity-10 text-theme-success';
      case 'complete': return 'bg-theme-info bg-opacity-10 text-theme-info';
      case 'failed': return 'bg-theme-error bg-opacity-10 text-theme-error';
      case 'pending': case 'preparing': return 'bg-theme-warning bg-opacity-10 text-theme-warning';
      default: return 'bg-theme-surface text-theme-secondary';
    }
  };

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-theme">
            <th className="text-left px-4 py-3 text-xs font-medium text-theme-tertiary uppercase">Task ID</th>
            <th className="text-left px-4 py-3 text-xs font-medium text-theme-tertiary uppercase">Slot</th>
            <th className="text-left px-4 py-3 text-xs font-medium text-theme-tertiary uppercase">Status</th>
            <th className="text-left px-4 py-3 text-xs font-medium text-theme-tertiary uppercase">Desired</th>
            <th className="text-left px-4 py-3 text-xs font-medium text-theme-tertiary uppercase">Image</th>
            <th className="text-left px-4 py-3 text-xs font-medium text-theme-tertiary uppercase">Error</th>
            <th className="text-left px-4 py-3 text-xs font-medium text-theme-tertiary uppercase">Updated</th>
          </tr>
        </thead>
        <tbody>
          {tasks.map((task) => (
            <tr key={task.id} className="border-b border-theme hover:bg-theme-surface-hover">
              <td className="px-4 py-3 text-theme-primary font-mono text-xs">
                {task.docker_task_id.substring(0, 12)}
              </td>
              <td className="px-4 py-3 text-theme-secondary">{task.slot ?? '-'}</td>
              <td className="px-4 py-3">
                <span className={`px-2 py-0.5 rounded text-xs font-medium ${getStatusColor(task.status)}`}>
                  {task.status}
                </span>
              </td>
              <td className="px-4 py-3 text-theme-secondary">{task.desired_state}</td>
              <td className="px-4 py-3 text-theme-tertiary text-xs truncate max-w-[200px]">{task.image}</td>
              <td className="px-4 py-3 text-theme-error text-xs truncate max-w-[200px]">{task.error || '-'}</td>
              <td className="px-4 py-3 text-theme-tertiary text-xs">
                {task.updated_at ? new Date(task.updated_at).toLocaleString() : '-'}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
};
