import React, { useState, useEffect } from 'react';
import { plansApi, DetailedPlan, PlanFormData } from '@enterprise/features/business/plans/services/plansApi';
import { PlanDiscountConfig } from './PlanDiscountConfig';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Package, Save } from 'lucide-react';

interface PlanFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSaved: () => void;
  plan?: DetailedPlan | null;
  showSuccess: (message: string) => void;
  showError: (message: string) => void;
}

export const PlanFormModal: React.FC<PlanFormModalProps> = ({
  isOpen,
  onClose,
  onSaved,
  plan,
  showSuccess,
  showError
}) => {
  const [loading, setLoading] = useState(false);
  const [activeTab, setActiveTab] = useState<'basic' | 'features' | 'discounts'>('basic');

  // Enhanced keyboard navigation for tabs
  const handleTabKeyDown = (e: React.KeyboardEvent, tabId: 'basic' | 'features' | 'discounts') => {
    const tabs = ['basic', 'features', 'discounts'];
    const currentIndex = tabs.indexOf(activeTab);
    
    switch (e.key) {
      case 'Enter':
      case ' ':
        e.preventDefault();
        setActiveTab(tabId);
        break;
      case 'ArrowLeft': {
        e.preventDefault();
        const prevIndex = currentIndex > 0 ? currentIndex - 1 : tabs.length - 1;
        setActiveTab(tabs[prevIndex] as 'basic' | 'features' | 'discounts');
        break;
      }
      case 'ArrowRight': {
        e.preventDefault();
        const nextIndex = currentIndex < tabs.length - 1 ? currentIndex + 1 : 0;
        setActiveTab(tabs[nextIndex] as 'basic' | 'features' | 'discounts');
        break;
      }
      case 'Home':
        e.preventDefault();
        setActiveTab('basic');
        break;
      case 'End':
        e.preventDefault();
        setActiveTab('discounts');
        break;
    }
  };
  const [formData, setFormData] = useState<PlanFormData>({
    name: '',
    description: '',
    price_cents: 0,
    currency: 'USD',
    billing_cycle: 'monthly',
    status: 'active',
    trial_days: 14,
    is_public: true,
    features: plansApi.getDefaultFeatures(),
    limits: plansApi.getDefaultLimits(),
    default_role: 'member',
    metadata: {},
    stripe_price_id: '',
    paypal_plan_id: '',
    // Discount defaults
    has_annual_discount: false,
    annual_discount_percent: 0,
    has_volume_discount: false,
    volume_discount_tiers: [],
    has_promotional_discount: false,
    promotional_discount_percent: 0,
    promotional_discount_start: '',
    promotional_discount_end: '',
    promotional_discount_code: ''
  });

  const isEditing = Boolean(plan);

  useEffect(() => {
    if (isOpen && plan) {
      setFormData({
        name: plan.name,
        description: plan.description,
        price_cents: plan.price_cents,
        currency: plan.currency,
        billing_cycle: plan.billing_cycle,
        status: plan.status,
        trial_days: plan.trial_days,
        is_public: plan.is_public,
        features: plan.features || plansApi.getDefaultFeatures(),
        limits: plan.limits || plansApi.getDefaultLimits(),
        default_role: plan.default_role || 'member',
        metadata: plan.metadata || {},
        stripe_price_id: plan.stripe_price_id || '',
        paypal_plan_id: plan.paypal_plan_id || '',
        // Discount fields
        has_annual_discount: plan.has_annual_discount || false,
        annual_discount_percent: plan.annual_discount_percent || 0,
        has_volume_discount: plan.has_volume_discount || false,
        volume_discount_tiers: plan.volume_discount_tiers || [],
        has_promotional_discount: plan.has_promotional_discount || false,
        promotional_discount_percent: plan.promotional_discount_percent || 0,
        promotional_discount_start: plan.promotional_discount_start || '',
        promotional_discount_end: plan.promotional_discount_end || '',
        promotional_discount_code: plan.promotional_discount_code || ''
      });
    } else if (isOpen && !plan) {
      // Reset form for new plan
      setFormData({
        name: '',
        description: '',
        price_cents: 0,
        currency: 'USD',
        billing_cycle: 'monthly',
        status: 'active',
        trial_days: 14,
        is_public: true,
        features: plansApi.getDefaultFeatures(),
        limits: plansApi.getDefaultLimits(),
        default_role: 'member',
        metadata: {},
        stripe_price_id: '',
        paypal_plan_id: '',
        // Discount defaults
        has_annual_discount: false,
        annual_discount_percent: 0,
        has_volume_discount: false,
        volume_discount_tiers: [],
        has_promotional_discount: false,
        promotional_discount_percent: 0,
        promotional_discount_start: '',
        promotional_discount_end: '',
        promotional_discount_code: ''
      });
    }
  }, [isOpen, plan]);

  const handleInputChange = (field: string, value: string | number | boolean) => {
    setFormData(prev => ({ ...prev, [field]: value }));
  };

  const handleDiscountChange = (field: string, value: string | number | boolean | readonly unknown[]) => {
    setFormData(prev => ({ ...prev, [field]: value }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    try {
      setLoading(true);
      
      if (isEditing && plan) {
        await plansApi.updatePlan(plan.id, formData);
        showSuccess('Plan updated successfully');
      } else {
        await plansApi.createPlan(formData);
        showSuccess('Plan created successfully');
      }
      
      onSaved();
      onClose();
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : 'Failed to save plan';
      showError(errorMsg);
    } finally {
      setLoading(false);
    }
  };

  const modalFooter = (
    <div className="flex justify-end space-x-3">
      <Button
        variant="secondary"
        onClick={onClose}
        disabled={loading}
      >
        Cancel
      </Button>
      <Button
        variant="primary"
        onClick={handleSubmit}
        loading={loading}
      >
        {!loading && <Save className="w-4 h-4 mr-2" />}
        {loading ? (isEditing ? 'Updating...' : 'Creating...') : (isEditing ? 'Update Plan' : 'Create Plan')}
      </Button>
    </div>
  );

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={isEditing ? 'Edit Plan' : 'Create New Plan'}
      subtitle={isEditing ? 'Update subscription plan details' : 'Define a new subscription plan'}
      icon={<Package />}
      maxWidth="4xl"
      footer={modalFooter}
      closeOnBackdrop={!loading}
      closeOnEscape={!loading}
    >
      <div className="w-full">

        {/* Tab Navigation - Standardized Design matching Plans List */}
        <div className="mb-6">
          <nav className="flex space-x-4 sm:space-x-6 lg:space-x-8 border-b border-theme overflow-x-auto scrollbar-hide" role="tablist" aria-label="Plan configuration sections">
            {[
              { id: 'basic', label: 'Basic Info', icon: '📝', description: 'Plan details and pricing' },
              { id: 'features', label: 'Features & Limits', icon: '⚡', description: 'Available features and usage limits' },
              { id: 'discounts', label: 'Discounts', icon: '🏷️', description: 'Promotional and volume discounts' }
            ].map((tab) => (
              <button
                key={tab.id}
                type="button"
                role="tab"
                aria-selected={activeTab === tab.id}
                aria-controls={`${tab.id}-panel`}
                aria-describedby={`${tab.id}-description`}
                tabIndex={activeTab === tab.id ? 0 : -1}
                onClick={() => setActiveTab(tab.id as 'basic' | 'features' | 'discounts')}
                onKeyDown={(e) => handleTabKeyDown(e, tab.id as 'basic' | 'features' | 'discounts')}
                className={`
                  flex items-center space-x-2 font-medium
                  text-sm py-2 px-4 cursor-pointer
                  border-b-2 -mb-px
                  ${activeTab === tab.id
                    ? 'border-theme-interactive-primary text-theme-interactive-primary'
                    : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme-border'
                  }
                `}
              >
                <span className="text-base" role="img" aria-hidden="true">{tab.icon}</span>
                <span>{tab.label}</span>
                
                {/* Tooltip for accessibility */}
                <div 
                  id={`${tab.id}-description`} 
                  className="sr-only"
                  aria-hidden="true"
                >
                  {tab.description}
                </div>
              </button>
            ))}
          </nav>
        </div>

        <form onSubmit={handleSubmit} className="space-y-6">
          {/* Basic Info Tab */}
          {activeTab === 'basic' && (
            <div 
              id="basic-panel"
              role="tabpanel" 
              aria-labelledby="basic-tab"
              className="space-y-6 animate-in fade-in-50"
            >
              <div className="card-theme p-6">
                <div className="flex items-center space-x-3 mb-6 pb-4 border-b border-theme-border">
                  <div className="w-10 h-10 bg-theme-interactive-primary rounded-lg flex items-center justify-center">
                    <span className="text-white text-xl" role="img" aria-label="Plan information">📝</span>
                  </div>
                  <div>
                    <h3 className="text-lg font-semibold text-theme-primary">Plan Information</h3>
                    <p className="text-sm text-theme-secondary">Configure basic plan details and pricing</p>
                  </div>
                </div>
                    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                      <div>
                        <label className="label-theme">
                          Plan Name *
                        </label>
                        <input
                          type="text"
                          required
                          value={formData.name}
                          onChange={(e) => handleInputChange('name', e.target.value)}
                          className="input-theme"
                          placeholder="e.g. Professional Plan"
                        />
                      </div>

                      <div>
                        <label className="label-theme">
                          Status
                        </label>
                        <select
                          value={formData.status}
                          onChange={(e) => handleInputChange('status', e.target.value)}
                          className="input-theme"
                        >
                          <option value="active">Active</option>
                          <option value="inactive">Inactive</option>
                          <option value="archived">Archived</option>
                        </select>
                      </div>
                    </div>

                    <div>
                      <label className="label-theme">
                        Description
                      </label>
                      <textarea
                        value={formData.description}
                        onChange={(e) => handleInputChange('description', e.target.value)}
                        className="input-theme"
                        rows={3}
                        placeholder="Describe what this plan includes..."
                      />
                    </div>

                    <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
                      <div>
                        <label className="label-theme">
                          Price (cents) *
                        </label>
                        <input
                          type="number"
                          required
                          min="0"
                          value={formData.price_cents}
                          onChange={(e) => handleInputChange('price_cents', parseInt(e.target.value))}
                          className="input-theme"
                          placeholder="2999"
                        />
                        <p className="text-xs text-theme-secondary mt-1">Enter price in cents (e.g., 2999 = $29.99)</p>
                      </div>

                      <div>
                        <label className="label-theme">
                          Currency
                        </label>
                        <select
                          value={formData.currency}
                          onChange={(e) => handleInputChange('currency', e.target.value)}
                          className="input-theme"
                        >
                          {plansApi.getAvailableCurrencies().map(curr => (
                            <option key={curr.value} value={curr.value}>
                              {curr.label}
                            </option>
                          ))}
                        </select>
                      </div>

                      <div>
                        <label className="label-theme">
                          Billing Cycle
                        </label>
                        <select
                          value={formData.billing_cycle}
                          onChange={(e) => handleInputChange('billing_cycle', e.target.value)}
                          className="input-theme"
                        >
                          {plansApi.getAvailableBillingCycles().map(cycle => (
                            <option key={cycle.value} value={cycle.value}>
                              {cycle.label}
                            </option>
                          ))}
                        </select>
                      </div>
                    </div>

                    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                      <div>
                        <label className="label-theme">
                          Trial Days
                        </label>
                        <input
                          type="number"
                          min="0"
                          max="365"
                          value={formData.trial_days}
                          onChange={(e) => handleInputChange('trial_days', parseInt(e.target.value))}
                          className="input-theme"
                        />
                      </div>

                      <div className="flex items-center mt-6">
                        <input
                          type="checkbox"
                          checked={formData.is_public}
                          onChange={(e) => handleInputChange('is_public', e.target.checked)}
                          className="h-4 w-4 text-theme-interactive-primary rounded border-theme"
                        />
                        <label className="ml-2 text-sm text-theme-primary">
                          Public plan (visible to new customers)
                        </label>
                      </div>
                    </div>
                  </div>
                </div>
            )}

          {/* Features Tab */}
          {activeTab === 'features' && (
            <div 
              id="features-panel"
              role="tabpanel" 
              aria-labelledby="features-tab"
              className="space-y-6 animate-in fade-in-50"
            >
              <div className="card-theme p-6">
                <div className="flex items-center space-x-3 mb-6 pb-4 border-b border-theme-border">
                  <div className="w-10 h-10 bg-theme-warning rounded-lg flex items-center justify-center">
                    <span className="text-white text-xl" role="img" aria-label="Features and limits">⚡</span>
                  </div>
                  <div>
                    <h3 className="text-lg font-semibold text-theme-primary">Features & Limits Configuration</h3>
                    <p className="text-sm text-theme-secondary">Define available features and usage quotas</p>
                  </div>
                </div>
                    
                {/* Core Features */}
                <div className="space-y-5">
                  <div className="flex items-center space-x-3 pb-3 border-b border-theme-border mt-6 mb-6">
                    <span className="text-lg font-semibold text-theme-primary flex items-center space-x-2">
                      <span className="text-xl" role="img" aria-label="Core features">⚡</span>
                      <span>Core Features</span>
                    </span>
                    <span className="badge-theme badge-theme-sm badge-theme-success">Essential</span>
                  </div>
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                        {Object.entries({
                          community_access: 'Community Access',
                          dashboard_access: 'Dashboard Access',
                          mobile_responsive: 'Mobile Responsive',
                          email_notifications: 'Email Notifications',
                          basic_reporting: 'Basic Reporting',
                          standard_support: 'Standard Support',
                          basic_analytics: 'Basic Analytics',
                          audit_logs: 'Audit Logs',
                        }).map(([key, label]) => (
                          <label key={key} className="flex items-center space-x-3">
                            <input
                              type="checkbox"
                              checked={formData.features[key] || false}
                              onChange={(e) => setFormData(prev => ({
                                ...prev,
                                features: { ...prev.features, [key]: e.target.checked }
                              }))}
                              className="w-4 h-4 text-theme-interactive-primary border-theme-border rounded focus:ring-theme-interactive-primary"
                            />
                            <span className="text-sm text-theme-primary">{label}</span>
                          </label>
                        ))}
                  </div>
                </div>

                {/* Advanced Features */}
                <div className="space-y-5">
                  <div className="flex items-center space-x-3 pb-3 border-b border-theme-border mt-6 mb-6">
                    <span className="text-lg font-semibold text-theme-primary flex items-center space-x-2">
                      <span className="text-xl" role="img" aria-label="Advanced features">🚀</span>
                      <span>Advanced Features</span>
                    </span>
                    <span className="badge-theme badge-theme-sm badge-theme-info">Professional</span>
                  </div>
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                        {Object.entries({
                          email_support: 'Email Support',
                          advanced_analytics: 'Advanced Analytics',
                          priority_support: 'Priority Support',
                          api_access: 'API Access',
                          custom_branding: 'Custom Branding',
                          data_export: 'Data Export',
                          team_collaboration: 'Team Collaboration',
                          webhook_integrations: 'Webhook Integrations',
                        }).map(([key, label]) => (
                          <label key={key} className="flex items-center space-x-3">
                            <input
                              type="checkbox"
                              checked={formData.features[key] || false}
                              onChange={(e) => setFormData(prev => ({
                                ...prev,
                                features: { ...prev.features, [key]: e.target.checked }
                              }))}
                              className="w-4 h-4 text-theme-interactive-primary border-theme-border rounded focus:ring-theme-interactive-primary"
                            />
                            <span className="text-sm text-theme-primary">{label}</span>
                          </label>
                        ))}
                  </div>
                </div>

                {/* Enterprise Features */}
                <div className="space-y-5">
                  <div className="flex items-center space-x-3 pb-3 border-b border-theme-border mt-6 mb-6">
                    <span className="text-lg font-semibold text-theme-primary flex items-center space-x-2">
                      <span className="text-xl" role="img" aria-label="Enterprise features">🏢</span>
                      <span>Enterprise Features</span>
                    </span>
                    <span className="badge-theme badge-theme-sm badge-theme-warning">Premium</span>
                  </div>
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                        {Object.entries({
                          custom_fields: 'Custom Fields',
                          advanced_filters: 'Advanced Filters',
                          custom_integrations: 'Custom Integrations',
                          dedicated_support: 'Dedicated Support',
                          white_label: 'White Label Solution',
                          sso_integration: 'Single Sign-On (SSO)',
                          advanced_security: 'Advanced Security',
                          sla_guarantees: 'SLA Guarantees',
                        }).map(([key, label]) => (
                          <label key={key} className="flex items-center space-x-3">
                            <input
                              type="checkbox"
                              checked={formData.features[key] || false}
                              onChange={(e) => setFormData(prev => ({
                                ...prev,
                                features: { ...prev.features, [key]: e.target.checked }
                              }))}
                              className="w-4 h-4 text-theme-interactive-primary border-theme-border rounded focus:ring-theme-interactive-primary"
                            />
                            <span className="text-sm text-theme-primary">{label}</span>
                          </label>
                        ))}
                  </div>
                </div>

                {/* Usage Limits */}
                <div className="space-y-5 pt-6">
                  <div className="flex items-center space-x-3 pb-3 border-b border-theme-border mt-0 mb-6">
                    <span className="text-lg font-semibold text-theme-primary flex items-center space-x-2">
                      <span className="text-xl" role="img" aria-label="Usage limits">📊</span>
                      <span>Usage Limits</span>
                    </span>
                    <span className="badge-theme badge-theme-sm badge-theme-secondary">Quotas</span>
                  </div>
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                    {/* Users Limit - EASILY IMPLEMENTABLE */}
                    <div>
                      <label className="label-theme">
                        Maximum Users per Account
                      </label>
                      <div className="flex items-center space-x-3">
                        <input
                          type="number"
                          min="1"
                          max="9999"
                          value={formData.limits?.max_users || 2}
                          onChange={(e) => setFormData(prev => ({
                            ...prev,
                            limits: { ...prev.limits, max_users: parseInt(e.target.value) || 2 }
                          }))}
                          className="input-theme flex-1"
                          disabled={loading || (formData.limits?.max_users || 0) >= 9999}
                        />
                        <label className="flex items-center">
                          <input
                            type="checkbox"
                            checked={(formData.limits?.max_users || 0) >= 9999}
                            onChange={(e) => setFormData(prev => ({
                              ...prev,
                              limits: { ...prev.limits, max_users: e.target.checked ? 9999 : 10 }
                            }))}
                            className="w-4 h-4 text-theme-success border-theme-border rounded focus:ring-theme-success"
                          />
                          <span className="ml-2 text-sm text-theme-secondary">Unlimited</span>
                        </label>
                      </div>
                    </div>
                    
                    {/* API Keys Limit - EASILY IMPLEMENTABLE */}
                    <div>
                      <label className="label-theme">
                        Maximum API Keys
                      </label>
                      <div className="flex items-center space-x-3">
                        <input
                          type="number"
                          min="1"
                          max="100"
                          value={formData.limits?.max_api_keys || 5}
                          onChange={(e) => setFormData(prev => ({
                            ...prev,
                            limits: { ...prev.limits, max_api_keys: parseInt(e.target.value) || 5 }
                          }))}
                          className="input-theme flex-1"
                          disabled={loading || (formData.limits?.max_api_keys || 0) >= 100}
                        />
                        <label className="flex items-center">
                          <input
                            type="checkbox"
                            checked={(formData.limits?.max_api_keys || 0) >= 100}
                            onChange={(e) => setFormData(prev => ({
                              ...prev,
                              limits: { ...prev.limits, max_api_keys: e.target.checked ? 100 : 25 }
                            }))}
                            className="w-4 h-4 text-theme-success border-theme-border rounded focus:ring-theme-success"
                          />
                          <span className="ml-2 text-sm text-theme-secondary">Unlimited</span>
                        </label>
                      </div>
                    </div>

                    {/* Webhooks Limit - EASILY IMPLEMENTABLE */}
                    <div>
                      <label className="label-theme">
                        Maximum Webhook Endpoints
                      </label>
                      <div className="flex items-center space-x-3">
                        <input
                          type="number"
                          min="1"
                          max="100"
                          value={formData.limits?.max_webhooks || 5}
                          onChange={(e) => setFormData(prev => ({
                            ...prev,
                            limits: { ...prev.limits, max_webhooks: parseInt(e.target.value) || 5 }
                          }))}
                          className="input-theme flex-1"
                          disabled={loading || (formData.limits?.max_webhooks || 0) >= 100}
                        />
                        <label className="flex items-center">
                          <input
                            type="checkbox"
                            checked={(formData.limits?.max_webhooks || 0) >= 100}
                            onChange={(e) => setFormData(prev => ({
                              ...prev,
                              limits: { ...prev.limits, max_webhooks: e.target.checked ? 100 : 25 }
                            }))}
                            className="w-4 h-4 text-theme-success border-theme-border rounded focus:ring-theme-success"
                          />
                          <span className="ml-2 text-sm text-theme-secondary">Unlimited</span>
                        </label>
                      </div>
                    </div>

                    {/* Workers Limit - EASILY IMPLEMENTABLE */}
                    <div>
                      <label className="label-theme">
                        Maximum Workers
                      </label>
                      <div className="flex items-center space-x-3">
                        <input
                          type="number"
                          min="1"
                          max="100"
                          value={formData.limits?.max_workers || 3}
                          onChange={(e) => setFormData(prev => ({
                            ...prev,
                            limits: { ...prev.limits, max_workers: parseInt(e.target.value) || 3 }
                          }))}
                          className="input-theme flex-1"
                          disabled={loading || (formData.limits?.max_workers || 0) >= 100}
                        />
                        <label className="flex items-center">
                          <input
                            type="checkbox"
                            checked={(formData.limits?.max_workers || 0) >= 100}
                            onChange={(e) => setFormData(prev => ({
                              ...prev,
                              limits: { ...prev.limits, max_workers: e.target.checked ? 100 : 20 }
                            }))}
                            className="w-4 h-4 text-theme-success border-theme-border rounded focus:ring-theme-success"
                          />
                          <span className="ml-2 text-sm text-theme-secondary">Unlimited</span>
                        </label>
                      </div>
                    </div>
                  </div>
                      
                  <div className="text-xs text-theme-tertiary bg-theme-background p-3 rounded-lg border border-theme-border">
                    💡 <strong>Tip:</strong> Features and limits determine what users can access and how much they can use. 
                    Core features are typically available in all plans, while advanced and enterprise features are for higher tiers.
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* Discounts Tab */}
          {activeTab === 'discounts' && (
            <div 
              id="discounts-panel"
              role="tabpanel" 
              aria-labelledby="discounts-tab"
              className="space-y-6 animate-in fade-in-50"
            >
              <div className="card-theme p-6">
                <div className="flex items-center space-x-3 mb-6 pb-4 border-b border-theme-border">
                  <div className="w-10 h-10 bg-theme-success rounded-lg flex items-center justify-center">
                    <span className="text-white text-xl" role="img" aria-label="Discount configuration">🏷️</span>
                  </div>
                  <div>
                    <h3 className="text-lg font-semibold text-theme-primary">Discount Configuration</h3>
                    <p className="text-sm text-theme-secondary">Set up promotional offers and volume pricing</p>
                  </div>
                </div>
                <PlanDiscountConfig
                    hasAnnualDiscount={formData.has_annual_discount}
                    annualDiscountPercent={formData.annual_discount_percent}
                    hasVolumeDiscount={formData.has_volume_discount}
                    volumeDiscountTiers={formData.volume_discount_tiers}
                    hasPromotionalDiscount={formData.has_promotional_discount}
                    promotionalDiscountPercent={formData.promotional_discount_percent}
                    promotionalDiscountStart={formData.promotional_discount_start}
                    promotionalDiscountEnd={formData.promotional_discount_end}
                    promotionalDiscountCode={formData.promotional_discount_code}
                  onDiscountChange={handleDiscountChange}
                  disabled={loading}
                />
              </div>
            </div>
          )}
        </form>
      </div>
    </Modal>
  );
};