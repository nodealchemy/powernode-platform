import React, { useState, useEffect } from 'react';
import { plansApi, DetailedPlan, PlanFormData } from '@/features/plans/services/plansApi';
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

  const handleInputChange = (field: string, value: any) => {
    setFormData(prev => ({ ...prev, [field]: value }));
  };

  const handleDiscountChange = (field: string, value: any) => {
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
    } catch (error: any) {
      console.error('Failed to save plan:', error);
      const errorMsg = error?.response?.data?.error || error?.message || 'Failed to save plan';
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

              {/* Tab Navigation */}
              <div className="border-b border-theme mb-6">
                <nav className="-mb-px flex space-x-8">
                  {[
                    { id: 'basic', label: 'Basic Info' },
                    { id: 'features', label: 'Features & Limits' },
                    { id: 'discounts', label: 'Discounts' }
                  ].map((tab) => (
                    <Button variant="outline" onClick={() => setActiveTab(tab.id as any)}
                      className={`py-2 px-1 border-b-2 font-medium text-sm ${
                        activeTab === tab.id
                          ? 'border-theme-interactive-primary text-theme-interactive-primary'
                          : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme'
                      }`}
                    >
                      {tab.label}
                    </Button>
                  ))}
                </nav>
              </div>

              <form onSubmit={handleSubmit}>
                {/* Basic Info Tab */}
                {activeTab === 'basic' && (
                  <div className="space-y-4">
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
                )}

                {/* Features Tab */}
                {activeTab === 'features' && (
                  <div className="space-y-6">
                    <p className="text-sm text-theme-secondary">
                      Configure features, limits, and default roles for this plan.
                    </p>
                    {/* Features configuration would go here - simplified for this example */}
                    <div>
                      <label className="label-theme">
                        Features & Limits Configuration
                      </label>
                      <p className="text-sm text-theme-secondary">
                        Advanced feature configuration coming soon...
                      </p>
                    </div>
                  </div>
                )}

                {/* Discounts Tab */}
                {activeTab === 'discounts' && (
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
                )}

              </form>
      </div>
    </Modal>
  );
};