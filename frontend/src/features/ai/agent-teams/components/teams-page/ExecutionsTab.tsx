import React, { useState, useCallback } from 'react';
import {
  Play, Pause, Square, ChevronDown, ChevronRight,
  Clock, Cpu, DollarSign, AlertTriangle, CheckCircle,
  XCircle, Loader2, User, RefreshCw, Zap, FileText, FileJson
} from 'lucide-react';
import { Team, TeamExecution } from '@/shared/services/ai/TeamsApiService';
import { MarkdownRenderer } from '@/shared/components/ui/MarkdownRenderer';
import api from '@/shared/services/api';

interface MemberCost {
  agent_id: string;
  agent_name: string;
  tokens_used: number;
  cost_usd: number;
  duration_ms: number;
  status: string;
}

interface ExecutionDetail {
  input_context?: Record<string, unknown>;
  output_result?: Record<string, unknown>;
  per_member_costs?: MemberCost[];
  tasks?: Array<{
    id: string;
    title?: string;
    status: string;
    assigned_to?: string;
    created_at: string;
    completed_at?: string;
  }>;
  messages?: Array<{
    id: string;
    content?: string;
    sender?: string;
    created_at: string;
  }>;
}

interface ExecutionsTabProps {
  selectedTeam: Team | null;
  executions: TeamExecution[];
  onStartExecution: () => void;
  onExecutionAction: (executionId: string, action: 'pause' | 'resume' | 'cancel') => void;
  onLoadExecutionTasks: (execution: TeamExecution) => void;
  getStatusColor: (status: string) => string;
}

const StatusIcon: React.FC<{ status: string }> = ({ status }) => {
  switch (status) {
    case 'completed': return <CheckCircle size={16} className="text-theme-success" />;
    case 'failed': case 'timeout': return <XCircle size={16} className="text-theme-danger" />;
    case 'running': return <Loader2 size={16} className="text-theme-warning animate-spin" />;
    case 'paused': return <Pause size={16} className="text-theme-info" />;
    case 'cancelled': return <XCircle size={16} className="text-theme-secondary" />;
    default: return <Clock size={16} className="text-theme-secondary" />;
  }
};

function formatDuration(ms: number | null | undefined): string {
  if (!ms) return '-';
  if (ms < 1000) return `${ms}ms`;
  const secs = ms / 1000;
  if (secs < 60) return `${secs.toFixed(1)}s`;
  const mins = Math.floor(secs / 60);
  const remainingSecs = Math.floor(secs % 60);
  return `${mins}m ${remainingSecs}s`;
}

function formatCost(cost: number | string | null | undefined): string {
  const num = Number(cost);
  if (!num || num === 0) return '$0.00';
  if (num < 0.01) return `$${num.toFixed(4)}`;
  return `$${num.toFixed(2)}`;
}

function extractMarkdown(output: Record<string, unknown>): string | null {
  // The execution output stores the markdown in the 'response' field
  if (typeof output.response === 'string' && output.response.length > 0) {
    return output.response;
  }
  // Check if the entire output is a string (edge case)
  if (typeof output === 'string') return output as string;
  return null;
}

function downloadContent(content: string, filename: string, mimeType: string): void {
  const blob = new Blob([content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

export const ExecutionsTab: React.FC<ExecutionsTabProps> = ({
  selectedTeam,
  executions,
  onStartExecution,
  onExecutionAction,
  onLoadExecutionTasks,
  getStatusColor,
}) => {
  const [expandedId, setExpandedId] = useState<string | null>(null);
  const [details, setDetails] = useState<Record<string, ExecutionDetail>>({});
  const [loadingDetail, setLoadingDetail] = useState<string | null>(null);

  const fetchDetail = useCallback(async (execution: TeamExecution) => {
    if (!selectedTeam) return;
    if (details[execution.id]) return; // Already loaded

    setLoadingDetail(execution.id);
    try {
      const response = await api.get(`/ai/agent_teams/${selectedTeam.id}/executions/${execution.id}`);
      const detail = response.data.data as ExecutionDetail;
      setDetails(prev => ({ ...prev, [execution.id]: detail }));
    } catch {
      // Silently fail - we'll still show the base execution data
    } finally {
      setLoadingDetail(null);
    }
  }, [selectedTeam, details]);

  const handleToggleExpand = useCallback((execution: TeamExecution) => {
    if (expandedId === execution.id) {
      setExpandedId(null);
    } else {
      setExpandedId(execution.id);
      fetchDetail(execution);
      onLoadExecutionTasks(execution);
    }
  }, [expandedId, fetchDetail, onLoadExecutionTasks]);

  if (!selectedTeam) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <p className="text-theme-secondary">Select a team to view executions</p>
      </div>
    );
  }

  if (executions.length === 0) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <Play size={48} className="mx-auto text-theme-secondary mb-4" />
        <h3 className="text-lg font-semibold text-theme-primary mb-2">No executions</h3>
        <p className="text-theme-secondary mb-6">Start a team execution to see results here</p>
        <button onClick={onStartExecution} className="btn-theme btn-theme-primary">
          Start Execution
        </button>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      {executions.map(execution => {
        const isExpanded = expandedId === execution.id;
        const detail = details[execution.id];
        const isLoadingThis = loadingDetail === execution.id;
        const progressPct = execution.progress_percentage ?? (
          execution.tasks_total > 0
            ? Math.round((execution.tasks_completed / execution.tasks_total) * 100)
            : 0
        );

        return (
          <div
            key={execution.id}
            className={`bg-theme-surface border rounded-lg transition-all ${
              isExpanded ? 'border-theme-accent/60 shadow-sm' : 'border-theme hover:border-theme-accent/30'
            }`}
          >
            {/* Card Header - Always visible */}
            <div
              className="p-4 cursor-pointer"
              onClick={() => handleToggleExpand(execution)}
            >
              <div className="flex items-center justify-between mb-2">
                <div className="flex items-center gap-3">
                  {isExpanded
                    ? <ChevronDown size={16} className="text-theme-secondary" />
                    : <ChevronRight size={16} className="text-theme-secondary" />
                  }
                  <StatusIcon status={execution.status} />
                  <span className="font-mono text-sm text-theme-secondary">{execution.execution_id.slice(0, 12)}</span>
                  <span className={`px-2 py-0.5 text-xs rounded font-medium ${getStatusColor(execution.status)}`}>
                    {execution.status}
                  </span>
                </div>
                <div className="flex items-center gap-2" onClick={(e) => e.stopPropagation()}>
                  {execution.status === 'running' && (
                    <>
                      <button
                        onClick={() => onExecutionAction(execution.id, 'pause')}
                        className="btn-theme btn-theme-warning btn-theme-sm"
                        title="Pause"
                      >
                        <Pause size={14} />
                      </button>
                      <button
                        onClick={() => onExecutionAction(execution.id, 'cancel')}
                        className="btn-theme btn-theme-danger btn-theme-sm"
                        title="Cancel"
                      >
                        <Square size={14} />
                      </button>
                    </>
                  )}
                  {execution.status === 'paused' && (
                    <button
                      onClick={() => onExecutionAction(execution.id, 'resume')}
                      className="btn-theme btn-theme-success btn-theme-sm"
                      title="Resume"
                    >
                      <Play size={14} />
                    </button>
                  )}
                </div>
              </div>

              <p className="text-sm text-theme-primary mb-2 line-clamp-2">
                {execution.objective || 'No objective'}
              </p>

              {/* Progress bar */}
              <div className="w-full bg-theme-bg rounded-full h-1.5 mb-2">
                <div
                  className={`h-1.5 rounded-full transition-all ${
                    execution.status === 'failed' ? 'bg-theme-danger' :
                    execution.status === 'completed' ? 'bg-theme-success' :
                    'bg-theme-accent'
                  }`}
                  style={{ width: `${progressPct}%` }}
                />
              </div>

              {/* Summary metrics */}
              <div className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-theme-secondary">
                <span className="flex items-center gap-1">
                  <Cpu size={12} />
                  {execution.tasks_completed}/{execution.tasks_total} agents
                </span>
                {execution.tasks_failed > 0 && (
                  <span className="flex items-center gap-1 text-theme-danger">
                    <AlertTriangle size={12} />
                    {execution.tasks_failed} failed
                  </span>
                )}
                <span className="flex items-center gap-1">
                  <Zap size={12} />
                  {(execution.total_tokens_used || 0).toLocaleString()} tokens
                </span>
                {Number(execution.total_cost_usd) > 0 && (
                  <span className="flex items-center gap-1">
                    <DollarSign size={12} />
                    {formatCost(execution.total_cost_usd)}
                  </span>
                )}
                <span className="flex items-center gap-1">
                  <Clock size={12} />
                  {formatDuration(execution.duration_ms)}
                </span>
                {execution.started_at && (
                  <span className="ml-auto">
                    {new Date(execution.started_at).toLocaleString()}
                  </span>
                )}
              </div>
            </div>

            {/* Expanded Detail Panel */}
            {isExpanded && (
              <div className="border-t border-theme px-4 pb-4">
                {isLoadingThis ? (
                  <div className="flex items-center justify-center py-8">
                    <Loader2 size={20} className="animate-spin text-theme-accent mr-2" />
                    <span className="text-sm text-theme-secondary">Loading details...</span>
                  </div>
                ) : (
                  <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 pt-4">
                    {/* Per-Agent Breakdown */}
                    <div className="space-y-3">
                      <h4 className="text-sm font-medium text-theme-primary flex items-center gap-2">
                        <User size={14} />
                        Agent Results
                      </h4>
                      {detail?.per_member_costs && detail.per_member_costs.length > 0 ? (
                        <div className="space-y-2">
                          {detail.per_member_costs.map((member, idx) => (
                            <div
                              key={member.agent_id || idx}
                              className="flex items-center justify-between p-2.5 bg-theme-bg rounded-md border border-theme/50"
                            >
                              <div className="flex items-center gap-2 min-w-0">
                                <StatusIcon status={member.status} />
                                <span className="text-sm text-theme-primary truncate">
                                  {member.agent_name}
                                </span>
                              </div>
                              <div className="flex items-center gap-3 text-xs text-theme-secondary shrink-0">
                                <span>{(member.tokens_used || 0).toLocaleString()} tok</span>
                                <span>{formatCost(member.cost_usd)}</span>
                                <span>{formatDuration(member.duration_ms)}</span>
                                <span className={`px-1.5 py-0.5 rounded text-[10px] font-medium ${getStatusColor(member.status)}`}>
                                  {member.status}
                                </span>
                              </div>
                            </div>
                          ))}
                        </div>
                      ) : (
                        <p className="text-xs text-theme-secondary italic py-2">No agent execution data available</p>
                      )}
                    </div>

                    {/* Right column - Input/Output/Error */}
                    <div className="space-y-3">
                      {/* Input Context */}
                      {detail?.input_context && Object.keys(detail.input_context).length > 0 && (
                        <div>
                          <h4 className="text-sm font-medium text-theme-primary mb-1.5">Input</h4>
                          <div className="bg-theme-bg rounded-md p-2.5 border border-theme/50 max-h-32 overflow-y-auto">
                            {detail.input_context.task ? (
                              <p className="text-xs text-theme-secondary whitespace-pre-wrap">
                                {String(detail.input_context.task)}
                              </p>
                            ) : (
                              <pre className="text-xs text-theme-secondary overflow-x-auto">
                                {JSON.stringify(detail.input_context, null, 2)}
                              </pre>
                            )}
                          </div>
                        </div>
                      )}

                      {/* Output Result */}
                      {detail?.output_result && Object.keys(detail.output_result).length > 0 && (() => {
                        const outputResult = detail.output_result!;
                        const mdContent = extractMarkdown(outputResult);
                        return (
                          <div>
                            <h4 className="text-sm font-medium text-theme-primary mb-1.5 flex items-center justify-between">
                              <span className="flex items-center gap-2">
                                <CheckCircle size={14} className="text-theme-success" />
                                Output
                              </span>
                              <div className="flex items-center gap-1">
                                {mdContent && (
                                  <button
                                    onClick={(e) => {
                                      e.stopPropagation();
                                      downloadContent(mdContent, `${execution.execution_id}-output.md`, 'text/markdown');
                                    }}
                                    className="flex items-center gap-1 px-2 py-1 text-[10px] rounded bg-theme-bg border border-theme/50 text-theme-secondary hover:text-theme-primary hover:border-theme-accent/50 transition-colors"
                                    title="Download as Markdown"
                                  >
                                    <FileText size={12} />
                                    .md
                                  </button>
                                )}
                                <button
                                  onClick={(e) => {
                                    e.stopPropagation();
                                    downloadContent(JSON.stringify(outputResult, null, 2), `${execution.execution_id}-output.json`, 'application/json');
                                  }}
                                  className="flex items-center gap-1 px-2 py-1 text-[10px] rounded bg-theme-bg border border-theme/50 text-theme-secondary hover:text-theme-primary hover:border-theme-accent/50 transition-colors"
                                  title="Download as JSON"
                                >
                                  <FileJson size={12} />
                                  .json
                                </button>
                              </div>
                            </h4>
                            <div className="bg-theme-bg rounded-md border border-theme/50 max-h-[480px] overflow-y-auto">
                              {mdContent ? (
                                <div className="p-3">
                                  <MarkdownRenderer
                                    content={mdContent}
                                    variant="admin"
                                    maxWidth="none"
                                    fontSize="sm"
                                    enableAdvancedFeatures={false}
                                    className="execution-output-md"
                                  />
                                </div>
                              ) : (
                                <pre className="text-xs text-theme-secondary whitespace-pre-wrap overflow-x-auto p-2.5">
                                  {JSON.stringify(outputResult, null, 2)}
                                </pre>
                              )}
                            </div>
                          </div>
                        );
                      })()}

                      {/* Error / Termination */}
                      {execution.termination_reason && (
                        <div>
                          <h4 className="text-sm font-medium text-theme-danger mb-1.5 flex items-center gap-2">
                            <AlertTriangle size={14} />
                            Error
                          </h4>
                          <div className="bg-theme-danger/5 border border-theme-danger/20 rounded-md p-2.5">
                            <p className="text-xs text-theme-danger whitespace-pre-wrap">
                              {execution.termination_reason}
                            </p>
                          </div>
                        </div>
                      )}

                      {/* Execution Metadata */}
                      <div>
                        <h4 className="text-sm font-medium text-theme-primary mb-1.5">Details</h4>
                        <div className="grid grid-cols-2 gap-2 text-xs">
                          <div className="bg-theme-bg rounded p-2 border border-theme/50">
                            <span className="text-theme-secondary block">Execution ID</span>
                            <span className="text-theme-primary font-mono">{execution.execution_id}</span>
                          </div>
                          <div className="bg-theme-bg rounded p-2 border border-theme/50">
                            <span className="text-theme-secondary block">Duration</span>
                            <span className="text-theme-primary">{formatDuration(execution.duration_ms)}</span>
                          </div>
                          <div className="bg-theme-bg rounded p-2 border border-theme/50">
                            <span className="text-theme-secondary block">Total Tokens</span>
                            <span className="text-theme-primary">{(execution.total_tokens_used || 0).toLocaleString()}</span>
                          </div>
                          <div className="bg-theme-bg rounded p-2 border border-theme/50">
                            <span className="text-theme-secondary block">Total Cost</span>
                            <span className="text-theme-primary">{formatCost(execution.total_cost_usd)}</span>
                          </div>
                          {execution.started_at && (
                            <div className="bg-theme-bg rounded p-2 border border-theme/50">
                              <span className="text-theme-secondary block">Started</span>
                              <span className="text-theme-primary">{new Date(execution.started_at).toLocaleString()}</span>
                            </div>
                          )}
                          {execution.completed_at && (
                            <div className="bg-theme-bg rounded p-2 border border-theme/50">
                              <span className="text-theme-secondary block">Completed</span>
                              <span className="text-theme-primary">{new Date(execution.completed_at).toLocaleString()}</span>
                            </div>
                          )}
                        </div>
                      </div>
                    </div>

                    {/* Tasks Summary - Full width */}
                    {detail?.tasks && detail.tasks.length > 0 && (
                      <div className="lg:col-span-2">
                        <h4 className="text-sm font-medium text-theme-primary mb-2 flex items-center gap-2">
                          <RefreshCw size={14} />
                          Tasks ({detail.tasks.length})
                        </h4>
                        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
                          {detail.tasks.map(task => (
                            <div key={task.id} className="flex items-center gap-2 p-2 bg-theme-bg rounded border border-theme/50">
                              <StatusIcon status={task.status} />
                              <span className="text-xs text-theme-primary truncate flex-1">
                                {task.title || task.assigned_to || task.id.slice(0, 8)}
                              </span>
                              <span className={`px-1.5 py-0.5 text-[10px] rounded font-medium ${getStatusColor(task.status)}`}>
                                {task.status}
                              </span>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}

                    {/* Messages Summary - Full width */}
                    {detail?.messages && detail.messages.length > 0 && (
                      <div className="lg:col-span-2">
                        <h4 className="text-sm font-medium text-theme-primary mb-2">
                          Messages ({detail.messages.length})
                        </h4>
                        <div className="space-y-1.5 max-h-40 overflow-y-auto">
                          {detail.messages.slice(0, 10).map(msg => (
                            <div key={msg.id} className="flex gap-2 text-xs p-1.5 bg-theme-bg rounded border border-theme/50">
                              {msg.sender && (
                                <span className="text-theme-accent font-medium shrink-0">{msg.sender}:</span>
                              )}
                              <span className="text-theme-secondary truncate">
                                {msg.content?.slice(0, 120) || '-'}
                              </span>
                            </div>
                          ))}
                          {detail.messages.length > 10 && (
                            <p className="text-xs text-theme-secondary text-center py-1">
                              +{detail.messages.length - 10} more messages
                            </p>
                          )}
                        </div>
                      </div>
                    )}
                  </div>
                )}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
};
