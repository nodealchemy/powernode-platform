import React from 'react';
import { GitBranch, Terminal } from 'lucide-react';
import { Card, CardContent, CardTitle } from '@/shared/components/ui/Card';
import { AiWorkflowRun, AiWorkflowNodeExecution, WorkflowRunStatus } from '@/shared/types/workflow';
import { formatDuration } from './executionUtils';
import { NodeExecutionCard } from './NodeExecutionCard';

interface NodeExecutionListProps {
  run: AiWorkflowRun;
  currentRun: AiWorkflowRun;
  runStatus: WorkflowRunStatus;
  mergedNodes: AiWorkflowNodeExecution[];
  loading: boolean;
  expandedNodes: Set<string>;
  expandedInputs: Set<string>;
  expandedOutputs: Set<string>;
  expandedMetadata: Set<string>;
  liveNodeDurations: Record<string, number>;
  onToggleNode: (id: string) => void;
  onToggleInput: (id: string) => void;
  onToggleOutput: (id: string) => void;
  onToggleMetadata: (id: string) => void;
  onCopy: (text: string, format: string) => void;
}

export const NodeExecutionList: React.FC<NodeExecutionListProps> = ({
  run,
  currentRun,
  runStatus,
  mergedNodes,
  loading,
  expandedNodes,
  expandedInputs,
  expandedOutputs,
  expandedMetadata,
  liveNodeDurations,
  onToggleNode,
  onToggleInput,
  onToggleOutput,
  onToggleMetadata,
  onCopy
}) => {
  return (
    <>
      {/* Execution Summary */}
      <Card>
        <CardTitle className="text-sm">Execution Summary</CardTitle>
        <CardContent className="space-y-1">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
            <div>
              <span className="text-theme-muted">Trigger:</span>
              <p className="font-medium text-theme-primary capitalize">{run.trigger_type || 'manual'}</p>
            </div>
            <div>
              <span className="text-theme-muted">Started:</span>
              <p className="font-medium text-theme-primary">{new Date(run.started_at || run.created_at).toLocaleTimeString()}</p>
            </div>
            {run.completed_at && (
              <div>
                <span className="text-theme-muted">Completed:</span>
                <p className="font-medium text-theme-primary">{new Date(run.completed_at).toLocaleTimeString()}</p>
              </div>
            )}
            <div>
              <span className="text-theme-muted">Total Duration:</span>
              <p className="font-medium text-theme-primary">{formatDuration((currentRun.duration_seconds || 0) * 1000)}</p>
            </div>
          </div>

          {run.input_variables && Object.keys(run.input_variables).length > 0 && (
            <div className="mt-2 pt-2 border-t border-theme">
              <p className="text-sm text-theme-muted mb-1">Input Variables:</p>
              <pre className="text-xs bg-theme-code p-2 rounded border border-theme overflow-x-auto">
                <code className="text-theme-code-text">{JSON.stringify(run.input_variables, null, 2)}</code>
              </pre>
            </div>
          )}

          {run.error_details && Object.keys(run.error_details).length > 0 && runStatus === 'failed' && (
            <div className="mt-2 pt-2 border-t border-theme-error/20">
              <p className="text-sm text-theme-error font-medium mb-1">Error Details:</p>
              <div className="bg-theme-error/10 border border-theme-error/20 rounded p-3">
                <p className="text-sm text-theme-error">{run.error_details.error_message || 'An error occurred during execution'}</p>
                {run.error_details.stack_trace && (
                  <pre className="text-xs mt-2 overflow-x-auto"><code>{run.error_details.stack_trace}</code></pre>
                )}
              </div>
            </div>
          )}
        </CardContent>
      </Card>

      {/* Node Execution Timeline */}
      {mergedNodes.length > 0 ? (
        <Card>
          <CardTitle className="text-sm flex items-center gap-2">
            <GitBranch className="h-4 w-4" />
            Node Execution Timeline
          </CardTitle>
          <CardContent className="space-y-1">
            {mergedNodes.map((node, index) => (
              <NodeExecutionCard
                key={`${node.execution_id || `fallback-${index}`}-${node.node?.node_id || index}`}
                node={node}
                index={index}
                isLast={index === mergedNodes.length - 1}
                isExpanded={expandedNodes.has(node.execution_id)}
                isInputExpanded={expandedInputs.has(node.execution_id)}
                isOutputExpanded={expandedOutputs.has(node.execution_id)}
                isMetadataExpanded={expandedMetadata.has(node.execution_id)}
                liveDuration={liveNodeDurations[node.execution_id]}
                onToggle={() => onToggleNode(node.execution_id)}
                onToggleInput={() => onToggleInput(node.execution_id)}
                onToggleOutput={() => onToggleOutput(node.execution_id)}
                onToggleMetadata={() => onToggleMetadata(node.execution_id)}
                onCopy={onCopy}
              />
            ))}
          </CardContent>
        </Card>
      ) : (
        <Card>
          <CardTitle className="text-sm flex items-center gap-2">
            <GitBranch className="h-4 w-4" />
            Node Execution Timeline
          </CardTitle>
          <CardContent>
            <div className="text-center py-8 text-theme-muted">
              <Terminal className="h-8 w-8 mx-auto mb-2 opacity-50" />
              <p className="text-sm">No workflow nodes found.</p>
              <p className="text-xs mt-2">{loading ? 'Loading workflow structure...' : 'This workflow may not have any defined nodes.'}</p>
            </div>
          </CardContent>
        </Card>
      )}
    </>
  );
};
