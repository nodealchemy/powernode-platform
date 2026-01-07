import React, { useState, useEffect, useRef } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  ArrowLeft, ArrowRight, Check, Plus, Trash2, GripVertical,
  Play, GitBranch, Calendar, Zap, Brain, Terminal, MessageSquare,
  GitPullRequest, Upload, Rocket, Settings, AlertCircle, Loader2,
  ChevronDown, ChevronUp, RefreshCw
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { PageErrorBoundary } from '@/shared/components/error/ErrorBoundary';
import { Button } from '@/shared/components/ui/Button';
import { usePipelines } from '@/features/cicd/hooks/usePipelines';
import { NotificationSettings } from '@/features/cicd/components/NotificationSettings';
import { StepApprovalSettings } from '@/features/cicd/components/StepApprovalSettings';
import type {
  CiCdPipelineFormData,
  CiCdPipelineStepFormData,
  CiCdPipelineTriggers,
  CiCdStepType,
  NotificationRecipient,
  NotificationSettingsConfig,
  StepApprovalSettings as StepApprovalSettingsType,
} from '@/types/cicd';

// Wizard step definitions
type WizardStep = 'info' | 'triggers' | 'steps' | 'notifications' | 'review';

const WIZARD_STEPS: Array<{ id: WizardStep; label: string; description: string }> = [
  { id: 'info', label: 'Basic Info', description: 'Name and configuration' },
  { id: 'triggers', label: 'Triggers', description: 'When to run' },
  { id: 'steps', label: 'Steps', description: 'What to do' },
  { id: 'notifications', label: 'Notifications', description: 'Who to notify' },
  { id: 'review', label: 'Review', description: 'Confirm and create' },
];

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
  { type: 'run_tests', label: 'Run Tests', description: 'Execute test suites', icon: Terminal, category: 'action' },
  { type: 'post_comment', label: 'Post Comment', description: 'Comment on PR or issue', icon: MessageSquare, category: 'action' },
  { type: 'upload_artifact', label: 'Upload Artifact', description: 'Store build outputs', icon: Upload, category: 'action' },
  { type: 'download_artifact', label: 'Download Artifact', description: 'Retrieve build outputs', icon: Upload, category: 'action' },
  { type: 'deploy', label: 'Deploy', description: 'Deploy to environment', icon: Rocket, category: 'deploy' },
  { type: 'notify', label: 'Notify', description: 'Send notifications', icon: MessageSquare, category: 'action' },
  { type: 'custom', label: 'Custom', description: 'Custom shell command or action', icon: Settings, category: 'action' },
];

// Default notification settings
const DEFAULT_NOTIFICATION_SETTINGS: NotificationSettingsConfig = {
  on_approval_required: true,
  on_completion: false,
  on_failure: true,
};

// Default step approval settings
const DEFAULT_APPROVAL_SETTINGS: StepApprovalSettingsType = {
  timeout_hours: 24,
  require_comment: false,
  notification_recipients: [],
};

// Default form values
const DEFAULT_FORM_DATA: CiCdPipelineFormData = {
  name: '',
  description: '',
  pipeline_type: 'standard',
  is_active: true,
  triggers: {
    manual: true,
  },
  timeout_minutes: 60,
  allow_concurrent: false,
  steps: [],
  notification_recipients: [],
  notification_settings: DEFAULT_NOTIFICATION_SETTINGS,
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

const getStepsWithIssues = (steps: CiCdPipelineStepFormData[]): Array<{ index: number; step: CiCdPipelineStepFormData; validation: StepValidationResult }> => {
  return steps
    .map((step, index) => ({
      index,
      step,
      validation: validateStepConfiguration(step),
    }))
    .filter(({ validation }) => !validation.isValid);
};

// Wizard Progress Indicator
const WizardProgress: React.FC<{
  currentStep: WizardStep;
  onStepClick: (step: WizardStep) => void;
  completedSteps: Set<WizardStep>;
}> = ({ currentStep, onStepClick, completedSteps }) => {
  const currentIndex = WIZARD_STEPS.findIndex(s => s.id === currentStep);

  return (
    <div className="flex items-center justify-between mb-8">
      {WIZARD_STEPS.map((step, index) => {
        const isCompleted = completedSteps.has(step.id);
        const isCurrent = step.id === currentStep;
        const isPast = index < currentIndex;
        const isClickable = isPast || isCompleted;

        return (
          <React.Fragment key={step.id}>
            <button
              onClick={() => isClickable && onStepClick(step.id)}
              disabled={!isClickable}
              className={`flex items-center gap-3 ${isClickable ? 'cursor-pointer' : 'cursor-default'}`}
            >
              <div
                className={`w-10 h-10 rounded-full flex items-center justify-center font-medium text-sm transition-colors ${
                  isCurrent
                    ? 'bg-theme-primary text-white'
                    : isCompleted
                    ? 'bg-theme-success text-white'
                    : 'bg-theme-surface-secondary text-theme-tertiary'
                }`}
              >
                {isCompleted ? <Check className="w-5 h-5" /> : index + 1}
              </div>
              <div className="hidden md:block text-left">
                <p className={`text-sm font-medium ${isCurrent ? 'text-theme-primary' : 'text-theme-secondary'}`}>
                  {step.label}
                </p>
                <p className="text-xs text-theme-tertiary">{step.description}</p>
              </div>
            </button>
            {index < WIZARD_STEPS.length - 1 && (
              <div
                className={`flex-1 h-0.5 mx-4 ${
                  index < currentIndex ? 'bg-theme-success' : 'bg-theme-surface-secondary'
                }`}
              />
            )}
          </React.Fragment>
        );
      })}
    </div>
  );
};

// Step 1: Basic Info
const BasicInfoStep: React.FC<{
  formData: CiCdPipelineFormData;
  onChange: (data: Partial<CiCdPipelineFormData>) => void;
  errors: Record<string, string>;
}> = ({ formData, onChange, errors }) => {
  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-xl font-semibold text-theme-primary mb-2">Pipeline Information</h2>
        <p className="text-theme-secondary">Configure the basic settings for your pipeline.</p>
      </div>

      <div className="space-y-4">
        {/* Name */}
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">
            Pipeline Name <span className="text-theme-danger">*</span>
          </label>
          <input
            type="text"
            value={formData.name}
            onChange={(e) => onChange({ name: e.target.value })}
            placeholder="e.g., Code Review Pipeline"
            className={`w-full px-4 py-2 bg-theme-surface border rounded-lg focus:outline-none focus:ring-2 focus:ring-theme-primary ${
              errors.name ? 'border-theme-danger' : 'border-theme'
            }`}
          />
          {errors.name && <p className="mt-1 text-sm text-theme-danger">{errors.name}</p>}
        </div>

        {/* Description */}
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">Description</label>
          <textarea
            value={formData.description || ''}
            onChange={(e) => onChange({ description: e.target.value })}
            placeholder="Describe what this pipeline does..."
            rows={3}
            className="w-full px-4 py-2 bg-theme-surface border border-theme rounded-lg focus:outline-none focus:ring-2 focus:ring-theme-primary"
          />
        </div>

        {/* Pipeline Type */}
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">Pipeline Type</label>
          <select
            value={formData.pipeline_type || 'standard'}
            onChange={(e) => onChange({ pipeline_type: e.target.value })}
            className="w-full px-4 py-2 bg-theme-surface border border-theme rounded-lg focus:outline-none focus:ring-2 focus:ring-theme-primary"
          >
            <option value="standard">Standard</option>
            <option value="ai_review">AI Code Review</option>
            <option value="ai_implement">AI Implementation</option>
            <option value="deploy">Deployment</option>
            <option value="security">Security Scan</option>
            <option value="custom">Custom</option>
          </select>
          <p className="mt-1 text-xs text-theme-secondary">
            {formData.pipeline_type === 'ai_review' && 'Automated code review using Claude AI to analyze PRs and provide feedback'}
            {formData.pipeline_type === 'ai_implement' && 'AI-powered feature implementation with automated code generation'}
            {formData.pipeline_type === 'deploy' && 'Deployment workflows with staging and production environments'}
            {formData.pipeline_type === 'security' && 'Security scanning and vulnerability detection pipelines'}
            {formData.pipeline_type === 'custom' && 'Fully customizable workflow with your own step configuration'}
            {(!formData.pipeline_type || formData.pipeline_type === 'standard') && 'General purpose pipeline for custom workflows'}
          </p>
        </div>

        {/* Settings Row */}
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {/* Timeout */}
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">
              Timeout (minutes)
            </label>
            <input
              type="number"
              value={formData.timeout_minutes || 60}
              onChange={(e) => onChange({ timeout_minutes: parseInt(e.target.value) || 60 })}
              min={1}
              max={1440}
              className="w-full px-4 py-2 bg-theme-surface border border-theme rounded-lg focus:outline-none focus:ring-2 focus:ring-theme-primary"
            />
          </div>

          {/* Concurrent Runs */}
          <div className="flex items-start gap-3 pt-6">
            <input
              type="checkbox"
              id="allowConcurrent"
              checked={formData.allow_concurrent || false}
              onChange={(e) => onChange({ allow_concurrent: e.target.checked })}
              className="w-4 h-4 mt-0.5 rounded border-theme text-theme-primary focus:ring-theme-primary"
            />
            <div>
              <label htmlFor="allowConcurrent" className="text-sm text-theme-primary">
                Allow concurrent runs
              </label>
              <p className="text-xs text-theme-tertiary">
                If disabled, new triggers wait for the current run to complete
              </p>
            </div>
          </div>
        </div>

        {/* Active Status */}
        <div className="flex items-center gap-3 p-4 bg-theme-surface-secondary rounded-lg">
          <input
            type="checkbox"
            id="isActive"
            checked={formData.is_active}
            onChange={(e) => onChange({ is_active: e.target.checked })}
            className="w-4 h-4 rounded border-theme text-theme-primary focus:ring-theme-primary"
          />
          <div>
            <label htmlFor="isActive" className="text-sm font-medium text-theme-primary">
              Activate pipeline immediately
            </label>
            <p className="text-xs text-theme-tertiary">
              When enabled, the pipeline will start accepting triggers right away
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

// Step 2: Triggers
const TriggersStep: React.FC<{
  formData: CiCdPipelineFormData;
  onChange: (data: Partial<CiCdPipelineFormData>) => void;
}> = ({ formData, onChange }) => {
  const triggers = formData.triggers || {};

  const updateTriggers = (newTriggers: Partial<CiCdPipelineTriggers>) => {
    onChange({ triggers: { ...triggers, ...newTriggers } });
  };

  const [scheduleInput, setScheduleInput] = useState('');
  const [branchInput, setBranchInput] = useState('');

  const addSchedule = () => {
    if (scheduleInput.trim()) {
      const current = triggers.schedule || [];
      updateTriggers({ schedule: [...current, scheduleInput.trim()] });
      setScheduleInput('');
    }
  };

  const removeSchedule = (index: number) => {
    const current = triggers.schedule || [];
    updateTriggers({ schedule: current.filter((_, i) => i !== index) });
  };

  const addBranch = () => {
    if (branchInput.trim()) {
      const current = triggers.push?.branches || [];
      updateTriggers({ push: { branches: [...current, branchInput.trim()] } });
      setBranchInput('');
    }
  };

  const removeBranch = (index: number) => {
    const current = triggers.push?.branches || [];
    updateTriggers({ push: { branches: current.filter((_, i) => i !== index) } });
  };

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-xl font-semibold text-theme-primary mb-2">Pipeline Triggers</h2>
        <p className="text-theme-secondary">Configure when this pipeline should run.</p>
      </div>

      <div className="space-y-4">
        {/* Manual Trigger */}
        <div className="p-4 bg-theme-surface rounded-lg border border-theme">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-theme-surface-secondary rounded-lg">
              <Play className="w-5 h-5 text-theme-primary" />
            </div>
            <div className="flex-1">
              <div className="flex items-center gap-3">
                <input
                  type="checkbox"
                  id="manualTrigger"
                  checked={triggers.manual || false}
                  onChange={(e) => updateTriggers({ manual: e.target.checked })}
                  className="w-4 h-4 rounded border-theme text-theme-primary focus:ring-theme-primary"
                />
                <label htmlFor="manualTrigger" className="font-medium text-theme-primary">
                  Manual Trigger
                </label>
              </div>
              <p className="text-sm text-theme-tertiary mt-1">Run pipeline manually from the dashboard</p>
            </div>
          </div>
        </div>

        {/* Git Push Trigger */}
        <div className="p-4 bg-theme-surface rounded-lg border border-theme">
          <div className="flex items-start gap-3">
            <div className="p-2 bg-theme-surface-secondary rounded-lg">
              <GitBranch className="w-5 h-5 text-theme-info" />
            </div>
            <div className="flex-1">
              <div className="flex items-center gap-3 mb-2">
                <input
                  type="checkbox"
                  id="pushTrigger"
                  checked={(triggers.push?.branches?.length || 0) > 0}
                  onChange={(e) => {
                    if (e.target.checked) {
                      updateTriggers({ push: { branches: ['main'] } });
                    } else {
                      updateTriggers({ push: undefined });
                    }
                  }}
                  className="w-4 h-4 rounded border-theme text-theme-primary focus:ring-theme-primary"
                />
                <label htmlFor="pushTrigger" className="font-medium text-theme-primary">
                  Git Push
                </label>
              </div>
              <p className="text-sm text-theme-tertiary mb-3">Run when code is pushed to specified branches</p>

              {(triggers.push?.branches?.length || 0) > 0 && (
                <div className="space-y-2">
                  <div className="flex flex-wrap gap-2">
                    {triggers.push?.branches?.map((branch, index) => (
                      <span
                        key={index}
                        className="inline-flex items-center gap-1 px-2 py-1 bg-blue-100 text-theme-info dark:bg-blue-900/30 dark:text-blue-300 rounded text-sm"
                      >
                        {branch}
                        <button
                          onClick={() => removeBranch(index)}
                          className="hover:text-blue-900 dark:hover:text-blue-100"
                        >
                          <Trash2 className="w-3 h-3" />
                        </button>
                      </span>
                    ))}
                  </div>
                  <div className="flex gap-2">
                    <input
                      type="text"
                      value={branchInput}
                      onChange={(e) => setBranchInput(e.target.value)}
                      onKeyDown={(e) => e.key === 'Enter' && addBranch()}
                      placeholder="Add branch..."
                      className="flex-1 px-3 py-1 bg-theme-surface border border-theme rounded text-sm focus:outline-none focus:ring-2 focus:ring-theme-primary"
                    />
                    <Button onClick={addBranch} variant="secondary" size="sm">
                      <Plus className="w-4 h-4" />
                    </Button>
                  </div>
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Pull Request Trigger */}
        <div className="p-4 bg-theme-surface rounded-lg border border-theme">
          <div className="flex items-start gap-3">
            <div className="p-2 bg-theme-surface-secondary rounded-lg">
              <GitPullRequest className="w-5 h-5 text-theme-interactive-primary" />
            </div>
            <div className="flex-1">
              <div className="flex items-center gap-3 mb-2">
                <input
                  type="checkbox"
                  id="prTrigger"
                  checked={(triggers.pull_request?.length || 0) > 0}
                  onChange={(e) => {
                    if (e.target.checked) {
                      updateTriggers({ pull_request: ['opened', 'synchronize'] });
                    } else {
                      updateTriggers({ pull_request: undefined });
                    }
                  }}
                  className="w-4 h-4 rounded border-theme text-theme-primary focus:ring-theme-primary"
                />
                <label htmlFor="prTrigger" className="font-medium text-theme-primary">
                  Pull Request
                </label>
              </div>
              <p className="text-sm text-theme-tertiary mb-3">Run on pull request events</p>

              {(triggers.pull_request?.length || 0) > 0 && (
                <div className="flex flex-wrap gap-2">
                  {['opened', 'synchronize', 'reopened', 'closed'].map((event) => (
                    <label key={event} className="inline-flex items-center gap-2">
                      <input
                        type="checkbox"
                        checked={triggers.pull_request?.includes(event) || false}
                        onChange={(e) => {
                          const current = triggers.pull_request || [];
                          if (e.target.checked) {
                            updateTriggers({ pull_request: [...current, event] });
                          } else {
                            updateTriggers({ pull_request: current.filter((e) => e !== event) });
                          }
                        }}
                        className="w-3 h-3 rounded border-theme"
                      />
                      <span className="text-sm text-theme-secondary capitalize">{event}</span>
                    </label>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Schedule Trigger */}
        <div className="p-4 bg-theme-surface rounded-lg border border-theme">
          <div className="flex items-start gap-3">
            <div className="p-2 bg-theme-surface-secondary rounded-lg">
              <Calendar className="w-5 h-5 text-theme-success" />
            </div>
            <div className="flex-1">
              <div className="flex items-center gap-3 mb-2">
                <input
                  type="checkbox"
                  id="scheduleTrigger"
                  checked={(triggers.schedule?.length || 0) > 0}
                  onChange={(e) => {
                    if (e.target.checked) {
                      updateTriggers({ schedule: ['0 0 * * *'] });
                    } else {
                      updateTriggers({ schedule: undefined });
                    }
                  }}
                  className="w-4 h-4 rounded border-theme text-theme-primary focus:ring-theme-primary"
                />
                <label htmlFor="scheduleTrigger" className="font-medium text-theme-primary">
                  Scheduled
                </label>
              </div>
              <p className="text-sm text-theme-tertiary mb-3">Run on a cron schedule</p>

              {(triggers.schedule?.length || 0) > 0 && (
                <div className="space-y-3">
                  <div className="flex flex-wrap gap-2">
                    {triggers.schedule?.map((cron, index) => (
                      <span
                        key={index}
                        className="inline-flex items-center gap-1 px-2 py-1 bg-green-100 text-theme-success dark:bg-green-900/30 dark:text-green-300 rounded text-sm font-mono"
                      >
                        {cron}
                        <button
                          onClick={() => removeSchedule(index)}
                          className="hover:text-green-900 dark:hover:text-green-100"
                        >
                          <Trash2 className="w-3 h-3" />
                        </button>
                      </span>
                    ))}
                  </div>

                  {/* Cron Preset Selector */}
                  <div className="flex flex-wrap gap-2">
                    <span className="text-xs text-theme-tertiary self-center">Quick add:</span>
                    <button
                      type="button"
                      onClick={() => {
                        setScheduleInput('0 * * * *');
                        updateTriggers({ schedule: [...(triggers.schedule || []), '0 * * * *'] });
                      }}
                      className="px-2 py-1 text-xs bg-theme-surface-secondary hover:bg-theme-surface-tertiary text-theme-primary rounded transition-colors"
                      title="Every hour at minute 0"
                    >
                      Every hour
                    </button>
                    <button
                      type="button"
                      onClick={() => {
                        setScheduleInput('0 0 * * *');
                        updateTriggers({ schedule: [...(triggers.schedule || []), '0 0 * * *'] });
                      }}
                      className="px-2 py-1 text-xs bg-theme-surface-secondary hover:bg-theme-surface-tertiary text-theme-primary rounded transition-colors"
                      title="Daily at midnight UTC"
                    >
                      Daily midnight
                    </button>
                    <button
                      type="button"
                      onClick={() => {
                        setScheduleInput('0 9 * * 1-5');
                        updateTriggers({ schedule: [...(triggers.schedule || []), '0 9 * * 1-5'] });
                      }}
                      className="px-2 py-1 text-xs bg-theme-surface-secondary hover:bg-theme-surface-tertiary text-theme-primary rounded transition-colors"
                      title="Weekdays at 9 AM UTC"
                    >
                      Weekdays 9 AM
                    </button>
                    <button
                      type="button"
                      onClick={() => {
                        setScheduleInput('0 0 * * 1');
                        updateTriggers({ schedule: [...(triggers.schedule || []), '0 0 * * 1'] });
                      }}
                      className="px-2 py-1 text-xs bg-theme-surface-secondary hover:bg-theme-surface-tertiary text-theme-primary rounded transition-colors"
                      title="Every Monday at midnight UTC"
                    >
                      Weekly Monday
                    </button>
                  </div>

                  <div className="flex gap-2">
                    <input
                      type="text"
                      value={scheduleInput}
                      onChange={(e) => setScheduleInput(e.target.value)}
                      onKeyDown={(e) => e.key === 'Enter' && addSchedule()}
                      placeholder="Custom cron (e.g., 0 0 * * *)"
                      className="flex-1 px-3 py-1 bg-theme-surface border border-theme rounded text-sm font-mono focus:outline-none focus:ring-2 focus:ring-theme-primary"
                    />
                    <Button onClick={addSchedule} variant="secondary" size="sm">
                      <Plus className="w-4 h-4" />
                    </Button>
                  </div>
                  <p className="text-xs text-theme-tertiary">
                    Format: minute hour day month weekday (e.g., "0 9 * * 1-5" = 9 AM weekdays)
                  </p>
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Workflow Dispatch */}
        <div className="p-4 bg-theme-surface rounded-lg border border-theme">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-theme-surface-secondary rounded-lg">
              <Zap className="w-5 h-5 text-yellow-500" />
            </div>
            <div className="flex-1">
              <div className="flex items-center gap-3">
                <input
                  type="checkbox"
                  id="workflowDispatch"
                  checked={!!triggers.workflow_dispatch}
                  onChange={(e) => updateTriggers({ workflow_dispatch: e.target.checked ? {} : undefined })}
                  className="w-4 h-4 rounded border-theme text-theme-primary focus:ring-theme-primary"
                />
                <label htmlFor="workflowDispatch" className="font-medium text-theme-primary">
                  Workflow Dispatch (API/Webhook)
                </label>
              </div>
              <p className="text-sm text-theme-tertiary mt-1">Trigger via API calls or external webhooks</p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

// Step 3: Pipeline Steps
const StepsConfigStep: React.FC<{
  formData: CiCdPipelineFormData;
  onChange: (data: Partial<CiCdPipelineFormData>) => void;
}> = ({ formData, onChange }) => {
  const steps = formData.steps || [];
  const [showAddStep, setShowAddStep] = useState(false);
  const [expandedStep, setExpandedStep] = useState<number | null>(null);
  const hasInitializedRef = useRef(false);

  // Auto-expand first step when steps load for the first time
  useEffect(() => {
    if (steps.length > 0 && !hasInitializedRef.current && expandedStep === null) {
      hasInitializedRef.current = true;
      setExpandedStep(0);
    }
  }, [steps.length, expandedStep]);

  const addStep = (stepType: CiCdStepType) => {
    const stepConfig = STEP_TYPES.find((s) => s.type === stepType);
    const newStep: CiCdPipelineStepFormData = {
      name: stepConfig?.label || stepType,
      step_type: stepType,
      position: steps.length + 1,
      configuration: {},
      inputs: {},
      is_active: true,
      continue_on_error: false,
    };
    onChange({ steps: [...steps, newStep] });
    setShowAddStep(false);
    setExpandedStep(steps.length);
  };

  const updateStep = (index: number, updates: Partial<CiCdPipelineStepFormData>) => {
    const newSteps = [...steps];
    newSteps[index] = { ...newSteps[index], ...updates };
    onChange({ steps: newSteps });
  };

  const removeStep = (index: number) => {
    const newSteps = steps.filter((_, i) => i !== index).map((step, i) => ({
      ...step,
      position: i + 1,
    }));
    onChange({ steps: newSteps });
    if (expandedStep === index) setExpandedStep(null);
  };

  const moveStep = (index: number, direction: 'up' | 'down') => {
    if (direction === 'up' && index === 0) return;
    if (direction === 'down' && index === steps.length - 1) return;

    const newSteps = [...steps];
    const newIndex = direction === 'up' ? index - 1 : index + 1;
    [newSteps[index], newSteps[newIndex]] = [newSteps[newIndex], newSteps[index]];
    newSteps.forEach((step, i) => {
      step.position = i + 1;
    });
    onChange({ steps: newSteps });
  };

  const getStepIcon = (stepType: CiCdStepType) => {
    const config = STEP_TYPES.find((s) => s.type === stepType);
    return config?.icon || Settings;
  };

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-xl font-semibold text-theme-primary mb-2">Pipeline Steps</h2>
        <p className="text-theme-secondary">Configure the steps that will run in your pipeline.</p>
      </div>

      {/* Steps List */}
      <div className="space-y-3">
        {steps.length === 0 ? (
          <div className="p-8 bg-theme-surface rounded-lg border border-theme border-dashed text-center">
            <Settings className="w-12 h-12 text-theme-tertiary mx-auto mb-3 opacity-50" />
            <p className="text-theme-secondary mb-2">No steps configured yet</p>
            <p className="text-sm text-theme-tertiary mb-4">Add steps to define what your pipeline should do</p>
            <Button onClick={() => setShowAddStep(true)} variant="primary">
              <Plus className="w-4 h-4 mr-2" />
              Add First Step
            </Button>
          </div>
        ) : (
          <>
            {steps.map((step, index) => {
              const StepIcon = getStepIcon(step.step_type);
              const isExpanded = expandedStep === index;
              const stepValidation = validateStepConfiguration(step);

              return (
                <div key={index} className={`bg-theme-surface rounded-lg border overflow-hidden ${!stepValidation.isValid ? 'border-yellow-400 dark:border-yellow-600' : 'border-theme'}`}>
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
                        disabled={index === steps.length - 1}
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
                          <span className="inline-flex items-center gap-1 px-1.5 py-0.5 text-[10px] font-medium bg-yellow-100 text-yellow-700 dark:bg-yellow-900/40 dark:text-yellow-300 rounded" title={stepValidation.message}>
                            <AlertCircle className="w-3 h-3" />
                            Incomplete
                          </span>
                        )}
                      </div>
                      <p className="text-xs text-theme-tertiary">{step.step_type}</p>
                    </div>
                    <div className="flex items-center gap-2">
                      <button
                        onClick={() => setExpandedStep(isExpanded ? null : index)}
                        className={`p-2 hover:bg-theme-surface-secondary rounded-lg ${!stepValidation.isValid ? 'text-theme-warning dark:text-yellow-400' : 'text-theme-secondary hover:text-theme-primary'}`}
                        title={!stepValidation.isValid ? 'Configure step (incomplete)' : 'Configure step'}
                      >
                        <Settings className="w-4 h-4" />
                      </button>
                      <button
                        onClick={() => removeStep(index)}
                        className="p-2 text-theme-secondary hover:text-theme-danger hover:bg-red-50 dark:hover:bg-red-900/20 rounded-lg"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </div>
                  </div>

                  {/* Step Configuration (Expanded) */}
                  {isExpanded && (
                    <div className="p-4 border-t border-theme bg-theme-surface-secondary space-y-4">
                      <div>
                        <label className="block text-sm font-medium text-theme-primary mb-1">
                          Step Name
                        </label>
                        <input
                          type="text"
                          value={step.name}
                          onChange={(e) => updateStep(index, { name: e.target.value })}
                          className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-theme-primary"
                        />
                      </div>

                      {/* Step-specific configuration based on type */}
                      {step.step_type === 'custom' && (
                        <div>
                          <label className="block text-sm font-medium text-theme-primary mb-1">
                            Command
                          </label>
                          <input
                            type="text"
                            value={(step.configuration as Record<string, string>)?.command || ''}
                            onChange={(e) =>
                              updateStep(index, {
                                configuration: { ...step.configuration, command: e.target.value },
                              })
                            }
                            placeholder="npm run build"
                            className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm font-mono focus:outline-none focus:ring-2 focus:ring-theme-primary"
                          />
                        </div>
                      )}

                      {step.step_type === 'claude_execute' && (
                        <div>
                          <label className="block text-sm font-medium text-theme-primary mb-1">
                            Task Description
                          </label>
                          <textarea
                            value={(step.configuration as Record<string, string>)?.task || ''}
                            onChange={(e) =>
                              updateStep(index, {
                                configuration: { ...step.configuration, task: e.target.value },
                              })
                            }
                            placeholder="Describe what Claude should do..."
                            rows={3}
                            className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-theme-primary"
                          />
                        </div>
                      )}

                      {step.step_type === 'checkout' && (
                        <div className="grid grid-cols-2 gap-4">
                          <div>
                            <label className="block text-sm font-medium text-theme-primary mb-1">
                              Branch
                            </label>
                            <input
                              type="text"
                              value={(step.configuration as Record<string, string>)?.branch || ''}
                              onChange={(e) =>
                                updateStep(index, {
                                  configuration: { ...step.configuration, branch: e.target.value },
                                })
                              }
                              placeholder="main (default: trigger branch)"
                              className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-theme-primary"
                            />
                          </div>
                          <div>
                            <label className="block text-sm font-medium text-theme-primary mb-1">
                              Depth
                            </label>
                            <input
                              type="number"
                              value={(step.configuration as Record<string, number>)?.depth || 1}
                              onChange={(e) =>
                                updateStep(index, {
                                  configuration: { ...step.configuration, depth: parseInt(e.target.value) },
                                })
                              }
                              min={0}
                              className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-theme-primary"
                            />
                          </div>
                        </div>
                      )}

                      {step.step_type === 'post_comment' && (
                        <div>
                          <label className="block text-sm font-medium text-theme-primary mb-1">
                            Comment Template
                          </label>
                          <textarea
                            value={(step.configuration as Record<string, string>)?.template || ''}
                            onChange={(e) =>
                              updateStep(index, {
                                configuration: { ...step.configuration, template: e.target.value },
                              })
                            }
                            placeholder="Comment content (supports variables like ${{outputs.step_name.result}})"
                            rows={3}
                            className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-theme-primary"
                          />
                        </div>
                      )}

                      {step.step_type === 'deploy' && (
                        <div className="grid grid-cols-2 gap-4">
                          <div>
                            <label className="block text-sm font-medium text-theme-primary mb-1">
                              Environment
                            </label>
                            <select
                              value={(step.configuration as Record<string, string>)?.environment || 'staging'}
                              onChange={(e) =>
                                updateStep(index, {
                                  configuration: { ...step.configuration, environment: e.target.value },
                                })
                              }
                              className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-theme-primary"
                            >
                              <option value="development">Development</option>
                              <option value="staging">Staging</option>
                              <option value="production">Production</option>
                            </select>
                          </div>
                          <div>
                            <label className="block text-sm font-medium text-theme-primary mb-1">
                              Strategy
                            </label>
                            <select
                              value={(step.configuration as Record<string, string>)?.strategy || 'rolling'}
                              onChange={(e) =>
                                updateStep(index, {
                                  configuration: { ...step.configuration, strategy: e.target.value },
                                })
                              }
                              className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-theme-primary"
                            >
                              <option value="rolling">Rolling</option>
                              <option value="blue_green">Blue/Green</option>
                              <option value="canary">Canary</option>
                            </select>
                          </div>
                        </div>
                      )}

                      {/* Condition */}
                      <div>
                        <label className="block text-sm font-medium text-theme-primary mb-1">
                          Condition (optional)
                        </label>
                        <input
                          type="text"
                          value={step.condition || ''}
                          onChange={(e) => updateStep(index, { condition: e.target.value || undefined })}
                          placeholder="e.g., ${{ steps.checkout.outcome == 'success' }}"
                          className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-sm font-mono focus:outline-none focus:ring-2 focus:ring-theme-primary"
                        />
                      </div>

                      {/* Options */}
                      <div className="flex items-center gap-6">
                        <label
                          className="inline-flex items-center gap-2 cursor-pointer"
                          title="If checked, the pipeline continues executing even if this step fails"
                        >
                          <input
                            type="checkbox"
                            checked={step.continue_on_error || false}
                            onChange={(e) => updateStep(index, { continue_on_error: e.target.checked })}
                            className="w-4 h-4 rounded border-theme"
                          />
                          <span className="text-sm text-theme-secondary">Continue on error</span>
                        </label>
                        <label
                          className="inline-flex items-center gap-2 cursor-pointer"
                          title="Uncheck to skip this step without removing it from the pipeline"
                        >
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
          </>
        )}
      </div>

      {/* Add Step Modal */}
      {showAddStep && (
        <>
          <div className="fixed inset-0 bg-black/50 z-40" onClick={() => setShowAddStep(false)} />
          <div className="fixed inset-x-4 top-1/2 -translate-y-1/2 max-w-2xl mx-auto bg-theme-surface rounded-xl shadow-xl z-50 max-h-[80vh] overflow-y-auto">
            <div className="p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-2">Add Step</h3>
              <p className="text-sm text-theme-secondary mb-4">Choose a step type to add to your pipeline</p>

              {/* Category: Git Operations */}
              <div className="mb-4">
                <h4 className="text-xs font-semibold text-theme-tertiary uppercase tracking-wide mb-2 flex items-center gap-2">
                  <GitBranch className="w-3 h-3" />
                  Git Operations
                </h4>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                  {STEP_TYPES.filter(s => s.category === 'git').map((stepType) => {
                    const Icon = stepType.icon;
                    const isRecommended = stepType.type === 'checkout';
                    return (
                      <button
                        key={stepType.type}
                        onClick={() => addStep(stepType.type)}
                        className="flex items-start gap-3 p-3 bg-theme-surface-secondary rounded-lg border border-theme hover:border-theme-primary text-left transition-colors relative"
                      >
                        {isRecommended && (
                          <span className="absolute -top-2 -right-2 px-1.5 py-0.5 text-[10px] font-medium bg-green-100 text-theme-success dark:bg-green-900/40 dark:text-green-300 rounded">
                            Recommended
                          </span>
                        )}
                        <div className="p-1.5 bg-blue-100 dark:bg-blue-900/30 rounded">
                          <Icon className="w-4 h-4 text-theme-info dark:text-blue-400" />
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

              {/* Category: AI Tasks */}
              <div className="mb-4">
                <h4 className="text-xs font-semibold text-theme-tertiary uppercase tracking-wide mb-2 flex items-center gap-2">
                  <Brain className="w-3 h-3" />
                  AI Tasks
                </h4>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                  {STEP_TYPES.filter(s => s.category === 'ai').map((stepType) => {
                    const Icon = stepType.icon;
                    return (
                      <button
                        key={stepType.type}
                        onClick={() => addStep(stepType.type)}
                        className="flex items-start gap-3 p-3 bg-theme-surface-secondary rounded-lg border border-theme hover:border-theme-primary text-left transition-colors"
                      >
                        <div className="p-1.5 bg-purple-100 dark:bg-purple-900/30 rounded">
                          <Icon className="w-4 h-4 text-theme-interactive-primary dark:text-purple-400" />
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

              {/* Category: Build & Test */}
              <div className="mb-4">
                <h4 className="text-xs font-semibold text-theme-tertiary uppercase tracking-wide mb-2 flex items-center gap-2">
                  <Terminal className="w-3 h-3" />
                  Build & Test
                </h4>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                  {STEP_TYPES.filter(s => s.category === 'action').map((stepType) => {
                    const Icon = stepType.icon;
                    const isRecommended = stepType.type === 'run_tests';
                    return (
                      <button
                        key={stepType.type}
                        onClick={() => addStep(stepType.type)}
                        className="flex items-start gap-3 p-3 bg-theme-surface-secondary rounded-lg border border-theme hover:border-theme-primary text-left transition-colors relative"
                      >
                        {isRecommended && (
                          <span className="absolute -top-2 -right-2 px-1.5 py-0.5 text-[10px] font-medium bg-green-100 text-theme-success dark:bg-green-900/40 dark:text-green-300 rounded">
                            Recommended
                          </span>
                        )}
                        <div className="p-1.5 bg-cyan-100 dark:bg-cyan-900/30 rounded">
                          <Icon className="w-4 h-4 text-cyan-600 dark:text-cyan-400" />
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

              {/* Category: Deploy & Release */}
              <div className="mb-4">
                <h4 className="text-xs font-semibold text-theme-tertiary uppercase tracking-wide mb-2 flex items-center gap-2">
                  <Rocket className="w-3 h-3" />
                  Deploy & Release
                </h4>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                  {STEP_TYPES.filter(s => s.category === 'deploy').map((stepType) => {
                    const Icon = stepType.icon;
                    const isRecommended = stepType.type === 'deploy';
                    return (
                      <button
                        key={stepType.type}
                        onClick={() => addStep(stepType.type)}
                        className="flex items-start gap-3 p-3 bg-theme-surface-secondary rounded-lg border border-theme hover:border-theme-primary text-left transition-colors relative"
                      >
                        {isRecommended && (
                          <span className="absolute -top-2 -right-2 px-1.5 py-0.5 text-[10px] font-medium bg-green-100 text-theme-success dark:bg-green-900/40 dark:text-green-300 rounded">
                            Recommended
                          </span>
                        )}
                        <div className="p-1.5 bg-orange-100 dark:bg-orange-900/30 rounded">
                          <Icon className="w-4 h-4 text-theme-warning dark:text-orange-400" />
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

              <div className="mt-4 flex justify-end border-t border-theme pt-4">
                <Button onClick={() => setShowAddStep(false)} variant="ghost">
                  Cancel
                </Button>
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  );
};

// Step 4: Notifications
const NotificationsStep: React.FC<{
  formData: CiCdPipelineFormData;
  onChange: (data: Partial<CiCdPipelineFormData>) => void;
}> = ({ formData, onChange }) => {
  const recipients = formData.notification_recipients || [];
  const settings = formData.notification_settings || DEFAULT_NOTIFICATION_SETTINGS;

  const handleNotificationChange = (
    newRecipients: NotificationRecipient[],
    newSettings: NotificationSettingsConfig
  ) => {
    onChange({
      notification_recipients: newRecipients,
      notification_settings: newSettings,
    });
  };

  // Count steps that require approval
  const stepsWithApproval = (formData.steps || []).filter(s => s.requires_approval).length;

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-xl font-semibold text-theme-primary mb-2">Notifications</h2>
        <p className="text-theme-secondary">
          Configure who receives notifications for this pipeline.
        </p>
      </div>

      <div className="bg-theme-surface rounded-lg border border-theme p-6">
        <NotificationSettings
          recipients={recipients}
          settings={settings}
          onChange={handleNotificationChange}
        />
      </div>

      {stepsWithApproval > 0 && (
        <div className="p-4 bg-blue-50 dark:bg-blue-900/20 rounded-lg border border-blue-200 dark:border-blue-800">
          <div className="flex items-start gap-3">
            <div className="p-2 bg-blue-100 dark:bg-blue-900/50 rounded-lg">
              <AlertCircle className="w-5 h-5 text-theme-info dark:text-blue-400" />
            </div>
            <div>
              <h3 className="font-medium text-blue-800 dark:text-blue-200">
                {stepsWithApproval} step{stepsWithApproval > 1 ? 's' : ''} require{stepsWithApproval === 1 ? 's' : ''} approval
              </h3>
              <p className="text-sm text-theme-info dark:text-blue-300 mt-1">
                When these steps are reached, the pipeline will pause and send notification
                emails to the recipients configured above (unless step-specific recipients are set).
              </p>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

// Step 5: Review
const ReviewStep: React.FC<{
  formData: CiCdPipelineFormData;
}> = ({ formData }) => {
  const triggers = formData.triggers || {};
  const steps = formData.steps || [];

  const getActiveTriggers = () => {
    const active: string[] = [];
    if (triggers.manual) active.push('Manual');
    if (triggers.push?.branches?.length) active.push(`Push (${triggers.push.branches.join(', ')})`);
    if (triggers.pull_request?.length) active.push(`PR (${triggers.pull_request.join(', ')})`);
    if (triggers.schedule?.length) active.push(`Schedule (${triggers.schedule.join(', ')})`);
    if (triggers.workflow_dispatch) active.push('API/Webhook');
    return active.length > 0 ? active : ['None'];
  };

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-xl font-semibold text-theme-primary mb-2">Review Pipeline</h2>
        <p className="text-theme-secondary">Review your pipeline configuration before creating.</p>
      </div>

      <div className="space-y-4">
        {/* Basic Info */}
        <div className="p-4 bg-theme-surface rounded-lg border border-theme">
          <h3 className="text-sm font-medium text-theme-tertiary mb-3">Basic Information</h3>
          <div className="grid grid-cols-2 gap-4">
            <div>
              <p className="text-xs text-theme-tertiary">Name</p>
              <p className="font-medium text-theme-primary">{formData.name || '-'}</p>
            </div>
            <div>
              <p className="text-xs text-theme-tertiary">Type</p>
              <p className="font-medium text-theme-primary">{formData.pipeline_type || 'standard'}</p>
            </div>
            <div>
              <p className="text-xs text-theme-tertiary">Timeout</p>
              <p className="font-medium text-theme-primary">{formData.timeout_minutes} minutes</p>
            </div>
            <div>
              <p className="text-xs text-theme-tertiary">Status</p>
              <p className={`font-medium ${formData.is_active ? 'text-theme-success' : 'text-theme-secondary'}`}>
                {formData.is_active ? 'Active' : 'Inactive'}
              </p>
            </div>
          </div>
          {formData.description && (
            <div className="mt-3 pt-3 border-t border-theme">
              <p className="text-xs text-theme-tertiary">Description</p>
              <p className="text-sm text-theme-secondary">{formData.description}</p>
            </div>
          )}
        </div>

        {/* Triggers */}
        <div className="p-4 bg-theme-surface rounded-lg border border-theme">
          <h3 className="text-sm font-medium text-theme-tertiary mb-3">Triggers</h3>
          <div className="flex flex-wrap gap-2">
            {getActiveTriggers().map((trigger, index) => (
              <span
                key={index}
                className="px-2 py-1 bg-theme-surface-secondary rounded text-sm text-theme-primary"
              >
                {trigger}
              </span>
            ))}
          </div>
        </div>

        {/* Steps */}
        <div className="p-4 bg-theme-surface rounded-lg border border-theme">
          <h3 className="text-sm font-medium text-theme-tertiary mb-3">
            Steps ({steps.length})
          </h3>
          {steps.length === 0 ? (
            <p className="text-sm text-theme-tertiary">No steps configured</p>
          ) : (
            <div className="space-y-2">
              {steps.map((step, index) => {
                const StepIcon = STEP_TYPES.find((s) => s.type === step.step_type)?.icon || Settings;
                const stepValidation = validateStepConfiguration(step);
                return (
                  <div key={index} className={`flex items-center gap-3 p-2 rounded ${!stepValidation.isValid ? 'bg-yellow-50 dark:bg-yellow-900/20 border border-yellow-200 dark:border-yellow-700' : 'bg-theme-surface-secondary'}`}>
                    <span className="w-6 h-6 flex items-center justify-center text-xs font-medium text-theme-tertiary">
                      {index + 1}
                    </span>
                    <StepIcon className="w-4 h-4 text-theme-secondary" />
                    <span className="text-sm text-theme-primary flex-1">{step.name}</span>
                    <span className="text-xs text-theme-tertiary">({step.step_type})</span>
                    {step.requires_approval && (
                      <span className="text-xs text-theme-info dark:text-blue-400 px-1.5 py-0.5 bg-blue-100 dark:bg-blue-900/30 rounded">
                        Approval Required
                      </span>
                    )}
                    {!stepValidation.isValid && (
                      <span className="text-xs text-theme-warning dark:text-yellow-400 flex items-center gap-1">
                        <AlertCircle className="w-3 h-3" />
                        {stepValidation.message}
                      </span>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </div>

        {/* Notifications */}
        <div className="p-4 bg-theme-surface rounded-lg border border-theme">
          <h3 className="text-sm font-medium text-theme-tertiary mb-3">Notifications</h3>
          <div className="space-y-3">
            <div>
              <p className="text-xs text-theme-tertiary">Recipients</p>
              {(formData.notification_recipients?.length || 0) === 0 ? (
                <p className="text-sm text-theme-secondary">No recipients configured</p>
              ) : (
                <div className="flex flex-wrap gap-2 mt-1">
                  {formData.notification_recipients?.map((recipient, index) => (
                    <span
                      key={index}
                      className="px-2 py-1 bg-theme-surface-secondary rounded text-sm text-theme-primary"
                    >
                      {recipient.display_name || recipient.value}
                    </span>
                  ))}
                </div>
              )}
            </div>
            <div className="flex gap-4 text-sm">
              <span className={formData.notification_settings?.on_approval_required ? 'text-theme-success' : 'text-theme-tertiary'}>
                {formData.notification_settings?.on_approval_required ? '✓' : '○'} On approval required
              </span>
              <span className={formData.notification_settings?.on_completion ? 'text-theme-success' : 'text-theme-tertiary'}>
                {formData.notification_settings?.on_completion ? '✓' : '○'} On completion
              </span>
              <span className={formData.notification_settings?.on_failure ? 'text-theme-success' : 'text-theme-tertiary'}>
                {formData.notification_settings?.on_failure ? '✓' : '○'} On failure
              </span>
            </div>
          </div>
        </div>

        {/* Warnings */}
        {(() => {
          const stepsWithIssues = getStepsWithIssues(steps);
          const hasNoSteps = steps.length === 0;
          const hasIncompleteSteps = stepsWithIssues.length > 0;

          if (!hasNoSteps && !hasIncompleteSteps) return null;

          return (
            <div className="space-y-3">
              {hasNoSteps && (
                <div className="p-4 bg-yellow-50 dark:bg-yellow-900/20 rounded-lg border border-yellow-200 dark:border-yellow-800">
                  <div className="flex items-start gap-3">
                    <AlertCircle className="w-5 h-5 text-theme-warning dark:text-yellow-400 mt-0.5" />
                    <div>
                      <p className="font-medium text-yellow-800 dark:text-yellow-200">No steps configured</p>
                      <p className="text-sm text-yellow-700 dark:text-yellow-300">
                        This pipeline has no steps. You can add steps after creating the pipeline.
                      </p>
                    </div>
                  </div>
                </div>
              )}

              {hasIncompleteSteps && (
                <div className="p-4 bg-yellow-50 dark:bg-yellow-900/20 rounded-lg border border-yellow-200 dark:border-yellow-800">
                  <div className="flex items-start gap-3">
                    <AlertCircle className="w-5 h-5 text-theme-warning dark:text-yellow-400 mt-0.5" />
                    <div>
                      <p className="font-medium text-yellow-800 dark:text-yellow-200">
                        {stepsWithIssues.length} step{stepsWithIssues.length > 1 ? 's have' : ' has'} incomplete configuration
                      </p>
                      <ul className="mt-1 space-y-1">
                        {stepsWithIssues.map(({ index, step, validation }) => (
                          <li key={index} className="text-sm text-yellow-700 dark:text-yellow-300">
                            Step {index + 1} ({step.name}): {validation.message}
                          </li>
                        ))}
                      </ul>
                      <p className="text-sm text-yellow-700 dark:text-yellow-300 mt-2">
                        You can still create the pipeline, but these steps may fail during execution.
                      </p>
                    </div>
                  </div>
                </div>
              )}
            </div>
          );
        })()}
      </div>
    </div>
  );
};

// Local storage key for draft persistence
const DRAFT_STORAGE_KEY = 'powernode_pipeline_draft';

interface DraftData {
  formData: CiCdPipelineFormData;
  currentStep: WizardStep;
  completedSteps: WizardStep[];
  savedAt: string;
}

// Main Page Component
const CreatePipelinePageContent: React.FC = () => {
  const navigate = useNavigate();
  const { createPipeline } = usePipelines();

  const [currentStep, setCurrentStep] = useState<WizardStep>('info');
  const [completedSteps, setCompletedSteps] = useState<Set<WizardStep>>(new Set());
  const [formData, setFormData] = useState<CiCdPipelineFormData>(DEFAULT_FORM_DATA);
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [showDraftPrompt, setShowDraftPrompt] = useState(false);
  const [draftAge, setDraftAge] = useState<string>('');
  const draftInitializedRef = useRef(false);

  // Check for existing draft on mount
  useEffect(() => {
    if (draftInitializedRef.current) return;
    draftInitializedRef.current = true;

    try {
      const savedDraft = localStorage.getItem(DRAFT_STORAGE_KEY);
      if (savedDraft) {
        const draft: DraftData = JSON.parse(savedDraft);
        // Check if draft has actual content (not just defaults)
        if (draft.formData.name?.trim() || (draft.formData.steps && draft.formData.steps.length > 0)) {
          // Calculate age
          const savedDate = new Date(draft.savedAt);
          const now = new Date();
          const diffMs = now.getTime() - savedDate.getTime();
          const diffMins = Math.floor(diffMs / 60000);
          const diffHours = Math.floor(diffMins / 60);
          const diffDays = Math.floor(diffHours / 24);

          if (diffDays > 7) {
            // Draft is too old, clear it
            localStorage.removeItem(DRAFT_STORAGE_KEY);
          } else {
            let ageStr = 'just now';
            if (diffMins >= 1 && diffMins < 60) ageStr = `${diffMins} minute${diffMins > 1 ? 's' : ''} ago`;
            else if (diffHours >= 1 && diffHours < 24) ageStr = `${diffHours} hour${diffHours > 1 ? 's' : ''} ago`;
            else if (diffDays >= 1) ageStr = `${diffDays} day${diffDays > 1 ? 's' : ''} ago`;

            setDraftAge(ageStr);
            setShowDraftPrompt(true);
          }
        }
      }
    } catch {
      localStorage.removeItem(DRAFT_STORAGE_KEY);
    }
  }, []);

  // Save draft to localStorage when form data changes
  useEffect(() => {
    // Don't save if we're showing the draft prompt (user hasn't decided yet)
    if (showDraftPrompt) return;

    // Only save if there's meaningful content
    if (formData.name?.trim() || (formData.steps && formData.steps.length > 0)) {
      const draft: DraftData = {
        formData,
        currentStep,
        completedSteps: Array.from(completedSteps),
        savedAt: new Date().toISOString(),
      };
      localStorage.setItem(DRAFT_STORAGE_KEY, JSON.stringify(draft));
    }
  }, [formData, currentStep, completedSteps, showDraftPrompt]);

  const restoreDraft = () => {
    try {
      const savedDraft = localStorage.getItem(DRAFT_STORAGE_KEY);
      if (savedDraft) {
        const draft: DraftData = JSON.parse(savedDraft);
        setFormData(draft.formData);
        setCurrentStep(draft.currentStep);
        setCompletedSteps(new Set(draft.completedSteps));
      }
    } catch {
      // Ignore errors
    }
    setShowDraftPrompt(false);
  };

  const discardDraft = () => {
    localStorage.removeItem(DRAFT_STORAGE_KEY);
    setShowDraftPrompt(false);
  };

  const currentStepIndex = WIZARD_STEPS.findIndex((s) => s.id === currentStep);

  const updateFormData = (updates: Partial<CiCdPipelineFormData>) => {
    setFormData((prev) => ({ ...prev, ...updates }));
    // Clear relevant errors
    Object.keys(updates).forEach((key) => {
      if (errors[key]) {
        setErrors((prev) => {
          const next = { ...prev };
          delete next[key];
          return next;
        });
      }
    });
  };

  const validateStep = (step: WizardStep): boolean => {
    const newErrors: Record<string, string> = {};

    if (step === 'info') {
      if (!formData.name?.trim()) {
        newErrors.name = 'Pipeline name is required';
      } else if (formData.name.length < 3) {
        newErrors.name = 'Pipeline name must be at least 3 characters';
      }
    }

    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const goToStep = (step: WizardStep) => {
    if (validateStep(currentStep)) {
      setCompletedSteps((prev) => new Set([...prev, currentStep]));
      setCurrentStep(step);
    }
  };

  const handleNext = () => {
    if (currentStepIndex < WIZARD_STEPS.length - 1) {
      goToStep(WIZARD_STEPS[currentStepIndex + 1].id);
    }
  };

  const handleBack = () => {
    if (currentStepIndex > 0) {
      setCurrentStep(WIZARD_STEPS[currentStepIndex - 1].id);
    }
  };

  const handleSubmit = async () => {
    if (!validateStep(currentStep)) return;

    setIsSubmitting(true);
    try {
      const pipeline = await createPipeline(formData);
      if (pipeline) {
        // Clear draft on successful creation
        localStorage.removeItem(DRAFT_STORAGE_KEY);
        navigate(`/app/automation/pipelines/${pipeline.id}`);
      }
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <PageContainer
      title="Create Pipeline"
      description="Set up a new automation pipeline"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'Automation', href: '/app/automation' },
        { label: 'Pipelines', href: '/app/automation/pipelines' },
        { label: 'Create' },
      ]}
    >
      <div className="max-w-4xl mx-auto">
        {/* Draft Restore Prompt */}
        {showDraftPrompt && (
          <div className="mb-6 p-4 bg-blue-50 dark:bg-blue-950/30 rounded-lg border border-blue-200 dark:border-blue-800">
            <div className="flex items-start gap-3">
              <div className="p-2 bg-blue-100 dark:bg-blue-900/50 rounded-lg">
                <RefreshCw className="w-5 h-5 text-theme-info dark:text-blue-400" />
              </div>
              <div className="flex-1">
                <h3 className="font-medium text-blue-800 dark:text-blue-200">Resume your draft?</h3>
                <p className="text-sm text-theme-info dark:text-blue-300 mt-1">
                  You have an unsaved pipeline draft from {draftAge}. Would you like to continue where you left off?
                </p>
                <div className="flex items-center gap-3 mt-3">
                  <Button onClick={restoreDraft} variant="primary" size="sm">
                    Resume Draft
                  </Button>
                  <Button onClick={discardDraft} variant="ghost" size="sm">
                    Start Fresh
                  </Button>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Progress Indicator */}
        <WizardProgress
          currentStep={currentStep}
          onStepClick={goToStep}
          completedSteps={completedSteps}
        />

        {/* Step Content */}
        <div className="bg-theme-surface rounded-xl border border-theme p-6 mb-6">
          {currentStep === 'info' && (
            <BasicInfoStep formData={formData} onChange={updateFormData} errors={errors} />
          )}
          {currentStep === 'triggers' && (
            <TriggersStep formData={formData} onChange={updateFormData} />
          )}
          {currentStep === 'steps' && (
            <StepsConfigStep formData={formData} onChange={updateFormData} />
          )}
          {currentStep === 'notifications' && (
            <NotificationsStep formData={formData} onChange={updateFormData} />
          )}
          {currentStep === 'review' && <ReviewStep formData={formData} />}
        </div>

        {/* Navigation Buttons */}
        <div className="flex items-center justify-between">
          <Button
            onClick={() => navigate('/app/automation/pipelines')}
            variant="ghost"
          >
            Cancel
          </Button>

          <div className="flex items-center gap-3">
            {currentStepIndex > 0 && (
              <Button onClick={handleBack} variant="secondary">
                <ArrowLeft className="w-4 h-4 mr-2" />
                Back
              </Button>
            )}

            {currentStepIndex < WIZARD_STEPS.length - 1 ? (
              <Button onClick={handleNext} variant="primary">
                Next
                <ArrowRight className="w-4 h-4 ml-2" />
              </Button>
            ) : (
              <Button
                onClick={handleSubmit}
                variant="primary"
                disabled={isSubmitting}
              >
                {isSubmitting ? (
                  <>
                    <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                    Creating...
                  </>
                ) : (
                  <>
                    <Check className="w-4 h-4 mr-2" />
                    Create Pipeline
                  </>
                )}
              </Button>
            )}
          </div>
        </div>
      </div>
    </PageContainer>
  );
};

export function CreatePipelinePage() {
  return (
    <PageErrorBoundary>
      <CreatePipelinePageContent />
    </PageErrorBoundary>
  );
}

export default CreatePipelinePage;
