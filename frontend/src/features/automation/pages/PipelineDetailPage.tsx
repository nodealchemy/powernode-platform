import React, { useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import {
  Play, Pause, RefreshCw, Edit, Trash2, Copy, FileCode,
  Clock, CheckCircle, XCircle, AlertCircle, GitBranch, Calendar,
  Zap, Brain, MoreVertical, ExternalLink, Layers,
  List, BarChart3
} from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { PageErrorBoundary } from '@/shared/components/error/ErrorBoundary';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { usePipeline } from '@/features/cicd/hooks/usePipelines';
import { usePipelineRuns } from '@/features/cicd/hooks/usePipelineRuns';
import { ciCdPipelinesApi } from '@/services/ciCdApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import type { CiCdPipeline, CiCdPipelineRunStatus, CiCdPipelineStep } from '@/types/cicd';

type TabType = 'overview' | 'runs' | 'steps';

// Status Badge Component
const StatusBadge: React.FC<{ isActive: boolean }> = ({ isActive }) => (
  <span
    className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium ${
      isActive
        ? 'bg-green-100 text-theme-success dark:bg-green-900/30 dark:text-green-300'
        : 'bg-theme-surface-secondary text-theme-secondary'
    }`}
  >
    {isActive ? (
      <>
        <CheckCircle className="w-3 h-3" />
        Active
      </>
    ) : (
      <>
        <Pause className="w-3 h-3" />
        Inactive
      </>
    )}
  </span>
);

// Run Status Badge Component
const RunStatusBadge: React.FC<{ status: CiCdPipelineRunStatus | string }> = ({ status }) => {
  const configs: Record<string, { bg: string; text: string; icon: React.ElementType; label: string }> = {
    pending: { bg: 'bg-yellow-100 dark:bg-yellow-900/30', text: 'text-yellow-700 dark:text-yellow-300', icon: Clock, label: 'Pending' },
    queued: { bg: 'bg-yellow-100 dark:bg-yellow-900/30', text: 'text-yellow-700 dark:text-yellow-300', icon: Clock, label: 'Queued' },
    running: { bg: 'bg-blue-100 dark:bg-blue-900/30', text: 'text-theme-info dark:text-blue-300', icon: RefreshCw, label: 'Running' },
    success: { bg: 'bg-green-100 dark:bg-green-900/30', text: 'text-theme-success dark:text-green-300', icon: CheckCircle, label: 'Success' },
    failed: { bg: 'bg-red-100 dark:bg-red-900/30', text: 'text-theme-danger dark:text-red-300', icon: XCircle, label: 'Failed' },
    failure: { bg: 'bg-red-100 dark:bg-red-900/30', text: 'text-theme-danger dark:text-red-300', icon: XCircle, label: 'Failed' },
    cancelled: { bg: 'bg-theme-surface-secondary', text: 'text-theme-secondary', icon: AlertCircle, label: 'Cancelled' },
  };
  const config = configs[status] || configs.pending;
  const Icon = config.icon;

  return (
    <span className={`inline-flex items-center gap-1 px-2 py-1 rounded-full text-xs font-medium ${config.bg} ${config.text}`}>
      <Icon className={`w-3 h-3 ${status === 'running' ? 'animate-spin' : ''}`} />
      {config.label}
    </span>
  );
};

// Step Type Badge Component
const StepTypeBadge: React.FC<{ stepType: string }> = ({ stepType }) => {
  const configs: Record<string, { bg: string; text: string; label: string }> = {
    checkout: { bg: 'bg-blue-100 dark:bg-blue-900/30', text: 'text-theme-info dark:text-blue-300', label: 'Checkout' },
    claude_execute: { bg: 'bg-purple-100 dark:bg-purple-900/30', text: 'text-purple-700 dark:text-purple-300', label: 'Claude Execute' },
    post_comment: { bg: 'bg-green-100 dark:bg-green-900/30', text: 'text-theme-success dark:text-green-300', label: 'Post Comment' },
    create_pr: { bg: 'bg-indigo-100 dark:bg-indigo-900/30', text: 'text-indigo-700 dark:text-indigo-300', label: 'Create PR' },
    create_branch: { bg: 'bg-indigo-100 dark:bg-indigo-900/30', text: 'text-indigo-700 dark:text-indigo-300', label: 'Create Branch' },
    deploy: { bg: 'bg-orange-100 dark:bg-orange-900/30', text: 'text-orange-700 dark:text-orange-300', label: 'Deploy' },
    run_tests: { bg: 'bg-cyan-100 dark:bg-cyan-900/30', text: 'text-cyan-700 dark:text-cyan-300', label: 'Run Tests' },
    upload_artifact: { bg: 'bg-teal-100 dark:bg-teal-900/30', text: 'text-teal-700 dark:text-teal-300', label: 'Upload Artifact' },
    download_artifact: { bg: 'bg-teal-100 dark:bg-teal-900/30', text: 'text-teal-700 dark:text-teal-300', label: 'Download Artifact' },
    notify: { bg: 'bg-pink-100 dark:bg-pink-900/30', text: 'text-pink-700 dark:text-pink-300', label: 'Notify' },
    custom: { bg: 'bg-theme-surface-secondary', text: 'text-theme-secondary', label: 'Custom' },
  };
  const config = configs[stepType] || { bg: 'bg-theme-surface-secondary', text: 'text-theme-secondary', label: stepType };

  return (
    <span className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${config.bg} ${config.text}`}>
      {config.label}
    </span>
  );
};

// Trigger Info Component
interface TriggerItem {
  icon: React.ElementType;
  label: string;
  detail?: string;
}

const TriggerInfo: React.FC<{ triggers: CiCdPipeline['triggers'] }> = ({ triggers }) => {
  const getTriggers = (): TriggerItem[] => {
    const active: TriggerItem[] = [];

    if (triggers.manual) {
      active.push({ icon: Play, label: 'Manual' });
    }
    if (triggers.push?.branches?.length) {
      active.push({ icon: GitBranch, label: 'Push', detail: triggers.push.branches.join(', ') });
    }
    if (triggers.pull_request?.length) {
      active.push({ icon: GitBranch, label: 'Pull Request', detail: triggers.pull_request.join(', ') });
    }
    if (triggers.schedule?.length) {
      active.push({ icon: Calendar, label: 'Scheduled', detail: triggers.schedule.join(', ') });
    }
    if (triggers.workflow_dispatch) {
      active.push({ icon: Zap, label: 'Workflow Dispatch' });
    }

    return active.length > 0 ? active : [{ icon: Play, label: 'Manual Only' }];
  };

  const activeTriggers = getTriggers();

  return (
    <div className="space-y-2">
      {activeTriggers.map((trigger, index) => {
        const Icon = trigger.icon;
        return (
          <div key={index} className="flex items-center gap-2 text-sm">
            <Icon className="w-4 h-4 text-theme-secondary" />
            <span className="text-theme-primary">{trigger.label}</span>
            {trigger.detail && (
              <span className="text-theme-tertiary text-xs">({trigger.detail})</span>
            )}
          </div>
        );
      })}
    </div>
  );
};

// Format helpers
const formatTimeAgo = (dateString: string | null): string => {
  if (!dateString) return 'Never';
  const date = new Date(dateString);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMins / 60);
  const diffDays = Math.floor(diffHours / 24);

  if (diffMins < 1) return 'just now';
  if (diffMins < 60) return `${diffMins}m ago`;
  if (diffHours < 24) return `${diffHours}h ago`;
  return `${diffDays}d ago`;
};

const formatDuration = (seconds: number | null): string => {
  if (!seconds) return '-';
  if (seconds < 60) return `${Math.round(seconds)}s`;
  if (seconds < 3600) return `${Math.round(seconds / 60)}m ${Math.round(seconds % 60)}s`;
  return `${Math.round(seconds / 3600)}h ${Math.round((seconds % 3600) / 60)}m`;
};

const formatDate = (dateString: string): string => {
  return new Date(dateString).toLocaleDateString('en-US', {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
};

// Overview Tab Component
const OverviewTab: React.FC<{ pipeline: CiCdPipeline; onViewRun: (runId: string) => void }> = ({ pipeline, onViewRun }) => {
  const hasAiSteps = pipeline.steps?.some(step => step.step_type === 'claude_execute');

  // Get step type distribution
  const stepTypeCount = (pipeline.steps || []).reduce((acc, step) => {
    acc[step.step_type] = (acc[step.step_type] || 0) + 1;
    return acc;
  }, {} as Record<string, number>);

  return (
    <div className="space-y-6">
      {/* Pipeline Info Card */}
      <div className="bg-theme-surface rounded-lg border border-theme p-6">
        <div className="flex items-start justify-between mb-4">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-theme-surface-secondary rounded-lg">
              {hasAiSteps ? (
                <Brain className="w-6 h-6 text-theme-accent" />
              ) : (
                <GitBranch className="w-6 h-6 text-theme-info" />
              )}
            </div>
            <div>
              <h3 className="text-lg font-semibold text-theme-primary">{pipeline.name}</h3>
              <p className="text-sm text-theme-tertiary font-mono">{pipeline.slug}</p>
            </div>
          </div>
          <StatusBadge isActive={pipeline.is_active} />
        </div>

        {pipeline.description && (
          <p className="text-theme-secondary mb-4">{pipeline.description}</p>
        )}

        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 pt-4 border-t border-theme">
          <div>
            <p className="text-sm text-theme-tertiary">Type</p>
            <p className="text-theme-primary font-medium capitalize">{pipeline.pipeline_type || 'Standard'}</p>
          </div>
          <div>
            <p className="text-sm text-theme-tertiary">Version</p>
            <p className="text-theme-primary font-medium">v{pipeline.version}</p>
          </div>
          <div>
            <p className="text-sm text-theme-tertiary">Timeout</p>
            <p className="text-theme-primary font-medium">{pipeline.timeout_minutes} min</p>
          </div>
          <div>
            <p className="text-sm text-theme-tertiary">Concurrent Runs</p>
            <p className="text-theme-primary font-medium">{pipeline.allow_concurrent ? 'Allowed' : 'Disabled'}</p>
          </div>
        </div>
      </div>

      {/* Stats Cards */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div className="bg-theme-surface rounded-lg border border-theme p-4">
          <div className="flex items-center gap-2 mb-2">
            <Play className="w-4 h-4 text-theme-secondary" />
            <p className="text-sm text-theme-tertiary">Total Runs</p>
          </div>
          <p className="text-2xl font-semibold text-theme-primary">{pipeline.run_count || 0}</p>
        </div>
        <div className="bg-theme-surface rounded-lg border border-theme p-4">
          <div className="flex items-center gap-2 mb-2">
            <CheckCircle className="w-4 h-4 text-theme-success" />
            <p className="text-sm text-theme-tertiary">Success Rate</p>
          </div>
          <p className={`text-2xl font-semibold ${
            pipeline.success_rate !== null && pipeline.success_rate >= 80
              ? 'text-theme-success dark:text-green-400'
              : pipeline.success_rate !== null && pipeline.success_rate >= 50
                ? 'text-theme-warning dark:text-yellow-400'
                : 'text-theme-secondary'
          }`}>
            {pipeline.success_rate !== null ? `${Math.round(pipeline.success_rate)}%` : 'N/A'}
          </p>
        </div>
        <div className="bg-theme-surface rounded-lg border border-theme p-4">
          <div className="flex items-center gap-2 mb-2">
            <Layers className="w-4 h-4 text-theme-secondary" />
            <p className="text-sm text-theme-tertiary">Steps</p>
          </div>
          <p className="text-2xl font-semibold text-theme-primary">{pipeline.step_count || 0}</p>
        </div>
        <div className="bg-theme-surface rounded-lg border border-theme p-4">
          <div className="flex items-center gap-2 mb-2">
            <Clock className="w-4 h-4 text-theme-secondary" />
            <p className="text-sm text-theme-tertiary">Last Run</p>
          </div>
          <p className="text-lg font-medium text-theme-primary">
            {formatTimeAgo(pipeline.last_run?.started_at || null)}
          </p>
          {pipeline.last_run && (
            <RunStatusBadge status={pipeline.last_run.status as CiCdPipelineRunStatus} />
          )}
        </div>
      </div>

      {/* Last Run Failed Warning */}
      {pipeline.last_run && (pipeline.last_run.status === 'failure' || pipeline.last_run.status === 'failed') && (
        <div className="bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg p-4">
          <div className="flex items-start gap-3">
            <div className="p-2 bg-red-100 dark:bg-red-900/40 rounded-lg shrink-0">
              <AlertCircle className="w-5 h-5 text-theme-danger dark:text-red-400" />
            </div>
            <div className="flex-1 min-w-0">
              <h4 className="text-sm font-medium text-red-800 dark:text-red-300 mb-1">
                Last Run Failed
              </h4>
              <p className="text-sm text-theme-danger dark:text-red-400 mb-3">
                {pipeline.last_run.error_message || 'The pipeline run encountered an error.'}
              </p>
              <button
                onClick={() => onViewRun(pipeline.last_run!.id)}
                className="inline-flex items-center gap-1 text-sm font-medium text-theme-danger dark:text-red-300 hover:underline"
              >
                View Run Details
                <ExternalLink className="w-3 h-3" />
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Pipeline Workflow Visual */}
      {pipeline.steps && pipeline.steps.length > 0 && (
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <h4 className="text-sm font-medium text-theme-primary mb-4">Pipeline Workflow</h4>
          <div className="flex items-center gap-2 overflow-x-auto pb-2">
            {pipeline.steps.sort((a, b) => a.position - b.position).map((step, index) => (
              <React.Fragment key={step.id}>
                <div className="flex-shrink-0 flex flex-col items-center">
                  <div className={`w-10 h-10 rounded-full flex items-center justify-center text-sm font-medium ${
                    step.is_active
                      ? 'bg-theme-interactive-primary text-white'
                      : 'bg-theme-surface-secondary text-theme-tertiary'
                  }`}>
                    {index + 1}
                  </div>
                  <div className="mt-2 text-center max-w-24">
                    <p className={`text-xs font-medium truncate ${step.is_active ? 'text-theme-primary' : 'text-theme-tertiary'}`}>
                      {step.name}
                    </p>
                    <StepTypeBadge stepType={step.step_type} />
                  </div>
                </div>
                {index < (pipeline.steps?.length || 0) - 1 && (
                  <div className="flex-shrink-0 w-8 h-0.5 bg-theme-secondary/30 mt-[-20px]" />
                )}
              </React.Fragment>
            ))}
          </div>
        </div>
      )}

      {/* Two Column Layout */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Triggers */}
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <h4 className="text-sm font-medium text-theme-primary mb-4">Triggers</h4>
          <TriggerInfo triggers={pipeline.triggers} />
        </div>

        {/* Step Types Distribution */}
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <h4 className="text-sm font-medium text-theme-primary mb-4">Step Types</h4>
          <div className="space-y-2">
            {Object.entries(stepTypeCount).map(([type, count]) => (
              <div key={type} className="flex items-center justify-between">
                <StepTypeBadge stepType={type} />
                <span className="text-sm text-theme-secondary">{count} step{count !== 1 ? 's' : ''}</span>
              </div>
            ))}
            {Object.keys(stepTypeCount).length === 0 && (
              <p className="text-sm text-theme-tertiary">No steps configured</p>
            )}
          </div>
        </div>
      </div>

      {/* Recent Runs */}
      {pipeline.recent_runs && pipeline.recent_runs.length > 0 && (
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <div className="flex items-center justify-between mb-4">
            <h4 className="text-sm font-medium text-theme-primary">Recent Runs</h4>
            <span className="text-xs text-theme-tertiary">Last {pipeline.recent_runs.length} runs</span>
          </div>
          <div className="space-y-3">
            {pipeline.recent_runs.map((run) => (
              <button
                key={run.id}
                onClick={() => onViewRun(run.id)}
                className="w-full flex items-center justify-between p-3 rounded-lg bg-theme-surface-secondary hover:bg-theme-surface-tertiary transition-colors text-left"
              >
                <div className="flex items-center gap-3">
                  <span className="font-medium text-theme-primary">#{run.run_number}</span>
                  <RunStatusBadge status={run.status as CiCdPipelineRunStatus} />
                  <span className="text-xs text-theme-tertiary px-2 py-0.5 bg-theme-surface rounded">
                    {run.trigger_type}
                  </span>
                </div>
                <div className="flex items-center gap-4 text-sm text-theme-tertiary">
                  {run.duration_seconds && (
                    <span className="flex items-center gap-1">
                      <Clock className="w-3 h-3" />
                      {formatDuration(run.duration_seconds)}
                    </span>
                  )}
                  <span>{formatTimeAgo(run.started_at)}</span>
                  <ExternalLink className="w-4 h-4" />
                </div>
              </button>
            ))}
          </div>
        </div>
      )}

      {/* AI Provider (if configured) */}
      {pipeline.ai_provider_name && (
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <h4 className="text-sm font-medium text-theme-primary mb-2">AI Provider</h4>
          <div className="flex items-center gap-2">
            <Brain className="w-5 h-5 text-theme-accent" />
            <span className="text-theme-secondary">{pipeline.ai_provider_name}</span>
          </div>
        </div>
      )}

      {/* Metadata */}
      <div className="bg-theme-surface rounded-lg border border-theme p-6">
        <h4 className="text-sm font-medium text-theme-primary mb-4">Details</h4>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
          <div>
            <p className="text-theme-tertiary">Created</p>
            <p className="text-theme-secondary">{formatDate(pipeline.created_at)}</p>
          </div>
          <div>
            <p className="text-theme-tertiary">Last Updated</p>
            <p className="text-theme-secondary">{formatDate(pipeline.updated_at)}</p>
          </div>
          {pipeline.created_by_name && (
            <div>
              <p className="text-theme-tertiary">Created By</p>
              <p className="text-theme-secondary">{pipeline.created_by_name}</p>
            </div>
          )}
          <div>
            <p className="text-theme-tertiary">Pipeline ID</p>
            <p className="text-theme-tertiary font-mono text-xs truncate">{pipeline.id}</p>
          </div>
        </div>
      </div>
    </div>
  );
};

// Steps Tab Component
const StepsTab: React.FC<{ steps: CiCdPipelineStep[] }> = ({ steps }) => {
  const [expandedSteps, setExpandedSteps] = React.useState<Set<string>>(new Set());

  const toggleStep = (stepId: string) => {
    setExpandedSteps((prev) => {
      const next = new Set(prev);
      if (next.has(stepId)) {
        next.delete(stepId);
      } else {
        next.add(stepId);
      }
      return next;
    });
  };

  const expandAll = () => {
    setExpandedSteps(new Set(steps.map((s) => s.id)));
  };

  const collapseAll = () => {
    setExpandedSteps(new Set());
  };

  if (!steps || steps.length === 0) {
    return (
      <div className="bg-theme-surface rounded-lg border border-theme p-8 text-center">
        <Layers className="w-12 h-12 text-theme-secondary mx-auto mb-4 opacity-50" />
        <h3 className="text-lg font-medium text-theme-primary mb-2">No Steps Configured</h3>
        <p className="text-theme-secondary">Add steps to define your pipeline workflow.</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Step controls */}
      <div className="flex items-center justify-between">
        <p className="text-sm text-theme-secondary">
          {steps.length} step{steps.length !== 1 ? 's' : ''} • {steps.filter((s) => s.is_active).length} active
        </p>
        <div className="flex items-center gap-2">
          <button
            onClick={expandAll}
            className="text-xs text-theme-primary hover:underline"
          >
            Expand All
          </button>
          <span className="text-theme-tertiary">|</span>
          <button
            onClick={collapseAll}
            className="text-xs text-theme-primary hover:underline"
          >
            Collapse All
          </button>
        </div>
      </div>

      {/* Steps list */}
      <div className="space-y-3">
        {steps.sort((a, b) => a.position - b.position).map((step, index) => {
          const isExpanded = expandedSteps.has(step.id);
          const hasConfig = step.configuration && Object.keys(step.configuration).length > 0;
          const hasInputs = step.inputs && Object.keys(step.inputs).length > 0;
          const hasOutputs = step.outputs && (Array.isArray(step.outputs) ? step.outputs.length > 0 : Object.keys(step.outputs).length > 0);

          return (
            <div
              key={step.id}
              className={`bg-theme-surface rounded-lg border transition-colors ${
                step.is_active ? 'border-theme' : 'border-dashed border-theme opacity-60'
              }`}
            >
              {/* Step Header */}
              <button
                onClick={() => toggleStep(step.id)}
                className="w-full p-4 text-left"
              >
                <div className="flex items-start justify-between">
                  <div className="flex items-center gap-3">
                    <div
                      className={`w-10 h-10 rounded-full flex items-center justify-center text-sm font-bold ${
                        step.is_active
                          ? 'bg-theme-interactive-primary text-white'
                          : 'bg-theme-surface-secondary text-theme-tertiary'
                      }`}
                    >
                      {index + 1}
                    </div>
                    <div>
                      <div className="flex items-center gap-2 flex-wrap">
                        <h4 className="font-medium text-theme-primary">{step.name}</h4>
                        <StepTypeBadge stepType={step.step_type} />
                        {!step.is_active && (
                          <span className="text-xs px-2 py-0.5 bg-theme-surface-secondary text-theme-tertiary rounded">
                            Disabled
                          </span>
                        )}
                        {step.continue_on_error && (
                          <span className="text-xs px-2 py-0.5 bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-300 rounded">
                            Continue on Error
                          </span>
                        )}
                      </div>
                      {step.condition && (
                        <p className="text-xs text-theme-tertiary mt-1">
                          <span className="text-theme-secondary">When:</span>{' '}
                          <code className="bg-theme-surface-secondary px-1 rounded font-mono">
                            {step.condition}
                          </code>
                        </p>
                      )}
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    {step.shared_prompt_template_name && (
                      <span className="text-xs px-2 py-0.5 bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-300 rounded flex items-center gap-1">
                        <Brain className="w-3 h-3" />
                        {step.shared_prompt_template_name}
                      </span>
                    )}
                    <div
                      className={`transform transition-transform ${isExpanded ? 'rotate-180' : ''}`}
                    >
                      <svg className="w-5 h-5 text-theme-secondary" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                      </svg>
                    </div>
                  </div>
                </div>
              </button>

              {/* Expanded Details */}
              {isExpanded && (
                <div className="px-4 pb-4 pt-0 border-t border-theme mt-0">
                  <div className="pt-4 grid grid-cols-1 lg:grid-cols-2 gap-4">
                    {/* Configuration */}
                    {hasConfig && (
                      <div className="bg-theme-surface-secondary rounded-lg p-4">
                        <h5 className="text-xs font-medium text-theme-tertiary uppercase tracking-wide mb-3">
                          Configuration
                        </h5>
                        <div className="space-y-2">
                          {Object.entries(step.configuration || {}).map(([key, value]) => (
                            <div key={key} className="flex items-start justify-between text-sm">
                              <span className="text-theme-secondary font-mono">{key}</span>
                              <span className="text-theme-primary font-medium text-right max-w-48 truncate">
                                {typeof value === 'object' ? JSON.stringify(value) : String(value)}
                              </span>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}

                    {/* Inputs */}
                    {hasInputs && (
                      <div className="bg-theme-surface-secondary rounded-lg p-4">
                        <h5 className="text-xs font-medium text-theme-tertiary uppercase tracking-wide mb-3">
                          Inputs
                        </h5>
                        <div className="space-y-2">
                          {Object.entries(step.inputs || {}).map(([key, value]) => (
                            <div key={key} className="flex items-start justify-between text-sm">
                              <span className="text-theme-secondary font-mono">{key}</span>
                              <span className="text-theme-primary font-mono text-xs text-right max-w-48 truncate">
                                {String(value)}
                              </span>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}

                    {/* Outputs */}
                    {hasOutputs && (
                      <div className="bg-theme-surface-secondary rounded-lg p-4">
                        <h5 className="text-xs font-medium text-theme-tertiary uppercase tracking-wide mb-3">
                          Outputs
                        </h5>
                        <div className="flex flex-wrap gap-2">
                          {Array.isArray(step.outputs) ? (
                            step.outputs.map((output, i) => (
                              <span
                                key={i}
                                className="text-xs px-2 py-1 bg-theme-surface rounded font-mono text-theme-primary"
                              >
                                {typeof output === 'object' && output.name
                                  ? `${output.name}: ${output.type || 'any'}`
                                  : String(output)}
                              </span>
                            ))
                          ) : (
                            Object.entries(step.outputs || {}).map(([key, value]) => (
                              <span
                                key={key}
                                className="text-xs px-2 py-1 bg-theme-surface rounded font-mono text-theme-primary"
                              >
                                {key}: {String(value)}
                              </span>
                            ))
                          )}
                        </div>
                      </div>
                    )}

                    {/* Step Info */}
                    <div className="bg-theme-surface-secondary rounded-lg p-4">
                      <h5 className="text-xs font-medium text-theme-tertiary uppercase tracking-wide mb-3">
                        Step Info
                      </h5>
                      <div className="space-y-2 text-sm">
                        <div className="flex justify-between">
                          <span className="text-theme-secondary">Position</span>
                          <span className="text-theme-primary">{step.position}</span>
                        </div>
                        <div className="flex justify-between">
                          <span className="text-theme-secondary">Type</span>
                          <span className="text-theme-primary capitalize">{step.step_type.replace('_', ' ')}</span>
                        </div>
                        <div className="flex justify-between">
                          <span className="text-theme-secondary">Status</span>
                          <span className={step.is_active ? 'text-theme-success dark:text-green-400' : 'text-theme-tertiary'}>
                            {step.is_active ? 'Active' : 'Disabled'}
                          </span>
                        </div>
                        <div className="flex justify-between">
                          <span className="text-theme-secondary">Error Handling</span>
                          <span className="text-theme-primary">
                            {step.continue_on_error ? 'Continue' : 'Stop Pipeline'}
                          </span>
                        </div>
                      </div>
                    </div>

                    {/* No config/inputs placeholder */}
                    {!hasConfig && !hasInputs && !hasOutputs && (
                      <div className="bg-theme-surface-secondary rounded-lg p-4 text-center">
                        <p className="text-sm text-theme-tertiary">No additional configuration</p>
                      </div>
                    )}
                  </div>

                  {/* Step ID */}
                  <div className="mt-4 pt-3 border-t border-theme">
                    <p className="text-xs text-theme-tertiary font-mono">
                      Step ID: {step.id}
                    </p>
                  </div>
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
};

// Runs Tab Component
const RunsTab: React.FC<{
  pipelineId: string;
  onViewRun: (runId: string) => void;
}> = ({ pipelineId, onViewRun }) => {
  const { runs, loading, cancelRun, retryRun } = usePipelineRuns({
    pipeline_id: pipelineId,
    per_page: 20,
  });

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  if (runs.length === 0) {
    return (
      <div className="bg-theme-surface rounded-lg border border-theme p-8 text-center">
        <Play className="w-12 h-12 text-theme-secondary mx-auto mb-4 opacity-50" />
        <h3 className="text-lg font-medium text-theme-primary mb-2">No Runs Yet</h3>
        <p className="text-theme-secondary">Trigger this pipeline to see run history here.</p>
      </div>
    );
  }

  return (
    <div className="space-y-3">
      {runs.map((run) => (
        <div
          key={run.id}
          className="bg-theme-surface rounded-lg border border-theme hover:border-theme-primary transition-colors"
        >
          <button
            onClick={() => onViewRun(run.id)}
            className="w-full p-4 text-left"
          >
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-4">
                <div className="flex flex-col">
                  <span className="font-medium text-theme-primary">
                    Run #{run.run_number}
                  </span>
                </div>
                <RunStatusBadge status={run.status} />
                <span className="text-xs text-theme-tertiary px-2 py-1 bg-theme-surface-secondary rounded">
                  {run.trigger_type}
                </span>
              </div>

              <div className="flex items-center gap-4 text-sm text-theme-tertiary">
                {run.branch && (
                  <span className="hidden sm:flex items-center gap-1">
                    <GitBranch className="w-3 h-3" />
                    {run.branch}
                  </span>
                )}
                {run.duration_seconds && (
                  <span className="flex items-center gap-1">
                    <Clock className="w-3 h-3" />
                    {formatDuration(run.duration_seconds)}
                  </span>
                )}
                <span>{formatTimeAgo(run.started_at)}</span>
              </div>
            </div>

            {run.current_step && run.status === 'running' && (
              <div className="mt-3 pt-3 border-t border-theme">
                <div className="flex items-center justify-between text-sm">
                  <span className="text-theme-secondary">
                    Step: {run.current_step.name}
                  </span>
                  <div className="flex items-center gap-2">
                    <div className="w-24 h-2 bg-theme-secondary/20 rounded-full overflow-hidden">
                      <div
                        className="h-full bg-theme-primary rounded-full transition-all"
                        style={{ width: `${run.progress_percentage}%` }}
                      />
                    </div>
                    <span className="text-xs text-theme-tertiary">
                      {run.progress_percentage}%
                    </span>
                  </div>
                </div>
              </div>
            )}

            {run.error_message && (
              <div className="mt-3 pt-3 border-t border-theme">
                <p className="text-sm text-theme-danger dark:text-red-400 truncate">
                  {run.error_message}
                </p>
              </div>
            )}
          </button>

          <div className="px-4 pb-4 flex items-center justify-end gap-2 border-t border-theme pt-3">
            {(run.status === 'pending' || run.status === 'running') && (
              <Button
                onClick={(e) => {
                  e.stopPropagation();
                  cancelRun(run.id);
                }}
                variant="secondary"
                size="sm"
              >
                <XCircle className="w-4 h-4 mr-1" />
                Cancel
              </Button>
            )}
            {(run.status === 'failure' || run.status === 'cancelled') && (
              <Button
                onClick={(e) => {
                  e.stopPropagation();
                  retryRun(run.id);
                }}
                variant="primary"
                size="sm"
              >
                <RefreshCw className="w-4 h-4 mr-1" />
                Retry
              </Button>
            )}
            {run.external_run_url && (
              <a
                href={run.external_run_url}
                target="_blank"
                rel="noopener noreferrer"
                onClick={(e) => e.stopPropagation()}
                className="text-theme-primary hover:underline text-sm flex items-center gap-1"
              >
                <ExternalLink className="w-3 h-3" />
                View External
              </a>
            )}
          </div>
        </div>
      ))}
    </div>
  );
};

// Main Page Component
const PipelineDetailPageContent: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { showNotification } = useNotifications();

  const { pipeline, loading, error, refresh } = usePipeline(id || null);
  const [activeTab, setActiveTab] = useState<TabType>('overview');
  const [showMenu, setShowMenu] = useState(false);
  const [triggering, setTriggering] = useState(false);

  const handleTrigger = async () => {
    if (!id) return;
    setTriggering(true);
    try {
      const run = await ciCdPipelinesApi.trigger(id);
      showNotification('Pipeline triggered successfully', 'success');
      navigate(`/app/automation/runs/${run.id}`);
    } catch (err) {
      showNotification('Failed to trigger pipeline', 'error');
    } finally {
      setTriggering(false);
    }
  };

  const handleDuplicate = async () => {
    if (!id) return;
    try {
      const duplicated = await ciCdPipelinesApi.duplicate(id);
      showNotification('Pipeline duplicated successfully', 'success');
      navigate(`/app/automation/pipelines/${duplicated.id}`);
    } catch (err) {
      showNotification('Failed to duplicate pipeline', 'error');
    }
  };

  const handleExportYaml = async () => {
    if (!id) return;
    try {
      const result = await ciCdPipelinesApi.exportYaml(id);
      const blob = new Blob([result.yaml], { type: 'text/yaml' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `${result.pipeline_name}.yml`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      showNotification('Pipeline YAML exported', 'success');
    } catch (err) {
      showNotification('Failed to export pipeline YAML', 'error');
    }
  };

  const handleDelete = async () => {
    if (!id) return;
    if (window.confirm('Are you sure you want to delete this pipeline? This action cannot be undone.')) {
      try {
        await ciCdPipelinesApi.delete(id);
        showNotification('Pipeline deleted successfully', 'success');
        navigate('/app/automation/pipelines');
      } catch (err) {
        showNotification('Failed to delete pipeline', 'error');
      }
    }
  };

  const pageActions: PageAction[] = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: refresh,
      variant: 'secondary',
      icon: RefreshCw,
    },
    {
      id: 'trigger',
      label: triggering ? 'Triggering...' : 'Trigger',
      onClick: handleTrigger,
      variant: 'primary',
      icon: Play,
      disabled: !pipeline?.is_active || triggering,
    },
  ];

  if (loading) {
    return (
      <PageContainer
        title="Pipeline Details"
        breadcrumbs={[
          { label: 'Dashboard', href: '/app' },
          { label: 'Automation', href: '/app/automation' },
          { label: 'Pipelines', href: '/app/automation/pipelines' },
          { label: 'Loading...' },
        ]}
      >
        <div className="flex items-center justify-center py-12">
          <LoadingSpinner size="lg" />
        </div>
      </PageContainer>
    );
  }

  if (error || !pipeline) {
    return (
      <PageContainer
        title="Pipeline Not Found"
        breadcrumbs={[
          { label: 'Dashboard', href: '/app' },
          { label: 'Automation', href: '/app/automation' },
          { label: 'Pipelines', href: '/app/automation/pipelines' },
          { label: 'Not Found' },
        ]}
      >
        <div className="bg-theme-surface rounded-lg border border-theme p-8 text-center">
          <AlertCircle className="w-12 h-12 text-theme-danger mx-auto mb-4" />
          <h3 className="text-lg font-medium text-theme-primary mb-2">Pipeline Not Found</h3>
          <p className="text-theme-secondary mb-4">{error || 'The requested pipeline could not be found.'}</p>
          <Button onClick={() => navigate('/app/automation/pipelines')} variant="primary">
            Back to Pipelines
          </Button>
        </div>
      </PageContainer>
    );
  }

  const tabs: Array<{ id: TabType; label: string; icon: React.ElementType }> = [
    { id: 'overview', label: 'Overview', icon: BarChart3 },
    { id: 'steps', label: `Steps (${pipeline.step_count || 0})`, icon: List },
    { id: 'runs', label: `Runs (${pipeline.run_count || 0})`, icon: Play },
  ];

  return (
    <PageContainer
      title={pipeline.name}
      description={pipeline.description || `Pipeline automation for ${pipeline.slug}`}
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'Automation', href: '/app/automation' },
        { label: 'Pipelines', href: '/app/automation/pipelines' },
        { label: pipeline.name },
      ]}
      actions={pageActions}
    >
      <div className="space-y-6">
        {/* Action Menu */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            {tabs.map((tab) => {
              const Icon = tab.icon;
              return (
                <button
                  key={tab.id}
                  onClick={() => setActiveTab(tab.id)}
                  className={`flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-colors ${
                    activeTab === tab.id
                      ? 'bg-theme-interactive-primary text-white'
                      : 'text-theme-secondary hover:bg-theme-surface-secondary'
                  }`}
                >
                  <Icon className="w-4 h-4" />
                  {tab.label}
                </button>
              );
            })}
          </div>

          <div className="relative">
            <Button
              onClick={() => setShowMenu(!showMenu)}
              variant="ghost"
              size="sm"
            >
              <MoreVertical className="w-4 h-4" />
            </Button>

            {showMenu && (
              <>
                <div
                  className="fixed inset-0 z-10"
                  onClick={() => setShowMenu(false)}
                />
                <div className="absolute right-0 top-full mt-1 w-48 bg-theme-surface rounded-lg shadow-lg border border-theme z-20">
                  <button
                    onClick={() => {
                      navigate(`/app/automation/pipelines/${id}/edit`);
                      setShowMenu(false);
                    }}
                    className="w-full px-4 py-2 text-left text-sm text-theme-primary hover:bg-theme-surface-secondary flex items-center gap-2"
                  >
                    <Edit className="w-4 h-4" />
                    Edit Pipeline
                  </button>
                  <button
                    onClick={() => {
                      handleExportYaml();
                      setShowMenu(false);
                    }}
                    className="w-full px-4 py-2 text-left text-sm text-theme-primary hover:bg-theme-surface-secondary flex items-center gap-2"
                  >
                    <FileCode className="w-4 h-4" />
                    Export YAML
                  </button>
                  <button
                    onClick={() => {
                      handleDuplicate();
                      setShowMenu(false);
                    }}
                    className="w-full px-4 py-2 text-left text-sm text-theme-primary hover:bg-theme-surface-secondary flex items-center gap-2"
                  >
                    <Copy className="w-4 h-4" />
                    Duplicate
                  </button>
                  <button
                    onClick={() => {
                      handleDelete();
                      setShowMenu(false);
                    }}
                    className="w-full px-4 py-2 text-left text-sm text-theme-danger hover:bg-red-50 dark:hover:bg-red-900/20 flex items-center gap-2"
                  >
                    <Trash2 className="w-4 h-4" />
                    Delete
                  </button>
                </div>
              </>
            )}
          </div>
        </div>

        {/* Tab Content */}
        {activeTab === 'overview' && (
          <OverviewTab
            pipeline={pipeline}
            onViewRun={(runId) => navigate(`/app/automation/runs/${runId}`)}
          />
        )}
        {activeTab === 'steps' && <StepsTab steps={pipeline.steps || []} />}
        {activeTab === 'runs' && (
          <RunsTab
            pipelineId={pipeline.id}
            onViewRun={(runId) => navigate(`/app/automation/runs/${runId}`)}
          />
        )}
      </div>
    </PageContainer>
  );
};

export function PipelineDetailPage() {
  return (
    <PageErrorBoundary>
      <PipelineDetailPageContent />
    </PageErrorBoundary>
  );
}

export default PipelineDetailPage;
