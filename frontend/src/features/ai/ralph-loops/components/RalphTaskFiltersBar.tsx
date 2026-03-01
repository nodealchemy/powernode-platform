import React from 'react';
import { RefreshCw, Plus } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Select } from '@/shared/components/ui/Select';
import { cn } from '@/shared/utils/cn';

const statusOptions = [
  { value: '', label: 'All Tasks' },
  { value: 'pending', label: 'Pending' },
  { value: 'in_progress', label: 'In Progress' },
  { value: 'passed', label: 'Passed' },
  { value: 'failed', label: 'Failed' },
  { value: 'blocked', label: 'Blocked' },
  { value: 'skipped', label: 'Skipped' },
];

interface RalphTaskFiltersBarProps {
  statusFilter: string;
  onStatusFilterChange: (value: string) => void;
  loading: boolean;
  onRefresh: () => void;
  canEdit: boolean;
  showAddTask: boolean;
  onToggleAddTask: () => void;
}

export const RalphTaskFiltersBar: React.FC<RalphTaskFiltersBarProps> = ({
  statusFilter,
  onStatusFilterChange,
  loading,
  onRefresh,
  canEdit,
  showAddTask,
  onToggleAddTask,
}) => {
  return (
    <div className="flex items-center justify-between">
      <h3 className="font-medium text-theme-text-primary">Tasks</h3>
      <div className="flex items-center gap-2">
        <Select
          value={statusFilter}
          onChange={(value) => onStatusFilterChange(value)}
          className="w-36"
        >
          {statusOptions.map((option) => (
            <option key={option.value} value={option.value}>
              {option.label}
            </option>
          ))}
        </Select>
        <Button variant="ghost" size="sm" onClick={onRefresh} disabled={loading}>
          <RefreshCw className={cn('w-4 h-4', loading && 'animate-spin')} />
        </Button>
        {canEdit && (
          <Button
            variant="outline"
            size="sm"
            onClick={onToggleAddTask}
            className={cn('min-w-[120px]', showAddTask && 'bg-theme-bg-secondary')}
          >
            <Plus className="w-4 h-4 mr-1" />
            Add Task
          </Button>
        )}
      </div>
    </div>
  );
};
