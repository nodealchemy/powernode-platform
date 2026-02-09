import React from 'react';
import {
  FileText, GitBranch, GitMerge, Terminal,
  Database, Map, CheckSquare, Play, ExternalLink
} from 'lucide-react';
import type { ExecutionResource, ResourceType } from '../types';
import { ResourceSourceLink } from './ResourceSourceLink';

interface ResourceCardProps {
  resource: ExecutionResource;
  onClick: (resource: ExecutionResource) => void;
}

const TYPE_ICONS: Record<ResourceType, React.ElementType> = {
  artifact: FileText,
  git_branch: GitBranch,
  git_merge: GitMerge,
  execution_output: Terminal,
  shared_memory: Database,
  trajectory: Map,
  review: CheckSquare,
  runner_job: Play,
};

const STATUS_STYLES: Record<string, string> = {
  completed: 'bg-theme-success/10 text-theme-success',
  running: 'bg-theme-info/10 text-theme-info',
  failed: 'bg-theme-danger/10 text-theme-danger',
  pending: 'bg-theme-warning/10 text-theme-warning',
  available: 'bg-theme-surface text-theme-secondary',
  approved: 'bg-theme-success/10 text-theme-success',
  rejected: 'bg-theme-danger/10 text-theme-danger',
};

export function ResourceCard({ resource, onClick }: ResourceCardProps) {
  const Icon = TYPE_ICONS[resource.resource_type] || FileText;

  return (
    <div
      onClick={() => onClick(resource)}
      className="p-4 rounded-lg border border-theme bg-theme-surface hover:bg-theme-surface-hover transition-colors cursor-pointer"
    >
      <div className="flex items-start justify-between mb-2">
        <div className="flex items-center gap-2">
          <Icon className="w-4 h-4 text-theme-tertiary" />
          <span className="text-xs font-medium text-theme-tertiary uppercase">
            {resource.resource_type.replace('_', ' ')}
          </span>
        </div>
        <span className={`inline-flex px-2 py-0.5 rounded-full text-xs font-medium ${STATUS_STYLES[resource.status] || STATUS_STYLES.available}`}>
          {resource.status}
        </span>
      </div>

      <h3 className="text-sm font-semibold text-theme-primary mb-1 truncate">
        {resource.name}
      </h3>

      {resource.description && (
        <p className="text-xs text-theme-secondary mb-2 line-clamp-2">
          {resource.description}
        </p>
      )}

      {resource.preview && (
        <div className="text-xs text-theme-tertiary bg-theme-background-secondary rounded p-2 mb-2 line-clamp-3 font-mono">
          {resource.preview}
        </div>
      )}

      <div className="flex items-center justify-between mt-2">
        <div className="flex items-center gap-2">
          <ResourceSourceLink sourceType={resource.source_type} sourceId={resource.source_id} />
          {resource.agent_name && (
            <span className="text-xs text-theme-tertiary">
              by {resource.agent_name}
            </span>
          )}
        </div>
        <div className="flex items-center gap-2">
          {resource.url && (
            <a
              href={resource.url}
              target="_blank"
              rel="noopener noreferrer"
              onClick={(e) => e.stopPropagation()}
              className="text-theme-primary hover:text-theme-primary-hover"
            >
              <ExternalLink className="w-3.5 h-3.5" />
            </a>
          )}
          <span className="text-xs text-theme-tertiary">
            {new Date(resource.created_at).toLocaleDateString()}
          </span>
        </div>
      </div>
    </div>
  );
}
