import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import {
  Play, Pause, RefreshCw, Edit, Trash2, Copy, FileCode,
  Clock, CheckCircle, XCircle, AlertCircle, GitBranch, Calendar,
  Zap, Brain, MoreVertical, ExternalLink, Layers, Workflow,
  List, BarChart3, Plus, Settings, ChevronUp, ChevronDown, GripVertical,
  Save, X, Terminal, MessageSquare, GitPullRequest, Upload, Rocket
} from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { PageErrorBoundary } from '@/shared/components/error/ErrorBoundary';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { usePipeline } from '@/features/cicd/hooks/usePipelines';
import { usePipelineRuns } from '@/features/cicd/hooks/usePipelineRuns';
import { ciCdPipelinesApi } from '@/services/ciCdApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { StepApprovalSettings } from '@/features/cicd/components/StepApprovalSettings';
import type { CiCdPipeline, CiCdPipelineRunStatus, CiCdPipelineStep, CiCdStepType, CiCdPipelineStepFormData, StepApprovalSettings as StepApprovalSettingsType } from '@/types/cicd';

type TabType = 'overview' | 'runs' | 'steps';

// Step type configurations
const STEP_TYPES: Array<{
  type: CiCdStepType;
  label: string;
  description: string;
  icon: React.ElementType;
  category: 'git' | 'ai' | 'action' | 'deploy';
}> = [
  { type: 'checkout', label: 'Checkout', description: 'Clone repository code', icon: GitBranch, category: 'git' },
  { type: 'create_branch', label: 'Create Branch', description: 'Create a new git branch', icon: GitBranch, category: 'git' },
  { type: 'create_pr', label: 'Create PR', description: 'Create a pull request', icon: GitPullRequest, category: 'git' },
  { type: 'claude_execute', label: 'Claude Execute', description: 'AI-powered task execution', icon: Brain, category: 'ai' },
  { type: 'ai_workflow', label: 'AI Workflow', description: 'Execute an AI workflow', icon: Workflow, category: 'ai' },
  { type: 'run_tests', label: 'Run Tests', description: 'Execute test suites', icon: Terminal, category: 'action' },
  { type: 'post_comment', label: 'Post Comment', description: 'Comment on PR or issue', icon: MessageSquare, category: 'action' },
  { type: 'upload_artifact', label: 'Upload Artifact', description: 'Store build outputs', icon: Upload, category: 'action' },
  { type: 'download_artifact', label: 'Download Artifact', description: 'Retrieve build outputs', icon: Upload, category: 'action' },
  { type: 'deploy', label: 'Deploy', description: 'Deploy to environment', icon: Rocket, category: 'deploy' },
  { type: 'notify', label: 'Notify', description: 'Send notifications', icon: MessageSquare, category: 'action' },
  { type: 'custom', label: 'Custom', description: 'Custom shell command', icon: Settings, category: 'action' },
];

// Default approval settings
const DEFAULT_APPROVAL_SETTINGS: StepApprovalSettingsType = {
  timeout_hours: 24,
  require_comment: false,
  notification_recipients: [],
};

// Trigger Modal Component
interface TriggerModalProps {
  isOpen: boolean;
  onClose: () => void;
  onTrigger: (context: Record<string, unknown>) => Promise<void>;
  pipeline: CiCdPipeline;
  triggering: boolean;
}

const TriggerModal: React.FC<TriggerModalProps> = ({ isOpen, onClose, onTrigger, pipeline, triggering }) => {
  const [inputMessage, setInputMessage] = useState('');
  const [branch, setBranch] = useState('');
  const [additionalContext, setAdditionalContext] = useState('');
  const [contextError, setContextError] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setContextError(null);

    const context: Record<string, unknown> = {};

    if (inputMessage.trim()) {
      context.message = inputMessage.trim();
    }

    if (branch.trim()) {
      context.branch = branch.trim();
    }

    if (additionalContext.trim()) {
      try {
        const parsed = JSON.parse(additionalContext);
        Object.assign(context, parsed);
      } catch {
        setContextError('Invalid JSON format');
        return;
      }
    }

    await onTrigger(context);
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      <div className="absolute inset-0 bg-black/50" onClick={onClose} />
      <div className="relative bg-theme-surface border border-theme rounded-lg shadow-xl w-full max-w-lg mx-4">
        <div className="flex items-center justify-between p-4 border-b border-theme">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-theme-success/10 rounded-lg">
              <Play className="w-5 h-5 text-theme-success" />
            </div>
            <div>
              <h2 className="text-lg font-semibold text-theme-primary">Trigger Pipeline</h2>
              <p className="text-sm text-theme-secondary">{pipeline.name}</p>
            </div>
          </div>
          <button onClick={onClose} className="p-2 hover:bg-theme-bg-subtle rounded-lg text-theme-secondary">
            <X className="w-5 h-5" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-4 space-y-4">
          {/* Input Message */}
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Input Message
            </label>
            <textarea
              value={inputMessage}
              onChange={(e) => setInputMessage(e.target.value)}
              placeholder="Enter a message or instructions for this pipeline run..."
              rows={3}
              className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary resize-none"
            />
            <p className="mt-1 text-xs text-theme-tertiary">
              This message will be available to pipeline steps as context.message
            </p>
          </div>

          {/* Branch */}
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Branch (optional)
            </label>
            <input
              type="text"
              value={branch}
              onChange={(e) => setBranch(e.target.value)}
              placeholder="master"
              className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
            />
          </div>

          {/* Additional Context */}
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Additional Context (JSON)
            </label>
            <textarea
              value={additionalContext}
              onChange={(e) => {
                setAdditionalContext(e.target.value);
                setContextError(null);
              }}
              placeholder='{"pr_number": 123, "environment": "staging"}'
              rows={3}
              className={`w-full px-3 py-2 bg-theme-surface border rounded-lg text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary resize-none font-mono text-sm ${contextError ? 'border-theme-danger' : 'border-theme'}`}
            />
            {contextError && (
              <p className="mt-1 text-xs text-theme-danger">{contextError}</p>
            )}
          </div>

          {/* Actions */}
          <div className="flex items-center justify-end gap-3 pt-4 border-t border-theme">
            <Button type="button" onClick={onClose} variant="secondary" disabled={triggering}>
              Cancel
            </Button>
            <Button type="submit" variant="primary" disabled={triggering}>
              {triggering ? (
                <>
                  <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                  Triggering...
                </>
              ) : (
                <>
                  <Play className="w-4 h-4 mr-2" />
                  Trigger Pipeline
                </>
              )}
            </Button>
          </div>
        </form>
      </div>
    </div>
  );
};

// Step validation helper
interface StepValidationResult {
  isValid: boolean;
  message: string;
}

const validateStepConfiguration = (step: CiCdPipelineStepFormData): StepValidationResult => {
  const config = step.configuration as Record<string, unknown>;
  switch (step.step_type) {
    case 'claude_execute':
      if (!config?.task || (config.task as string).trim() === '') {
        return { isValid: false, message: 'Task description is required' };
      }
      break;
    case 'custom':
      if (!config?.command || (config.command as string).trim() === '') {
        return { isValid: false, message: 'Command is required' };
      }
      break;
    case 'deploy':
      if (!config?.environment) {
        return { isValid: false, message: 'Environment is required' };
      }
      break;
    case 'post_comment':
      if (!config?.template || (config.template as string).trim() === '') {
        return { isValid: false, message: 'Comment template is required' };
      }
      break;
    case 'create_branch':
      if (!config?.branch_name || (config.branch_name as string).trim() === '') {
        return { isValid: false, message: 'Branch name is required' };
      }
      break;
  }
  return { isValid: true, message: '' };
};

// Status Badge Component
const StatusBadge: React.FC<{ isActive: boolean }> = ({ isActive }) => (
  <span
    className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-medium ${
      isActive
        ? 'bg-theme-success/10 text-theme-success dark:bg-theme-success/20'
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
    pending: { bg: 'bg-theme-warning/10 dark:bg-theme-warning/20', text: 'text-theme-warning', icon: Clock, label: 'Pending' },
    queued: { bg: 'bg-theme-warning/10 dark:bg-theme-warning/20', text: 'text-theme-warning', icon: Clock, label: 'Queued' },
    running: { bg: 'bg-theme-info/10 dark:bg-theme-info/20', text: 'text-theme-info', icon: RefreshCw, label: 'Running' },
    success: { bg: 'bg-theme-success/10 dark:bg-theme-success/20', text: 'text-theme-success', icon: CheckCircle, label: 'Success' },
    failed: { bg: 'bg-theme-danger/10 dark:bg-theme-danger/20', text: 'text-theme-danger', icon: XCircle, label: 'Failed' },
    failure: { bg: 'bg-theme-danger/10 dark:bg-theme-danger/20', text: 'text-theme-danger', icon: XCircle, label: 'Failed' },
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
    checkout: { bg: 'bg-theme-info/10 dark:bg-theme-info/20', text: 'text-theme-info', label: 'Checkout' },
    claude_execute: { bg: 'bg-theme-accent/10 dark:bg-theme-accent/20', text: 'text-theme-accent', label: 'Claude Execute' },
    ai_workflow: { bg: 'bg-theme-accent/10 dark:bg-theme-accent/20', text: 'text-theme-accent', label: 'AI Workflow' },
    post_comment: { bg: 'bg-theme-success/10 dark:bg-theme-success/20', text: 'text-theme-success', label: 'Post Comment' },
    create_pr: { bg: 'bg-theme-info/10 dark:bg-theme-info/20', text: 'text-theme-info', label: 'Create PR' },
    create_branch: { bg: 'bg-theme-info/10 dark:bg-theme-info/20', text: 'text-theme-info', label: 'Create Branch' },
    deploy: { bg: 'bg-theme-warning/10 dark:bg-theme-warning/20', text: 'text-theme-warning', label: 'Deploy' },
    run_tests: { bg: 'bg-theme-info/10 dark:bg-theme-info/20', text: 'text-theme-info', label: 'Run Tests' },
    upload_artifact: { bg: 'bg-theme-success/10 dark:bg-theme-success/20', text: 'text-theme-success', label: 'Upload Artifact' },
    download_artifact: { bg: 'bg-theme-success/10 dark:bg-theme-success/20', text: 'text-theme-success', label: 'Download Artifact' },
    notify: { bg: 'bg-theme-accent/10 dark:bg-theme-accent/20', text: 'text-theme-accent', label: 'Notify' },
    custom: { bg: 'bg-theme-surface-secondary', text: 'text-theme-secondary', label: 'Custom' },
  };
  const config = configs[stepType] || { bg: 'bg-theme-surface dark:bg-theme-background/30', text: 'text-theme-secondary', label: stepType };

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
const OverviewTab: React.FC<{ pipeline: CiCdPipeline; onViewRun: (runId: string) => void; onPipelineUpdated: () => void }> = ({ pipeline, onViewRun, onPipelineUpdated }) => {
  const { showNotification } = useNotifications();
  const [isEditing, setIsEditing] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [editedPipeline, setEditedPipeline] = useState({
    name: pipeline.name,
    description: pipeline.description || '',
    pipeline_type: pipeline.pipeline_type || 'standard',
    timeout_minutes: pipeline.timeout_minutes,
    allow_concurrent: pipeline.allow_concurrent,
    is_active: pipeline.is_active,
  });

  const hasAiSteps = pipeline.steps?.some(step => step.step_type === 'claude_execute');

  // Get step type distribution
  const stepTypeCount = (pipeline.steps || []).reduce((acc, step) => {
    acc[step.step_type] = (acc[step.step_type] || 0) + 1;
    return acc;
  }, {} as Record<string, number>);

  const handleSave = async () => {
    setIsSaving(true);
    try {
      await ciCdPipelinesApi.update(pipeline.id, editedPipeline);
      showNotification('Pipeline updated successfully', 'success');
      setIsEditing(false);
      onPipelineUpdated();
    } catch (err) {
      showNotification('Failed to update pipeline', 'error');
    } finally {
      setIsSaving(false);
    }
  };

  const handleCancel = () => {
    setEditedPipeline({
      name: pipeline.name,
      description: pipeline.description || '',
      pipeline_type: pipeline.pipeline_type || 'standard',
      timeout_minutes: pipeline.timeout_minutes,
      allow_concurrent: pipeline.allow_concurrent,
      is_active: pipeline.is_active,
    });
    setIsEditing(false);
  };

  return (
    <div className="space-y-6">
      {/* Pipeline Info Card */}
      <div className="bg-theme-surface rounded-lg border border-theme p-6">
        {isEditing ? (
          <>
            {/* Edit Mode Header */}
            <div className="flex items-center justify-between mb-4 pb-4 border-b border-theme">
              <div className="flex items-center gap-2">
                <Edit className="w-5 h-5 text-theme-info" />
                <span className="font-medium text-theme-primary">Edit Pipeline Settings</span>
              </div>
              <div className="flex items-center gap-2">
                <Button onClick={handleCancel} variant="secondary" size="sm" disabled={isSaving}>
                  <X className="w-4 h-4 mr-1" />
                  Cancel
                </Button>
                <Button onClick={handleSave} variant="primary" size="sm" disabled={isSaving}>
                  {isSaving ? (
                    <>
                      <RefreshCw className="w-4 h-4 mr-1 animate-spin" />
                      Saving...
                    </>
                  ) : (
                    <>
                      <Save className="w-4 h-4 mr-1" />
                      Save
                    </>
                  )}
                </Button>
              </div>
            </div>

            {/* Edit Form */}
            <div className="space-y-4">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-1">Name</label>
                  <input
                    type="text"
                    value={editedPipeline.name}
                    onChange={(e) => setEditedPipeline({ ...editedPipeline, name: e.target.value })}
                    className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-1">Type</label>
                  <select
                    value={editedPipeline.pipeline_type}
                    onChange={(e) => setEditedPipeline({ ...editedPipeline, pipeline_type: e.target.value })}
                    className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                  >
                    <option value="standard">Standard</option>
                    <option value="ci">CI</option>
                    <option value="cd">CD</option>
                    <option value="review">Review</option>
                    <option value="deployment">Deployment</option>
                  </select>
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium text-theme-primary mb-1">Description</label>
                <textarea
                  value={editedPipeline.description}
                  onChange={(e) => setEditedPipeline({ ...editedPipeline, description: e.target.value })}
                  rows={3}
                  placeholder="Describe what this pipeline does..."
                  className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary resize-none"
                />
              </div>

              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-1">Timeout (minutes)</label>
                  <input
                    type="number"
                    value={editedPipeline.timeout_minutes}
                    onChange={(e) => setEditedPipeline({ ...editedPipeline, timeout_minutes: parseInt(e.target.value) || 60 })}
                    min={1}
                    max={1440}
                    className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                  />
                </div>
                <div className="flex items-center gap-3 pt-6">
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input
                      type="checkbox"
                      checked={editedPipeline.allow_concurrent}
                      onChange={(e) => setEditedPipeline({ ...editedPipeline, allow_concurrent: e.target.checked })}
                      className="sr-only peer"
                    />
                    <div className="w-11 h-6 bg-theme-secondary/30 peer-focus:outline-none peer-focus:ring-2 peer-focus:ring-theme-primary rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-theme-primary after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-theme-surface after:border-theme after:border after:rounded-full after:h-5 after:w-5 after:transition-all after:shadow-sm peer-checked:bg-theme-primary peer-checked:after:bg-theme-surface"></div>
                  </label>
                  <span className="text-sm text-theme-primary">Allow Concurrent Runs</span>
                </div>
                <div className="flex items-center gap-3 pt-6">
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input
                      type="checkbox"
                      checked={editedPipeline.is_active}
                      onChange={(e) => setEditedPipeline({ ...editedPipeline, is_active: e.target.checked })}
                      className="sr-only peer"
                    />
                    <div className="w-11 h-6 bg-theme-secondary/30 peer-focus:outline-none peer-focus:ring-2 peer-focus:ring-theme-primary rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-theme-primary after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-theme-surface after:border-theme after:border after:rounded-full after:h-5 after:w-5 after:transition-all after:shadow-sm peer-checked:bg-theme-primary peer-checked:after:bg-theme-surface"></div>
                  </label>
                  <span className="text-sm text-theme-primary">Active</span>
                </div>
              </div>
            </div>
          </>
        ) : (
          <>
            {/* View Mode */}
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
              <div className="flex items-center gap-2">
                <Button onClick={() => setIsEditing(true)} variant="secondary" size="sm">
                  <Edit className="w-4 h-4 mr-1" />
                  Edit
                </Button>
                <StatusBadge isActive={pipeline.is_active} />
              </div>
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
          </>
        )}
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
              ? 'text-theme-success'
              : pipeline.success_rate !== null && pipeline.success_rate >= 50
                ? 'text-theme-warning'
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
        <div className="bg-theme-danger/5 dark:bg-theme-danger/10 border border-theme-danger/20 dark:border-theme-danger/30 rounded-lg p-4">
          <div className="flex items-start gap-3">
            <div className="p-2 bg-theme-danger/10 dark:bg-theme-danger/20 rounded-lg shrink-0">
              <AlertCircle className="w-5 h-5 text-theme-danger" />
            </div>
            <div className="flex-1 min-w-0">
              <h4 className="text-sm font-medium text-theme-danger mb-1">
                Last Run Failed
              </h4>
              <p className="text-sm text-theme-danger/80 mb-3">
                {pipeline.last_run.error_message || 'The pipeline run encountered an error.'}
              </p>
              <button
                onClick={() => onViewRun(pipeline.last_run!.id)}
                className="inline-flex items-center gap-1 text-sm font-medium text-theme-danger hover:underline"
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

// Steps Tab Component with Inline Editing
const StepsTab: React.FC<{
  steps: CiCdPipelineStep[];
  pipelineId: string;
  onStepsUpdated: () => void;
}> = ({ steps, pipelineId, onStepsUpdated }) => {
  const { showNotification } = useNotifications();
  const [expandedSteps, setExpandedSteps] = React.useState<Set<string>>(new Set());
  const [isEditMode, setIsEditMode] = useState(false);
  const [editedSteps, setEditedSteps] = useState<CiCdPipelineStepFormData[]>([]);
  const [isSaving, setIsSaving] = useState(false);
  const [showAddStep, setShowAddStep] = useState(false);
  const [expandedEditStep, setExpandedEditStep] = useState<number | null>(null);

  // Initialize edited steps when entering edit mode
  useEffect(() => {
    if (isEditMode) {
      setEditedSteps(
        steps.map((s) => ({
          id: s.id,
          name: s.name,
          step_type: s.step_type as CiCdStepType,
          position: s.position,
          configuration: s.configuration || {},
          inputs: s.inputs || {},
          outputs: Array.isArray(s.outputs) ? {} : (s.outputs || {}),
          condition: s.condition || undefined,
          is_active: s.is_active,
          continue_on_error: s.continue_on_error,
          requires_approval: s.requires_approval,
          approval_settings: s.approval_settings || DEFAULT_APPROVAL_SETTINGS,
          shared_prompt_template_id: s.shared_prompt_template_id || undefined,
        }))
      );
    }
  }, [isEditMode, steps]);

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

  const updateStep = (index: number, updates: Partial<CiCdPipelineStepFormData>) => {
    const newSteps = [...editedSteps];
    newSteps[index] = { ...newSteps[index], ...updates };
    setEditedSteps(newSteps);
  };

  const removeStep = (index: number) => {
    const newSteps = editedSteps.filter((_, i) => i !== index).map((step, i) => ({
      ...step,
      position: i + 1,
    }));
    setEditedSteps(newSteps);
    if (expandedEditStep === index) setExpandedEditStep(null);
  };

  const moveStep = (index: number, direction: 'up' | 'down') => {
    if (direction === 'up' && index === 0) return;
    if (direction === 'down' && index === editedSteps.length - 1) return;

    const newSteps = [...editedSteps];
    const newIndex = direction === 'up' ? index - 1 : index + 1;
    [newSteps[index], newSteps[newIndex]] = [newSteps[newIndex], newSteps[index]];
    newSteps.forEach((step, i) => {
      step.position = i + 1;
    });
    setEditedSteps(newSteps);
    setExpandedEditStep(newIndex);
  };

  const addStep = (stepType: CiCdStepType) => {
    const stepConfig = STEP_TYPES.find((s) => s.type === stepType);
    const newStep: CiCdPipelineStepFormData = {
      name: stepConfig?.label || stepType,
      step_type: stepType,
      position: editedSteps.length + 1,
      configuration: {},
      inputs: {},
      is_active: true,
      continue_on_error: false,
    };
    setEditedSteps([...editedSteps, newStep]);
    setShowAddStep(false);
    setExpandedEditStep(editedSteps.length);
  };

  const handleSave = async () => {
    setIsSaving(true);
    try {
      await ciCdPipelinesApi.update(pipelineId, { steps: editedSteps });
      showNotification('Steps updated successfully', 'success');
      setIsEditMode(false);
      onStepsUpdated();
    } catch (err) {
      showNotification('Failed to update steps', 'error');
    } finally {
      setIsSaving(false);
    }
  };

  const handleCancel = () => {
    setIsEditMode(false);
    setEditedSteps([]);
    setExpandedEditStep(null);
  };

  const getStepIcon = (stepType: string) => {
    const config = STEP_TYPES.find((s) => s.type === stepType);
    return config?.icon || Settings;
  };

  // Edit Mode View (check first so Add First Step works)
  if (isEditMode) {
    return (
      <div className="space-y-4">
        {/* Edit Mode Header */}
        <div className="flex items-center justify-between bg-theme-info/10 border border-theme-info/30 rounded-lg p-4">
          <div className="flex items-center gap-2">
            <Edit className="w-5 h-5 text-theme-info" />
            <span className="font-medium text-theme-primary">Editing Steps</span>
            <span className="text-sm text-theme-secondary">({editedSteps.length} steps)</span>
          </div>
          <div className="flex items-center gap-2">
            <Button onClick={handleCancel} variant="secondary" size="sm" disabled={isSaving}>
              <X className="w-4 h-4 mr-1" />
              Cancel
            </Button>
            <Button onClick={handleSave} variant="primary" size="sm" disabled={isSaving}>
              {isSaving ? (
                <>
                  <RefreshCw className="w-4 h-4 mr-1 animate-spin" />
                  Saving...
                </>
              ) : (
                <>
                  <Save className="w-4 h-4 mr-1" />
                  Save Changes
                </>
              )}
            </Button>
          </div>
        </div>

        {/* Editable Steps List */}
        <div className="space-y-3">
          {editedSteps.map((step, index) => {
            const StepIcon = getStepIcon(step.step_type);
            const isExpanded = expandedEditStep === index;
            const stepValidation = validateStepConfiguration(step);

            return (
              <div key={step.id || index} className={`bg-theme-surface rounded-lg border overflow-hidden ${!stepValidation.isValid ? 'border-theme-warning' : 'border-theme'}`}>
                {/* Step Header */}
                <div className="flex items-center gap-3 p-4">
                  <div className="flex flex-col gap-1">
                    <button
                      onClick={() => moveStep(index, 'up')}
                      disabled={index === 0}
                      className="p-0.5 text-theme-tertiary hover:text-theme-primary disabled:opacity-30"
                    >
                      <ChevronUp className="w-4 h-4" />
                    </button>
                    <button
                      onClick={() => moveStep(index, 'down')}
                      disabled={index === editedSteps.length - 1}
                      className="p-0.5 text-theme-tertiary hover:text-theme-primary disabled:opacity-30"
                    >
                      <ChevronDown className="w-4 h-4" />
                    </button>
                  </div>
                  <GripVertical className="w-4 h-4 text-theme-tertiary" />
                  <div className="w-8 h-8 rounded-full bg-theme-surface-secondary flex items-center justify-center">
                    <span className="text-sm font-medium text-theme-secondary">{index + 1}</span>
                  </div>
                  <div className="p-2 bg-theme-surface-secondary rounded-lg">
                    <StepIcon className="w-5 h-5 text-theme-primary" />
                  </div>
                  <div className="flex-1">
                    <div className="flex items-center gap-2">
                      <h4 className="font-medium text-theme-primary">{step.name}</h4>
                      {!stepValidation.isValid && (
                        <span className="inline-flex items-center gap-1 px-1.5 py-0.5 text-[10px] font-medium bg-theme-warning/10 text-theme-warning rounded" title={stepValidation.message}>
                          <AlertCircle className="w-3 h-3" />
                          Incomplete
                        </span>
                      )}
                    </div>
                    <p className="text-xs text-theme-tertiary">{step.step_type}</p>
                  </div>
                  <div className="flex items-center gap-2">
                    <button
                      onClick={() => setExpandedEditStep(isExpanded ? null : index)}
                      className="p-2 hover:bg-theme-surface-secondary rounded-lg text-theme-secondary hover:text-theme-primary"
                    >
                      <Settings className="w-4 h-4" />
                    </button>
                    <button
                      onClick={() => removeStep(index)}
                      className="p-2 text-theme-secondary hover:text-theme-danger hover:bg-theme-danger/10 rounded-lg"
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                </div>

                {/* Step Configuration (Expanded) */}
                {isExpanded && (
                  <div className="p-4 border-t border-theme bg-theme-surface-secondary space-y-4">
                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-1">Step Name</label>
                      <input
                        type="text"
                        value={step.name}
                        onChange={(e) => updateStep(index, { name: e.target.value })}
                        className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                      />
                    </div>

                    {/* Step-specific configuration */}
                    {step.step_type === 'custom' && (
                      <div>
                        <label className="block text-sm font-medium text-theme-primary mb-1">Command</label>
                        <input
                          type="text"
                          value={(step.configuration as Record<string, string>)?.command || ''}
                          onChange={(e) => updateStep(index, { configuration: { ...step.configuration, command: e.target.value } })}
                          placeholder="npm run build"
                          className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm font-mono text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                        />
                      </div>
                    )}

                    {step.step_type === 'claude_execute' && (
                      <div>
                        <label className="block text-sm font-medium text-theme-primary mb-1">Task Description</label>
                        <textarea
                          value={(step.configuration as Record<string, string>)?.task || ''}
                          onChange={(e) => updateStep(index, { configuration: { ...step.configuration, task: e.target.value } })}
                          placeholder="Describe what Claude should do..."
                          rows={3}
                          className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                        />
                      </div>
                    )}

                    {step.step_type === 'ai_workflow' && (
                      <div className="space-y-4">
                        <div>
                          <label className="block text-sm font-medium text-theme-primary mb-1">Workflow ID</label>
                          <input
                            type="text"
                            value={(step.configuration as Record<string, string>)?.workflow_id || ''}
                            onChange={(e) => updateStep(index, { configuration: { ...step.configuration, workflow_id: e.target.value } })}
                            placeholder="Enter AI Workflow ID or select from list"
                            className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                          />
                          <p className="text-xs text-theme-tertiary mt-1">The ID of the AI workflow to execute</p>
                        </div>
                        <div>
                          <label className="block text-sm font-medium text-theme-primary mb-1">Input Variables (JSON)</label>
                          <textarea
                            value={(step.configuration as Record<string, string>)?.input_variables || ''}
                            onChange={(e) => updateStep(index, { configuration: { ...step.configuration, input_variables: e.target.value } })}
                            placeholder='{"key": "value", "branch": "${{ trigger.branch }}"}'
                            rows={3}
                            className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm font-mono text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                          />
                          <p className="text-xs text-theme-tertiary mt-1">JSON object with variables to pass to the workflow</p>
                        </div>
                        <div className="grid grid-cols-2 gap-4">
                          <div>
                            <label className="block text-sm font-medium text-theme-primary mb-1">Timeout (minutes)</label>
                            <input
                              type="number"
                              value={(step.configuration as Record<string, number>)?.timeout_minutes || 30}
                              onChange={(e) => updateStep(index, { configuration: { ...step.configuration, timeout_minutes: parseInt(e.target.value) } })}
                              min={1}
                              max={120}
                              className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                            />
                          </div>
                          <div className="flex items-end pb-2">
                            <label className="inline-flex items-center gap-2 cursor-pointer">
                              <input
                                type="checkbox"
                                checked={(step.configuration as Record<string, boolean>)?.wait_for_completion !== false}
                                onChange={(e) => updateStep(index, { configuration: { ...step.configuration, wait_for_completion: e.target.checked } })}
                                className="w-4 h-4 rounded border-theme text-theme-primary"
                              />
                              <span className="text-sm text-theme-secondary">Wait for completion</span>
                            </label>
                          </div>
                        </div>
                      </div>
                    )}

                    {step.step_type === 'checkout' && (
                      <div className="grid grid-cols-2 gap-4">
                        <div>
                          <label className="block text-sm font-medium text-theme-primary mb-1">Branch</label>
                          <input
                            type="text"
                            value={(step.configuration as Record<string, string>)?.branch || ''}
                            onChange={(e) => updateStep(index, { configuration: { ...step.configuration, branch: e.target.value } })}
                            placeholder="main (default: trigger branch)"
                            className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                          />
                        </div>
                        <div>
                          <label className="block text-sm font-medium text-theme-primary mb-1">Depth</label>
                          <input
                            type="number"
                            value={(step.configuration as Record<string, number>)?.depth || 1}
                            onChange={(e) => updateStep(index, { configuration: { ...step.configuration, depth: parseInt(e.target.value) } })}
                            min={0}
                            className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                          />
                        </div>
                      </div>
                    )}

                    {step.step_type === 'post_comment' && (
                      <div>
                        <label className="block text-sm font-medium text-theme-primary mb-1">Comment Template</label>
                        <textarea
                          value={(step.configuration as Record<string, string>)?.template || ''}
                          onChange={(e) => updateStep(index, { configuration: { ...step.configuration, template: e.target.value } })}
                          placeholder="Comment content (supports variables like ${{outputs.step_name.result}})"
                          rows={3}
                          className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                        />
                      </div>
                    )}

                    {step.step_type === 'deploy' && (
                      <div className="grid grid-cols-2 gap-4">
                        <div>
                          <label className="block text-sm font-medium text-theme-primary mb-1">Environment</label>
                          <select
                            value={(step.configuration as Record<string, string>)?.environment || 'staging'}
                            onChange={(e) => updateStep(index, { configuration: { ...step.configuration, environment: e.target.value } })}
                            className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                          >
                            <option value="development">Development</option>
                            <option value="staging">Staging</option>
                            <option value="production">Production</option>
                          </select>
                        </div>
                        <div>
                          <label className="block text-sm font-medium text-theme-primary mb-1">Strategy</label>
                          <select
                            value={(step.configuration as Record<string, string>)?.strategy || 'rolling'}
                            onChange={(e) => updateStep(index, { configuration: { ...step.configuration, strategy: e.target.value } })}
                            className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                          >
                            <option value="rolling">Rolling</option>
                            <option value="blue_green">Blue/Green</option>
                            <option value="canary">Canary</option>
                          </select>
                        </div>
                      </div>
                    )}

                    {step.step_type === 'create_branch' && (
                      <div>
                        <label className="block text-sm font-medium text-theme-primary mb-1">Branch Name</label>
                        <input
                          type="text"
                          value={(step.configuration as Record<string, string>)?.branch_name || ''}
                          onChange={(e) => updateStep(index, { configuration: { ...step.configuration, branch_name: e.target.value } })}
                          placeholder="feature/my-branch"
                          className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm font-mono text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                        />
                      </div>
                    )}

                    {step.step_type === 'run_tests' && (
                      <div className="grid grid-cols-2 gap-4">
                        <div>
                          <label className="block text-sm font-medium text-theme-primary mb-1">Test Command</label>
                          <input
                            type="text"
                            value={(step.configuration as Record<string, string>)?.command || ''}
                            onChange={(e) => updateStep(index, { configuration: { ...step.configuration, command: e.target.value } })}
                            placeholder="npm test"
                            className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm font-mono text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                          />
                        </div>
                        <div>
                          <label className="block text-sm font-medium text-theme-primary mb-1">Coverage Threshold</label>
                          <input
                            type="number"
                            value={(step.configuration as Record<string, number>)?.coverage_threshold || 80}
                            onChange={(e) => updateStep(index, { configuration: { ...step.configuration, coverage_threshold: parseInt(e.target.value) } })}
                            min={0}
                            max={100}
                            className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                          />
                        </div>
                      </div>
                    )}

                    {step.step_type === 'notify' && (() => {
                      const channels = (step.configuration as Record<string, string[]>)?.channels || [];
                      const hasEmail = channels.includes('email');
                      const hasSlack = channels.includes('slack');
                      const hasWebhook = channels.includes('webhook');

                      return (
                        <div className="space-y-4">
                          {/* Channel Selection */}
                          <div>
                            <label className="block text-sm font-medium text-theme-primary mb-1">Notification Channels</label>
                            <div className="flex flex-wrap gap-4 mt-2">
                              {[
                                { value: 'email', label: 'Email' },
                                { value: 'slack', label: 'Slack' },
                                { value: 'webhook', label: 'Webhook' },
                              ].map((channel) => {
                                const isChecked = channels.includes(channel.value);
                                return (
                                  <label key={channel.value} className="inline-flex items-center gap-2 cursor-pointer">
                                    <input
                                      type="checkbox"
                                      checked={isChecked}
                                      onChange={(e) => {
                                        const currentChannels = [...channels];
                                        if (e.target.checked) {
                                          if (!currentChannels.includes(channel.value)) {
                                            currentChannels.push(channel.value);
                                          }
                                        } else {
                                          const idx = currentChannels.indexOf(channel.value);
                                          if (idx > -1) {
                                            currentChannels.splice(idx, 1);
                                          }
                                        }
                                        updateStep(index, {
                                          configuration: { ...step.configuration, channels: currentChannels }
                                        });
                                      }}
                                      className="w-4 h-4 rounded border-theme"
                                    />
                                    <span className="text-sm text-theme-secondary">{channel.label}</span>
                                  </label>
                                );
                              })}
                            </div>
                            <p className="text-xs text-theme-tertiary mt-1">Select one or more notification channels</p>
                          </div>

                          {/* Email Configuration */}
                          {hasEmail && (
                            <div className="p-3 bg-theme-bg rounded-lg border border-theme space-y-3">
                              <h5 className="text-sm font-medium text-theme-primary flex items-center gap-2">
                                <span className="w-2 h-2 bg-theme-info rounded-full"></span>
                                Email Settings
                              </h5>
                              <div>
                                <label className="block text-xs font-medium text-theme-secondary mb-1">Recipients</label>
                                <input
                                  type="text"
                                  value={(step.configuration as Record<string, string>)?.email_recipients || ''}
                                  onChange={(e) => updateStep(index, { configuration: { ...step.configuration, email_recipients: e.target.value } })}
                                  placeholder="user@example.com, team@example.com"
                                  className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                                />
                              </div>
                              <div>
                                <label className="block text-xs font-medium text-theme-secondary mb-1">Subject</label>
                                <input
                                  type="text"
                                  value={(step.configuration as Record<string, string>)?.email_subject || ''}
                                  onChange={(e) => updateStep(index, { configuration: { ...step.configuration, email_subject: e.target.value } })}
                                  placeholder="Pipeline {{pipeline.name}} - {{status}}"
                                  className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                                />
                              </div>
                            </div>
                          )}

                          {/* Slack Configuration */}
                          {hasSlack && (
                            <div className="p-3 bg-theme-bg rounded-lg border border-theme space-y-3">
                              <h5 className="text-sm font-medium text-theme-primary flex items-center gap-2">
                                <span className="w-2 h-2 bg-theme-interactive-primary rounded-full"></span>
                                Slack Settings
                              </h5>
                              <div>
                                <label className="block text-xs font-medium text-theme-secondary mb-1">Webhook URL</label>
                                <input
                                  type="text"
                                  value={(step.configuration as Record<string, string>)?.slack_webhook_url || ''}
                                  onChange={(e) => updateStep(index, { configuration: { ...step.configuration, slack_webhook_url: e.target.value } })}
                                  placeholder="https://hooks.slack.com/services/..."
                                  className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                                />
                              </div>
                              <div>
                                <label className="block text-xs font-medium text-theme-secondary mb-1">Channel (optional)</label>
                                <input
                                  type="text"
                                  value={(step.configuration as Record<string, string>)?.slack_channel || ''}
                                  onChange={(e) => updateStep(index, { configuration: { ...step.configuration, slack_channel: e.target.value } })}
                                  placeholder="#deployments"
                                  className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                                />
                              </div>
                            </div>
                          )}

                          {/* Webhook Configuration */}
                          {hasWebhook && (
                            <div className="p-3 bg-theme-bg rounded-lg border border-theme space-y-3">
                              <h5 className="text-sm font-medium text-theme-primary flex items-center gap-2">
                                <span className="w-2 h-2 bg-theme-success rounded-full"></span>
                                Webhook Settings
                              </h5>
                              <div>
                                <label className="block text-xs font-medium text-theme-secondary mb-1">Webhook URL</label>
                                <input
                                  type="text"
                                  value={(step.configuration as Record<string, string>)?.webhook_url || ''}
                                  onChange={(e) => updateStep(index, { configuration: { ...step.configuration, webhook_url: e.target.value } })}
                                  placeholder="https://api.example.com/webhook"
                                  className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                                />
                              </div>
                              <div>
                                <label className="block text-xs font-medium text-theme-secondary mb-1">HTTP Method</label>
                                <select
                                  value={(step.configuration as Record<string, string>)?.webhook_method || 'POST'}
                                  onChange={(e) => updateStep(index, { configuration: { ...step.configuration, webhook_method: e.target.value } })}
                                  className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                                >
                                  <option value="POST">POST</option>
                                  <option value="PUT">PUT</option>
                                  <option value="PATCH">PATCH</option>
                                </select>
                              </div>
                              <div>
                                <label className="block text-xs font-medium text-theme-secondary mb-1">Headers (JSON)</label>
                                <input
                                  type="text"
                                  value={(step.configuration as Record<string, string>)?.webhook_headers || ''}
                                  onChange={(e) => updateStep(index, { configuration: { ...step.configuration, webhook_headers: e.target.value } })}
                                  placeholder='{"Authorization": "Bearer token"}'
                                  className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                                />
                              </div>
                            </div>
                          )}

                          {/* Shared Message Template */}
                          {channels.length > 0 && (
                            <div>
                              <label className="block text-sm font-medium text-theme-primary mb-1">Message Template</label>
                              <textarea
                                value={(step.configuration as Record<string, string>)?.message || ''}
                                onChange={(e) => updateStep(index, { configuration: { ...step.configuration, message: e.target.value } })}
                                placeholder="Pipeline run completed with status: {{status}}"
                                rows={3}
                                className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                              />
                            </div>
                          )}

                          {/* Trigger Conditions */}
                          <div className="flex items-center gap-4">
                            <label className="inline-flex items-center gap-2 cursor-pointer">
                              <input
                                type="checkbox"
                                checked={(step.configuration as Record<string, boolean>)?.on_success !== false}
                                onChange={(e) => updateStep(index, { configuration: { ...step.configuration, on_success: e.target.checked } })}
                                className="w-4 h-4 rounded border-theme"
                              />
                              <span className="text-sm text-theme-secondary">Notify on success</span>
                            </label>
                            <label className="inline-flex items-center gap-2 cursor-pointer">
                              <input
                                type="checkbox"
                                checked={(step.configuration as Record<string, boolean>)?.on_failure !== false}
                                onChange={(e) => updateStep(index, { configuration: { ...step.configuration, on_failure: e.target.checked } })}
                                className="w-4 h-4 rounded border-theme"
                              />
                              <span className="text-sm text-theme-secondary">Notify on failure</span>
                            </label>
                          </div>
                        </div>
                      );
                    })()}

                    {/* Condition */}
                    <div>
                      <label className="block text-sm font-medium text-theme-primary mb-1">Condition (optional)</label>
                      <input
                        type="text"
                        value={step.condition || ''}
                        onChange={(e) => updateStep(index, { condition: e.target.value || undefined })}
                        placeholder="e.g., ${{ steps.checkout.outcome == 'success' }}"
                        className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm font-mono text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
                      />
                    </div>

                    {/* Options */}
                    <div className="flex items-center gap-6">
                      <label className="inline-flex items-center gap-2 cursor-pointer">
                        <input
                          type="checkbox"
                          checked={step.continue_on_error || false}
                          onChange={(e) => updateStep(index, { continue_on_error: e.target.checked })}
                          className="w-4 h-4 rounded border-theme"
                        />
                        <span className="text-sm text-theme-secondary">Continue on error</span>
                      </label>
                      <label className="inline-flex items-center gap-2 cursor-pointer">
                        <input
                          type="checkbox"
                          checked={step.is_active !== false}
                          onChange={(e) => updateStep(index, { is_active: e.target.checked })}
                          className="w-4 h-4 rounded border-theme"
                        />
                        <span className="text-sm text-theme-secondary">Enabled</span>
                      </label>
                    </div>

                    {/* Approval Settings */}
                    <div className="pt-4 mt-4 border-t border-theme">
                      <StepApprovalSettings
                        requiresApproval={step.requires_approval || false}
                        settings={step.approval_settings || DEFAULT_APPROVAL_SETTINGS}
                        onApprovalToggle={(requires) => updateStep(index, { requires_approval: requires })}
                        onSettingsChange={(settings) => updateStep(index, { approval_settings: settings })}
                      />
                    </div>
                  </div>
                )}
              </div>
            );
          })}

          {/* Add Step Button */}
          <Button onClick={() => setShowAddStep(true)} variant="secondary" className="w-full">
            <Plus className="w-4 h-4 mr-2" />
            Add Step
          </Button>
        </div>

        {/* Add Step Modal */}
        {showAddStep && (
          <>
            <div className="fixed inset-0 bg-black/50 z-40" onClick={() => setShowAddStep(false)} />
            <div className="fixed inset-x-4 top-1/2 -translate-y-1/2 max-w-2xl mx-auto bg-theme-surface rounded-xl shadow-xl z-50 max-h-[80vh] overflow-y-auto">
              <div className="p-6">
                <h3 className="text-lg font-semibold text-theme-primary mb-2">Add Step</h3>
                <p className="text-sm text-theme-secondary mb-4">Choose a step type to add to your pipeline</p>

                {['git', 'ai', 'action', 'deploy'].map((category) => (
                  <div key={category} className="mb-4">
                    <h4 className="text-xs font-semibold text-theme-tertiary uppercase tracking-wide mb-2">
                      {category === 'git' ? 'Git Operations' : category === 'ai' ? 'AI Tasks' : category === 'action' ? 'Build & Test' : 'Deploy & Release'}
                    </h4>
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                      {STEP_TYPES.filter((s) => s.category === category).map((stepType) => {
                        const Icon = stepType.icon;
                        return (
                          <button
                            key={stepType.type}
                            onClick={() => addStep(stepType.type)}
                            className="flex items-start gap-3 p-3 bg-theme-surface-secondary rounded-lg border border-theme hover:border-theme-primary text-left transition-colors"
                          >
                            <div className="p-1.5 bg-theme-surface rounded">
                              <Icon className="w-4 h-4 text-theme-primary" />
                            </div>
                            <div className="min-w-0">
                              <h4 className="font-medium text-sm text-theme-primary">{stepType.label}</h4>
                              <p className="text-xs text-theme-tertiary truncate">{stepType.description}</p>
                            </div>
                          </button>
                        );
                      })}
                    </div>
                  </div>
                ))}

                <div className="flex justify-end pt-4 border-t border-theme">
                  <Button onClick={() => setShowAddStep(false)} variant="secondary">Cancel</Button>
                </div>
              </div>
            </div>
          </>
        )}
      </div>
    );
  }

  // Empty state (only shown when not in edit mode)
  if (!steps || steps.length === 0) {
    return (
      <div className="bg-theme-surface rounded-lg border border-theme p-8 text-center">
        <Layers className="w-12 h-12 text-theme-secondary mx-auto mb-4 opacity-50" />
        <h3 className="text-lg font-medium text-theme-primary mb-2">No Steps Configured</h3>
        <p className="text-theme-secondary mb-4">Add steps to define your pipeline workflow.</p>
        <Button onClick={() => { setIsEditMode(true); setShowAddStep(true); }} variant="primary">
          <Plus className="w-4 h-4 mr-2" />
          Add First Step
        </Button>
      </div>
    );
  }

  // View Mode (Read-only)
  return (
    <div className="space-y-4">
      {/* Step controls */}
      <div className="flex items-center justify-between">
        <p className="text-sm text-theme-secondary">
          {steps.length} step{steps.length !== 1 ? 's' : ''} • {steps.filter((s) => s.is_active).length} active
        </p>
        <div className="flex items-center gap-4">
          <div className="flex items-center gap-2">
            <button onClick={expandAll} className="text-xs text-theme-primary hover:underline">Expand All</button>
            <span className="text-theme-tertiary">|</span>
            <button onClick={collapseAll} className="text-xs text-theme-primary hover:underline">Collapse All</button>
          </div>
          <Button onClick={() => setIsEditMode(true)} variant="secondary" size="sm">
            <Edit className="w-4 h-4 mr-1" />
            Edit Steps
          </Button>
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
              <button onClick={() => toggleStep(step.id)} className="w-full p-4 text-left">
                <div className="flex items-start justify-between">
                  <div className="flex items-center gap-3">
                    <div className={`w-10 h-10 rounded-full flex items-center justify-center text-sm font-bold ${step.is_active ? 'bg-theme-interactive-primary text-white' : 'bg-theme-surface-secondary text-theme-tertiary'}`}>
                      {index + 1}
                    </div>
                    <div>
                      <div className="flex items-center gap-2 flex-wrap">
                        <h4 className="font-medium text-theme-primary">{step.name}</h4>
                        <StepTypeBadge stepType={step.step_type} />
                        {!step.is_active && (
                          <span className="text-xs px-2 py-0.5 bg-theme-surface-secondary text-theme-tertiary rounded">Disabled</span>
                        )}
                        {step.continue_on_error && (
                          <span className="text-xs px-2 py-0.5 bg-theme-warning/10 text-theme-warning rounded">Continue on Error</span>
                        )}
                        {step.requires_approval && (
                          <span className="text-xs px-2 py-0.5 bg-theme-accent/10 text-theme-accent rounded">Requires Approval</span>
                        )}
                      </div>
                      {step.condition && (
                        <p className="text-xs text-theme-tertiary mt-1">
                          <span className="text-theme-secondary">When:</span>{' '}
                          <code className="bg-theme-surface-secondary px-1 rounded font-mono">{step.condition}</code>
                        </p>
                      )}
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    {step.shared_prompt_template_name && (
                      <span className="text-xs px-2 py-0.5 bg-theme-accent/10 text-theme-accent rounded flex items-center gap-1">
                        <Brain className="w-3 h-3" />
                        {step.shared_prompt_template_name}
                      </span>
                    )}
                    <div className={`transform transition-transform ${isExpanded ? 'rotate-180' : ''}`}>
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
                    {hasConfig && (
                      <div className="bg-theme-surface-secondary rounded-lg p-4">
                        <h5 className="text-xs font-medium text-theme-tertiary uppercase tracking-wide mb-3">Configuration</h5>
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

                    {hasInputs && (
                      <div className="bg-theme-surface-secondary rounded-lg p-4">
                        <h5 className="text-xs font-medium text-theme-tertiary uppercase tracking-wide mb-3">Inputs</h5>
                        <div className="space-y-2">
                          {Object.entries(step.inputs || {}).map(([key, value]) => (
                            <div key={key} className="flex items-start justify-between text-sm">
                              <span className="text-theme-secondary font-mono">{key}</span>
                              <span className="text-theme-primary font-mono text-xs text-right max-w-48 truncate">{String(value)}</span>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}

                    {hasOutputs && (
                      <div className="bg-theme-surface-secondary rounded-lg p-4">
                        <h5 className="text-xs font-medium text-theme-tertiary uppercase tracking-wide mb-3">Outputs</h5>
                        <div className="flex flex-wrap gap-2">
                          {Array.isArray(step.outputs) ? (
                            step.outputs.map((output, i) => (
                              <span key={i} className="text-xs px-2 py-1 bg-theme-surface rounded font-mono text-theme-primary">
                                {typeof output === 'object' && output.name ? `${output.name}: ${output.type || 'any'}` : String(output)}
                              </span>
                            ))
                          ) : (
                            Object.entries(step.outputs || {}).map(([key, value]) => (
                              <span key={key} className="text-xs px-2 py-1 bg-theme-surface rounded font-mono text-theme-primary">
                                {key}: {String(value)}
                              </span>
                            ))
                          )}
                        </div>
                      </div>
                    )}

                    <div className="bg-theme-surface-secondary rounded-lg p-4">
                      <h5 className="text-xs font-medium text-theme-tertiary uppercase tracking-wide mb-3">Step Info</h5>
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
                          <span className={step.is_active ? 'text-theme-success' : 'text-theme-tertiary'}>
                            {step.is_active ? 'Active' : 'Disabled'}
                          </span>
                        </div>
                        <div className="flex justify-between">
                          <span className="text-theme-secondary">Error Handling</span>
                          <span className="text-theme-primary">{step.continue_on_error ? 'Continue' : 'Stop Pipeline'}</span>
                        </div>
                      </div>
                    </div>

                    {!hasConfig && !hasInputs && !hasOutputs && (
                      <div className="bg-theme-surface-secondary rounded-lg p-4 text-center">
                        <p className="text-sm text-theme-tertiary">No additional configuration</p>
                      </div>
                    )}
                  </div>

                  <div className="mt-4 pt-3 border-t border-theme">
                    <p className="text-xs text-theme-tertiary font-mono">Step ID: {step.id}</p>
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
                <p className="text-sm text-theme-danger truncate">
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
  const [showTriggerModal, setShowTriggerModal] = useState(false);

  const handleTrigger = () => {
    setShowTriggerModal(true);
  };

  const handleTriggerSubmit = async (context: Record<string, unknown>) => {
    if (!id) return;
    setTriggering(true);
    try {
      const run = await ciCdPipelinesApi.trigger(id, context);
      showNotification('Pipeline triggered successfully', 'success');
      setShowTriggerModal(false);
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
                      setActiveTab('steps');
                      setShowMenu(false);
                    }}
                    className="w-full px-4 py-2 text-left text-sm text-theme-primary hover:bg-theme-surface-secondary flex items-center gap-2"
                  >
                    <Edit className="w-4 h-4" />
                    Edit Steps
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
                    className="w-full px-4 py-2 text-left text-sm text-theme-danger hover:bg-theme-danger/10 flex items-center gap-2"
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
            onPipelineUpdated={refresh}
          />
        )}
        {activeTab === 'steps' && (
          <StepsTab
            steps={pipeline.steps || []}
            pipelineId={pipeline.id}
            onStepsUpdated={refresh}
          />
        )}
        {activeTab === 'runs' && (
          <RunsTab
            pipelineId={pipeline.id}
            onViewRun={(runId) => navigate(`/app/automation/runs/${runId}`)}
          />
        )}
      </div>

      {/* Trigger Modal */}
      <TriggerModal
        isOpen={showTriggerModal}
        onClose={() => setShowTriggerModal(false)}
        onTrigger={handleTriggerSubmit}
        pipeline={pipeline}
        triggering={triggering}
      />
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
