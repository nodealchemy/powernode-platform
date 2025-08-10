import React, { useState, useEffect } from 'react';
import { XMarkIcon } from '@heroicons/react/24/outline';
import { plansApi, DetailedPlan, PlanFormData } from '../../services/plansApi';
import { PlanDiscountConfig } from './PlanDiscountConfig';

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
    default_roles: [],
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
        default_roles: plan.default_roles || [],
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
        default_roles: [],
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

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto">
      <div className="flex items-end justify-center min-h-screen pt-4 px-4 pb-20 text-center sm:block sm:p-0">
        <div className="fixed inset-0 bg-black bg-opacity-50 transition-opacity" onClick={onClose}></div>

        <span className="hidden sm:inline-block sm:align-middle sm:h-screen" aria-hidden="true">&#8203;</span>

        <div className="relative inline-block align-bottom card-theme rounded-lg px-4 pt-5 pb-4 text-left overflow-hidden shadow-xl transform transition-all sm:my-8 sm:align-middle sm:max-w-4xl sm:w-full sm:p-6">
          <div className="absolute top-0 right-0 pt-4 pr-4">
            <button
              type="button"
              className="bg-theme-background-secondary hover:bg-theme-background-muted rounded-md text-theme-tertiary hover:text-theme-secondary p-1 transition-colors"
              onClick={onClose}
            >
              <XMarkIcon className="h-6 w-6" />
            </button>
          </div>

          <div className="sm:flex sm:items-start">
            <div className="w-full mt-3 sm:mt-0 sm:text-left">
              <h3 className="text-lg leading-6 font-medium text-theme-primary mb-6">
                {isEditing ? 'Edit Plan' : 'Create New Plan'}
              </h3>

              {/* Tab Navigation */}
              <div className="border-b border-theme mb-6">
                <nav className="-mb-px flex space-x-8">
                  {[
                    { id: 'basic', label: 'Basic Info' },
                    { id: 'features', label: 'Features & Limits' },
                    { id: 'discounts', label: 'Discounts' }
                  ].map((tab) => (
                    <button
                      key={tab.id}
                      onClick={() => setActiveTab(tab.id as any)}
                      className={`py-2 px-1 border-b-2 font-medium text-sm ${
                        activeTab === tab.id
                          ? 'border-blue-500 text-blue-600'
                          : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme'
                      }`}
                    >
                      {tab.label}
                    </button>
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
                          className="h-4 w-4 text-blue-600 rounded border-gray-300"
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

                {/* Form Actions */}
                <div className="mt-8 flex justify-end space-x-3">
                  <button
                    type="button"
                    onClick={onClose}
                    disabled={loading}
                    className="btn-theme btn-theme-secondary"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    disabled={loading}
                    className="btn-theme btn-theme-primary"
                  >
                    {loading ? (
                      <div className="flex items-center">
                        <div className="animate-spin h-4 w-4 border-2 border-white border-t-transparent rounded-full mr-2" />
                        {isEditing ? 'Updating...' : 'Creating...'}
                      </div>
                    ) : (
                      isEditing ? 'Update Plan' : 'Create Plan'
                    )}
                  </button>
                </div>
              </form>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};