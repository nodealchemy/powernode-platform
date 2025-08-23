import React, { useState, useEffect } from 'react';
import { Routes, Route, useNavigate, Navigate } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { plansApi } from '@/features/plans/services/plansApi';
import { DashboardLayout } from '@/shared/components/layout/DashboardLayout';
import { MetricCard } from '@/shared/components/ui/Card';

// Import all dashboard pages
import { SubscriptionsPage } from './business/SubscriptionsPage';
import { ReportsPage } from './business/ReportsPage';
import { PlansPage } from './business/PlansPage';
import { SettingsPage } from './SettingsPage';
import { PagesPage } from './content/PagesPage';
import { UsersPage } from './UsersPage';
import { AuditLogsPage } from './AuditLogsPage';
import { ApiKeysPage } from './ApiKeysPage';
import { MetricsPage } from './MetricsPage';
import { AnalyticsPage } from './business/AnalyticsPage';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { BarChart3, Users, CreditCard, Settings } from 'lucide-react';

// Import individual pages directly (no more management page groupings)
import { CustomersPage } from './business/CustomersPage';
import { BillingPage } from './business/BillingPage';

// Import system pages
import WebhookManagementPage from '@/pages/app/WebhookManagementPage';
import { AuditLogsPage as SystemAuditLogsPage } from '@/pages/app/AuditLogsPage';

// Import admin pages
import { AdminSettingsPage } from '@/pages/app/admin/AdminSettingsPage';
import { AdminUsersPage } from '@/pages/app/admin/AdminUsersPage';
import { AdminRolesPage } from '@/pages/app/admin/AdminRolesPage';
import { WorkersPage as SystemWorkersPage } from '@/pages/app/system/WorkersPage';
import { AdminMaintenancePage } from '@/pages/app/admin/AdminMaintenancePage';

// Test page
import { TestWebSocket } from '@/pages/app/TestWebSocket';

// Dashboard overview page
const DashboardOverview: React.FC = () => {
  const navigate = useNavigate();
  const { user } = useSelector((state: RootState) => state.auth);
  const [hasPlans, setHasPlans] = useState(false);
  const [hasPaymentGateways, setHasPaymentGateways] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let mounted = true; // Track if component is still mounted
    
    const checkSetupStatus = async () => {
      try {
        // Check plans using public endpoint (no auth required)
        const plansResponse = await plansApi.getPublicPlans();
        
        // Only update state if component is still mounted
        if (mounted) {
          setHasPlans(plansResponse.data.plans.length > 0);
          
          // Skip payment gateway check for now due to API issues
          // TODO: Re-enable when payment gateway API is fixed
          setHasPaymentGateways(false);
        }
      } catch (error) {
        if (mounted) {
          console.error('Failed to check setup status:', error);
          // Assume no setup on error
          setHasPlans(false);
          setHasPaymentGateways(false);
        }
      } finally {
        if (mounted) {
          setLoading(false);
        }
      }
    };
    
    checkSetupStatus();
    
    // Cleanup function to prevent state updates on unmounted component
    return () => {
      mounted = false;
    };
  }, [user]);

  // Calculate completion status
  const completedTasks = [
    true, // Account created (always true if user is logged in)
    user?.email_verified || false, // Email verification (check actual status)
    hasPlans, // Plans setup
    hasPaymentGateways // Payment gateways configured
  ];
  const completedCount = completedTasks.filter(Boolean).length;
  const totalTasks = completedTasks.length;
  
  const pageActions: PageAction[] = [
    {
      id: 'analytics',
      label: 'Analytics',
      onClick: () => navigate('/app/business/analytics'),
      variant: 'secondary',
      icon: BarChart3
    },
    {
      id: 'customers',
      label: 'Customers',
      onClick: () => navigate('/app/business/customers'),
      variant: 'secondary',
      icon: Users
    },
    {
      id: 'payment-gateways',
      label: 'Payment Setup',
      onClick: () => navigate('/admin/settings/payment-gateways'),
      variant: 'secondary',
      icon: CreditCard
    },
    {
      id: 'settings',
      label: 'Settings',
      onClick: () => navigate('/app/profile'),
      variant: 'primary',
      icon: Settings
    }
  ];

  const breadcrumbs = [
    { label: 'Dashboard', icon: '🏠' }
  ];
  
  return (
    <PageContainer
      title={`Welcome back, ${user?.first_name}! 👋`}
      description="Here's an overview of your account activity and system status."
      breadcrumbs={breadcrumbs}
      actions={pageActions}
    >
      <div className="space-y-6">
        {/* Key Metrics Cards */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
          <MetricCard
            title="Total Revenue"
            value="$0.00"
            icon="💰"
            change={0}
            description="Revenue from all subscriptions"
          />

          <MetricCard
            title="Active Subscriptions"
            value={0}
            icon="📊"
            description="Ready to grow"
          />

          <MetricCard
            title="Monthly Growth"
            value="0%"
            icon="📈"
            description="Start your journey"
          />

          <MetricCard
            title="System Health"
            value="100%"
            icon="✅"
            description="All systems operational"
          />
        </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Getting Started Card */}
        <div className="card-theme-elevated p-6">
          <div className="flex items-center justify-between mb-6">
            <h3 className="text-xl font-semibold text-theme-primary">
              Getting Started
            </h3>
            <span className="bg-theme-info text-theme-on-primary px-3 py-1 rounded-full text-xs font-medium bg-opacity-10 text-theme-info">
              {loading ? 'Loading...' : `${completedCount} of ${totalTasks} complete`}
            </span>
          </div>
          
          <div className="space-y-4">
            <div className="flex items-start space-x-3">
              <div className="flex-shrink-0 mt-1">
                <div className="h-5 w-5 bg-theme-success rounded-full flex items-center justify-center">
                  <span className="text-white text-xs">✓</span>
                </div>
              </div>
              <div className="flex-1">
                <p className="text-sm font-medium text-theme-primary">Account created successfully</p>
                <p className="text-xs text-theme-tertiary mt-1">Your Powernode account is ready to use</p>
              </div>
            </div>

            <div className="flex items-start space-x-3">
              <div className="flex-shrink-0 mt-1">
                <div className={`h-5 w-5 rounded-full flex items-center justify-center ${
                  user?.email_verified ? 'bg-theme-success' : 'bg-theme-error'
                }`}>
                  <span className="text-white text-xs">
                    {user?.email_verified ? '✓' : '✗'}
                  </span>
                </div>
              </div>
              <div className="flex-1">
                <p className={`text-sm font-medium ${
                  user?.email_verified ? 'text-theme-primary' : 'text-theme-primary'
                }`}>
                  {user?.email_verified ? 'Email verification completed' : 'Email verification required'}
                </p>
                <p className="text-xs text-theme-tertiary mt-1">
                  {user?.email_verified ? 'Your email address has been verified' : 'Please verify your email address'}
                </p>
                {!user?.email_verified && (
                  <button 
                    onClick={() => navigate('/verify-email')}
                    className="btn-theme btn-theme-primary mt-2 text-xs px-3 py-1"
                  >
                    Verify Email
                  </button>
                )}
              </div>
            </div>

            <div className="flex items-start space-x-3">
              <div className="flex-shrink-0 mt-1">
                <div className={`h-5 w-5 rounded-full flex items-center justify-center ${
                  hasPlans ? 'bg-theme-success' : 'bg-theme-warning'
                }`}>
                  <span className="text-white text-xs">
                    {hasPlans ? '✓' : '!'}
                  </span>
                </div>
              </div>
              <div className="flex-1">
                <p className={`text-sm font-medium ${hasPlans ? 'text-theme-primary' : 'text-theme-primary'}`}>
                  {hasPlans ? 'Subscription plans configured' : 'Set up your first subscription plan'}
                </p>
                <p className="text-xs text-theme-tertiary mt-1">
                  {hasPlans ? 'You have plans ready for customers' : 'Create plans to start accepting payments'}
                </p>
                {!hasPlans && (
                  <button 
                    onClick={() => navigate('/app/business/plans')}
                    className="btn-theme btn-theme-primary mt-2 text-xs px-3 py-1"
                  >
                    Create Plan
                  </button>
                )}
              </div>
            </div>

            <div className="flex items-start space-x-3">
              <div className="flex-shrink-0 mt-1">
                <div className={`h-5 w-5 rounded-full flex items-center justify-center ${
                  hasPaymentGateways ? 'bg-theme-success' : 'bg-theme-warning'
                }`}>
                  <span className="text-white text-xs">
                    {hasPaymentGateways ? '✓' : '!'}
                  </span>
                </div>
              </div>
              <div className="flex-1">
                <p className={`text-sm font-medium ${hasPaymentGateways ? 'text-theme-primary' : 'text-theme-primary'}`}>
                  {hasPaymentGateways ? 'Payment gateways configured' : 'Configure payment methods'}
                </p>
                <p className="text-xs text-theme-tertiary mt-1">
                  {hasPaymentGateways ? 'Stripe or PayPal is ready for payments' : 'Set up Stripe or PayPal integration'}
                </p>
                {!hasPaymentGateways && (
                  <button 
                    onClick={() => navigate('/app/admin/settings/payment-gateways')}
                    className="btn-theme btn-theme-primary mt-2 text-xs px-3 py-1"
                  >
                    Configure Payments
                  </button>
                )}
              </div>
            </div>
          </div>
        </div>

        {/* Quick Actions Card */}
        <div className="card-theme-elevated p-6">
          <h3 className="text-xl font-semibold text-theme-primary mb-6">
            Quick Actions
          </h3>
          
          <div className="grid grid-cols-1 gap-3">
            <button 
              onClick={() => navigate('/app/business/customers')}
              className="btn-theme btn-theme-secondary flex items-center justify-between p-4 text-left hover:bg-theme-surface-hover"
            >
              <div className="flex items-center space-x-3">
                <span className="text-2xl">👥</span>
                <div>
                  <p className="font-medium text-theme-primary">Manage Customers</p>
                  <p className="text-xs text-theme-tertiary">View and organize your customer base</p>
                </div>
              </div>
              <span className="text-theme-tertiary">→</span>
            </button>

            <button 
              onClick={() => navigate('/app/business/analytics')}
              className="btn-theme btn-theme-secondary flex items-center justify-between p-4 text-left hover:bg-theme-surface-hover"
            >
              <div className="flex items-center space-x-3">
                <span className="text-2xl">📊</span>
                <div>
                  <p className="font-medium text-theme-primary">View Analytics</p>
                  <p className="text-xs text-theme-tertiary">Track revenue and growth metrics</p>
                </div>
              </div>
              <span className="text-theme-tertiary">→</span>
            </button>

            <button 
              onClick={() => navigate('/app/admin/settings/payment-gateways')}
              className="btn-theme btn-theme-secondary flex items-center justify-between p-4 text-left hover:bg-theme-surface-hover"
            >
              <div className="flex items-center space-x-3">
                <span className="text-2xl">💳</span>
                <div>
                  <p className="font-medium text-theme-primary">Payment Gateways</p>
                  <p className="text-xs text-theme-tertiary">Configure Stripe and PayPal</p>
                </div>
              </div>
              <span className="text-theme-tertiary">→</span>
            </button>

            <button 
              onClick={() => navigate('/app/profile')}
              className="btn-theme btn-theme-secondary flex items-center justify-between p-4 text-left hover:bg-theme-surface-hover"
            >
              <div className="flex items-center space-x-3">
                <span className="text-2xl">⚙️</span>
                <div>
                  <p className="font-medium text-theme-primary">Account Settings</p>
                  <p className="text-xs text-theme-tertiary">Customize your account preferences</p>
                </div>
              </div>
              <span className="text-theme-tertiary">→</span>
            </button>
          </div>
        </div>
      </div>

      {/* System Status Alert */}
      <div className="alert-theme alert-theme-success">
        <div className="flex items-center">
          <span className="text-2xl mr-3">🚀</span>
          <div>
            <h4 className="font-medium text-theme-success">Powernode Platform Ready</h4>
            <p className="text-sm text-theme-success mt-1">
              Your subscription platform is set up and ready for configuration. Start by creating your first subscription plan!
            </p>
          </div>
        </div>
      </div>
      </div>
    </PageContainer>
  );
};

const DashboardPage: React.FC = () => {
  
  return (
    <DashboardLayout>
      <Routes>
        {/* Dashboard Overview */}
        <Route path="/" element={<DashboardOverview />} />
        
        {/* Individual Pages - No More Management Page Groupings */}
        
        {/* Business Pages */}
        <Route path="/business/customers" element={<CustomersPage />} />
        <Route path="/business/subscriptions" element={<SubscriptionsPage />} />
        <Route path="/business/billing/*" element={<BillingPage />} />
        
        {/* Core Pages */}
        <Route path="/content/pages" element={<PagesPage />} />
        <Route path="/business/plans/*" element={<PlansPage />} />
        
        
        {/* Reports Page */}
        <Route path="/business/reports/*" element={<ReportsPage />} />
        
        {/* System Pages */}
        <Route path="/profile/*" element={<SettingsPage />} />
        {/* Workers moved to admin routes */}
        <Route path="/audit-logs" element={<AuditLogsPage />} />
        <Route path="/api-keys" element={<ApiKeysPage />} />
        
        {/* System Management Pages */}
        <Route path="/system/webhooks" element={<WebhookManagementPage />} />
        <Route path="/system/audit-logs" element={<SystemAuditLogsPage />} />
        
        {/* Business Analytics Pages */}
        <Route path="/business/analytics/*" element={<AnalyticsPage />} />
        <Route path="/metrics" element={<MetricsPage />} />
        
        {/* Admin routes - consistent with navigation */}
        <Route path="/users" element={<UsersPage />} />
        
        {/* Admin management routes */}
        <Route path="/admin/settings/*" element={<AdminSettingsPage />} />
        <Route path="/admin/users" element={<AdminUsersPage />} />
        <Route path="/admin/roles" element={<AdminRolesPage />} />
        <Route path="/system/workers" element={<SystemWorkersPage />} />
        <Route path="/admin/maintenance/*" element={<AdminMaintenancePage />} />
        <Route path="/admin" element={<Navigate to="/app/admin/settings" replace />} />
        
        {/* Test route */}
        <Route path="/test-websocket" element={<TestWebSocket />} />
      </Routes>
    </DashboardLayout>
  );
};

export { DashboardPage };