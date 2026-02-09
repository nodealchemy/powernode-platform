

import { GitBranch, GitCommit, ExternalLink, Plus, Minus, FileText } from 'lucide-react';
import type { ExecutionResource } from '../types';

interface GitResourceDetailProps {
  resource: ExecutionResource;
}

export function GitResourceDetail({ resource }: GitResourceDetailProps) {
  const isMerge = resource.resource_type === 'git_merge';

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 gap-4">
        {resource.branch_name && (
          <div className="flex items-center gap-2">
            <GitBranch className="w-4 h-4 text-theme-text-tertiary" />
            <div>
              <div className="text-xs text-theme-text-tertiary">Branch</div>
              <div className="text-sm font-mono text-theme-text-primary">{resource.branch_name}</div>
            </div>
          </div>
        )}

        {resource.commit_sha && (
          <div className="flex items-center gap-2">
            <GitCommit className="w-4 h-4 text-theme-text-tertiary" />
            <div>
              <div className="text-xs text-theme-text-tertiary">Commit</div>
              <div className="text-sm font-mono text-theme-text-primary">{resource.commit_sha?.slice(0, 8)}</div>
            </div>
          </div>
        )}
      </div>

      {(resource.files_changed !== null || resource.lines_added !== null) && (
        <div className="flex items-center gap-4 p-3 rounded-lg bg-theme-bg-secondary">
          {resource.files_changed !== null && (
            <div className="flex items-center gap-1.5">
              <FileText className="w-4 h-4 text-theme-text-tertiary" />
              <span className="text-sm text-theme-text-primary">{resource.files_changed} files</span>
            </div>
          )}
          {resource.lines_added !== null && (
            <div className="flex items-center gap-1">
              <Plus className="w-3.5 h-3.5 text-theme-success" />
              <span className="text-sm text-theme-success">{resource.lines_added}</span>
            </div>
          )}
          {resource.lines_removed !== null && (
            <div className="flex items-center gap-1">
              <Minus className="w-3.5 h-3.5 text-theme-danger" />
              <span className="text-sm text-theme-danger">{resource.lines_removed}</span>
            </div>
          )}
        </div>
      )}

      {isMerge && resource.metadata && (
        <div className="space-y-2">
          <h4 className="text-sm font-medium text-theme-text-primary">Merge Details</h4>
          <div className="text-sm text-theme-text-secondary">
            Strategy: {(resource.metadata as Record<string, unknown>).strategy as string || 'N/A'}
          </div>
        </div>
      )}

      {resource.pull_request_url && (
        <a
          href={resource.pull_request_url}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center gap-1.5 text-sm text-theme-primary hover:underline"
        >
          <ExternalLink className="w-3.5 h-3.5" />
          View Pull Request
        </a>
      )}

      {resource.agent_name && (
        <div className="text-sm text-theme-text-secondary">
          Agent: <span className="font-medium text-theme-text-primary">{resource.agent_name}</span>
        </div>
      )}
    </div>
  );
}
