import React from 'react';
import { AlertTriangle, CheckCircle } from 'lucide-react';
import type { ParallelWorktree, ConflictPair } from '../types';

interface ConflictMatrixProps {
  worktrees: ParallelWorktree[];
  conflictMatrix: Record<string, ConflictPair>;
}

export const ConflictMatrix: React.FC<ConflictMatrixProps> = ({ worktrees, conflictMatrix }) => {
  if (worktrees.length < 2) {
    return (
      <div className="text-sm text-theme-text-secondary text-center py-8">
        At least 2 worktrees required for conflict detection
      </div>
    );
  }

  const hasAnyConflicts = Object.values(conflictMatrix).some(p => p.has_conflicts);

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2 mb-4">
        {hasAnyConflicts ? (
          <>
            <AlertTriangle className="w-5 h-5 text-theme-status-warning" />
            <span className="text-sm font-medium text-theme-status-warning">Conflicts detected between worktrees</span>
          </>
        ) : (
          <>
            <CheckCircle className="w-5 h-5 text-theme-status-success" />
            <span className="text-sm font-medium text-theme-status-success">No conflicts detected</span>
          </>
        )}
      </div>

      {/* Matrix table */}
      <div className="overflow-x-auto">
        <table className="min-w-full text-xs">
          <thead>
            <tr>
              <th className="p-2 text-left text-theme-text-secondary font-medium" />
              {worktrees.map(wt => (
                <th key={wt.id} className="p-2 text-left text-theme-text-secondary font-medium truncate max-w-[120px]">
                  {wt.agent_name || wt.branch_name.split('/').pop()}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {worktrees.map((wtRow, rowIdx) => (
              <tr key={wtRow.id} className="border-t border-theme">
                <td className="p-2 font-medium text-theme-text-primary truncate max-w-[120px]">
                  {wtRow.agent_name || wtRow.branch_name.split('/').pop()}
                </td>
                {worktrees.map((wtCol, colIdx) => {
                  if (rowIdx === colIdx) {
                    return <td key={wtCol.id} className="p-2 bg-theme-bg-secondary text-center">&mdash;</td>;
                  }
                  if (rowIdx > colIdx) {
                    return <td key={wtCol.id} className="p-2 bg-theme-bg-secondary" />;
                  }
                  const key = `${wtRow.id}:${wtCol.id}`;
                  const altKey = `${wtCol.id}:${wtRow.id}`;
                  const pair = conflictMatrix[key] || conflictMatrix[altKey];

                  if (!pair) {
                    return <td key={wtCol.id} className="p-2 text-center text-theme-text-tertiary">&mdash;</td>;
                  }

                  return (
                    <td key={wtCol.id} className={`p-2 text-center ${pair.has_conflicts ? 'bg-theme-status-error/10' : 'bg-theme-status-success/10'}`}>
                      {pair.has_conflicts ? (
                        <div className="flex flex-col items-center gap-1">
                          <AlertTriangle className="w-4 h-4 text-theme-status-error" />
                          <span className="text-theme-status-error">{pair.conflict_files.length} files</span>
                        </div>
                      ) : (
                        <CheckCircle className="w-4 h-4 text-theme-status-success mx-auto" />
                      )}
                    </td>
                  );
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Conflict details */}
      {hasAnyConflicts && (
        <div className="mt-4 space-y-2">
          <h4 className="text-sm font-medium text-theme-text-primary">Conflict Details</h4>
          {Object.entries(conflictMatrix)
            .filter(([, pair]) => pair.has_conflicts)
            .map(([key, pair]) => {
              const [idA, idB] = key.split(':');
              const wtA = worktrees.find(w => w.id === idA);
              const wtB = worktrees.find(w => w.id === idB);
              return (
                <div key={key} className="bg-theme-bg-secondary rounded-lg p-3">
                  <div className="text-sm font-medium text-theme-text-primary mb-1">
                    {wtA?.agent_name || wtA?.branch_name.split('/').pop()} vs {wtB?.agent_name || wtB?.branch_name.split('/').pop()}
                  </div>
                  <div className="flex flex-wrap gap-1">
                    {pair.conflict_files.map(file => (
                      <span key={file} className="px-2 py-0.5 bg-theme-status-error/10 text-theme-status-error rounded text-xs font-mono">
                        {file}
                      </span>
                    ))}
                  </div>
                </div>
              );
            })}
        </div>
      )}
    </div>
  );
};
