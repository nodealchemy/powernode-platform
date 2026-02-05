// Review Configuration Section - Inline config in TeamBuilderModal
import React from 'react';
import { Shield } from 'lucide-react';
import type { ReviewConfig } from '@/shared/services/ai/TeamsApiService';
export type { ReviewConfig };

interface ReviewConfigSectionProps {
  config: ReviewConfig;
  onChange: (config: ReviewConfig) => void;
  availableRoleTypes?: string[];
}

const TASK_TYPE_OPTIONS = [
  { value: 'execution', label: 'Execution' },
  { value: 'coordination', label: 'Coordination' },
  { value: 'escalation', label: 'Escalation' },
  { value: 'human_input', label: 'Human Input' },
];

export const ReviewConfigSection: React.FC<ReviewConfigSectionProps> = ({
  config,
  onChange,
  availableRoleTypes = ['reviewer', 'validator', 'manager']
}) => {
  const updateConfig = (partial: Partial<ReviewConfig>) => {
    onChange({ ...config, ...partial });
  };

  const toggleTaskType = (taskType: string) => {
    const current = config.review_task_types || [];
    const updated = current.includes(taskType)
      ? current.filter(t => t !== taskType)
      : [...current, taskType];
    updateConfig({ review_task_types: updated });
  };

  return (
    <details className="border border-theme rounded-lg" data-testid="review-config-section">
      <summary className="flex items-center gap-2 p-4 cursor-pointer hover:bg-theme-accent/50 transition-colors">
        <Shield size={18} className="text-theme-primary" />
        <span className="text-sm font-medium text-theme-primary">Review Configuration</span>
        {config.auto_review_enabled && (
          <span className="ml-auto px-2 py-0.5 text-xs rounded-full bg-theme-success/10 text-theme-success">
            Enabled
          </span>
        )}
      </summary>

      <div className="px-4 pb-4 space-y-4 border-t border-theme pt-4">
        {/* Enable Toggle */}
        <label className="flex items-center gap-3 cursor-pointer">
          <input
            type="checkbox"
            checked={config.auto_review_enabled}
            onChange={(e) => updateConfig({ auto_review_enabled: e.target.checked })}
            className="w-4 h-4 rounded border-theme text-theme-info focus:ring-theme-primary"
          />
          <span className="text-sm text-theme-primary">Enable automatic reviews</span>
        </label>

        {config.auto_review_enabled && (
          <>
            {/* Review Mode */}
            <div>
              <label className="block text-xs font-medium text-theme-secondary mb-2">
                Review Mode
              </label>
              <div className="flex gap-4">
                <label className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="radio"
                    name="review_mode"
                    value="blocking"
                    checked={config.review_mode === 'blocking'}
                    onChange={() => updateConfig({ review_mode: 'blocking' })}
                    className="text-theme-info focus:ring-theme-primary"
                  />
                  <div>
                    <span className="text-sm text-theme-primary">Blocking</span>
                    <p className="text-xs text-theme-secondary">Task waits for review approval</p>
                  </div>
                </label>

                <label className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="radio"
                    name="review_mode"
                    value="shadow"
                    checked={config.review_mode === 'shadow'}
                    onChange={() => updateConfig({ review_mode: 'shadow' })}
                    className="text-theme-info focus:ring-theme-primary"
                  />
                  <div>
                    <span className="text-sm text-theme-primary">Shadow (async)</span>
                    <p className="text-xs text-theme-secondary">Task completes, review runs in background</p>
                  </div>
                </label>
              </div>
            </div>

            {/* Task Types */}
            <div>
              <label className="block text-xs font-medium text-theme-secondary mb-2">
                Review Task Types
              </label>
              <div className="flex flex-wrap gap-3">
                {TASK_TYPE_OPTIONS.map(option => (
                  <label key={option.value} className="flex items-center gap-2 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={(config.review_task_types || []).includes(option.value)}
                      onChange={() => toggleTaskType(option.value)}
                      className="w-4 h-4 rounded border-theme text-theme-info focus:ring-theme-primary"
                    />
                    <span className="text-sm text-theme-primary">{option.label}</span>
                  </label>
                ))}
              </div>
            </div>

            {/* Reviewer Role Type */}
            <div>
              <label className="block text-xs font-medium text-theme-secondary mb-2">
                Reviewer Role Type
              </label>
              <select
                value={config.reviewer_role_type}
                onChange={(e) => updateConfig({ reviewer_role_type: e.target.value })}
                className="w-full px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
              >
                {availableRoleTypes.map(type => (
                  <option key={type} value={type}>{type}</option>
                ))}
              </select>
            </div>

            {/* Quality Threshold */}
            <div>
              <label className="block text-xs font-medium text-theme-secondary mb-2">
                Quality Threshold: {config.quality_threshold.toFixed(1)}
              </label>
              <input
                type="range"
                min="0"
                max="1"
                step="0.1"
                value={config.quality_threshold}
                onChange={(e) => updateConfig({ quality_threshold: parseFloat(e.target.value) })}
                className="w-full"
              />
              <div className="flex justify-between text-xs text-theme-secondary mt-1">
                <span>0.0</span>
                <span>1.0</span>
              </div>
            </div>

            {/* Max Revisions */}
            <div>
              <label className="block text-xs font-medium text-theme-secondary mb-2">
                Max Revisions
              </label>
              <input
                type="number"
                min="1"
                max="10"
                value={config.max_revisions}
                onChange={(e) => updateConfig({ max_revisions: parseInt(e.target.value, 10) || 3 })}
                className="w-24 px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
              />
            </div>
          </>
        )}
      </div>
    </details>
  );
};
