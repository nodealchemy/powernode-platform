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

      {/* Plans Grid - Enhanced UX Design with Perfect Alignment */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
        {plans.map((plan) => (
          <div key={plan.id} className="group card-theme shadow-sm hover:shadow-lg transition-all duration-300 overflow-hidden border border-theme-light hover:border-blue-200 flex flex-col h-full">
            {/* Plan Header - Flexible Content */}
            <div className="p-8 relative flex-grow">
              {/* Status Badge */}
              <div className="flex justify-between items-start mb-6">
                <div className="flex-1">
                  <h3 className="text-xl font-bold text-theme-primary mb-2 group-hover:text-blue-600 transition-colors">
                    {plan.name}
                  </h3>
                  <div className="h-10">
                    {plan.description && (
                      <p className="text-theme-secondary text-sm leading-relaxed line-clamp-2">
                        {plan.description}
                      </p>
                    )}
                  </div>
                </div>
                <span className={`ml-4 px-3 py-1 text-xs font-semibold rounded-full border ${plansApi.getStatusColor(plan.status || 'inactive')} flex-shrink-0`}>
                  {(plan.status || 'inactive').charAt(0).toUpperCase() + (plan.status || 'inactive').slice(1)}
                </span>
              </div>
              
              {/* Pricing Section - Fixed Height */}
              <div className="mb-6 h-24 flex flex-col justify-center">
                <div className="flex items-baseline mb-2">
                  <span className="text-4xl font-bold text-theme-primary tracking-tight">
                    {plan.formatted_price}
                  </span>
                  <span className="text-theme-secondary text-base font-medium ml-2">
                    /{plan.billing_cycle ? plan.billing_cycle.slice(0, -2) : 'month'}
                  </span>
                </div>
                <div className="h-4">
                  {plan.billing_cycle !== 'monthly' && plan.monthly_price && (
                    <div className="text-sm text-theme-tertiary">
                      Equivalent to {plan.monthly_price}/month
                    </div>
                  )}
                </div>
                <div className="h-6 mt-1">
                  {plan.trial_days > 0 && (
                    <div className="inline-flex items-center px-2 py-1 bg-green-50 text-green-700 text-xs font-medium rounded-full">
                      {plan.trial_days}-day free trial
                    </div>
                  )}
                </div>
              </div>

              {/* Usage Stats - Fixed Height */}
              <div className="flex items-center justify-between p-4 bg-theme-background-secondary rounded-lg h-20">
                <div className="text-center flex-1">
                  <div className="text-2xl font-bold text-theme-primary">
                    {plan.subscription_count || 0}
                  </div>
                  <div className="text-xs text-theme-secondary uppercase tracking-wide">
                    Total
                  </div>
                </div>
                <div className="h-8 w-px bg-theme-border"></div>
                <div className="text-center flex-1">
                  <div className="text-2xl font-bold text-green-600">
                    {plan.active_subscription_count || 0}
                  </div>
                  <div className="text-xs text-theme-secondary uppercase tracking-wide">
                    Active
                  </div>
                </div>
                {!hasAdminAccess && (
                  <>
                    <div className="h-8 w-px bg-theme-border"></div>
                    <div className="text-center flex-1">
                      <span className={`inline-flex items-center px-2 py-1 text-xs font-medium rounded-full ${plan.is_public ? 'bg-green-100 text-green-800' : 'bg-gray-100 text-gray-600'}`}>
                        {plan.is_public ? 'Public' : 'Private'}
                      </span>
                    </div>
                  </>
                )}
              </div>
            </div>

            {/* Plan Actions - Fixed to Bottom with Consistent Height */}
            {hasAdminAccess && (
              <div className="p-8 pt-0 mt-auto">
                <div className="space-y-3">
                  {/* Primary Actions */}
                  <div className="grid grid-cols-2 gap-3">
                    <button
                      onClick={() => handleEditPlan(plan.id)}
                      className="btn-theme btn-theme-primary flex items-center justify-center space-x-2 py-2.5 h-10"
                    >
                      <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                      </svg>
                      <span>Edit</span>
                    </button>
                    <button
                      onClick={() => handleDuplicatePlan(plan.id)}
                      className="btn-theme btn-theme-secondary flex items-center justify-center space-x-2 py-2.5 h-10"
                    >
                      <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
                      </svg>
                      <span>Copy</span>
                    </button>
                  </div>
                  
                  {/* Secondary Actions */}
                  <div className="grid grid-cols-2 gap-3">
                    <button
                      onClick={() => handleToggleStatus(plan.id)}
                      className={`flex items-center justify-center space-x-2 px-4 py-2.5 rounded-lg text-sm font-medium transition-all duration-200 h-10 ${
                        plan.status === 'active'
                          ? 'bg-amber-100 text-amber-800 hover:bg-amber-200 border border-amber-200'
                          : 'bg-green-100 text-green-800 hover:bg-green-200 border border-green-200'
                      }`}
                    >
                      <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} 
                          d={plan.status === 'active' 
                            ? "M10 9v6m4-6v6m7-3a9 9 0 11-18 0 9 9 0 0118 0z"
                            : "M14.828 14.828a4 4 0 01-5.656 0M9 10h1.586a1 1 0 01.707.293l2.414 2.414a1 1 0 00.707.293H15a2 2 0 002-2V9a2 2 0 00-2-2h-1.586a1 1 0 01-.707-.293L11.293 5.293A1 1 0 0010.586 5H9a2 2 0 00-2 2v2a2 2 0 002 2zm0 0v6a2 2 0 002 2h2a2 2 0 002-2v-6"
                          } 
                        />
                      </svg>
                      <span>{plan.status === 'active' ? 'Pause' : 'Activate'}</span>
                    </button>
                    <button
                      onClick={() => handleDeletePlan(plan.id)}
                      disabled={plan.can_be_deleted === false}
                      className="flex items-center justify-center space-x-2 px-4 py-2.5 rounded-lg text-sm font-medium transition-all duration-200 bg-red-50 text-red-700 hover:bg-red-100 border border-red-200 disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:bg-red-50 h-10"
                    >
                      <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                      </svg>
                      <span>Delete</span>
                    </button>
                  </div>
                  
                  {/* Warning Message - Fixed Height Space */}
                  <div className="h-8">
                    {plan.can_be_deleted === false && (
                      <div className="text-xs text-theme-tertiary text-center bg-theme-background-secondary px-3 py-2 rounded">
                        Cannot delete plan with active subscriptions
                      </div>
                    )}
                  </div>
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