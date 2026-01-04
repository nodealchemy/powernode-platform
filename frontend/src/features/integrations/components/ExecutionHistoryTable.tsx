import { useState } from 'react';
import type { IntegrationExecutionSummary, IntegrationExecution } from '../types';
import { IntegrationStatusBadge } from './IntegrationStatusBadge';
import { integrationsApi } from '../services/integrationsApi';

interface ExecutionHistoryTableProps {
  executions: IntegrationExecutionSummary[];
  onRetry?: (id: string) => void;
  onCancel?: (id: string) => void;
  onViewDetails?: (execution: IntegrationExecution) => void;
  isLoading?: boolean;
}

export function ExecutionHistoryTable({
  executions,
  onRetry,
  onCancel,
  onViewDetails,
  isLoading = false,
}: ExecutionHistoryTableProps) {
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [detailsLoading, setDetailsLoading] = useState<string | null>(null);
  const [executionDetails, setExecutionDetails] = useState<Record<string, IntegrationExecution>>({});

  const handleToggleDetails = async (id: string) => {
    if (expandedId === id) {
      setExpandedId(null);
      return;
    }

    setExpandedId(id);

    if (!executionDetails[id]) {
      setDetailsLoading(id);
      const response = await integrationsApi.getExecution(id);
      if (response.success && response.data) {
        setExecutionDetails((prev) => ({
          ...prev,
          [id]: response.data!.execution,
        }));
      }
      setDetailsLoading(null);
    }
  };

  if (isLoading) {
    return (
      <div className="bg-theme-card border border-theme rounded-lg p-8">
        <div className="flex items-center justify-center">
          <div className="animate-spin rounded-full h-6 w-6 border-2 border-theme-primary border-t-transparent" />
          <span className="ml-2 text-theme-secondary">Loading executions...</span>
        </div>
      </div>
    );
  }

  if (executions.length === 0) {
    return (
      <div className="bg-theme-card border border-theme rounded-lg p-8 text-center">
        <p className="text-theme-secondary">No execution history yet</p>
      </div>
    );
  }

  return (
    <div className="bg-theme-card border border-theme rounded-lg overflow-hidden">
      <table className="w-full">
        <thead className="bg-theme-surface border-b border-theme">
          <tr>
            <th className="px-4 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">
              Status
            </th>
            <th className="px-4 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">
              Triggered By
            </th>
            <th className="px-4 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">
              Duration
            </th>
            <th className="px-4 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">
              Started
            </th>
            <th className="px-4 py-3 text-right text-xs font-medium text-theme-tertiary uppercase tracking-wider">
              Actions
            </th>
          </tr>
        </thead>
        <tbody className="divide-y divide-theme">
          {executions.map((execution) => (
            <>
              <tr
                key={execution.id}
                className="hover:bg-theme-surface transition-colors cursor-pointer"
                onClick={() => handleToggleDetails(execution.id)}
              >
                <td className="px-4 py-3">
                  <IntegrationStatusBadge status={execution.status} size="sm" />
                </td>
                <td className="px-4 py-3 text-sm text-theme-secondary">
                  {execution.triggered_by || 'Manual'}
                </td>
                <td className="px-4 py-3 text-sm text-theme-secondary">
                  {execution.execution_time_ms
                    ? integrationsApi.formatDuration(execution.execution_time_ms)
                    : '-'}
                </td>
                <td className="px-4 py-3 text-sm text-theme-secondary">
                  {new Date(execution.created_at).toLocaleString()}
                </td>
                <td className="px-4 py-3 text-right">
                  <div className="flex items-center justify-end gap-2">
                    {execution.status === 'failed' && onRetry && (
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          onRetry(execution.id);
                        }}
                        className="px-2 py-1 text-xs text-theme-primary hover:bg-theme-primary hover:bg-opacity-10 rounded transition-colors"
                      >
                        Retry
                      </button>
                    )}
                    {(execution.status === 'queued' || execution.status === 'running') &&
                      onCancel && (
                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            onCancel(execution.id);
                          }}
                          className="px-2 py-1 text-xs text-theme-error hover:bg-theme-error hover:bg-opacity-10 rounded transition-colors"
                        >
                          Cancel
                        </button>
                      )}
                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        handleToggleDetails(execution.id);
                      }}
                      className="px-2 py-1 text-xs text-theme-secondary hover:text-theme-primary transition-colors"
                    >
                      {expandedId === execution.id ? 'Hide' : 'Details'}
                    </button>
                  </div>
                </td>
              </tr>
              {expandedId === execution.id && (
                <tr key={`${execution.id}-details`}>
                  <td colSpan={5} className="px-4 py-4 bg-theme-surface">
                    {detailsLoading === execution.id ? (
                      <div className="flex items-center justify-center py-4">
                        <div className="animate-spin rounded-full h-5 w-5 border-2 border-theme-primary border-t-transparent" />
                      </div>
                    ) : executionDetails[execution.id] ? (
                      <ExecutionDetails
                        execution={executionDetails[execution.id]}
                        onViewDetails={onViewDetails}
                      />
                    ) : (
                      <p className="text-sm text-theme-tertiary">
                        Failed to load details
                      </p>
                    )}
                  </td>
                </tr>
              )}
            </>
          ))}
        </tbody>
      </table>
    </div>
  );
}

interface ExecutionDetailsProps {
  execution: IntegrationExecution;
  onViewDetails?: (execution: IntegrationExecution) => void;
}

function ExecutionDetails({ execution, onViewDetails }: ExecutionDetailsProps) {
  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div>
          <p className="text-xs text-theme-tertiary">Execution ID</p>
          <p className="text-sm text-theme-primary font-mono truncate">
            {execution.id}
          </p>
        </div>
        <div>
          <p className="text-xs text-theme-tertiary">Response Code</p>
          <p className="text-sm text-theme-primary">
            {execution.response_code || '-'}
          </p>
        </div>
        <div>
          <p className="text-xs text-theme-tertiary">Response Size</p>
          <p className="text-sm text-theme-primary">
            {execution.response_size_bytes
              ? `${(execution.response_size_bytes / 1024).toFixed(2)} KB`
              : '-'}
          </p>
        </div>
        <div>
          <p className="text-xs text-theme-tertiary">Retry Count</p>
          <p className="text-sm text-theme-primary">{execution.retry_count}</p>
        </div>
      </div>

      {execution.error_message && (
        <div className="p-3 bg-theme-error bg-opacity-10 rounded-lg">
          <p className="text-xs text-theme-error font-medium">
            {execution.error_class || 'Error'}
          </p>
          <p className="text-sm text-theme-error mt-1">{execution.error_message}</p>
        </div>
      )}

      {execution.input_data && Object.keys(execution.input_data).length > 0 && (
        <div>
          <p className="text-xs text-theme-tertiary mb-2">Input Data</p>
          <pre className="p-3 bg-theme-card rounded text-xs text-theme-secondary overflow-x-auto">
            {JSON.stringify(execution.input_data, null, 2)}
          </pre>
        </div>
      )}

      {execution.output_data && Object.keys(execution.output_data).length > 0 && (
        <div>
          <p className="text-xs text-theme-tertiary mb-2">Output Data</p>
          <pre className="p-3 bg-theme-card rounded text-xs text-theme-secondary overflow-x-auto">
            {JSON.stringify(execution.output_data, null, 2)}
          </pre>
        </div>
      )}

      {onViewDetails && (
        <button
          onClick={() => onViewDetails(execution)}
          className="text-sm text-theme-primary hover:underline"
        >
          View Full Details
        </button>
      )}
    </div>
  );
}
