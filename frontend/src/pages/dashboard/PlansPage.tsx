import React, { useState, useEffect } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store';
import {
  plansApi,
  Plan,
  DetailedPlan
} from '../../services/plansApi';
import { PlanFormModal } from '../../components/admin/PlanFormModal';

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
        <div className="text-theme-secondary">Loading plans...</div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-2xl font-bold text-theme-primary">Plans Management</h1>
          <p className="text-theme-secondary">
            {hasAdminAccess 
              ? "Manage subscription plans and pricing tiers."
              : "View available subscription plans."
            }
          </p>
        </div>
        {hasAdminAccess && (
          <button
            onClick={handleCreatePlan}
            className="btn-theme btn-theme-primary"
          >
            Create Plan
          </button>
        )}
      </div>

      {successMessage && (
        <div className="bg-theme-success text-theme-success card-theme px-4 py-3">
          {successMessage}
        </div>
      )}

      {errorMessage && (
        <div className="bg-theme-error text-theme-error card-theme px-4 py-3">
          {errorMessage}
        </div>
      )}

      {/* Plans Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
        {plans.map((plan) => (
          <div key={plan.id} className="card-theme shadow-md overflow-hidden">
            {/* Plan Header */}
            <div className="p-6 border-b border-theme">
              <div className="flex justify-between items-start mb-4">
                <h3 className="text-lg font-semibold text-theme-primary">{plan.name}</h3>
                <span className={`px-2 py-1 text-xs font-medium rounded-full ${plansApi.getStatusColor(plan.status || 'inactive')}`}>
                  {(plan.status || 'inactive').charAt(0).toUpperCase() + (plan.status || 'inactive').slice(1)}
                </span>
              </div>
              
              <div className="mb-4">
                <div className="text-3xl font-bold text-theme-primary">
                  {plan.formatted_price}
                </div>
                <div className="text-sm text-theme-secondary">
                  per {plan.billing_cycle ? plan.billing_cycle.slice(0, -2) : 'month'} {/* Remove 'ly' suffix */}
                </div>
                {plan.billing_cycle !== 'monthly' && (
                  <div className="text-xs text-theme-tertiary">
                    ({plan.monthly_price}/month)
                  </div>
                )}
              </div>

              {plan.description && (
                <p className="text-theme-secondary text-sm mb-4">{plan.description}</p>
              )}

              <div className="flex justify-between items-center text-sm text-theme-secondary">
                <span>{plan.subscription_count || 0} subscriptions</span>
                <span>{plan.active_subscription_count || 0} active</span>
              </div>
            </div>

            {/* Plan Actions */}
            {hasAdminAccess && (
              <div className="card-content bg-theme-background-secondary space-y-2">
                <div className="flex space-x-2">
                  <button
                    onClick={() => handleEditPlan(plan.id)}
                    className="flex-1 btn-theme btn-theme-primary btn-theme-sm"
                  >
                    Edit
                  </button>
                  <button
                    onClick={() => handleDuplicatePlan(plan.id)}
                    className="flex-1 btn-theme btn-theme-secondary btn-theme-sm"
                  >
                    Duplicate
                  </button>
                </div>
                <div className="flex space-x-2">
                  <button
                    onClick={() => handleToggleStatus(plan.id)}
                    className={`flex-1 px-3 py-1 rounded text-sm transition-colors duration-150 ${
                      plan.status === 'active'
                        ? 'bg-theme-warning text-white hover:opacity-80'
                        : 'bg-theme-success text-white hover:opacity-80'
                    }`}
                  >
                    {plan.status === 'active' ? 'Deactivate' : 'Activate'}
                  </button>
                  <button
                    onClick={() => handleDeletePlan(plan.id)}
                    disabled={plan.can_be_deleted === false}
                    className="flex-1 bg-theme-error text-white px-3 py-1 rounded text-sm hover:opacity-80 transition-colors duration-150 disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    Delete
                  </button>
                </div>
              </div>
            )}

            {/* Plan Details for non-admin users */}
            {!hasAdminAccess && (
              <div className="card-content bg-theme-background-secondary">
                <div className="flex justify-between items-center text-sm text-theme-secondary">
                  <span>Trial: {plan.trial_days} days</span>
                  <span className={`px-2 py-1 text-xs rounded ${plan.is_public ? 'bg-theme-success text-theme-success' : 'bg-theme-background-tertiary text-theme-secondary'}`}>
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
          <div className="text-theme-secondary text-lg">No plans found</div>
          {hasAdminAccess && (
            <button
              onClick={handleCreatePlan}
              className="mt-4 btn-theme btn-theme-primary"
            >
              Create Your First Plan
            </button>
          )}
        </div>
      )}

      {/* Create Plan Modal */}
      <PlanFormModal
        isOpen={showCreateModal}
        onClose={() => setShowCreateModal(false)}
        onSaved={handlePlanSaved}
        showSuccess={showSuccess}
        showError={showError}
      />

      {/* Edit Plan Modal */}
      <PlanFormModal
        isOpen={showEditModal}
        onClose={() => setShowEditModal(false)}
        onSaved={handlePlanSaved}
        plan={selectedPlan}
        showSuccess={showSuccess}
        showError={showError}
      />
    </div>
  );
};