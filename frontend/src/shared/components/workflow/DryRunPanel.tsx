import React, { useState } from 'react';
import { Play, CheckCircle, XCircle, AlertTriangle, Clock, DollarSign } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Card } from '@/shared/components/ui/Card';

export interface DryRunResult {
  workflow_id: string;
  workflow_name: string;
  version: string;
  started_at: string;
  completed_at?: string;
  duration_ms?: number;
  nodes_executed: Array<{
    node_id: string;
    node_type: string;
    name: string;
    simulated_at: string;
    estimated_duration_ms: number;
    estimated_cost: number;
    inputs: Record<string, any>;
    outputs: Record<string, any>;
    status: string;
  }>;
  variables_snapshot: Record<string, any>;
  validation_errors: string[];
  warnings: string[];
  estimated_cost: number;
  estimated_duration_ms: number;
  execution_path: string[];
  status: 'pending' | 'completed' | 'failed' | 'error';
  summary?: {
    total_nodes: number;
    ai_agent_nodes: number;
    api_call_nodes: number;
    estimated_duration_seconds: number;
    estimated_cost_usd: number;
  };
}

export interface DryRunPanelProps {
  workflowId: string;
  onExecuteDryRun: (inputVariables: Record<string, any>) => Promise<DryRunResult>;
  onClose: () => void;
  className?: string;
}

export const DryRunPanel: React.FC<DryRunPanelProps> = ({
  onExecuteDryRun,
  onClose,
  className = ''
}) => {
  const [isRunning, setIsRunning] = useState(false);
  const [result, setResult] = useState<DryRunResult | null>(null);
  const [inputVariables, setInputVariables] = useState<Record<string, any>>({});
  const [error, setError] = useState<string | null>(null);

  const handleRunDryRun = async () => {
    setIsRunning(true);
    setError(null);
    setResult(null);

    try {
      const dryRunResult = await onExecuteDryRun(inputVariables);
      setResult(dryRunResult);
    } catch (error: any) {
      setError(error.message || 'Dry run failed');
    } finally {
      setIsRunning(false);
    }
  };

  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'completed':
        return <CheckCircle className="h-5 w-5 text-theme-success" />;
      case 'failed':
        return <XCircle className="h-5 w-5 text-theme-danger" />;
      case 'error':
        return <AlertTriangle className="h-5 w-5 text-theme-danger" />;
      default:
        return <Clock className="h-5 w-5 text-theme-secondary" />;
    }
  };

  return (
    <div className={`fixed inset-y-0 right-0 w-96 bg-theme-surface border-l border-theme shadow-xl z-50 overflow-y-auto ${className}`}>
      {/* Header */}
      <div className="sticky top-0 bg-theme-surface border-b border-theme p-4 flex items-center justify-between z-10">
        <h3 className="text-lg font-semibold text-theme-primary">Dry Run Test</h3>
        <button
          onClick={onClose}
          className="text-theme-secondary hover:text-theme-primary transition-colors"
        >
          ✕
        </button>
      </div>

      {/* Content */}
      <div className="p-4 space-y-4">
        {/* Input Variables Section */}
        <Card className="p-4">
          <h4 className="text-sm font-medium text-theme-primary mb-3">Input Variables (Optional)</h4>
          <textarea
            className="w-full h-24 px-3 py-2 bg-theme-background border border-theme rounded-lg text-theme-primary text-sm font-mono resize-none focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
            placeholder='{"key": "value"}'
            value={JSON.stringify(inputVariables, null, 2)}
            onChange={(e) => {
              try {
                setInputVariables(JSON.parse(e.target.value || '{}'));
              } catch {
                // Invalid JSON, ignore
              }
            }}
          />
        </Card>

        {/* Run Button */}
        <Button
          onClick={handleRunDryRun}
          disabled={isRunning}
          className="w-full"
        >
          {isRunning ? (
            <>
              <Clock className="h-4 w-4 mr-2 animate-spin" />
              Running Test...
            </>
          ) : (
            <>
              <Play className="h-4 w-4 mr-2" />
              Run Dry Run
            </>
          )}
        </Button>

        {/* Error Display */}
        {error && (
          <Card className="p-4 bg-theme-danger/10 border-theme-danger">
            <div className="flex items-start gap-2">
              <XCircle className="h-5 w-5 text-theme-danger flex-shrink-0 mt-0.5" />
              <div>
                <p className="text-sm font-medium text-theme-danger">Error</p>
                <p className="text-sm text-theme-primary mt-1">{error}</p>
              </div>
            </div>
          </Card>
        )}

        {/* Results Display */}
        {result && (
          <div className="space-y-4">
            {/* Status Header */}
            <Card className="p-4">
              <div className="flex items-center gap-3 mb-3">
                {getStatusIcon(result.status)}
                <div>
                  <p className="text-sm font-medium text-theme-primary capitalize">{result.status}</p>
                  {result.duration_ms && (
                    <p className="text-xs text-theme-secondary">{result.duration_ms}ms</p>
                  )}
                </div>
              </div>

              {/* Summary Stats */}
              {result.summary && (
                <div className="grid grid-cols-2 gap-3 pt-3 border-t border-theme">
                  <div>
                    <p className="text-xs text-theme-secondary">Nodes Tested</p>
                    <p className="text-sm font-medium text-theme-primary">{result.summary.total_nodes}</p>
                  </div>
                  <div>
                    <p className="text-xs text-theme-secondary">Est. Duration</p>
                    <p className="text-sm font-medium text-theme-primary">{result.summary.estimated_duration_seconds}s</p>
                  </div>
                  <div>
                    <p className="text-xs text-theme-secondary">AI Agents</p>
                    <p className="text-sm font-medium text-theme-primary">{result.summary.ai_agent_nodes}</p>
                  </div>
                  <div>
                    <p className="text-xs text-theme-secondary">Est. Cost</p>
                    <p className="text-sm font-medium text-theme-primary flex items-center gap-1">
                      <DollarSign className="h-3 w-3" />
                      {result.summary.estimated_cost_usd.toFixed(4)}
                    </p>
                  </div>
                </div>
              )}
            </Card>

            {/* Validation Errors */}
            {result.validation_errors && result.validation_errors.length > 0 && (
              <Card className="p-4 bg-theme-danger/10 border-theme-danger">
                <h4 className="text-sm font-medium text-theme-danger mb-2 flex items-center gap-2">
                  <XCircle className="h-4 w-4" />
                  Validation Errors
                </h4>
                <ul className="space-y-1">
                  {result.validation_errors.map((error, index) => (
                    <li key={index} className="text-xs text-theme-primary">
                      • {error}
                    </li>
                  ))}
                </ul>
              </Card>
            )}

            {/* Warnings */}
            {result.warnings && result.warnings.length > 0 && (
              <Card className="p-4 bg-theme-warning/10 border-theme-warning">
                <h4 className="text-sm font-medium text-theme-warning mb-2 flex items-center gap-2">
                  <AlertTriangle className="h-4 w-4" />
                  Warnings
                </h4>
                <ul className="space-y-1">
                  {result.warnings.map((warning, index) => (
                    <li key={index} className="text-xs text-theme-primary">
                      • {warning}
                    </li>
                  ))}
                </ul>
              </Card>
            )}

            {/* Execution Path */}
            {result.execution_path && result.execution_path.length > 0 && (
              <Card className="p-4">
                <h4 className="text-sm font-medium text-theme-primary mb-3">Execution Path</h4>
                <div className="space-y-2">
                  {result.execution_path.map((nodeId, index) => {
                    const nodeExecution = result.nodes_executed.find(n => n.node_id === nodeId);
                    return (
                      <div key={index} className="flex items-center gap-2 text-xs">
                        <span className="text-theme-secondary">{index + 1}.</span>
                        <span className="text-theme-primary font-medium">
                          {nodeExecution?.name || nodeId}
                        </span>
                        <span className="text-theme-muted">
                          ({nodeExecution?.estimated_duration_ms}ms)
                        </span>
                      </div>
                    );
                  })}
                </div>
              </Card>
            )}

            {/* Variables Snapshot */}
            {result.variables_snapshot && Object.keys(result.variables_snapshot).length > 0 && (
              <Card className="p-4">
                <h4 className="text-sm font-medium text-theme-primary mb-3">Variables</h4>
                <div className="bg-theme-background rounded-lg p-3 max-h-64 overflow-y-auto">
                  <pre className="text-xs font-mono text-theme-primary">
                    {JSON.stringify(result.variables_snapshot, null, 2)}
                  </pre>
                </div>
              </Card>
            )}
          </div>
        )}
      </div>
    </div>
  );
};
