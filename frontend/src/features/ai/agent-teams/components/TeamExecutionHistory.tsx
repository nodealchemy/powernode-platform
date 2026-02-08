// Team Execution History - Shows past executions for a team
import React, { useState, useEffect } from 'react';
import { Clock, CheckCircle, XCircle, Loader, AlertTriangle, RefreshCw, ChevronDown } from 'lucide-react';
import { agentTeamsApi, TeamExecution } from '../services/agentTeamsApi';

interface TeamExecutionHistoryProps {
  teamId: string;
}

const getStatusIcon = (status: string) => {
  switch (status) {
    case 'completed':
      return <CheckCircle className="text-theme-success" size={14} />;
    case 'failed':
      return <XCircle className="text-theme-danger" size={14} />;
    case 'running':
      return <Loader className="animate-spin text-theme-info" size={14} />;
    case 'cancelled':
    case 'timeout':
      return <AlertTriangle className="text-theme-warning" size={14} />;
    default:
      return <Clock className="text-theme-muted" size={14} />;
  }
};

const getStatusColor = (status: string) => {
  switch (status) {
    case 'completed':
      return 'bg-theme-success/10 text-theme-success';
    case 'failed':
      return 'bg-theme-error/10 text-theme-danger';
    case 'running':
      return 'bg-theme-info/10 text-theme-info';
    case 'cancelled':
    case 'timeout':
      return 'bg-theme-warning/10 text-theme-warning';
    default:
      return 'bg-theme-accent text-theme-secondary';
  }
};

const formatDuration = (ms?: number) => {
  if (!ms) return '-';
  if (ms < 1000) return `${ms}ms`;
  if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
  const minutes = Math.floor(ms / 60000);
  const seconds = Math.round((ms % 60000) / 1000);
  return `${minutes}m ${seconds}s`;
};

const formatTime = (iso?: string) => {
  if (!iso) return '-';
  return new Date(iso).toLocaleString();
};

export const TeamExecutionHistory: React.FC<TeamExecutionHistoryProps> = ({ teamId }) => {
  const [executions, setExecutions] = useState<TeamExecution[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [expandedId, setExpandedId] = useState<string | null>(null);

  const loadExecutions = async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await agentTeamsApi.getExecutions(teamId, { per_page: 10 });
      setExecutions(response.data);
    } catch {
      setError('Failed to load execution history');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadExecutions();
  }, [teamId]);

  if (loading) {
    return (
      <div className="flex items-center justify-center p-6">
        <Loader className="animate-spin text-theme-info" size={20} />
        <span className="ml-2 text-sm text-theme-secondary">Loading history...</span>
      </div>
    );
  }

  if (error) {
    return (
      <div className="p-4 text-center">
        <p className="text-sm text-theme-danger mb-2">{error}</p>
        <button
          type="button"
          onClick={loadExecutions}
          className="text-xs text-theme-info hover:text-theme-primary underline"
        >
          Retry
        </button>
      </div>
    );
  }

  if (executions.length === 0) {
    return (
      <div className="p-6 text-center">
        <Clock size={24} className="mx-auto text-theme-secondary mb-2" />
        <p className="text-sm text-theme-secondary">No execution history yet</p>
      </div>
    );
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-3">
        <h4 className="text-sm font-semibold text-theme-primary">Execution History</h4>
        <button
          type="button"
          onClick={loadExecutions}
          className="p-1 rounded text-theme-secondary hover:bg-theme-accent hover:text-theme-primary transition-colors"
          title="Refresh"
        >
          <RefreshCw size={14} />
        </button>
      </div>

      <div className="space-y-1">
        {executions.map((execution) => (
          <div key={execution.id} className="border border-theme rounded-md overflow-hidden">
            <button
              type="button"
              className="w-full flex items-center justify-between p-3 hover:bg-theme-accent/50 transition-colors text-left"
              onClick={() => setExpandedId(prev => prev === execution.id ? null : execution.id)}
            >
              <div className="flex items-center gap-3">
                {getStatusIcon(execution.status)}
                <span className={`px-1.5 py-0.5 text-xs font-medium rounded ${getStatusColor(execution.status)}`}>
                  {execution.status}
                </span>
                <span className="text-xs text-theme-secondary">
                  {formatTime(execution.started_at || execution.created_at)}
                </span>
              </div>

              <div className="flex items-center gap-3">
                <span className="text-xs text-theme-secondary">
                  {execution.tasks_completed}/{execution.tasks_total} agents
                </span>
                {execution.tasks_failed > 0 && (
                  <span className="text-xs text-theme-danger">{execution.tasks_failed} failed</span>
                )}
                {(Number(execution.total_cost_usd) || 0) > 0 && (
                  <span className={`text-xs font-medium ${
                    (Number(execution.total_cost_usd) || 0) < 0.01 ? 'text-theme-success' :
                    (Number(execution.total_cost_usd) || 0) < 0.10 ? 'text-theme-warning' :
                    'text-theme-danger'
                  }`}>
                    ${(Number(execution.total_cost_usd) || 0).toFixed(4)}
                  </span>
                )}
                <span className="text-xs text-theme-secondary">
                  {formatDuration(execution.duration_ms)}
                </span>
                <ChevronDown className={`h-3 w-3 text-theme-secondary transition-transform ${expandedId === execution.id ? 'rotate-180' : ''}`} />
              </div>
            </button>

            {expandedId === execution.id && (
              <div className="border-t border-theme p-3 bg-theme-accent/30 text-xs space-y-2">
                <div className="grid grid-cols-2 gap-2">
                  <div>
                    <span className="text-theme-secondary">Execution ID:</span>{' '}
                    <span className="text-theme-primary font-mono">{execution.execution_id}</span>
                  </div>
                  {execution.triggered_by && (
                    <div>
                      <span className="text-theme-secondary">Triggered by:</span>{' '}
                      <span className="text-theme-primary">{execution.triggered_by.name}</span>
                    </div>
                  )}
                  {execution.objective && (
                    <div className="col-span-2">
                      <span className="text-theme-secondary">Objective:</span>{' '}
                      <span className="text-theme-primary">{execution.objective}</span>
                    </div>
                  )}
                  {execution.termination_reason && execution.termination_reason !== 'completed' && (
                    <div className="col-span-2">
                      <span className="text-theme-secondary">Reason:</span>{' '}
                      <span className="text-theme-danger">{execution.termination_reason}</span>
                    </div>
                  )}
                </div>
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
};
