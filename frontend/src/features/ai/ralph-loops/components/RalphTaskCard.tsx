import React from 'react';
import {
  CheckCircle,
  XCircle,
  Clock,
  AlertTriangle,
  PlayCircle,
  SkipForward,
  RefreshCw,
  ChevronRight,
  ChevronDown,
  Bot,
  GitBranch,
  Target,
  Loader2,
  Edit3,
  Workflow,
  Container,
  Network,
  User,
  Globe,
  Settings,
  Calendar,
  Hash,
  Zap,
} from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { cn } from '@/shared/utils/cn';
import { formatDateTime } from '@/shared/utils/formatters';
import type { RalphTask, RalphTaskSummary, RalphTaskStatus, RalphExecutionType } from '@/shared/services/ai/types/ralph-types';

const statusConfig: Record<RalphTaskStatus, {
  variant: 'success' | 'warning' | 'danger' | 'info' | 'outline';
  label: string;
  icon: React.FC<{ className?: string }>;
}> = {
  pending: { variant: 'outline', label: 'Pending', icon: Clock },
  in_progress: { variant: 'info', label: 'In Progress', icon: PlayCircle },
  passed: { variant: 'success', label: 'Passed', icon: CheckCircle },
  failed: { variant: 'danger', label: 'Failed', icon: XCircle },
  blocked: { variant: 'warning', label: 'Blocked', icon: AlertTriangle },
  skipped: { variant: 'outline', label: 'Skipped', icon: SkipForward },
};

const executionTypeConfig: Record<RalphExecutionType, {
  label: string;
  icon: React.FC<{ className?: string }>;
}> = {
  agent: { label: 'AI Agent', icon: Bot },
  workflow: { label: 'Workflow', icon: Workflow },
  pipeline: { label: 'Pipeline', icon: GitBranch },
  a2a_task: { label: 'A2A Task', icon: Network },
  container: { label: 'Container', icon: Container },
  human: { label: 'Human Review', icon: User },
  community: { label: 'Community Agent', icon: Globe },
};

const matchStrategyLabels: Record<string, string> = {
  all: 'Match All',
  any: 'Match Any',
  weighted: 'Weighted',
};

interface RalphTaskCardProps {
  task: RalphTaskSummary;
  isExpanded: boolean;
  details: RalphTask | undefined;
  isLoadingDetails: boolean;
  canEdit: boolean;
  onToggleExpansion: (taskId: string) => void;
  onOpenConfig: (taskId: string) => void;
  onSelectTask?: (task: RalphTaskSummary) => void;
}

export const RalphTaskCard: React.FC<RalphTaskCardProps> = ({
  task,
  isExpanded,
  details,
  isLoadingDetails,
  canEdit,
  onToggleExpansion,
  onOpenConfig,
  onSelectTask,
}) => {
  const status = statusConfig[task.status] || statusConfig.pending;
  const StatusIcon = status.icon;

  return (
    <Card className="transition-colors cursor-pointer hover:bg-theme-bg-secondary/50">
      <CardContent className="p-3">
        {/* Header row */}
        <div
          className="flex items-center justify-between"
          onClick={() => onToggleExpansion(task.id)}
        >
          <div className="flex items-center gap-3 flex-1 min-w-0">
            <StatusIcon className={cn(
              'w-5 h-5 flex-shrink-0',
              task.status === 'passed' && 'text-theme-status-success',
              task.status === 'failed' && 'text-theme-status-error',
              task.status === 'in_progress' && 'text-theme-status-info',
              task.status === 'blocked' && 'text-theme-status-warning',
              (task.status === 'pending' || task.status === 'skipped') && 'text-theme-text-secondary'
            )} />
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2">
                <span className="font-mono text-xs text-theme-text-secondary">
                  {task.task_key}
                </span>
                <Badge variant={status.variant} size="sm">
                  {status.label}
                </Badge>
                {task.priority > 0 && (
                  <span className="text-xs text-theme-text-secondary">
                    P{task.priority}
                  </span>
                )}
              </div>
              <p className={cn(
                'text-sm text-theme-text-primary mt-1',
                !isExpanded && 'truncate'
              )}>
                {task.description}
              </p>
            </div>
          </div>
          <div className="flex items-center gap-2 ml-2">
            {task.iteration_count > 0 && (
              <span className="text-xs text-theme-text-secondary">
                {task.iteration_count} iteration{task.iteration_count !== 1 ? 's' : ''}
              </span>
            )}
            {canEdit && (
              <Button
                variant="ghost"
                size="sm"
                onClick={(e) => {
                  e.stopPropagation();
                  onOpenConfig(task.id);
                }}
                title="Configure task"
              >
                <Edit3 className="w-4 h-4" />
              </Button>
            )}
            {isExpanded ? (
              <ChevronDown className="w-4 h-4 text-theme-text-secondary" />
            ) : (
              <ChevronRight className="w-4 h-4 text-theme-text-secondary" />
            )}
          </div>
        </div>

        {/* Expanded details */}
        {isExpanded && (
          <div className="mt-4 pt-3 border-t border-theme-border-primary space-y-4">
            {isLoadingDetails ? (
              <div className="flex items-center justify-center py-4">
                <Loader2 className="w-5 h-5 animate-spin text-theme-text-secondary" />
              </div>
            ) : details ? (
              <>
                {/* Error Message */}
                {details.error_message && (
                  <div className="p-3 rounded-lg bg-theme-status-error/10 border border-theme-status-error/30 text-theme-status-error text-sm">
                    <strong className="block mb-1">Error:</strong>
                    <span className="whitespace-pre-wrap">{details.error_message}</span>
                  </div>
                )}

                {/* Executor Configuration Section */}
                <div className="p-3 rounded-lg bg-theme-bg-secondary space-y-3">
                  <h4 className="text-sm font-medium text-theme-text-primary flex items-center gap-2">
                    <Settings className="w-4 h-4" />
                    Executor Configuration
                  </h4>

                  <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
                    <div>
                      <span className="text-theme-text-secondary block mb-1">Type</span>
                      {details.execution_type && (
                        <div className="flex items-center gap-1.5">
                          {(() => {
                            const config = executionTypeConfig[details.execution_type];
                            const Icon = config?.icon || Bot;
                            return <Icon className="w-4 h-4 text-theme-brand-primary" />;
                          })()}
                          <span className="text-theme-text-primary font-medium">
                            {executionTypeConfig[details.execution_type]?.label || details.execution_type}
                          </span>
                        </div>
                      )}
                    </div>
                    <div>
                      <span className="text-theme-text-secondary block mb-1">Executor ID</span>
                      <span className="text-theme-text-primary font-mono text-xs">
                        {details.executor_id ? details.executor_id.slice(0, 8) + '...' : 'Auto-select'}
                      </span>
                    </div>
                    <div>
                      <span className="text-theme-text-secondary block mb-1">Match Strategy</span>
                      <span className="text-theme-text-primary">
                        {matchStrategyLabels[details.capability_match_strategy || 'all'] || 'Match All'}
                      </span>
                    </div>
                    <div>
                      <span className="text-theme-text-secondary block mb-1">Attempts</span>
                      <span className="text-theme-text-primary flex items-center gap-1">
                        <Zap className="w-3 h-3" />
                        {details.execution_attempts || 0}
                      </span>
                    </div>
                  </div>

                  {/* Required Capabilities */}
                  {details.required_capabilities && details.required_capabilities.length > 0 && (
                    <div>
                      <span className="text-theme-text-secondary text-sm block mb-1.5">Required Capabilities</span>
                      <div className="flex flex-wrap gap-1.5">
                        {details.required_capabilities.map((cap) => (
                          <Badge key={cap} variant="info" size="sm">{cap}</Badge>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* Delegation Config */}
                  {details.delegation_config && Object.keys(details.delegation_config).length > 0 && (
                    <div className="pt-2 border-t border-theme-border-primary">
                      <span className="text-theme-text-secondary text-sm block mb-2">Delegation Settings</span>
                      <div className="grid grid-cols-2 md:grid-cols-3 gap-2 text-xs">
                        {details.delegation_config.timeout_seconds && (
                          <div>
                            <span className="text-theme-text-secondary">Timeout:</span>
                            <span className="text-theme-text-primary ml-1">{details.delegation_config.timeout_seconds}s</span>
                          </div>
                        )}
                        {details.delegation_config.max_delegation_depth && (
                          <div>
                            <span className="text-theme-text-secondary">Max Depth:</span>
                            <span className="text-theme-text-primary ml-1">{details.delegation_config.max_delegation_depth}</span>
                          </div>
                        )}
                        {details.delegation_config.retry_strategy && (
                          <div>
                            <span className="text-theme-text-secondary">Retry:</span>
                            <span className="text-theme-text-primary ml-1 capitalize">{details.delegation_config.retry_strategy}</span>
                          </div>
                        )}
                        {details.delegation_config.fallback_executor_type && (
                          <div>
                            <span className="text-theme-text-secondary">Fallback:</span>
                            <span className="text-theme-text-primary ml-1">
                              {executionTypeConfig[details.delegation_config.fallback_executor_type]?.label}
                            </span>
                          </div>
                        )}
                      </div>
                    </div>
                  )}
                </div>

                {/* Task Details Section */}
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div>
                    <div className="flex items-center gap-1.5 text-sm mb-2">
                      <GitBranch className="w-4 h-4 text-theme-text-secondary" />
                      <span className="font-medium text-theme-text-primary">Dependencies</span>
                    </div>
                    {details.dependencies && details.dependencies.length > 0 ? (
                      <div className="flex flex-wrap gap-1.5">
                        {details.dependencies.map((dep) => (
                          <Badge key={dep} variant="outline" size="sm">{dep}</Badge>
                        ))}
                      </div>
                    ) : (
                      <span className="text-sm text-theme-text-secondary">No dependencies</span>
                    )}
                  </div>
                  <div>
                    <div className="flex items-center gap-1.5 text-sm mb-2">
                      <Target className="w-4 h-4 text-theme-text-secondary" />
                      <span className="font-medium text-theme-text-primary">Acceptance Criteria</span>
                    </div>
                    {details.acceptance_criteria ? (
                      <p className="text-sm text-theme-text-primary whitespace-pre-wrap bg-theme-bg-secondary p-2 rounded">
                        {details.acceptance_criteria}
                      </p>
                    ) : (
                      <span className="text-sm text-theme-text-secondary">Not specified</span>
                    )}
                  </div>
                </div>

                {/* Timestamps & Iteration Info */}
                <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-xs p-3 bg-theme-bg-secondary rounded-lg">
                  <div>
                    <div className="flex items-center gap-1 text-theme-text-secondary mb-1">
                      <Hash className="w-3 h-3" />
                      <span>Priority</span>
                    </div>
                    <span className="text-theme-text-primary font-medium">{details.priority || 'Not set'}</span>
                  </div>
                  <div>
                    <div className="flex items-center gap-1 text-theme-text-secondary mb-1">
                      <RefreshCw className="w-3 h-3" />
                      <span>Iterations</span>
                    </div>
                    <span className="text-theme-text-primary font-medium">{details.iteration_count || 0}</span>
                  </div>
                  <div>
                    <div className="flex items-center gap-1 text-theme-text-secondary mb-1">
                      <Calendar className="w-3 h-3" />
                      <span>Created</span>
                    </div>
                    <span className="text-theme-text-primary">
                      {details.created_at ? formatDateTime(details.created_at) : 'N/A'}
                    </span>
                  </div>
                  <div>
                    <div className="flex items-center gap-1 text-theme-text-secondary mb-1">
                      <Calendar className="w-3 h-3" />
                      <span>Last Iteration</span>
                    </div>
                    <span className="text-theme-text-primary">
                      {details.iteration_completed_at ? formatDateTime(details.iteration_completed_at) : 'N/A'}
                    </span>
                  </div>
                </div>

                {/* Action Buttons */}
                <div className="flex items-center gap-2 pt-2 border-t border-theme-border-primary">
                  {onSelectTask && (
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={(e) => {
                        e.stopPropagation();
                        onSelectTask(task);
                      }}
                    >
                      <RefreshCw className="w-3 h-3 mr-1" />
                      View Iterations
                    </Button>
                  )}
                </div>
              </>
            ) : (
              <p className="text-sm text-theme-text-secondary">
                Failed to load task details
              </p>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  );
};
