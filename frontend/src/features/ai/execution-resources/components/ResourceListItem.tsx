import React from 'react';
import {
  FileText, GitBranch, GitMerge, Terminal,
  Database, Map, CheckSquare, Play
} from 'lucide-react';
import { formatRelativeTimeCompact } from '@/shared/utils/formatters';
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
  completed: 'bg-theme-success-fg/10 text-theme-success-fg',
  active: 'bg-theme-success-fg/10 text-theme-success-fg',
  ready: 'bg-theme-success-fg/10 text-theme-success-fg',
  approved: 'bg-theme-success-fg/10 text-theme-success-fg',
  running: 'bg-theme-info-fg/10 text-theme-info-fg',
  in_progress: 'bg-theme-info-fg/10 text-theme-info-fg',
  pending: 'bg-theme-warning-fg/10 text-theme-warning-fg',
  dispatched: 'bg-theme-warning-fg/10 text-theme-warning-fg',
  failed: 'bg-theme-error-fg/10 text-theme-error-fg',
  conflict: 'bg-theme-error-fg/10 text-theme-error-fg',
  rejected: 'bg-theme-error-fg/10 text-theme-error-fg',
  cancelled: 'bg-theme-background-secondary/10 text-theme-tertiary',
  archived: 'bg-theme-background-secondary/10 text-theme-tertiary',
};


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
              {formatRelativeTimeCompact(resource.created_at, { monthTier: true })}
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
