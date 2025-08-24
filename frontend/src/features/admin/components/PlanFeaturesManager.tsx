import React, { useState, useEffect, useCallback } from 'react';
import { Button } from '@/shared/components/ui/Button';
import { 
  Plus, Edit, Trash2, Save, X, Settings, Filter,
  CheckCircle, AlertTriangle, Eye, Download
} from 'lucide-react';
import { 
  planFeaturesApi, 
  PlanFeature, 
  Plan, 
  PlanLimit, 
  FeatureFormData,
  LimitFormData,
  PlanComparison
} from '@/shared/services/planFeaturesApi';
import { useNotification } from '@/shared/hooks/useNotification';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';

interface PlanFeaturesManagerProps {
  showComparison?: boolean;
  allowEditing?: boolean;
}

interface FeatureModalProps {
  isOpen: boolean;
  feature?: PlanFeature;
  onClose: () => void;
  onSave: (data: FeatureFormData) => void;
}

interface LimitModalProps {
  isOpen: boolean;
  plan: Plan;
  feature: PlanFeature;
  currentLimit?: PlanLimit;
  onClose: () => void;
  onSave: (data: LimitFormData) => void;
}

const FeatureModal: React.FC<FeatureModalProps> = ({ isOpen, feature, onClose, onSave }) => {
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
                onChange={(e) => setFormData(prev => ({ ...prev, category: e.target.value as any }))}
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
                  type: e.target.value as any,
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
                  value={formData.default_value.toString()}
                  onChange={(e) => setFormData(prev => ({ ...prev, default_value: e.target.value === 'true' }))}
                  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                >
                  <option value="false">Disabled</option>
                  <option value="true">Enabled</option>
                </select>
              ) : formData.type === 'numeric' ? (
                <input
                  type="number"
                  value={formData.default_value}
                  onChange={(e) => setFormData(prev => ({ ...prev, default_value: parseInt(e.target.value) || 0 }))}
                  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                />
              ) : (
                <input
                  type="text"
                  value={formData.default_value}
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

const LimitModal: React.FC<LimitModalProps> = ({ isOpen, plan, feature, currentLimit, onClose, onSave }) => {
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
                      value={formData.value || ''}
                      onChange={(e) => setFormData(prev => ({ ...prev, value: parseInt(e.target.value) || 0 }))}
                      className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                      min={feature.validation_rules?.min}
                      max={feature.validation_rules?.max}
                    />
                  ) : feature.type === 'enum' ? (
                    <select
                      value={formData.value || ''}
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
                      value={formData.value || ''}
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

export const PlanFeaturesManager: React.FC<PlanFeaturesManagerProps> = ({
  showComparison = true,
  allowEditing = true
}) => {
  const [features, setFeatures] = useState<PlanFeature[]>([]);
  const [plans, setPlans] = useState<Plan[]>([]);
  const [comparison, setComparison] = useState<PlanComparison | null>(null);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<'features' | 'limits' | 'comparison'>('features');
  const [selectedPlan, setSelectedPlan] = useState<string>('');
  
  // Modals
  const [featureModal, setFeatureModal] = useState<{ isOpen: boolean; feature?: PlanFeature }>({ isOpen: false });
  const [limitModal, setLimitModal] = useState<{
    isOpen: boolean;
    plan?: Plan;
    feature?: PlanFeature;
    currentLimit?: PlanLimit;
  }>({ isOpen: false });

  const { showNotification } = useNotification();

  const loadData = useCallback(async () => {
    try {
      setLoading(true);
      const [featuresResponse, plansResponse, comparisonResponse] = await Promise.all([
        planFeaturesApi.getFeatures(),
        planFeaturesApi.getPlans(),
        showComparison ? planFeaturesApi.getComparison() : Promise.resolve({ success: false, error: 'Comparison disabled' })
      ]);

      if (featuresResponse.success) {
        setFeatures(featuresResponse.data!);
      }
      if (plansResponse.success) {
        setPlans(plansResponse.data!);
        if (plansResponse.data!.length > 0 && !selectedPlan) {
          setSelectedPlan(plansResponse.data![0].id);
        }
      }
      if (comparisonResponse.success && 'data' in comparisonResponse && comparisonResponse.data) {
        setComparison(comparisonResponse.data);
      }
    } catch (error) {
      console.error('Failed to load plan features data:', error);
      showNotification('Failed to load plan features data', 'error');
    } finally {
      setLoading(false);
    }
  }, [showComparison, selectedPlan, showNotification]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  const handleCreateFeature = async (data: FeatureFormData) => {
    try {
      const response = await planFeaturesApi.createFeature(data);
      if (response.success) {
        setFeatures(prev => [...prev, response.data!]);
        showNotification('Feature created successfully', 'success');
        loadData(); // Reload to get updated comparison
      } else {
        showNotification(response.error || 'Failed to create feature', 'error');
      }
    } catch (error) {
      showNotification('Failed to create feature', 'error');
    }
  };

  const handleUpdateFeature = async (featureId: string, data: Partial<FeatureFormData>) => {
    try {
      const response = await planFeaturesApi.updateFeature(featureId, data);
      if (response.success) {
        setFeatures(prev => prev.map(f => f.id === featureId ? response.data! : f));
        showNotification('Feature updated successfully', 'success');
        loadData(); // Reload to get updated comparison
      } else {
        showNotification(response.error || 'Failed to update feature', 'error');
      }
    } catch (error) {
      showNotification('Failed to update feature', 'error');
    }
  };

  const handleDeleteFeature = async (featureId: string) => {
    if (!window.confirm('Are you sure you want to delete this feature? This will remove it from all plans.')) {
      return;
    }

    try {
      const response = await planFeaturesApi.deleteFeature(featureId);
      if (response.success) {
        setFeatures(prev => prev.filter(f => f.id !== featureId));
        showNotification('Feature deleted successfully', 'success');
        loadData(); // Reload to get updated comparison
      } else {
        showNotification(response.error || 'Failed to delete feature', 'error');
      }
    } catch (error) {
      showNotification('Failed to delete feature', 'error');
    }
  };

  const handleUpdateLimit = async (planId: string, featureId: string, data: LimitFormData) => {
    try {
      const response = await planFeaturesApi.updatePlanLimit(planId, featureId, data);
      if (response.success) {
        // Update the plans state
        setPlans(prev => prev.map(plan => {
          if (plan.id === planId) {
            const updatedLimits = plan.limits.filter(l => l.feature_id !== featureId);
            if (data.is_enabled) {
              updatedLimits.push(response.data!);
            }
            return { ...plan, limits: updatedLimits };
          }
          return plan;
        }));
        showNotification('Plan limit updated successfully', 'success');
        loadData(); // Reload to get updated comparison
      } else {
        showNotification(response.error || 'Failed to update plan limit', 'error');
      }
    } catch (error) {
      showNotification('Failed to update plan limit', 'error');
    }
  };

  const groupFeaturesByCategory = (features: PlanFeature[]) => {
    const allowedCategories: Array<PlanFeature['category']> = ['core', 'advanced', 'integrations', 'support', 'analytics'];
    const groups: Record<string, PlanFeature[]> = {};
    
    features.forEach(feature => {
      const category = feature.category;
      
      if (allowedCategories.includes(category)) {
        if (category === 'core') {
          groups.core = groups.core || [];
          groups.core.push(feature);
        } else if (category === 'advanced') {
          groups.advanced = groups.advanced || [];
          groups.advanced.push(feature);
        } else if (category === 'integrations') {
          groups.integrations = groups.integrations || [];
          groups.integrations.push(feature);
        } else if (category === 'support') {
          groups.support = groups.support || [];
          groups.support.push(feature);
        } else if (category === 'analytics') {
          groups.analytics = groups.analytics || [];
          groups.analytics.push(feature);
        }
      }
    });
    
    return groups;
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  const selectedPlanData = plans.find(p => p.id === selectedPlan);
  const groupedFeatures = groupFeaturesByCategory(features);

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row gap-4 justify-between items-start sm:items-center">
        <div>
          <h2 className="text-2xl font-bold text-theme-primary">Plan Features & Limits</h2>
          <p className="text-theme-secondary">Configure feature availability and limits for subscription plans</p>
        </div>
        
        {allowEditing && (
          <Button variant="outline" onClick={() => setFeatureModal({ isOpen: true })}
            className="px-4 py-2 bg-theme-interactive-primary text-white rounded-md hover:bg-theme-interactive-primary-hover flex items-center gap-2"
          >
            <Plus className="w-4 h-4" />
            Add Feature
          </Button>
        )}
      </div>

      {/* Tab Navigation */}
      <div className="border-b border-theme">
        <nav className="flex space-x-8">
          {[
            { id: 'features', label: 'Features', icon: Settings },
            { id: 'limits', label: 'Plan Limits', icon: Filter },
            ...(showComparison ? [{ id: 'comparison', label: 'Comparison', icon: Eye }] : [])
          ].map(tab => {
            const Icon = tab.icon;
            return (
              <Button variant="outline" onClick={() => setActiveTab(tab.id as any)}
                className={`flex items-center gap-2 py-3 px-1 border-b-2 font-medium text-sm ${
                  activeTab === tab.id
                    ? 'border-theme-interactive-primary text-theme-interactive-primary'
                    : 'border-transparent text-theme-secondary hover:text-theme-primary'
                }`}
              >
                <Icon className="w-4 h-4" />
                {tab.label}
              </Button>
            );
          })}
        </nav>
      </div>

      {/* Tab Content */}
      {activeTab === 'features' && (
        <div className="space-y-6">
          {Object.entries(groupedFeatures).map(([category, categoryFeatures]) => (
            <div key={category} className="bg-theme-surface rounded-lg border border-theme">
              <div className="px-6 py-4 border-b border-theme">
                <div className="flex items-center gap-3">
                  <span className="text-2xl">{planFeaturesApi.getCategoryIcon(category)}</span>
                  <h3 className="text-lg font-semibold text-theme-primary capitalize">
                    {category.replace('_', ' ')} Features
                  </h3>
                  <span className={`px-2 py-1 rounded-full text-xs font-medium ${planFeaturesApi.getCategoryColor(category)}`}>
                    {categoryFeatures.length} feature{categoryFeatures.length !== 1 ? 's' : ''}
                  </span>
                </div>
              </div>

              <div className="divide-y divide-theme">
                {categoryFeatures.map(feature => (
                  <div key={feature.id} className="px-6 py-4">
                    <div className="flex items-center justify-between">
                      <div className="flex-1">
                        <div className="flex items-center gap-3 mb-2">
                          <span className="text-lg">{planFeaturesApi.getTypeIcon(feature.type)}</span>
                          <h4 className="font-medium text-theme-primary">{feature.name}</h4>
                          <span className={`px-2 py-1 rounded-full text-xs ${planFeaturesApi.getCategoryColor(feature.category)}`}>
                            {feature.type}
                          </span>
                          {feature.is_system_feature && (
                            <span className="px-2 py-1 rounded-full text-xs bg-theme-warning bg-opacity-10 text-theme-warning">
                              System
                            </span>
                          )}
                        </div>
                        <p className="text-sm text-theme-secondary mb-2">{feature.description}</p>
                        <p className="text-xs text-theme-secondary">
                          Default: {planFeaturesApi.formatFeatureValue(feature, feature.default_value)}
                        </p>
                      </div>
                      
                      {allowEditing && !feature.is_system_feature && (
                        <div className="flex items-center gap-2">
                          <Button variant="outline" onClick={() => setFeatureModal({ isOpen: true, feature })}
                            className="p-2 text-theme-secondary hover:text-theme-primary transition-colors"
                            title="Edit feature"
                          >
                            <Edit className="w-4 h-4" />
                          </Button>
                          <Button variant="outline" onClick={() => handleDeleteFeature(feature.id)}
                            className="p-2 text-theme-secondary hover:text-theme-error transition-colors"
                            title="Delete feature"
                          >
                            <Trash2 className="w-4 h-4" />
                          </Button>
                        </div>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      )}

      {activeTab === 'limits' && (
        <div className="space-y-6">
          {/* Plan Selector */}
          <div className="bg-theme-surface rounded-lg border border-theme p-6">
            <div className="flex items-center gap-4">
              <label className="text-sm font-medium text-theme-primary">Select Plan:</label>
              <select
                value={selectedPlan}
                onChange={(e) => setSelectedPlan(e.target.value)}
                className="px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
              >
                {plans.map(plan => (
                  <option key={plan.id} value={plan.id}>
                    {plan.name} ({planFeaturesApi.formatPrice(plan.price_cents)}/{plan.billing_interval})
                  </option>
                ))}
              </select>
            </div>
          </div>

          {/* Plan Limits */}
          {selectedPlanData && Object.entries(groupedFeatures).map(([category, categoryFeatures]) => (
            <div key={category} className="bg-theme-surface rounded-lg border border-theme">
              <div className="px-6 py-4 border-b border-theme">
                <div className="flex items-center gap-3">
                  <span className="text-2xl">{planFeaturesApi.getCategoryIcon(category)}</span>
                  <h3 className="text-lg font-semibold text-theme-primary capitalize">
                    {category.replace('_', ' ')} Limits
                  </h3>
                </div>
              </div>

              <div className="divide-y divide-theme">
                {categoryFeatures.map(feature => {
                  const currentLimit = selectedPlanData.limits.find(l => l.feature_id === feature.id);
                  
                  return (
                    <div key={feature.id} className="px-6 py-4">
                      <div className="flex items-center justify-between">
                        <div className="flex-1">
                          <div className="flex items-center gap-3 mb-2">
                            <span className="text-lg">{planFeaturesApi.getTypeIcon(feature.type)}</span>
                            <h4 className="font-medium text-theme-primary">{feature.name}</h4>
                            {currentLimit ? (
                              currentLimit.is_unlimited ? (
                                <span className="px-2 py-1 rounded-full text-xs bg-theme-success bg-opacity-10 text-theme-success">
                                  Unlimited
                                </span>
                              ) : currentLimit.is_enabled ? (
                                <span className="px-2 py-1 rounded-full text-xs bg-theme-info bg-opacity-10 text-theme-info">
                                  {planFeaturesApi.formatFeatureValue(feature, currentLimit.value)}
                                </span>
                              ) : (
                                <span className="px-2 py-1 rounded-full text-xs bg-theme-error bg-opacity-10 text-theme-error">
                                  Disabled
                                </span>
                              )
                            ) : (
                              <span className="px-2 py-1 rounded-full text-xs bg-theme-surface text-theme-secondary">
                                Not configured
                              </span>
                            )}
                          </div>
                          <p className="text-sm text-theme-secondary">{feature.description}</p>
                        </div>
                        
                        {allowEditing && (
                          <Button variant="outline" onClick={() => setLimitModal({
                              isOpen: true,
                              plan: selectedPlanData,
                              feature,
                              currentLimit
                            })}
                            className="px-3 py-1 text-sm border border-theme text-theme-primary rounded-md hover:bg-theme-surface transition-colors"
                          >
                            Configure
                          </Button>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      )}

      {activeTab === 'comparison' && comparison && (
        <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden">
          <div className="px-6 py-4 border-b border-theme">
            <div className="flex items-center justify-between">
              <h3 className="text-lg font-semibold text-theme-primary">Plan Comparison</h3>
              <Button variant="outline" onClick={() => {/* TODO: Export comparison */}}
                className="px-3 py-1 text-sm border border-theme text-theme-primary rounded-md hover:bg-theme-surface transition-colors flex items-center gap-2"
              >
                <Download className="w-4 h-4" />
                Export
              </Button>
            </div>
          </div>

          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-theme-background">
                <tr>
                  <th className="px-6 py-3 text-left text-sm font-medium text-theme-primary">Feature</th>
                  {comparison.plans.map(({ plan }) => (
                    <th key={plan.id} className="px-6 py-3 text-center text-sm font-medium text-theme-primary">
                      <div>
                        <div className="font-semibold">{plan.name}</div>
                        <div className="text-xs text-theme-secondary">
                          {planFeaturesApi.formatPrice(plan.price_cents)}/{plan.billing_interval}
                        </div>
                      </div>
                    </th>
                  ))}
                </tr>
              </thead>
              <tbody className="divide-y divide-theme">
                {comparison.features.map(feature => (
                  <tr key={feature.id}>
                    <td className="px-6 py-4">
                      <div className="flex items-center gap-3">
                        <span className="text-lg">{planFeaturesApi.getTypeIcon(feature.type)}</span>
                        <div>
                          <div className="font-medium text-theme-primary">{feature.name}</div>
                          <div className="text-xs text-theme-secondary">{feature.description}</div>
                        </div>
                      </div>
                    </td>
                    {comparison.plans.map(({ plan, feature_values }) => {
                      const value = feature_values[feature.id];
                      return (
                        <td key={plan.id} className="px-6 py-4 text-center">
                          {value !== undefined ? (
                            value === 'unlimited' ? (
                              <span className="inline-flex items-center gap-1 px-2 py-1 rounded-full text-xs bg-theme-success bg-opacity-10 text-theme-success">
                                <CheckCircle className="w-3 h-3" />
                                Unlimited
                              </span>
                            ) : value === null || value === false ? (
                              <span className="text-theme-error">
                                <X className="w-4 h-4 mx-auto" />
                              </span>
                            ) : (
                              <span className="font-medium text-theme-primary">
                                {planFeaturesApi.formatFeatureValue(feature, value)}
                              </span>
                            )
                          ) : (
                            <span className="text-theme-secondary">-</span>
                          )}
                        </td>
                      );
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Modals */}
      <FeatureModal
        isOpen={featureModal.isOpen}
        feature={featureModal.feature}
        onClose={() => setFeatureModal({ isOpen: false })}
        onSave={featureModal.feature ? 
          (data) => handleUpdateFeature(featureModal.feature!.id, data) :
          handleCreateFeature
        }
      />

      {limitModal.plan && limitModal.feature && (
        <LimitModal
          isOpen={limitModal.isOpen}
          plan={limitModal.plan}
          feature={limitModal.feature}
          currentLimit={limitModal.currentLimit}
          onClose={() => setLimitModal({ isOpen: false })}
          onSave={(data) => handleUpdateLimit(limitModal.plan!.id, limitModal.feature!.id, data)}
        />
      )}
    </div>
  );
};

export default PlanFeaturesManager;