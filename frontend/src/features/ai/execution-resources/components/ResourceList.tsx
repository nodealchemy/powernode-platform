import React from 'react';
import {
  FileText, GitBranch, GitMerge, Terminal,
  Database, Map, CheckSquare, Play, ExternalLink
} from 'lucide-react';
import type { ExecutionResource, ResourceType } from '../types';

interface ResourceListProps {
  resources: ExecutionResource[];
  onResourceClick: (resource: ExecutionResource) => void;
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

export function ResourceList({ resources, onResourceClick }: ResourceListProps) {
  if (resources.length === 0) {
    return (
      <div className="text-center py-12 text-theme-tertiary">
        No resources found
      </div>
    );
  }

  return (
    <div className="overflow-x-auto">
      <table className="w-full text-sm">
        <thead>
          <tr className="border-b border-theme">
            <th className="text-left py-3 px-4 text-theme-secondary font-medium">Type</th>
            <th className="text-left py-3 px-4 text-theme-secondary font-medium">Name</th>
            <th className="text-left py-3 px-4 text-theme-secondary font-medium">Source</th>
            <th className="text-left py-3 px-4 text-theme-secondary font-medium">Agent</th>
            <th className="text-left py-3 px-4 text-theme-secondary font-medium">Status</th>
            <th className="text-left py-3 px-4 text-theme-secondary font-medium">Created</th>
            <th className="text-left py-3 px-4 text-theme-secondary font-medium"></th>
          </tr>
        </thead>
        <tbody>
          {resources.map((resource) => {
            const Icon = TYPE_ICONS[resource.resource_type] || FileText;
            return (
              <tr
                key={`${resource.resource_type}-${resource.id}`}
                onClick={() => onResourceClick(resource)}
                className="border-b border-theme hover:bg-theme-surface-hover cursor-pointer transition-colors"
              >
                <td className="py-3 px-4">
                  <div className="flex items-center gap-2">
                    <Icon className="w-4 h-4 text-theme-tertiary" />
                    <span className="text-xs text-theme-tertiary capitalize">
                      {resource.resource_type.replace('_', ' ')}
                    </span>
                  </div>
                </td>
                <td className="py-3 px-4 text-theme-primary font-medium truncate max-w-[200px]">
                  {resource.name}
                </td>
                <td className="py-3 px-4 text-theme-secondary text-xs">
                  {resource.source_label}
                </td>
                <td className="py-3 px-4 text-theme-secondary text-xs">
                  {resource.agent_name || '-'}
                </td>
                <td className="py-3 px-4">
                  <span className="inline-flex px-2 py-0.5 rounded-full text-xs font-medium bg-theme-surface text-theme-secondary">
                    {resource.status}
                  </span>
                </td>
                <td className="py-3 px-4 text-theme-tertiary text-xs">
                  {new Date(resource.created_at).toLocaleDateString()}
                </td>
                <td className="py-3 px-4">
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
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
