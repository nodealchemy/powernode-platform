import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { ArrowLeft, Save, Plus, Trash2, GripVertical } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { devopsPipelinesApi } from '@/services/devopsPipelinesApi';
import type { DevopsPipelineFormData, DevopsPipelineStepFormData, DevopsStepType } from '@/types/devops-pipelines';

const STEP_TYPES: { value: DevopsStepType; label: string; description: string }[] = [
  { value: 'checkout', label: 'Checkout', description: 'Check out repository code' },
  { value: 'run_tests', label: 'Run Tests', description: 'Execute test suite' },
  { value: 'deploy', label: 'Deploy', description: 'Deploy to environment' },
  { value: 'claude_execute', label: 'Claude Execute', description: 'Run AI-powered code analysis' },
  { value: 'create_pr', label: 'Create PR', description: 'Create a pull request' },
  { value: 'post_comment', label: 'Post Comment', description: 'Post a comment to PR/issue' },
  { value: 'notify', label: 'Notify', description: 'Send notification' },
  { value: 'custom', label: 'Custom', description: 'Custom step type' },
];

export const PipelineCreatePage: React.FC = () => {
  const navigate = useNavigate();
  const { showNotification } = useNotifications();
  // WebSocket for real-time updates
  usePageWebSocket({
    pageType: 'devops',
    onDataUpdate: () => {
      // Trigger data refresh if needed
    }
  });
  const [saving, setSaving] = useState(false);

  const [formData, setFormData] = useState<DevopsPipelineFormData>({
    name: '',
    description: '',
    pipeline_type: 'standard',
    is_active: true,
    timeout_minutes: 30,
    allow_concurrent: false,
    triggers: {
      manual: true,
    },
    steps: [],
  });

  const [steps, setSteps] = useState<DevopsPipelineStepFormData[]>([]);


  const handleInputChange = (field: keyof DevopsPipelineFormData, value: unknown) => {
    setFormData(prev => ({ ...prev, [field]: value }));
  };

  const addStep = () => {
    const newStep: DevopsPipelineStepFormData = {
      name: `Step ${steps.length + 1}`,
      step_type: 'checkout',
      position: steps.length,
      is_active: true,
      continue_on_error: false,
    };
    setSteps([...steps, newStep]);
  };

  const updateStep = (index: number, field: keyof DevopsPipelineStepFormData, value: unknown) => {
    const updated = [...steps];
    updated[index] = { ...updated[index], [field]: value };
    setSteps(updated);
  };

  const removeStep = (index: number) => {
    const updated = steps.filter((_, i) => i !== index);
    // Update positions
    updated.forEach((step, i) => {
      step.position = i;
    });
    setSteps(updated);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();

    if (!formData.name.trim()) {
      showNotification('Pipeline name is required', 'error');
      return;
    }

    setSaving(true);
    try {
      const pipeline = await devopsPipelinesApi.create({
        ...formData,
        steps: steps.map((step, index) => ({
          ...step,
          position: index,
        })),
      });

      showNotification('Pipeline created successfully', 'success');
      navigate(`/app/devops/pipelines/${pipeline.id}`);
    } catch (_error) {
      showNotification('Failed to create pipeline', 'error');
    } finally {
      setSaving(false);
    }
  };

  return (
    <PageContainer
      title="Create Pipeline"
      description="Create a new DevOps pipeline for automated deployments"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'DevOps', href: '/app/devops' },
        { label: 'Pipelines', href: '/app/devops/pipelines' },
        { label: 'Create' },
      ]}
      actions={[
        {
          id: 'back',
          label: 'Back to Pipelines',
          onClick: () => navigate('/app/devops/pipelines'),
          icon: ArrowLeft,
          variant: 'outline',
        },
        {
          id: 'save',
          label: saving ? 'Creating...' : 'Create Pipeline',
          onClick: () => document.getElementById('pipeline-form')?.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true })),
          icon: Save,
          variant: 'primary',
          disabled: saving,
        },
      ]}
    >
      <form id="pipeline-form" onSubmit={handleSubmit} className="space-y-6">
        {/* Basic Information */}
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">Basic Information</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-theme-secondary mb-1">
                Pipeline Name <span className="text-theme-error">*</span>
              </label>
              <input
                type="text"
                value={formData.name}
                onChange={(e) => handleInputChange('name', e.target.value)}
                className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:ring-2 focus:ring-theme-primary focus:border-transparent"
                placeholder="e.g., Production Deploy"
                required
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-theme-secondary mb-1">
                Pipeline Type
              </label>
              <select
                value={formData.pipeline_type || 'standard'}
                onChange={(e) => handleInputChange('pipeline_type', e.target.value)}
                className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:ring-2 focus:ring-theme-primary focus:border-transparent"
              >
                <option value="standard">Standard</option>
                <option value="ci">Continuous Integration</option>
                <option value="cd">Continuous Deployment</option>
                <option value="review">Code Review</option>
              </select>
            </div>
            <div className="md:col-span-2">
              <label className="block text-sm font-medium text-theme-secondary mb-1">
                Description
              </label>
              <textarea
                value={formData.description || ''}
                onChange={(e) => handleInputChange('description', e.target.value)}
                rows={3}
                className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:ring-2 focus:ring-theme-primary focus:border-transparent"
                placeholder="Describe what this pipeline does..."
              />
            </div>
          </div>
        </div>

        {/* Configuration */}
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">Configuration</h3>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div>
              <label className="block text-sm font-medium text-theme-secondary mb-1">
                Timeout (minutes)
              </label>
              <input
                type="number"
                value={formData.timeout_minutes || 30}
                onChange={(e) => handleInputChange('timeout_minutes', parseInt(e.target.value) || 30)}
                min={1}
                max={180}
                className="w-full px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary focus:ring-2 focus:ring-theme-primary focus:border-transparent"
              />
            </div>
            <div className="flex items-center gap-2 pt-6">
              <input
                type="checkbox"
                id="is_active"
                checked={formData.is_active}
                onChange={(e) => handleInputChange('is_active', e.target.checked)}
                className="w-4 h-4 rounded border-theme text-theme-primary focus:ring-theme-primary"
              />
              <label htmlFor="is_active" className="text-sm text-theme-secondary">
                Active (can be triggered)
              </label>
            </div>
            <div className="flex items-center gap-2 pt-6">
              <input
                type="checkbox"
                id="allow_concurrent"
                checked={formData.allow_concurrent || false}
                onChange={(e) => handleInputChange('allow_concurrent', e.target.checked)}
                className="w-4 h-4 rounded border-theme text-theme-primary focus:ring-theme-primary"
              />
              <label htmlFor="allow_concurrent" className="text-sm text-theme-secondary">
                Allow concurrent runs
              </label>
            </div>
          </div>
        </div>

        {/* Steps */}
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-semibold text-theme-primary">Pipeline Steps</h3>
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={addStep}
            >
              <Plus className="w-4 h-4 mr-2" />
              Add Step
            </Button>
          </div>

          {steps.length === 0 ? (
            <div className="text-center py-8 text-theme-secondary">
              <p className="mb-2">No steps configured yet</p>
              <p className="text-sm">Click "Add Step" to add your first pipeline step</p>
            </div>
          ) : (
            <div className="space-y-3">
              {steps.map((step, index) => (
                <div
                  key={index}
                  className="flex items-start gap-3 p-4 bg-theme-surface-hover rounded-lg border border-theme"
                >
                  <div className="flex items-center gap-2 text-theme-secondary cursor-move">
                    <GripVertical className="w-4 h-4" />
                    <span className="text-sm font-medium">{index + 1}</span>
                  </div>
                  <div className="flex-1 grid grid-cols-1 md:grid-cols-3 gap-3">
                    <div>
                      <label className="block text-xs font-medium text-theme-secondary mb-1">
                        Step Name
                      </label>
                      <input
                        type="text"
                        value={step.name}
                        onChange={(e) => updateStep(index, 'name', e.target.value)}
                        className="w-full px-2 py-1.5 text-sm bg-theme-surface border border-theme rounded text-theme-primary"
                        placeholder="Step name"
                      />
                    </div>
                    <div>
                      <label className="block text-xs font-medium text-theme-secondary mb-1">
                        Step Type
                      </label>
                      <select
                        value={step.step_type}
                        onChange={(e) => updateStep(index, 'step_type', e.target.value as DevopsStepType)}
                        className="w-full px-2 py-1.5 text-sm bg-theme-surface border border-theme rounded text-theme-primary"
                      >
                        {STEP_TYPES.map((type) => (
                          <option key={type.value} value={type.value}>
                            {type.label}
                          </option>
                        ))}
                      </select>
                    </div>
                    <div className="flex items-end gap-2">
                      <label className="flex items-center gap-1.5 text-xs text-theme-secondary">
                        <input
                          type="checkbox"
                          checked={step.continue_on_error || false}
                          onChange={(e) => updateStep(index, 'continue_on_error', e.target.checked)}
                          className="w-3 h-3 rounded border-theme"
                        />
                        Continue on error
                      </label>
                    </div>
                  </div>
                  <button
                    type="button"
                    onClick={() => removeStep(index)}
                    className="p-1.5 text-theme-error hover:bg-theme-error/10 rounded"
                  >
                    <Trash2 className="w-4 h-4" />
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Triggers */}
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">Triggers</h3>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <label className="flex items-center gap-2 text-sm text-theme-secondary">
              <input
                type="checkbox"
                checked={formData.triggers?.manual || false}
                onChange={(e) => handleInputChange('triggers', { ...formData.triggers, manual: e.target.checked })}
                className="w-4 h-4 rounded border-theme text-theme-primary"
              />
              Manual
            </label>
            <label className="flex items-center gap-2 text-sm text-theme-secondary">
              <input
                type="checkbox"
                checked={!!formData.triggers?.push}
                onChange={(e) => handleInputChange('triggers', { ...formData.triggers, push: e.target.checked ? { branches: ['main'] } : undefined })}
                className="w-4 h-4 rounded border-theme text-theme-primary"
              />
              On Push
            </label>
            <label className="flex items-center gap-2 text-sm text-theme-secondary">
              <input
                type="checkbox"
                checked={!!formData.triggers?.pull_request}
                onChange={(e) => handleInputChange('triggers', { ...formData.triggers, pull_request: e.target.checked ? ['opened', 'synchronize'] : undefined })}
                className="w-4 h-4 rounded border-theme text-theme-primary"
              />
              On Pull Request
            </label>
            <label className="flex items-center gap-2 text-sm text-theme-secondary">
              <input
                type="checkbox"
                checked={!!formData.triggers?.schedule}
                onChange={(e) => handleInputChange('triggers', { ...formData.triggers, schedule: e.target.checked ? ['0 0 * * *'] : undefined })}
                className="w-4 h-4 rounded border-theme text-theme-primary"
              />
              Scheduled
            </label>
          </div>
        </div>
      </form>
    </PageContainer>
  );
};

export default PipelineCreatePage;
