import React, { useState, useEffect } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store';
import {
  plansApi,
  Plan,
  DetailedPlan,
  PlanFormData
} from '../../services/plansApi';

export const PlansPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const [plans, setPlans] = useState<Plan[]>([]);
  const [loading, setLoading] = useState(true);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showEditModal, setShowEditModal] = useState(false);
  const [selectedPlan, setSelectedPlan] = useState<DetailedPlan | null>(null);
  const [successMessage, setSuccessMessage] = useState('');
  const [errorMessage, setErrorMessage] = useState('');

  // Check if user has admin access
  const hasAdminAccess = user?.role === 'owner' || user?.role === 'admin';

  useEffect(() => {
    loadPlans();
  }, []);

  const loadPlans = async () => {
    try {
      setLoading(true);
      const response = await plansApi.getPlans();
      setPlans(response.data?.plans || []);
    } catch (error: any) {
      console.error('Failed to load plans:', error);
      const errorMsg = error?.response?.data?.error || error?.message || 'Failed to load plans';
      setErrorMessage(errorMsg);
    } finally {
      setLoading(false);
    }
  };

  const showSuccess = (message: string) => {
    setSuccessMessage(message);
    setErrorMessage('');
    setTimeout(() => setSuccessMessage(''), 3000);
  };

  const showError = (message: string) => {
    setErrorMessage(message);
    setSuccessMessage('');
    setTimeout(() => setErrorMessage(''), 5000);
  };

  const handleCreatePlan = () => {
    setSelectedPlan(null);
    setShowCreateModal(true);
  };

  const handleEditPlan = async (planId: string) => {
    try {
      const response = await plansApi.getPlan(planId);
      setSelectedPlan(response.data?.plan || null);
      setShowEditModal(true);
    } catch (error) {
      console.error('Failed to load plan details:', error);
      showError('Failed to load plan details');
    }
  };

  const handleDuplicatePlan = async (planId: string) => {
    try {
      await plansApi.duplicatePlan(planId);
      showSuccess('Plan duplicated successfully');
      loadPlans();
    } catch (error) {
      console.error('Failed to duplicate plan:', error);
      showError('Failed to duplicate plan');
    }
  };

  const handleToggleStatus = async (planId: string) => {
    try {
      await plansApi.togglePlanStatus(planId);
      showSuccess('Plan status updated successfully');
      loadPlans();
    } catch (error) {
      console.error('Failed to update plan status:', error);
      showError('Failed to update plan status');
    }
  };

  const handleDeletePlan = async (planId: string) => {
    if (!window.confirm('Are you sure you want to delete this plan? This action cannot be undone.')) {
      return;
    }

    try {
      await plansApi.deletePlan(planId);
      showSuccess('Plan deleted successfully');
      loadPlans();
    } catch (error) {
      console.error('Failed to delete plan:', error);
      showError('Failed to delete plan');
    }
  };

  const handlePlanSaved = () => {
    setShowCreateModal(false);
    setShowEditModal(false);
    setSelectedPlan(null);
    loadPlans();
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-600">Loading plans...</div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Plans Management</h1>
          <p className="text-gray-600">
            {hasAdminAccess 
              ? "Manage subscription plans and pricing tiers."
              : "View available subscription plans."
            }
          </p>
        </div>
        {hasAdminAccess && (
          <button
            onClick={handleCreatePlan}
            className="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition-colors duration-150"
          >
            Create Plan
          </button>
        )}
      </div>

      {successMessage && (
        <div className="bg-green-100 border border-green-400 text-green-700 px-4 py-3 rounded">
          {successMessage}
        </div>
      )}

      {errorMessage && (
        <div className="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded">
          {errorMessage}
        </div>
      )}

      {/* Plans Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
        {plans.map((plan) => (
          <div key={plan.id} className="bg-white rounded-lg shadow-md overflow-hidden">
            {/* Plan Header */}
            <div className="p-6 border-b border-gray-200">
              <div className="flex justify-between items-start mb-4">
                <h3 className="text-lg font-semibold text-gray-900">{plan.name}</h3>
                <span className={`px-2 py-1 text-xs font-medium rounded-full ${plansApi.getStatusColor(plan.status || 'inactive')}`}>
                  {(plan.status || 'inactive').charAt(0).toUpperCase() + (plan.status || 'inactive').slice(1)}
                </span>
              </div>
              
              <div className="mb-4">
                <div className="text-3xl font-bold text-gray-900">
                  {plan.formatted_price}
                </div>
                <div className="text-sm text-gray-500">
                  per {plan.billing_cycle ? plan.billing_cycle.slice(0, -2) : 'month'} {/* Remove 'ly' suffix */}
                </div>
                {plan.billing_cycle !== 'monthly' && (
                  <div className="text-xs text-gray-400">
                    ({plan.monthly_price}/month)
                  </div>
                )}
              </div>

              {plan.description && (
                <p className="text-gray-600 text-sm mb-4">{plan.description}</p>
              )}

              <div className="flex justify-between items-center text-sm text-gray-500">
                <span>{plan.subscription_count || 0} subscriptions</span>
                <span>{plan.active_subscription_count || 0} active</span>
              </div>
            </div>

            {/* Plan Actions */}
            {hasAdminAccess && (
              <div className="p-4 bg-gray-50 space-y-2">
                <div className="flex space-x-2">
                  <button
                    onClick={() => handleEditPlan(plan.id)}
                    className="flex-1 bg-blue-600 text-white px-3 py-1 rounded text-sm hover:bg-blue-700 transition-colors duration-150"
                  >
                    Edit
                  </button>
                  <button
                    onClick={() => handleDuplicatePlan(plan.id)}
                    className="flex-1 bg-gray-600 text-white px-3 py-1 rounded text-sm hover:bg-gray-700 transition-colors duration-150"
                  >
                    Duplicate
                  </button>
                </div>
                <div className="flex space-x-2">
                  <button
                    onClick={() => handleToggleStatus(plan.id)}
                    className={`flex-1 px-3 py-1 rounded text-sm transition-colors duration-150 ${
                      plan.status === 'active'
                        ? 'bg-yellow-600 text-white hover:bg-yellow-700'
                        : 'bg-green-600 text-white hover:bg-green-700'
                    }`}
                  >
                    {plan.status === 'active' ? 'Deactivate' : 'Activate'}
                  </button>
                  <button
                    onClick={() => handleDeletePlan(plan.id)}
                    disabled={plan.can_be_deleted === false}
                    className="flex-1 bg-red-600 text-white px-3 py-1 rounded text-sm hover:bg-red-700 transition-colors duration-150 disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    Delete
                  </button>
                </div>
              </div>
            )}

            {/* Plan Details for non-admin users */}
            {!hasAdminAccess && (
              <div className="p-4 bg-gray-50">
                <div className="flex justify-between items-center text-sm text-gray-500">
                  <span>Trial: {plan.trial_days} days</span>
                  <span className={`px-2 py-1 text-xs rounded ${plan.is_public ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-800'}`}>
                    {plan.is_public ? 'Public' : 'Private'}
                  </span>
                </div>
              </div>
            )}
          </div>
        ))}
      </div>

      {plans.length === 0 && (
        <div className="text-center py-12">
          <div className="text-gray-500 text-lg">No plans found</div>
          {hasAdminAccess && (
            <button
              onClick={handleCreatePlan}
              className="mt-4 bg-blue-600 text-white px-6 py-2 rounded-md hover:bg-blue-700 transition-colors duration-150"
            >
              Create Your First Plan
            </button>
          )}
        </div>
      )}

      {/* Create Plan Modal */}
      {showCreateModal && (
        <PlanFormModal
          isOpen={showCreateModal}
          onClose={() => setShowCreateModal(false)}
          onSave={handlePlanSaved}
          onSuccess={showSuccess}
          onError={showError}
        />
      )}

      {/* Edit Plan Modal */}
      {showEditModal && selectedPlan && (
        <PlanFormModal
          isOpen={showEditModal}
          onClose={() => setShowEditModal(false)}
          onSave={handlePlanSaved}
          onSuccess={showSuccess}
          onError={showError}
          plan={selectedPlan}
        />
      )}
    </div>
  );
};

// Plan Form Modal Component
interface PlanFormModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSave: () => void;
  onSuccess: (message: string) => void;
  onError: (message: string) => void;
  plan?: DetailedPlan;
}

const PlanFormModal: React.FC<PlanFormModalProps> = ({
  isOpen,
  onClose,
  onSave,
  onSuccess,
  onError,
  plan
}) => {
  const [formData, setFormData] = useState<PlanFormData>({
    name: '',
    description: '',
    price_cents: 0,
    currency: 'USD',
    billing_cycle: 'monthly',
    status: 'inactive',
    trial_days: 0,
    is_public: true,
    features: plansApi.getDefaultFeatures(),
    limits: plansApi.getDefaultLimits(),
    default_roles: [],
    metadata: {}
  });

  const [saving, setSaving] = useState(false);
  const [activeTab, setActiveTab] = useState('basic');

  useEffect(() => {
    if (plan) {
      setFormData({
        name: plan.name,
        description: plan.description,
        price_cents: plan.price_cents,
        currency: plan.currency,
        billing_cycle: plan.billing_cycle,
        status: plan.status,
        trial_days: plan.trial_days,
        is_public: plan.is_public,
        features: plan.features,
        limits: plan.limits,
        default_roles: plan.default_roles,
        metadata: plan.metadata,
        stripe_price_id: plan.stripe_price_id || undefined,
        paypal_plan_id: plan.paypal_plan_id || undefined
      });
    }
  }, [plan]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    const validationErrors = plansApi.validatePlanData(formData);
    if (validationErrors.length > 0) {
      onError(validationErrors.join(', '));
      return;
    }

    setSaving(true);
    try {
      if (plan) {
        await plansApi.updatePlan(plan.id, formData);
        onSuccess('Plan updated successfully');
      } else {
        await plansApi.createPlan(formData);
        onSuccess('Plan created successfully');
      }
      onSave();
    } catch (error) {
      console.error('Failed to save plan:', error);
      onError(`Failed to ${plan ? 'update' : 'create'} plan`);
    } finally {
      setSaving(false);
    }
  };

  const handleFeatureChange = (featureKey: string, enabled: boolean) => {
    setFormData({
      ...formData,
      features: {
        ...formData.features,
        [featureKey]: enabled
      }
    });
  };

  const handleLimitChange = (limitKey: string, value: number) => {
    setFormData({
      ...formData,
      limits: {
        ...formData.limits,
        [limitKey]: value
      }
    });
  };

  if (!isOpen) return null;

  const tabs = [
    { id: 'basic', name: 'Basic Info', icon: '📝' },
    { id: 'features', name: 'Features', icon: '✨' },
    { id: 'limits', name: 'Limits', icon: '📊' },
    { id: 'advanced', name: 'Advanced', icon: '⚙️' }
  ];

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-white rounded-lg shadow-xl max-w-4xl w-full mx-4 max-h-screen overflow-hidden">
        <div className="flex justify-between items-center p-6 border-b border-gray-200">
          <h2 className="text-xl font-semibold text-gray-900">
            {plan ? 'Edit Plan' : 'Create New Plan'}
          </h2>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-gray-500"
          >
            <svg className="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Tab Navigation */}
        <div className="border-b border-gray-200">
          <nav className="flex space-x-8 px-6">
            {tabs.map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`py-4 px-1 border-b-2 font-medium text-sm ${
                  activeTab === tab.id
                    ? 'border-blue-500 text-blue-600'
                    : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
                }`}
              >
                <span className="mr-2">{tab.icon}</span>
                {tab.name}
              </button>
            ))}
          </nav>
        </div>

        <form onSubmit={handleSubmit} className="p-6 max-h-96 overflow-y-auto">
          {/* Basic Info Tab */}
          {activeTab === 'basic' && (
            <div className="space-y-4">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Plan Name *
                  </label>
                  <input
                    type="text"
                    value={formData.name}
                    onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                    placeholder="e.g. Professional"
                    required
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Status
                  </label>
                  <select
                    value={formData.status}
                    onChange={(e) => setFormData({ ...formData, status: e.target.value as any })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                  >
                    <option value="active">Active</option>
                    <option value="inactive">Inactive</option>
                    <option value="archived">Archived</option>
                  </select>
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Description
                </label>
                <textarea
                  value={formData.description}
                  onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                  placeholder="Brief description of the plan features..."
                  rows={3}
                />
              </div>

              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Price (cents) *
                  </label>
                  <input
                    type="number"
                    min="0"
                    value={formData.price_cents}
                    onChange={(e) => setFormData({ ...formData, price_cents: parseInt(e.target.value) || 0 })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                    placeholder="2999"
                    required
                  />
                  <p className="text-xs text-gray-500 mt-1">
                    Price in cents (e.g., 2999 = $29.99)
                  </p>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Currency
                  </label>
                  <select
                    value={formData.currency}
                    onChange={(e) => setFormData({ ...formData, currency: e.target.value })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                  >
                    {plansApi.getAvailableCurrencies().map(currency => (
                      <option key={currency.value} value={currency.value}>
                        {currency.label}
                      </option>
                    ))}
                  </select>
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Billing Cycle
                  </label>
                  <select
                    value={formData.billing_cycle}
                    onChange={(e) => setFormData({ ...formData, billing_cycle: e.target.value as any })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                  >
                    {plansApi.getAvailableBillingCycles().map(cycle => (
                      <option key={cycle.value} value={cycle.value}>
                        {cycle.label}
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Trial Days
                  </label>
                  <input
                    type="number"
                    min="0"
                    max="365"
                    value={formData.trial_days}
                    onChange={(e) => setFormData({ ...formData, trial_days: parseInt(e.target.value) || 0 })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                  />
                </div>

                <div className="flex items-center">
                  <input
                    type="checkbox"
                    id="is_public"
                    checked={formData.is_public}
                    onChange={(e) => setFormData({ ...formData, is_public: e.target.checked })}
                    className="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
                  />
                  <label htmlFor="is_public" className="ml-2 block text-sm text-gray-900">
                    Public Plan (visible to customers)
                  </label>
                </div>
              </div>
            </div>
          )}

          {/* Features Tab */}
          {activeTab === 'features' && (
            <div className="space-y-4">
              <h3 className="text-lg font-medium text-gray-900 mb-4">Plan Features</h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {Object.entries(formData.features).map(([featureKey, enabled]) => (
                  <div key={featureKey} className="flex items-center">
                    <input
                      type="checkbox"
                      id={featureKey}
                      checked={enabled}
                      onChange={(e) => handleFeatureChange(featureKey, e.target.checked)}
                      className="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
                    />
                    <label htmlFor={featureKey} className="ml-2 block text-sm text-gray-900">
                      {featureKey.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())}
                    </label>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Limits Tab */}
          {activeTab === 'limits' && (
            <div className="space-y-4">
              <h3 className="text-lg font-medium text-gray-900 mb-4">Plan Limits</h3>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {Object.entries(formData.limits).map(([limitKey, value]) => (
                  <div key={limitKey}>
                    <label className="block text-sm font-medium text-gray-700 mb-1">
                      {limitKey.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())}
                    </label>
                    <input
                      type="number"
                      min={limitKey.includes('global_access') ? '0' : '-1'}
                      value={value}
                      onChange={(e) => handleLimitChange(limitKey, parseInt(e.target.value) || 0)}
                      className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                    />
                    <p className="text-xs text-gray-500 mt-1">
                      Use -1 for unlimited {limitKey.includes('global_access') ? '(or 1 for true)' : ''}
                    </p>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Advanced Tab */}
          {activeTab === 'advanced' && (
            <div className="space-y-4">
              <h3 className="text-lg font-medium text-gray-900 mb-4">Advanced Settings</h3>
              
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    Stripe Price ID
                  </label>
                  <input
                    type="text"
                    value={formData.stripe_price_id || ''}
                    onChange={(e) => setFormData({ ...formData, stripe_price_id: e.target.value || undefined })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                    placeholder="price_..."
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    PayPal Plan ID
                  </label>
                  <input
                    type="text"
                    value={formData.paypal_plan_id || ''}
                    onChange={(e) => setFormData({ ...formData, paypal_plan_id: e.target.value || undefined })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                    placeholder="P-..."
                  />
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Default Roles (comma-separated)
                </label>
                <input
                  type="text"
                  value={formData.default_roles.join(', ')}
                  onChange={(e) => setFormData({ 
                    ...formData, 
                    default_roles: e.target.value.split(',').map(role => role.trim()).filter(role => role)
                  })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                  placeholder="user, member"
                />
              </div>
            </div>
          )}
        </form>

        <div className="px-6 py-4 bg-gray-50 border-t border-gray-200 flex justify-end space-x-3">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 border border-gray-300 rounded-md text-gray-700 hover:bg-gray-50 transition-colors duration-150"
            disabled={saving}
          >
            Cancel
          </button>
          <button
            onClick={handleSubmit}
            disabled={saving}
            className="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors duration-150 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {saving ? 'Saving...' : (plan ? 'Update Plan' : 'Create Plan')}
          </button>
        </div>
      </div>
    </div>
  );
};