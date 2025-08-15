import React, { useState, useEffect } from 'react';
import { Routes, Route, useNavigate } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { RootState } from '../../store';
import { plansApi } from '../../services/plansApi';
import { paymentGatewaysApi } from '../../services/paymentGatewaysApi';
import { DashboardLayout } from '../../components/dashboard/DashboardLayout';

// Import all dashboard pages
import { AnalyticsPage } from '../analytics/AnalyticsPage';
import { SubscriptionsPage } from './SubscriptionsPage';
import { ReportsPage } from './ReportsPage';
import { PlansPage } from './PlansPage';
import { SettingsPage } from './SettingsPage';
import { PaymentGatewaysPage } from './PaymentGatewaysPage';
import { WorkersPage } from './WorkersPage';
import { PagesPage } from './PagesPage';
import { UsersPage } from './UsersPage';
import { AdminSettingsPage } from '../admin';
import { AuditLogsPage } from './AuditLogsPage';
import { ApiKeysPage } from './ApiKeysPage';
import { MetricsPage } from './MetricsPage';
import { PageContainer, PageAction } from '../../components/layout/PageContainer';
import { BarChart3, Users, CreditCard, Settings } from 'lucide-react';

// Import individual pages directly (no more management page groupings)
import { CustomersPage } from './CustomersPage';
import { BillingPage } from './BillingPage';

// Import system pages
import WebhookManagementPage from '../system/WebhookManagementPage';
import { AuditLogsPage as SystemAuditLogsPage } from '../system/AuditLogsPage';

// Dashboard overview page
const DashboardOverview: React.FC = () => {
  const navigate = useNavigate();
  const { user } = useSelector((state: RootState) => state.auth);
  const [hasPlans, setHasPlans] = useState(false);
  const [hasPaymentGateways, setHasPaymentGateways] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const checkSetupStatus = async () => {
      try {
        // Check plans
        const plansResponse = await plansApi.getPlans();
        setHasPlans(plansResponse.data.plans.length > 0);
        
        // Check payment gateways
        const gatewaysResponse = await paymentGatewaysApi.getOverview();
        const hasStripe = gatewaysResponse.gateways.stripe.enabled && 
                         gatewaysResponse.status.stripe.status === 'connected';
        const hasPayPal = gatewaysResponse.gateways.paypal.enabled && 
                         gatewaysResponse.status.paypal.status === 'connected';
        setHasPaymentGateways(hasStripe || hasPayPal);
      } catch (error) {
        console.error('Failed to check setup status:', error);
        // Assume no setup on error
        setHasPlans(false);
        setHasPaymentGateways(false);
      } finally {
        setLoading(false);
      }
    };

    checkSetupStatus();
  }, []);

  // Calculate completion status
  const completedTasks = [
    true, // Account created (always true if user is logged in)
    user?.emailVerified || false, // Email verification (check actual status)
    hasPlans, // Plans setup
    hasPaymentGateways // Payment gateways configured
  ];
  const completedCount = completedTasks.filter(Boolean).length;
  const totalTasks = completedTasks.length;
  
  const pageActions: PageAction[] = [
    {
      id: 'analytics',
      label: 'Analytics',
      onClick: () => navigate('/dashboard/analytics'),
      variant: 'secondary',
      icon: BarChart3
    },
    {
      id: 'customers',
      label: 'Customers',
      onClick: () => navigate('/dashboard/customers'),
      variant: 'secondary',
      icon: Users
    },
    {
      id: 'payment-gateways',
      label: 'Payment Setup',
      onClick: () => navigate('/dashboard/payment-gateways'),
      variant: 'secondary',
      icon: CreditCard
    },
    {
      id: 'settings',
      label: 'Settings',
      onClick: () => navigate('/dashboard/settings'),
      variant: 'primary',
      icon: Settings
    }
  ];

  const breadcrumbs = [
    { label: 'Dashboard', icon: '🏠' }
  ];
  
  return (
    <PageContainer
      title={`Welcome back, ${user?.firstName}! 👋`}
      description="Here's an overview of your account activity and system status."
      breadcrumbs={breadcrumbs}
      actions={pageActions}
    >
      <div className="space-y-6">
        {/* Key Metrics Cards */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <div className="card-theme p-6 transition-theme-fast hover:shadow-theme-md">
          <div className="flex items-center justify-between">
            <div>
              <h3 className="text-sm font-medium text-theme-tertiary mb-1">Total Revenue</h3>
              <p className="text-3xl font-bold text-theme-primary">$0.00</p>
              <p className="text-xs text-theme-success mt-1">↗ +0% from last month</p>
            </div>
            <div className="h-12 w-12 bg-theme-success rounded-xl flex items-center justify-center bg-opacity-10">
              <span className="text-2xl">💰</span>
            </div>
          </div>
        </div>

        <div className="card-theme p-6 transition-theme-fast hover:shadow-theme-md">
          <div className="flex items-center justify-between">
            <div>
              <h3 className="text-sm font-medium text-theme-tertiary mb-1">Active Subscriptions</h3>
              <p className="text-3xl font-bold text-theme-primary">0</p>
              <p className="text-xs text-theme-info mt-1">Ready to grow</p>
            </div>
            <div className="h-12 w-12 bg-theme-info rounded-xl flex items-center justify-center bg-opacity-10">
              <span className="text-2xl">📊</span>
            </div>
          </div>
        </div>

        <div className="card-theme p-6 transition-theme-fast hover:shadow-theme-md">
          <div className="flex items-center justify-between">
            <div>
              <h3 className="text-sm font-medium text-theme-tertiary mb-1">Monthly Growth</h3>
              <p className="text-3xl font-bold text-theme-primary">0%</p>
              <p className="text-xs text-theme-warning mt-1">Start your journey</p>
            </div>
            <div className="h-12 w-12 bg-theme-warning rounded-xl flex items-center justify-center bg-opacity-10">
              <span className="text-2xl">📈</span>
            </div>
          </div>
        </div>

        <div className="card-theme p-6 transition-theme-fast hover:shadow-theme-md">
          <div className="flex items-center justify-between">
            <div>
              <h3 className="text-sm font-medium text-theme-tertiary mb-1">System Health</h3>
              <p className="text-3xl font-bold text-theme-success">100%</p>
              <p className="text-xs text-theme-success mt-1">All systems operational</p>
            </div>
            <div className="h-12 w-12 bg-theme-success rounded-xl flex items-center justify-center bg-opacity-10">
              <span className="text-2xl">✅</span>
            </div>
          </div>
        </div>
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
                  user?.emailVerified ? 'bg-theme-success' : 'bg-theme-error'
                }`}>
                  <span className="text-white text-xs">
                    {user?.emailVerified ? '✓' : '✗'}
                  </span>
                </div>
              </div>
              <div className="flex-1">
                <p className={`text-sm font-medium ${
                  user?.emailVerified ? 'text-theme-primary' : 'text-theme-primary'
                }`}>
                  {user?.emailVerified ? 'Email verification completed' : 'Email verification required'}
                </p>
                <p className="text-xs text-theme-tertiary mt-1">
                  {user?.emailVerified ? 'Your email address has been verified' : 'Please verify your email address'}
                </p>
                {!user?.emailVerified && (
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
                    onClick={() => navigate('/dashboard/plans')}
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
                    onClick={() => navigate('/dashboard/payment-gateways')}
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
              onClick={() => navigate('/dashboard/customers')}
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
              onClick={() => navigate('/dashboard/analytics')}
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
              onClick={() => navigate('/dashboard/payment-gateways')}
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
              onClick={() => navigate('/dashboard/settings')}
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
        <Route path="/customers" element={<CustomersPage />} />
        <Route path="/subscriptions" element={<SubscriptionsPage />} />
        <Route path="/billing" element={<BillingPage />} />
        
        {/* Core Pages */}
        <Route path="/pages" element={<PagesPage />} />
        <Route path="/plans" element={<PlansPage />} />
        <Route path="/plans/new" element={<PlansPage />} />
        
        {/* Admin Settings (Tabbed Version Only) */}
        <Route path="/admin-settings/*" element={<AdminSettingsPage />} />
        
        {/* Analytics Pages */}
        <Route path="/analytics" element={<AnalyticsPage />} />
        <Route path="/reports" element={<ReportsPage />} />
        
        {/* System Pages */}
        <Route path="/settings" element={<SettingsPage />} />
        <Route path="/payment-gateways" element={<PaymentGatewaysPage />} />
        <Route path="/workers" element={<WorkersPage />} />
        <Route path="/audit-logs" element={<AuditLogsPage />} />
        <Route path="/api-keys" element={<ApiKeysPage />} />
        
        {/* System Management Pages */}
        <Route path="/system/webhooks" element={<WebhookManagementPage />} />
        <Route path="/system/audit-logs" element={<SystemAuditLogsPage />} />
        
        {/* Additional Analytics Pages */}
        <Route path="/metrics" element={<MetricsPage />} />
        
        {/* Account Management - Profile and Settings */}
        <Route path="/profile" element={<SettingsPage />} />
        <Route path="/account/*" element={<SettingsPage />} />
        
        {/* Admin routes - consistent with navigation */}
        <Route path="/users" element={<UsersPage />} />
      </Routes>
    </DashboardLayout>
  );
};

export { DashboardPage };