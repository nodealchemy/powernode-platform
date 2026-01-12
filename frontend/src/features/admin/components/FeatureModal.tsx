import React, { useState, useEffect } from 'react';
import { Button } from '@/shared/components/ui/Button';
import { Save, AlertTriangle } from 'lucide-react';
import { planFeaturesApi, PlanFeature, FeatureFormData } from '@/shared/services/planFeaturesApi';

export interface FeatureModalProps {
  isOpen: boolean;
  feature?: PlanFeature;
  onClose: () => void;
  onSave: (data: FeatureFormData) => void;
}

export const FeatureModal: React.FC<FeatureModalProps> = ({ isOpen, feature, onClose, onSave }) => {
  const [formData, setFormData] = useState<FeatureFormData>(planFeaturesApi.getDefaultFormData());
  const [errors, setErrors] = useState<string[]>([]);

  useEffect(() => {
    if (feature) {
      setFormData({
        name: feature.name,
        description: feature.description,
        type: feature.type,
        category: feature.category,
        default_value: feature.default_value,
        validation_rules: feature.validation_rules || {}
      });
    } else {
      setFormData(planFeaturesApi.getDefaultFormData());
    }
    setErrors([]);
  }, [feature, isOpen]);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const validationErrors = planFeaturesApi.validateFeatureFormData(formData);
    if (validationErrors.length > 0) {
      setErrors(validationErrors);
      return;
    }
    onSave(formData);
    onClose();
  };

  const handleEnumValuesChange = (value: string) => {
    const enumValues = value.split('\n').map(v => v.trim()).filter(v => v);
    setFormData(prev => ({
      ...prev,
      validation_rules: { ...prev.validation_rules, enum_values: enumValues }
    }));
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center p-4 z-50">
      <div className="bg-theme-surface rounded-lg shadow-xl max-w-2xl w-full max-h-[90vh] overflow-auto">
        <div className="px-6 py-4 border-b border-theme">
          <h3 className="text-lg font-semibold text-theme-primary">
            {feature ? 'Edit Feature' : 'Create Feature'}
          </h3>
        </div>

        <form onSubmit={handleSubmit} className="p-6 space-y-6">
          {/* Errors */}
          {errors.length > 0 && (
            <div className="bg-theme-error-background border border-theme-error rounded-lg p-4">
              <div className="flex items-center gap-2 mb-2">
                <AlertTriangle className="w-5 h-5 text-theme-error" />
                <span className="font-medium text-theme-error">Please fix the following errors:</span>
              </div>
              <ul className="list-disc list-inside text-sm text-theme-error space-y-1">
                {errors.map((error, index) => (
                  <li key={index}>{error}</li>
                ))}
              </ul>
            </div>
          )}

          {/* Basic Info */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Feature Name *
              </label>
              <input
                type="text"
                value={formData.name}
                onChange={(e) => setFormData(prev => ({ ...prev, name: e.target.value }))}
                className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                placeholder="e.g., API Requests"
                required
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Category *
              </label>
              <select
                value={formData.category}
                onChange={(e) => setFormData(prev => ({ ...prev, category: e.target.value as 'core' | 'advanced' | 'integrations' | 'support' | 'analytics' }))}
                className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                required
              >
                <option value="core">Core Features</option>
                <option value="advanced">Advanced Features</option>
                <option value="integrations">Integrations</option>
                <option value="support">Support</option>
                <option value="analytics">Analytics</option>
              </select>
            </div>
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Description *
            </label>
            <textarea
              value={formData.description}
              onChange={(e) => setFormData(prev => ({ ...prev, description: e.target.value }))}
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
              rows={3}
              placeholder="Describe what this feature controls..."
              required
            />
          </div>

          {/* Type and Default Value */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Feature Type *
              </label>
              <select
                value={formData.type}
                onChange={(e) => setFormData(prev => ({
                  ...prev,
                  type: e.target.value as 'boolean' | 'numeric' | 'text' | 'enum',
                  default_value: e.target.value === 'boolean' ? false : e.target.value === 'numeric' ? 0 : ''
                }))}
                className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                required
              >
                <option value="boolean">Boolean (True/False)</option>
                <option value="numeric">Numeric (Number)</option>
                <option value="text">Text (String)</option>
                <option value="enum">Enum (Dropdown)</option>
              </select>
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Default Value
              </label>
              {formData.type === 'boolean' ? (
                <select
                  value={(formData.default_value ?? false).toString()}
                  onChange={(e) => setFormData(prev => ({ ...prev, default_value: e.target.value === 'true' }))}
                  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                >
                  <option value="false">Disabled</option>
                  <option value="true">Enabled</option>
                </select>
              ) : formData.type === 'numeric' ? (
                <input
                  type="number"
                  value={String(formData.default_value ?? 0)}
                  onChange={(e) => setFormData(prev => ({ ...prev, default_value: parseInt(e.target.value) || 0 }))}
                  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                />
              ) : (
                <input
                  type="text"
                  value={String(formData.default_value ?? '')}
                  onChange={(e) => setFormData(prev => ({ ...prev, default_value: e.target.value }))}
                  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                />
              )}
            </div>
          </div>

          {/* Validation Rules */}
          {(formData.type === 'numeric' || formData.type === 'enum') && (
            <div className="space-y-4">
              <h4 className="font-medium text-theme-primary">Validation Rules</h4>

              {formData.type === 'numeric' && (
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  <div>
                    <label className="block text-sm font-medium text-theme-primary mb-2">
                      Minimum Value
                    </label>
                    <input
                      type="number"
                      value={formData.validation_rules?.min || ''}
                      onChange={(e) => setFormData(prev => ({
                        ...prev,
                        validation_rules: {
                          ...prev.validation_rules,
                          min: e.target.value ? parseInt(e.target.value) : undefined
                        }
                      }))}
                      className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                    />
                  </div>

                  <div>
                    <label className="block text-sm font-medium text-theme-primary mb-2">
                      Maximum Value
                    </label>
                    <input
                      type="number"
                      value={formData.validation_rules?.max || ''}
                      onChange={(e) => setFormData(prev => ({
                        ...prev,
                        validation_rules: {
                          ...prev.validation_rules,
                          max: e.target.value ? parseInt(e.target.value) : undefined
                        }
                      }))}
                      className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                    />
                  </div>
                </div>
              )}

              {formData.type === 'enum' && (
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    Available Options (one per line)
                  </label>
                  <textarea
                    value={formData.validation_rules?.enum_values?.join('\n') || ''}
                    onChange={(e) => handleEnumValuesChange(e.target.value)}
                    className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                    rows={4}
                    placeholder="basic&#10;standard&#10;premium"
                  />
                </div>
              )}
            </div>
          )}
        </form>

        <div className="px-6 py-4 border-t border-theme flex justify-end gap-3">
          <Button onClick={onClose} type="button" variant="outline">
            Cancel
          </Button>
          <Button onClick={handleSubmit} variant="primary">
            <Save className="w-4 h-4" />
            {feature ? 'Update Feature' : 'Create Feature'}
          </Button>
        </div>
      </div>
    </div>
  );
};
