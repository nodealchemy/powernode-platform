import React, { useState, useEffect } from 'react';
import { Button } from '@/shared/components/ui/Button';
import { Save } from 'lucide-react';
import { planFeaturesApi, Plan, PlanFeature, PlanLimit, LimitFormData } from '@/shared/services/planFeaturesApi';

export interface LimitModalProps {
  isOpen: boolean;
  plan: Plan;
  feature: PlanFeature;
  currentLimit?: PlanLimit;
  onClose: () => void;
  onSave: (data: LimitFormData) => void;
}

export const LimitModal: React.FC<LimitModalProps> = ({ isOpen, plan, feature, currentLimit, onClose, onSave }) => {
  const [formData, setFormData] = useState<LimitFormData>(planFeaturesApi.getDefaultLimitData());
  const [errors, setErrors] = useState<string[]>([]);

  useEffect(() => {
    if (currentLimit) {
      setFormData({
        value: currentLimit.value,
        is_unlimited: currentLimit.is_unlimited,
        is_enabled: currentLimit.is_enabled,
        custom_message: currentLimit.custom_message || ''
      });
    } else {
      setFormData(planFeaturesApi.getDefaultLimitData());
    }
    setErrors([]);
  }, [currentLimit, isOpen]);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const validationErrors = planFeaturesApi.validateLimitFormData(feature, formData);
    if (validationErrors.length > 0) {
      setErrors(validationErrors);
      return;
    }
    onSave(formData);
    onClose();
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
      <div className="bg-theme-surface rounded-lg shadow-xl max-w-lg w-full">
        <div className="px-6 py-4 border-b border-theme">
          <h3 className="text-lg font-semibold text-theme-primary">
            Configure {feature.name} for {plan.name}
          </h3>
        </div>

        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          {/* Errors */}
          {errors.length > 0 && (
            <div className="bg-theme-error-background border border-theme-error rounded-lg p-4">
              <ul className="list-disc list-inside text-sm text-theme-error space-y-1">
                {errors.map((error, index) => (
                  <li key={index}>{error}</li>
                ))}
              </ul>
            </div>
          )}

          {/* Enable/Disable */}
          <div>
            <label className="flex items-center">
              <input
                type="checkbox"
                checked={formData.is_enabled}
                onChange={(e) => setFormData(prev => ({ ...prev, is_enabled: e.target.checked }))}
                className="w-4 h-4 text-theme-interactive-primary border-theme rounded focus:ring-theme-interactive-primary"
              />
              <span className="ml-2 text-sm font-medium text-theme-primary">Enable this feature</span>
            </label>
          </div>

          {formData.is_enabled && (
            <>
              {/* Unlimited toggle */}
              <div>
                <label className="flex items-center">
                  <input
                    type="checkbox"
                    checked={formData.is_unlimited}
                    onChange={(e) => setFormData(prev => ({ ...prev, is_unlimited: e.target.checked }))}
                    className="w-4 h-4 text-theme-interactive-primary border-theme rounded focus:ring-theme-interactive-primary"
                  />
                  <span className="ml-2 text-sm font-medium text-theme-primary">Unlimited</span>
                </label>
              </div>

              {/* Value input */}
              {!formData.is_unlimited && (
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    {feature.type === 'boolean' ? 'Default State' : 'Limit Value'}
                  </label>
                  {feature.type === 'boolean' ? (
                    <select
                      value={formData.value ? 'true' : 'false'}
                      onChange={(e) => setFormData(prev => ({ ...prev, value: e.target.value === 'true' }))}
                      className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                    >
                      <option value="false">Disabled</option>
                      <option value="true">Enabled</option>
                    </select>
                  ) : feature.type === 'numeric' ? (
                    <input
                      type="number"
                      value={String(formData.value ?? '')}
                      onChange={(e) => setFormData(prev => ({ ...prev, value: parseInt(e.target.value) || 0 }))}
                      className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                      min={feature.validation_rules?.min}
                      max={feature.validation_rules?.max}
                    />
                  ) : feature.type === 'enum' ? (
                    <select
                      value={String(formData.value ?? '')}
                      onChange={(e) => setFormData(prev => ({ ...prev, value: e.target.value }))}
                      className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                    >
                      <option value="">Select an option</option>
                      {feature.validation_rules?.enum_values?.map(option => (
                        <option key={option} value={option}>{option}</option>
                      ))}
                    </select>
                  ) : (
                    <input
                      type="text"
                      value={String(formData.value ?? '')}
                      onChange={(e) => setFormData(prev => ({ ...prev, value: e.target.value }))}
                      className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                    />
                  )}
                </div>
              )}

              {/* Custom message */}
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Custom Message (optional)
                </label>
                <textarea
                  value={formData.custom_message || ''}
                  onChange={(e) => setFormData(prev => ({ ...prev, custom_message: e.target.value }))}
                  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                  rows={2}
                  placeholder="Custom message shown when limit is reached"
                />
              </div>
            </>
          )}
        </form>

        <div className="px-6 py-4 border-t border-theme flex justify-end gap-3">
          <Button onClick={onClose} type="button" variant="outline">
            Cancel
          </Button>
          <Button onClick={handleSubmit} variant="primary">
            <Save className="w-4 h-4" />
            Save Limit
          </Button>
        </div>
      </div>
    </div>
  );
};
