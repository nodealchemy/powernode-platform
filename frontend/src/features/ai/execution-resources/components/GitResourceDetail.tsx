import {
  GitBranch, GitCommit, ExternalLink, Plus, Minus, FileText,
  Clock, HardDrive, Shield, AlertTriangle, Lock, CheckCircle, XCircle
} from 'lucide-react';
import type { ResourceDetailProps } from '../types';
import { DetailSection, StatCard, StatusBadge, formatDuration, formatBytes, formatTimestamp } from './DetailSection';

export function GitResourceDetail({ resource }: ResourceDetailProps) {
  const isMerge = resource.resource_type === 'git_merge';

  if (isMerge) {
    return <MergeDetail resource={resource} />;
  }

  return <BranchDetail resource={resource} />;
}

function BranchDetail({ resource }: ResourceDetailProps) {
  const hasError = resource.error_message || resource.error_code;

  return (
    <div className="space-y-4">
      {/* Branch + Commit */}
      <div className="grid grid-cols-2 gap-4">
        {resource.branch_name && (
          <div className="flex items-center gap-2">
            <GitBranch className="w-4 h-4 text-theme-tertiary" />
            <div>
              <div className="text-xs text-theme-tertiary">Branch</div>
              <div className="text-sm font-mono text-theme-primary">{resource.branch_name}</div>
            </div>
          </div>
        )}
        {resource.commit_sha && (
          <div className="flex items-center gap-2">
            <GitCommit className="w-4 h-4 text-theme-tertiary" />
            <div>
              <div className="text-xs text-theme-tertiary">Head Commit</div>
              <div className="text-sm font-mono text-theme-primary">{resource.commit_sha?.slice(0, 8)}</div>
            </div>
          </div>
        )}
      </div>

      {/* Stats */}
      <div className="grid grid-cols-3 gap-2">
        <StatCard label="Commits" value={resource.commit_count} icon={<GitCommit className="w-3.5 h-3.5" />} />
        <StatCard label="Duration" value={formatDuration(resource.duration_ms)} icon={<Clock className="w-3.5 h-3.5" />} />
        <StatCard label="Disk Usage" value={formatBytes(resource.disk_usage_bytes)} icon={<HardDrive className="w-3.5 h-3.5" />} />
      </div>

      {/* File changes */}
      {(resource.files_changed !== null || resource.lines_added !== null) && (
        <div className="flex items-center gap-4 p-3 rounded-lg bg-theme-surface border border-theme">
          {resource.files_changed !== null && (
            <div className="flex items-center gap-1.5">
              <FileText className="w-4 h-4 text-theme-tertiary" />
              <span className="text-sm text-theme-primary">{resource.files_changed} files</span>
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
              <Minus className="w-3.5 h-3.5 text-theme-error" />
              <span className="text-sm text-theme-error">{resource.lines_removed}</span>
            </div>
          )}
        </div>
      )}

      {/* Health & Lock */}
      <div className="flex flex-wrap gap-3 text-sm">
        {resource.healthy !== undefined && (
          <div className="flex items-center gap-1.5">
            {resource.healthy ? (
              <><CheckCircle className="w-4 h-4 text-theme-success" /><span className="text-theme-success">Healthy</span></>
            ) : (
              <><XCircle className="w-4 h-4 text-theme-error" /><span className="text-theme-error">Unhealthy</span></>
            )}
          </div>
        )}
        {resource.health_message && !resource.healthy && (
          <span className="text-xs text-theme-error">{resource.health_message}</span>
        )}
        {resource.locked && (
          <div className="flex items-center gap-1.5">
            <Lock className="w-4 h-4 text-theme-warning" />
            <span className="text-theme-warning">Locked{resource.lock_reason ? `: ${resource.lock_reason}` : ''}</span>
          </div>
        )}
        {resource.test_status && (
          <StatusBadge status={resource.test_status} />
        )}
      </div>

      {/* Detail info */}
      <DetailSection title="Details" defaultOpen={false}>
        <div className="space-y-2 text-sm">
          {resource.base_commit_sha && (
            <div className="flex justify-between">
              <span className="text-theme-tertiary">Base Commit</span>
              <span className="font-mono text-theme-primary">{resource.base_commit_sha.slice(0, 8)}</span>
            </div>
          )}
          {resource.worktree_path && (
            <div className="flex justify-between">
              <span className="text-theme-tertiary">Worktree Path</span>
              <span className="font-mono text-theme-primary text-xs truncate max-w-[200px]">{resource.worktree_path}</span>
            </div>
          )}
          {resource.estimated_cost_cents !== undefined && resource.estimated_cost_cents > 0 && (
            <div className="flex justify-between">
              <span className="text-theme-tertiary">Estimated Cost</span>
              <span className="text-theme-primary">${(Number(resource.estimated_cost_cents) / 100).toFixed(2)}</span>
            </div>
          )}
          {resource.tokens_used !== undefined && resource.tokens_used > 0 && (
            <div className="flex justify-between">
              <span className="text-theme-tertiary">Tokens Used</span>
              <span className="text-theme-primary">{resource.tokens_used.toLocaleString()}</span>
            </div>
          )}
        </div>
      </DetailSection>

      {/* Timestamps */}
      <DetailSection title="Timeline" defaultOpen={false}>
        <div className="space-y-1.5 text-xs text-theme-secondary">
          {resource.created_at && <div>Created: {formatTimestamp(resource.created_at)}</div>}
          {resource.ready_at && <div>Ready: {formatTimestamp(resource.ready_at)}</div>}
          {resource.completed_at && <div>Completed: {formatTimestamp(resource.completed_at)}</div>}
          {resource.timeout_at && <div>Timeout: {formatTimestamp(resource.timeout_at)}</div>}
        </div>
      </DetailSection>

      {/* Error */}
      {hasError && (
        <DetailSection title="Error" icon={<AlertTriangle className="w-4 h-4" />} defaultOpen>
          <div className="space-y-1">
            {resource.error_code && (
              <span className="text-xs px-2 py-0.5 rounded bg-theme-error/10 text-theme-error font-mono">{resource.error_code}</span>
            )}
            {resource.error_message && (
              <p className="text-sm text-theme-error">{resource.error_message}</p>
            )}
          </div>
        </DetailSection>
      )}

      {resource.agent_name && (
        <div className="text-sm text-theme-secondary">
          Agent: <span className="font-medium text-theme-primary">{resource.agent_name}</span>
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
    </div>
  );
}

function MergeDetail({ resource }: ResourceDetailProps) {
  const hasConflicts = resource.has_conflicts;
  const hasError = resource.error_message || resource.error_code;

  return (
    <div className="space-y-4">
      {/* Branches */}
      <div className="flex items-center gap-2 text-sm">
        <span className="font-mono px-2 py-0.5 rounded bg-theme-surface border border-theme text-theme-primary">{resource.source_branch}</span>
        <span className="text-theme-tertiary">&rarr;</span>
        <span className="font-mono px-2 py-0.5 rounded bg-theme-surface border border-theme text-theme-primary">{resource.target_branch}</span>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-3 gap-2">
        <StatCard label="Strategy" value={resource.strategy} icon={<GitBranch className="w-3.5 h-3.5" />} />
        <StatCard label="Duration" value={formatDuration(resource.duration_ms)} icon={<Clock className="w-3.5 h-3.5" />} />
        {resource.merge_order !== undefined && (
          <StatCard label="Merge Order" value={resource.merge_order} />
        )}
      </div>

      {/* Merge commit */}
      {resource.merge_commit_sha && (
        <div className="flex items-center gap-2 text-sm">
          <GitCommit className="w-4 h-4 text-theme-tertiary" />
          <span className="text-theme-tertiary">Merge Commit:</span>
          <span className="font-mono text-theme-primary">{resource.merge_commit_sha.slice(0, 8)}</span>
        </div>
      )}

      {/* Conflicts */}
      {hasConflicts && (
        <DetailSection title="Conflicts" icon={<AlertTriangle className="w-4 h-4" />} defaultOpen>
          <div className="space-y-2">
            {resource.conflict_files && resource.conflict_files.length > 0 && (
              <div className="space-y-1">
                <div className="text-xs text-theme-tertiary">Conflicting files:</div>
                {resource.conflict_files.map((file) => (
                  <div key={file} className="text-xs font-mono text-theme-error px-2 py-1 rounded bg-theme-error/5">
                    {file}
                  </div>
                ))}
              </div>
            )}
            {resource.conflict_details && (
              <div>
                <div className="text-xs text-theme-tertiary mb-1">Details:</div>
                <div className="text-sm text-theme-secondary whitespace-pre-wrap">{resource.conflict_details}</div>
              </div>
            )}
            {resource.conflict_resolution && (
              <div>
                <div className="text-xs text-theme-tertiary mb-1">Resolution:</div>
                <div className="text-sm text-theme-primary">{resource.conflict_resolution}</div>
              </div>
            )}
          </div>
        </DetailSection>
      )}

      {/* Rollback */}
      {resource.rolled_back && (
        <DetailSection title="Rollback" icon={<Shield className="w-4 h-4" />} defaultOpen>
          <div className="space-y-1 text-sm">
            <div className="text-theme-warning">This merge was rolled back</div>
            {resource.rollback_commit_sha && (
              <div className="text-theme-secondary">
                Rollback commit: <span className="font-mono">{resource.rollback_commit_sha.slice(0, 8)}</span>
              </div>
            )}
            {resource.rolled_back_at && (
              <div className="text-xs text-theme-tertiary">Rolled back at: {formatTimestamp(resource.rolled_back_at)}</div>
            )}
          </div>
        </DetailSection>
      )}

      {/* PR */}
      {(resource.pull_request_url || resource.pull_request_id) && (
        <div className="flex items-center gap-3 text-sm">
          {resource.pull_request_status && <StatusBadge status={resource.pull_request_status} />}
          {resource.pull_request_url && (
            <a
              href={resource.pull_request_url}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1.5 text-theme-primary hover:underline"
            >
              <ExternalLink className="w-3.5 h-3.5" />
              PR #{resource.pull_request_id || 'View'}
            </a>
          )}
        </div>
      )}

      {/* Timestamps */}
      {(resource.started_at || resource.completed_at) && (
        <div className="flex gap-4 text-xs text-theme-tertiary">
          {resource.started_at && <span>Started: {formatTimestamp(resource.started_at)}</span>}
          {resource.completed_at && <span>Completed: {formatTimestamp(resource.completed_at)}</span>}
        </div>
      )}

      {/* Error */}
      {hasError && (
        <DetailSection title="Error" icon={<AlertTriangle className="w-4 h-4" />} defaultOpen>
          <div className="space-y-1">
            {resource.error_code && (
              <span className="text-xs px-2 py-0.5 rounded bg-theme-error/10 text-theme-error font-mono">{resource.error_code}</span>
            )}
            {resource.error_message && (
              <p className="text-sm text-theme-error">{resource.error_message}</p>
            )}
          </div>
        </DetailSection>
      )}
    </div>
  );
}
