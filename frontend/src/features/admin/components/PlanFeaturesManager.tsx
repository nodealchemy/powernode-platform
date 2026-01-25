import React, { useState, useEffect, useCallback } from 'react';
import { Button } from '@/shared/components/ui/Button';
import {
  Plus, Edit, Trash2, Settings, Filter,
  CheckCircle, X, Eye, Download
} from 'lucide-react';
import {
  planFeaturesApi,
  PlanFeature,
  Plan,
  PlanLimit,
  FeatureFormData,
  LimitFormData,
  PlanComparison
} from '@/shared/services/billing/planFeaturesApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { FeatureModal } from './FeatureModal';
import { LimitModal } from './LimitModal';

interface PlanFeaturesManagerProps {
  showComparison?: boolean;
  allowEditing?: boolean;
}

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

  const { showNotification } = useNotifications();

  const loadData = useCallback(async () => {
    try {
      setLoading(true);
      const [featuresResponse, plansResponse, comparisonResponse] = await Promise.all([
        planFeaturesApi.getFeatures(),
        planFeaturesApi.getPlans(),
        showComparison ? planFeaturesApi.getComparison() : Promise.resolve({ success: false, error: 'Comparison disabled' })
      ]);

      if (featuresResponse.success) {
        setFeatures(featuresResponse.data || []);
      }
      if (plansResponse.success) {
        setPlans(plansResponse.data || []);
        if (plansResponse.data && plansResponse.data.length > 0 && !selectedPlan) {
          setSelectedPlan(plansResponse.data[0].id);
        }
      }
      if (comparisonResponse.success && 'data' in comparisonResponse && comparisonResponse.data) {
        setComparison(comparisonResponse.data);
      }
    } catch (error) {
      // Error handled by notification
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
        if (response.data) {
          const newFeature = response.data;
          setFeatures(prev => [...prev, newFeature]);
        }
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
        if (response.data) {
          const updatedFeature = response.data;
          setFeatures(prev => prev.map(f => f.id === featureId ? updatedFeature : f));
        }
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
              if (response.data) {
                updatedLimits.push(response.data);
              }
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
              <Button variant="outline" onClick={() => setActiveTab(tab.id as 'features' | 'limits' | 'comparison')}
                key={tab.id}
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
          (data) => featureModal.feature ? handleUpdateFeature(featureModal.feature.id, data) : undefined :
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
          onSave={(data) => limitModal.plan && limitModal.feature ? handleUpdateLimit(limitModal.plan.id, limitModal.feature.id, data) : undefined}
        />
      )}
    </div>
  );
};
