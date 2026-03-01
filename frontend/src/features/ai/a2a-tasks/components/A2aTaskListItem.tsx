import React from 'react';
import {
  Loader2,
  CheckCircle,
  XCircle,
  Clock,
  AlertCircle,
  ArrowRight,
} from 'lucide-react';
import { cn } from '@/shared/utils/cn';
import type { A2aTask } from '@/shared/services/ai/types/a2a-types';

interface A2aTaskListItemProps {
  task: A2aTask;
  isSelected: boolean;
  onClick: () => void;
}

const statusIconMap: Record<string, React.FC<{ className?: string }>> = {
  pending: Clock,
  active: Loader2,
  completed: CheckCircle,
  failed: XCircle,
  cancelled: AlertCircle,
  input_required: AlertCircle,
};

const statusColorMap: Record<string, string> = {
  pending: 'text-theme-muted',
  active: 'text-theme-info',
  completed: 'text-theme-success',
  failed: 'text-theme-danger',
  cancelled: 'text-theme-warning',
  input_required: 'text-theme-warning',
};

function timeAgo(timestamp: string): string {
  const diff = Date.now() - new Date(timestamp).getTime();
  if (diff < 60000) return 'Just now';
  if (diff < 3600000) return `${Math.floor(diff / 60000)}m ago`;
  if (diff < 86400000) return `${Math.floor(diff / 3600000)}h ago`;
  return new Date(timestamp).toLocaleDateString();
}

export const A2aTaskListItem: React.FC<A2aTaskListItemProps> = ({ task, isSelected, onClick }) => {
  const StatusIcon = statusIconMap[task.status] || Clock;
  const statusColor = statusColorMap[task.status] || 'text-theme-muted';

  return (
    <button
      onClick={onClick}
      className={cn(
        'w-full text-left px-3 py-2.5 border-l-2 transition-colors',
        isSelected
          ? 'border-l-theme-accent bg-theme-surface-hover'
          : 'border-l-transparent hover:bg-theme-surface-hover'
      )}
    >
      <div className="flex items-center gap-2">
        <StatusIcon
          className={cn(
            'h-4 w-4 shrink-0',
            statusColor,
            task.status === 'active' && 'animate-spin'
          )}
        />
        <span className="font-mono text-xs text-theme-primary truncate">
          {task.task_id.substring(0, 8)}
        </span>
        <span className="ml-auto text-xs text-theme-muted whitespace-nowrap">
          {timeAgo(task.created_at)}
        </span>
      </div>
      <div className="flex items-center gap-1 mt-1 ml-6 text-xs text-theme-secondary">
        <span className="font-mono truncate max-w-[80px]">
          {task.from_agent_id?.substring(0, 8) || 'Unknown'}
        </span>
        <ArrowRight className="h-3 w-3 shrink-0 text-theme-muted" />
        <span className="font-mono truncate max-w-[80px]">
          {task.to_agent_id?.substring(0, 8) || 'Unknown'}
        </span>
      </div>
    </button>
  );
};

export default A2aTaskListItem;
