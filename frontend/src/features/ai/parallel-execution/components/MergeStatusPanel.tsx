import React from 'react';
import { GitMerge, AlertTriangle, RotateCcw, FileCode } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { WorktreeStatusBadge } from './WorktreeStatusBadge';
import type { MergeOperation } from '../types';

interface MergeStatusPanelProps {
  mergeOperations: MergeOperation[];
  onRetryMerge?: () => void;
  sessionStatus?: string;
}

export const MergeStatusPanel: React.FC<MergeStatusPanelProps> = ({
  mergeOperations,
  onRetryMerge,
  sessionStatus,
}) => {
  if (mergeOperations.length === 0) {
    return (
      <div className="text-center p-8 text-theme-text-secondary">
        <GitMerge className="w-8 h-8 mx-auto mb-2 opacity-50" />
        <p>No merge operations yet.</p>
        <p className="text-xs mt-1">Merges will appear when all worktrees complete.</p>
      </div>
    );
  }

  const hasConflicts = mergeOperations.some((op) => op.has_conflicts);
  const hasFailed = mergeOperations.some((op) => op.status === 'failed');

  return (
    <div className="space-y-4">
      {/* Retry button */}
      {(hasFailed || hasConflicts) && sessionStatus === 'failed' && onRetryMerge && (
        <div className="flex items-center justify-between p-3 bg-theme-status-error/5 border border-theme-status-error/20 rounded-lg">
          <div className="flex items-center gap-2 text-sm text-theme-status-error">
            <AlertTriangle className="w-4 h-4" />
            <span>Merge {hasConflicts ? 'conflicts detected' : 'failed'}</span>
          </div>
          <Button variant="outline" size="sm" onClick={onRetryMerge}>
            <RotateCcw className="w-3 h-3 mr-1" />
            Retry Merge
          </Button>
        </div>
      )}

      {/* Operations list */}
      <div className="space-y-2">
        {mergeOperations.map((op) => (
          <div
            key={op.id}
            className="flex items-center justify-between p-3 bg-theme-bg-primary border border-theme rounded-lg"
          >
            <div className="flex items-center gap-3 min-w-0">
              <div className="flex-shrink-0">
                <span className="text-xs text-theme-text-tertiary">#{op.merge_order + 1}</span>
              </div>
              <div className="min-w-0">
                <div className="text-sm font-medium text-theme-text-primary truncate">
                  {op.source_branch} → {op.target_branch}
                </div>
                <div className="text-xs text-theme-text-secondary">
                  Strategy: {op.strategy}
                  {op.merge_commit_sha && (
                    <span className="ml-2 font-mono">{op.merge_commit_sha.substring(0, 8)}</span>
                  )}
                  {op.duration_ms && (
                    <span className="ml-2">{(op.duration_ms / 1000).toFixed(1)}s</span>
                  )}
                </div>
              </div>
            </div>

            <div className="flex items-center gap-2">
              {op.rolled_back && (
                <span className="text-xs text-theme-status-warning flex items-center gap-1">
                  <RotateCcw className="w-3 h-3" />
                  Rolled back
                </span>
              )}
              <WorktreeStatusBadge status={op.status} type="merge" size="sm" />
            </div>
          </div>
        ))}
      </div>

      {/* Conflict details */}
      {hasConflicts && (
        <div className="space-y-2">
          <h4 className="text-sm font-medium text-theme-text-primary">Conflict Files</h4>
          {mergeOperations
            .filter((op) => op.has_conflicts && op.conflict_files.length > 0)
            .map((op) => (
              <div key={op.id} className="p-3 bg-theme-status-error/5 border border-theme-status-error/20 rounded-lg">
                <div className="text-xs text-theme-text-secondary mb-2">{op.source_branch}</div>
                <div className="space-y-1">
                  {op.conflict_files.map((file) => (
                    <div key={file} className="flex items-center gap-1 text-xs text-theme-status-error">
                      <FileCode className="w-3 h-3" />
                      <span className="font-mono">{file}</span>
                    </div>
                  ))}
                </div>
              </div>
            ))}
        </div>
      )}
    </div>
  );
};
