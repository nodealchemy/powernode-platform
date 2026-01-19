import React, { useState, useEffect, useCallback, useRef } from 'react';
import { useSelector } from 'react-redux';
import { useLocation } from 'react-router-dom';
import { RootState } from '@/shared/services';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import {
  plansApi,
  Plan,
  DetailedPlan
} from '@/features/business/plans/services/plansApi';
import { PlanFormModal } from '@/features/admin/components/PlanFormModal';
import { hasPermissions } from '@/shared/utils/permissionUtils';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { Plus, RefreshCw } from 'lucide-react';

export const PlansPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const { showNotification } = useNotifications();
  const { confirm, ConfirmationDialog } = useConfirmation();
  const notificationRef = useRef(showNotification);
  notificationRef.current = showNotification;

  const location = useLocation();
  const [plans, setPlans] = useState<Plan[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showEditModal, setShowEditModal] = useState(false);
  const [selectedPlan, setSelectedPlan] = useState<DetailedPlan | null>(null);

  // WebSocket for real-time updates
  const { isConnected: _wsConnected } = usePageWebSocket({
    pageType: 'business',
    subscribeToSubscriptions: true,
    onDataUpdate: () => {
      // Trigger data refresh if needed
      loadPlans();
    }
  });

  // Check if user has plan management permissions for create/edit/delete actions
  const canManagePlans = hasPermissions(user, ['plans.manage']) || hasPermissions(user, ['admin.billing.read']);

  const loadPlans = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await plansApi.getPlans();
      setPlans(response.data?.plans || []);
    } catch (err: unknown) {
      const errorMsg = err instanceof Error ? err.message : 'Failed to load plans';
      setError(errorMsg);
      notificationRef.current(errorMsg, 'error');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadPlans();
  }, [loadPlans]);
  
  // All users can view plans, only those with permissions can manage them

  const showSuccess = (message: string) => {
    showNotification(message, 'success');
  };

  const showError = (message: string) => {
    showNotification(message, 'error');
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
    } catch (_error) {
      showError('Failed to load plan details');
    }
  };

  const handleDuplicatePlan = async (planId: string) => {
    try {
      // Load the plan details to pre-fill the creation modal
      const response = await plansApi.getPlan(planId);
      if (response.data?.plan) {
        const planToCopy = response.data.plan;

        // Create a copy with modified name and cleared IDs for new plan creation
        // Explicitly preserve all critical fields to ensure nothing is lost
        const duplicatedPlan = {
          ...planToCopy,
          id: `copy-of-${planToCopy.id}`,
          name: `Copy of ${planToCopy.name}`,

          // Core plan data (preserved)
          description: planToCopy.description,
          price_cents: planToCopy.price_cents,
          currency: planToCopy.currency,
          billing_cycle: planToCopy.billing_cycle,
          trial_days: planToCopy.trial_days,
          is_public: planToCopy.is_public,
          formatted_price: planToCopy.formatted_price,
          monthly_price: planToCopy.monthly_price,

          // Features and Limits (explicitly preserved)
          features: planToCopy.features ? { ...planToCopy.features } : {},
          limits: planToCopy.limits ? { ...planToCopy.limits } : {},
          default_role: planToCopy.default_role,
          metadata: planToCopy.metadata ? { ...planToCopy.metadata } : {},

          // Discount settings (explicitly preserved)
          has_annual_discount: planToCopy.has_annual_discount,
          annual_discount_percent: planToCopy.annual_discount_percent,
          has_volume_discount: planToCopy.has_volume_discount,
          volume_discount_tiers: planToCopy.volume_discount_tiers ? [...planToCopy.volume_discount_tiers] : [],
          has_promotional_discount: planToCopy.has_promotional_discount,
          promotional_discount_percent: planToCopy.promotional_discount_percent,
          promotional_discount_start: planToCopy.promotional_discount_start,
          promotional_discount_end: planToCopy.promotional_discount_end,
          promotional_discount_code: planToCopy.promotional_discount_code,
          annual_savings_amount: planToCopy.annual_savings_amount,
          annual_savings_percentage: planToCopy.annual_savings_percentage,

          // Reset payment gateway IDs since this will be a new plan
          stripe_price_id: null,
          paypal_plan_id: null,

          // Reset subscription counts
          subscription_count: 0,
          active_subscription_count: 0,
          can_be_deleted: true,

          // Set as inactive by default for review
          status: 'inactive' as const,

          // Update timestamps
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        };

        setSelectedPlan(duplicatedPlan);
        setShowCreateModal(true);
      } else {
        showError('Failed to load plan details');
      }
    } catch (_error) {
      showError('Failed to load plan for copying');
    }
  };

  const handleToggleStatus = async (planId: string) => {
    try {
      await plansApi.togglePlanStatus(planId);
      showSuccess('Plan status updated successfully');
      loadPlans();
    } catch (_error) {
      showError('Failed to update plan status');
    }
  };

  const handleDeletePlan = (planId: string) => {
    confirm({
      title: 'Delete Plan',
      message: 'Are you sure you want to delete this plan? This action cannot be undone. Active subscribers will be affected.',
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        try {
          await plansApi.deletePlan(planId);
          showSuccess('Plan deleted successfully');
          loadPlans();
        } catch (_error) {
          showError('Failed to delete plan');
        }
      }
    });
  };

  const handlePlanSaved = () => {
    setShowCreateModal(false);
    setShowEditModal(false);
    setSelectedPlan(null);
    loadPlans();
  };


  const tabs = [
    { id: 'overview', label: 'Overview', icon: '📊', path: '/' },
    { id: 'active', label: 'Active Plans', icon: '✅', path: '/active' },
    { id: 'analytics', label: 'Analytics', icon: '📈', path: '/analytics' }
  ];

  // Get active tab from URL
  const getActiveTab = () => {
    const path = location.pathname;
    if (path === '/app/business/plans') return 'overview';
    if (path.includes('/active')) return 'active';
    if (path.includes('/analytics')) return 'analytics';
    return 'overview';
  };

  const [activeTab, setActiveTab] = useState(getActiveTab());

  const activePlans = plans.filter(plan => plan.status === 'active');
  const totalRevenue = plans.reduce((sum, plan) => {
    const priceCents = typeof plan.price_cents === 'string' ? parseFloat(plan.price_cents) : (plan.price_cents || 0);
    return sum + (plan.active_subscription_count || 0) * (priceCents / 100);
  }, 0);

  const pageActions: PageAction[] = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: loadPlans,
      variant: 'secondary',
      icon: RefreshCw,
      disabled: loading
    },
    ...(canManagePlans ? [{
      id: 'create-plan',
      label: 'Create Plan',
      onClick: handleCreatePlan,
      variant: 'primary' as const,
      icon: Plus
    }] : [])
  ];

  const getBreadcrumbs = () => {
    const baseBreadcrumbs: Array<{ label: string; href?: string }> = [
      { label: 'Dashboard', href: '/app' },
      { label: 'Business', href: '/app/business' },
      { label: 'Plans' }
    ];

    // Add active tab to breadcrumbs if not the default overview tab
    const activeTabInfo = tabs.find(tab => tab.id === activeTab);
    if (activeTabInfo && activeTab !== 'overview') {
      baseBreadcrumbs.push({
        label: activeTabInfo.label
      });
    }

    return baseBreadcrumbs;
  };

  const getPageDescription = () => {
    if (loading) return "Loading plans...";
    if (error) return "Error loading plans";
    return canManagePlans 
      ? `Manage subscription plans and pricing tiers for ${user?.account?.name || 'your account'}`
      : "View available subscription plans and pricing options";
  };

  const getPageActions = () => {
    if (error) {
      return [{
        id: 'retry',
        label: 'Try Again',
        onClick: loadPlans,
        variant: 'primary' as const
      }];
    }
    return pageActions;
  };

  return (
    <PageContainer
      title="Plans"
      description={getPageDescription()}
      breadcrumbs={getBreadcrumbs()}
      actions={getPageActions()}
    >
      {loading ? (
        <LoadingSpinner size="lg" message="Loading plans..." />
      ) : error ? (
        <div className="alert-theme alert-theme-error">
          <div className="flex items-center">
            <div className="flex-shrink-0">
              <span className="text-xl">⚠️</span>
            </div>
            <div className="ml-3">
              <h3 className="text-sm font-medium">Error Loading Plans</h3>
              <p className="mt-1 text-sm">{error}</p>
            </div>
          </div>
        </div>
      ) : (
        <>
          <TabContainer
            tabs={tabs}
            activeTab={activeTab}
            onTabChange={setActiveTab}
            basePath="/app/business/plans"
            variant="underline"
            className="mb-6"
          >
            <TabPanel tabId="overview" activeTab={activeTab}>
              <div className="space-y-6">
            {/* Overview Stats */}
            <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
              <div className="card-theme p-4 text-center">
                <div className="text-2xl font-bold text-theme-interactive-primary">{plans.length}</div>
                <div className="text-sm text-theme-secondary">Total Plans</div>
                <div className="text-xs text-theme-tertiary">Created</div>
              </div>
              <div className="card-theme p-4 text-center">
                <div className="text-2xl font-bold text-theme-interactive-primary">{activePlans.length}</div>
                <div className="text-sm text-theme-secondary">Active Plans</div>
                <div className="text-xs text-theme-tertiary">Available</div>
              </div>
              <div className="card-theme p-4 text-center">
                <div className="text-2xl font-bold text-theme-interactive-primary">
                  {plans.reduce((sum, plan) => sum + (plan.subscription_count || 0), 0)}
                </div>
                <div className="text-sm text-theme-secondary">Total Subscriptions</div>
                <div className="text-xs text-theme-tertiary">All time</div>
              </div>
              <div className="card-theme p-4 text-center">
                <div className="text-2xl font-bold text-theme-interactive-primary">
                  ${totalRevenue.toFixed(2)}
                </div>
                <div className="text-sm text-theme-secondary">Monthly Revenue</div>
                <div className="text-xs text-theme-tertiary">Estimated</div>
              </div>
            </div>

            {/* Quick Actions */}
            <div className="card-theme p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-4">Quick Actions</h3>
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                {canManagePlans && (
                  <button 
                    onClick={handleCreatePlan}
                    className="border border-theme rounded-lg p-4 text-center hover:bg-theme-surface cursor-pointer transition-colors"
                  >
                    <div className="text-2xl mb-2">➕</div>
                    <div className="font-medium text-theme-primary">Create New Plan</div>
                    <div className="text-sm text-theme-secondary">Set up a new subscription tier</div>
                  </button>
                )}
                <div className="border border-theme rounded-lg p-4 text-center hover:bg-theme-surface cursor-pointer transition-colors">
                  <div className="text-2xl mb-2">📊</div>
                  <div className="font-medium text-theme-primary">Plan Analytics</div>
                  <div className="text-sm text-theme-secondary">View performance metrics</div>
                </div>
                <div className="border border-theme rounded-lg p-4 text-center hover:bg-theme-surface cursor-pointer transition-colors">
                  <div className="text-2xl mb-2">🔄</div>
                  <div className="font-medium text-theme-primary">Sync Pricing</div>
                  <div className="text-sm text-theme-secondary">Update pricing across platforms</div>
                </div>
              </div>
            </div>

            {/* Recent Activity */}
            <div className="card-theme p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-4">Recent Activity</h3>
              <div className="space-y-3">
                <div className="flex items-center space-x-3 py-2">
                  <div className="w-2 h-2 bg-theme-success-solid rounded-full"></div>
                  <span className="text-theme-primary">Pro Plan activated</span>
                  <span className="text-sm text-theme-secondary">2 hours ago</span>
                </div>
                <div className="flex items-center space-x-3 py-2">
                  <div className="w-2 h-2 bg-theme-info-solid rounded-full"></div>
                  <span className="text-theme-primary">Basic Plan pricing updated</span>
                  <span className="text-sm text-theme-secondary">1 day ago</span>
                </div>
                <div className="flex items-center space-x-3 py-2">
                  <div className="w-2 h-2 bg-theme-warning-solid rounded-full"></div>
                  <span className="text-theme-primary">Enterprise Plan created</span>
                  <span className="text-sm text-theme-secondary">3 days ago</span>
                </div>
              </div>
            </div>
              </div>
            </TabPanel>


            <TabPanel tabId="active" activeTab={activeTab}>
              <div className="space-y-6">
                {/* Plans Grid - Enhanced UX Design with Perfect Alignment */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
        {plans.map((plan) => (
          <div key={plan.id} className="group card-theme shadow-sm hover:shadow-lg transition-all duration-300 overflow-hidden border border-theme-light hover:border-theme-focus flex flex-col h-[580px]">
            {/* Plan Header - Flexible Content */}
            <div className="p-8 relative flex-grow">
              {/* Header with Status Badge */}
              <div className="flex justify-between items-start mb-6">
                <div className="flex-1">
                  <h3 className="text-xl font-bold text-theme-primary mb-2 group-hover:text-theme-link transition-colors">
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
                <div className="flex items-start flex-shrink-0">
                  {/* Status Badge */}
                  <span className={`px-3 py-1 text-xs font-semibold rounded-full border ${plansApi.getStatusColor(plan.status || 'inactive')}`}>
                    {(plan.status || 'inactive').charAt(0).toUpperCase() + (plan.status || 'inactive').slice(1)}
                  </span>
                </div>
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
                    <div className="inline-flex items-center px-2 py-1 bg-theme-success text-theme-success text-xs font-medium rounded-full">
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
                  <div className="text-2xl font-bold text-theme-success">
                    {plan.active_subscription_count || 0}
                  </div>
                  <div className="text-xs text-theme-secondary uppercase tracking-wide">
                    Active
                  </div>
                </div>
                {!canManagePlans && (
                  <>
                    <div className="h-8 w-px bg-theme-border"></div>
                    <div className="text-center flex-1">
                      <span className={`inline-flex items-center px-2 py-1 text-xs font-medium rounded-full ${plan.is_public ? 'bg-theme-success text-theme-success' : 'bg-theme-background-secondary text-theme-secondary'}`}>
                        {plan.is_public ? 'Public' : 'Private'}
                      </span>
                    </div>
                  </>
                )}
              </div>
            </div>

            {/* Plan Actions - Fixed to Bottom with Consistent Height */}
            <div className="p-8 pt-0 mt-auto">
              {canManagePlans ? (
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
                          ? 'bg-theme-warning text-theme-warning border-theme-warning'
                          : 'bg-theme-success text-theme-success border-theme-success'
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
                      className="flex items-center justify-center space-x-2 px-4 py-2.5 rounded-lg text-sm font-medium transition-all duration-200 bg-theme-error text-theme-error border-theme-error disabled:opacity-50 disabled:cursor-not-allowed h-10"
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
              ) : (
                /* Placeholder space to maintain consistent card height for non-management users */
                <div className="space-y-3">
                  <div className="h-10"></div>
                  <div className="h-10"></div>
                  <div className="h-8"></div>
                </div>
              )}
            </div>
          </div>
        ))}
      </div>

      {plans.length === 0 && (
        <div className="text-center py-12">
          <span className="text-6xl">📋</span>
          <h3 className="text-lg font-medium text-theme-primary mt-2">No plans found</h3>
          <p className="text-theme-secondary">Create your first subscription plan to get started.</p>
          {canManagePlans && (
            <button
              onClick={handleCreatePlan}
              className="mt-4 btn-theme btn-theme-primary"
            >
              Create Your First Plan
            </button>
          )}
        </div>
      )}
              </div>
            </TabPanel>

            <TabPanel tabId="analytics" activeTab={activeTab}>
              <div className="space-y-6">
            {/* Plan Performance */}
            <div className="card-theme p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-4">Plan Performance</h3>
              <div className="space-y-3">
                {plans.slice(0, 5).map((plan, index) => (
                  <div key={plan.id} className="flex items-center justify-between py-2">
                    <div className="flex items-center space-x-3">
                      <span className="text-theme-secondary font-medium">{index + 1}</span>
                      <span className="text-lg">📋</span>
                      <span className="text-theme-primary">{plan.name}</span>
                    </div>
                    <div className="text-sm text-theme-secondary">
                      {plan.subscription_count || 0} subscriptions
                    </div>
                  </div>
                ))}
              </div>
            </div>
            
            {/* Revenue Breakdown */}
            <div className="card-theme p-6">
              <h3 className="text-lg font-semibold text-theme-primary mb-4">Revenue Breakdown</h3>
              <div className="space-y-4">
                {plans.map((plan) => {
                  const priceCents = typeof plan.price_cents === 'string' ? parseFloat(plan.price_cents) : (plan.price_cents || 0);
                  const revenue = (plan.active_subscription_count || 0) * (priceCents / 100);
                  return (
                    <div key={plan.id} className="flex items-center justify-between py-2">
                      <div>
                        <span className="text-theme-primary font-medium">{plan.name}</span>
                        <div className="text-sm text-theme-secondary">
                          {plan.active_subscription_count || 0} active × {plan.formatted_price}
                        </div>
                      </div>
                      <div className="text-lg font-semibold text-theme-primary">
                        ${revenue.toFixed(2)}/mo
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
              </div>
            </TabPanel>
          </TabContainer>

      {/* Create Plan Modal */}
      <PlanFormModal
        isOpen={showCreateModal}
        onClose={() => {
          setShowCreateModal(false);
          setSelectedPlan(null);
        }}
        onSaved={handlePlanSaved}
        plan={selectedPlan}
        showSuccess={showSuccess}
        showError={showError}
      />

      {/* Edit Plan Modal */}
      <PlanFormModal
        isOpen={showEditModal}
        onClose={() => {
          setShowEditModal(false);
          setSelectedPlan(null);
        }}
        onSaved={handlePlanSaved}
        plan={selectedPlan}
        showSuccess={showSuccess}
        showError={showError}
      />
      {ConfirmationDialog}
        </>
      )}
    </PageContainer>
  );
};
