import React from 'react';
import { Card, CardContent, CardTitle } from '@/shared/components/ui/Card';
import type { ExecutionSummaryProps } from './types';

export const ExecutionSummaryCard: React.FC<ExecutionSummaryProps> = ({
  run,
  currentRun,
  runStatus,
  formatDuration
}) => {
  return (
    <Card>
      <CardTitle className="text-sm">Execution Summary</CardTitle>
      <CardContent className="space-y-1">
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
          <div>
            <span className="text-theme-muted">Trigger:</span>
            <p className="font-medium text-theme-primary capitalize">
              {run.trigger_type || 'manual'}
            </p>
          </div>
          <div>
            <span className="text-theme-muted">Started:</span>
            <p className="font-medium text-theme-primary">
              {new Date(run.started_at || run.created_at).toLocaleTimeString()}
            </p>
          </div>
          {run.completed_at && (
            <div>
              <span className="text-theme-muted">Completed:</span>
              <p className="font-medium text-theme-primary">
                {new Date(run.completed_at).toLocaleTimeString()}
              </p>
            </div>
          )}
          <div>
            <span className="text-theme-muted">Total Duration:</span>
            <p className="font-medium text-theme-primary">
              {formatDuration((currentRun.duration_seconds || 0) * 1000)}
            </p>
          </div>
        </div>

        {/* Input Variables */}
        {run.input_variables && Object.keys(run.input_variables).length > 0 && (
          <div className="mt-2 pt-2 border-t border-theme">
            <p className="text-sm text-theme-muted mb-1">Input Variables:</p>
            <pre className="text-xs bg-theme-code p-2 rounded border border-theme overflow-x-auto">
              <code className="text-theme-code-text">
                {JSON.stringify(run.input_variables, null, 2)}
              </code>
            </pre>
          </div>
        )}

        {/* Error Details - only show for failed workflow runs */}
        {run.error_details && Object.keys(run.error_details).length > 0 && runStatus === 'failed' && (
          <div className="mt-2 pt-2 border-t border-theme-error/20">
            <p className="text-sm text-theme-error font-medium mb-1">Error Details:</p>
            <div className="bg-theme-error/10 border border-theme-error/20 rounded p-3">
              <p className="text-sm text-theme-error">
                {run.error_details.error_message || 'An error occurred during execution'}
              </p>
              {run.error_details.stack_trace && (
                <pre className="text-xs mt-2 overflow-x-auto">
                  <code>{run.error_details.stack_trace}</code>
                </pre>
              )}
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
};
