import React from 'react';
import {
  FileText, GitBranch, GitMerge, Terminal,
  Database, Map, CheckSquare, Play
} from 'lucide-react';
import type { ExecutionResource, ResourceType } from '../types';

interface ResourceListItemProps {
  resource: ExecutionResource;
  isSelected: boolean;
  onClick: () => void;
}

const TYPE_CONFIG: Record<ResourceType, { icon: React.ElementType; label: string }> = {
  artifact: { icon: FileText, label: 'Artifact' },
  git_branch: { icon: GitBranch, label: 'Branch' },
  git_merge: { icon: GitMerge, label: 'Merge' },
  execution_output: { icon: Terminal, label: 'Output' },
  shared_memory: { icon: Database, label: 'Memory' },
  trajectory: { icon: Map, label: 'Trajectory' },
  review: { icon: CheckSquare, label: 'Review' },
  runner_job: { icon: Play, label: 'Runner Job' },
};

const STATUS_COLORS: Record<string, string> = {
  completed: 'bg-theme-success/10 text-theme-success',
  active: 'bg-theme-success/10 text-theme-success',
  ready: 'bg-theme-success/10 text-theme-success',
  approved: 'bg-theme-success/10 text-theme-success',
  running: 'bg-theme-info/10 text-theme-info',
  in_progress: 'bg-theme-info/10 text-theme-info',
  pending: 'bg-theme-warning/10 text-theme-warning',
  dispatched: 'bg-theme-warning/10 text-theme-warning',
  failed: 'bg-theme-error/10 text-theme-error',
  conflict: 'bg-theme-error/10 text-theme-error',
  rejected: 'bg-theme-error/10 text-theme-error',
  cancelled: 'bg-theme-tertiary/10 text-theme-tertiary',
  archived: 'bg-theme-tertiary/10 text-theme-tertiary',
};

function timeAgo(dateStr: string): string {
  const now = Date.now();
  const then = new Date(dateStr).getTime();
  const seconds = Math.floor((now - then) / 1000);

  if (seconds < 60) return 'just now';
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `${days}d ago`;
  const months = Math.floor(days / 30);
  return `${months}mo ago`;
}

export function ResourceListItem({ resource, isSelected, onClick }: ResourceListItemProps) {
  const config = TYPE_CONFIG[resource.resource_type];
  const Icon = config.icon;
  const statusColor = STATUS_COLORS[resource.status] || 'bg-theme-surface text-theme-secondary';

  return (
    <button
      onClick={onClick}
      className={`w-full text-left px-3 py-2.5 border-l-2 transition-colors hover:bg-theme-surface-hover ${
        isSelected
          ? 'border-l-theme-accent bg-theme-surface-hover'
          : 'border-l-transparent'
      }`}
    >
      <div className="flex items-start gap-2.5">
        <Icon className="w-4 h-4 text-theme-tertiary mt-0.5 flex-shrink-0" />
        <div className="min-w-0 flex-1">
          <div className="flex items-center justify-between gap-2">
            <span className="text-sm font-medium text-theme-primary truncate">
              {resource.name}
            </span>
            <span className="text-[10px] text-theme-tertiary whitespace-nowrap flex-shrink-0">
              {timeAgo(resource.created_at)}
            </span>
          </div>
          {resource.description && (
            <p className="text-[10px] text-theme-tertiary truncate mt-0.5">
              {resource.description}
            </p>
          )}
          <span className={`inline-flex mt-1 px-1.5 py-0.5 text-[10px] font-medium rounded-full capitalize ${statusColor}`}>
            {resource.status.replace(/_/g, ' ')}
          </span>
        </div>
      </div>
    </button>
  );
}
