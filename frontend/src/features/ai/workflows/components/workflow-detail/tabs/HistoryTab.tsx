import React from 'react';
import { BarChart3, TrendingUp, Trash2, AlertCircle } from 'lucide-react';
import { Card, CardContent, CardTitle } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { AiWorkflowRun } from '@/shared/types/workflow';
import { WorkflowExecutionDetails } from '../../WorkflowExecutionDetails';

interface HistoryTabProps {
  workflowId: string;
  workflowRuns: AiWorkflowRun[];
  runsLoading: boolean;
  runsError: string | null;
  expandedRuns: Set<string>;
  canDeleteWorkflowRuns: boolean;
  isDeletingAll: boolean;
  onShowSummaryModal: () => void;
  onShowDeleteAllConfirm: () => void;
  onLoadWorkflowRuns: () => void;
  getToggleHandler: (runId: string) => () => void;
  getDeleteHandler: (runId: string) => () => void;
  registerReloadCallback: (runId: string, callback: () => void) => () => void;
}

export const HistoryTab: React.FC<HistoryTabProps> = ({
  workflowId,
  workflowRuns,
  runsLoading,
  runsError,
  expandedRuns,
  canDeleteWorkflowRuns,
  isDeletingAll,
  onShowSummaryModal,
  onShowDeleteAllConfirm,
  onLoadWorkflowRuns,
  getToggleHandler,
  getDeleteHandler,
  registerReloadCallback
}) => {
  return (
    <Card>
      <div className="flex items-center justify-between mb-4">
        <CardTitle>Recent Executions</CardTitle>
        <div className="flex items-center gap-3">
          {process.env.NODE_ENV === 'development' && (
            <span className="text-xs text-theme-muted">
              Runs: {workflowRuns?.length || 0} | Auth: {canDeleteWorkflowRuns ? 'Yes' : 'No'}
            </span>
          )}
          {workflowRuns && workflowRuns.length > 0 && (
            <>
              <Button
                variant="outline"
                size="sm"
                onClick={onShowSummaryModal}
                className="gap-2"
              >
                <TrendingUp className="h-4 w-4" />
                View Summary
              </Button>
              {canDeleteWorkflowRuns && (
                <Button
                  variant="outline"
                  size="sm"
                  onClick={onShowDeleteAllConfirm}
                  className="gap-2 text-theme-danger hover:text-theme-danger hover:border-theme-danger/30"
                  disabled={isDeletingAll}
                >
                  <Trash2 className="h-4 w-4" />
                  Delete All
                </Button>
              )}
            </>
          )}
          {runsLoading && (
            <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-theme-interactive-primary"></div>
          )}
        </div>
      </div>
      <CardContent className="relative">
        {/* Loading overlay */}
        {runsLoading && (
          <div className="absolute inset-0 bg-theme-surface/80 backdrop-blur-sm flex items-center justify-center z-10 rounded-lg transition-all duration-200 ease-in-out">
            <div className="flex items-center gap-3">
              <div className="animate-spin rounded-full h-6 w-6 border-2 border-theme-interactive-primary border-t-transparent"></div>
              <span className="text-sm text-theme-muted">Loading execution history...</span>
            </div>
          </div>
        )}

        {/* Content */}
        <div className={`transition-all duration-300 ease-in-out ${runsLoading ? 'opacity-50' : 'opacity-100'}`}>
          {runsError ? (
            <div className="text-center py-8 animate-in fade-in-50 duration-300">
              <AlertCircle className="h-12 w-12 text-theme-error mx-auto mb-3 opacity-60" />
              <p className="text-theme-error mb-4">{runsError}</p>
              <Button
                variant="outline"
                onClick={onLoadWorkflowRuns}
                className="transition-all duration-200"
                disabled={runsLoading}
              >
                Try Again
              </Button>
            </div>
          ) : workflowRuns && workflowRuns.length > 0 ? (
            <div className="space-y-1 animate-in fade-in-50 slide-in-from-top-2 duration-500">
              {workflowRuns.map((run, index) => (
                <div
                  key={run.id || run.run_id}
                  className="animate-in fade-in-50 slide-in-from-left-1 duration-300"
                  style={{ animationDelay: `${index * 50}ms` }}
                >
                  <WorkflowExecutionDetails
                    run={run}
                    workflowId={workflowId}
                    isExpanded={expandedRuns.has(run.id || run.run_id || '')}
                    onToggle={getToggleHandler(run.id || run.run_id || '')}
                    onDelete={getDeleteHandler(run.id || run.run_id || '')}
                    onRegisterReloadCallback={registerReloadCallback}
                  />
                </div>
              ))}
            </div>
          ) : (
            <div className="text-center py-12 animate-in fade-in-50 duration-500">
              <BarChart3 className="h-16 w-16 text-theme-muted mx-auto mb-4 opacity-40" />
              <p className="text-theme-muted text-lg mb-2">No execution history found</p>
              <p className="text-theme-muted/70 text-sm">
                Execute the workflow to see results here
              </p>
            </div>
          )}
        </div>
      </CardContent>
    </Card>
  );
};
