import React, { useState, useEffect, useRef } from 'react';
import { Routes, Route, useNavigate, Navigate } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { plansApi } from '@/features/plans/services/plansApi';
import { paymentGatewaysApi } from '@/features/payment-gateways/services/paymentGatewaysApi';
import { DashboardLayout } from '@/shared/components/layout/DashboardLayout';
import { MetricCard } from '@/shared/components/ui/Card';

// Import all dashboard pages
import { ReportsPage } from './business/ReportsPage';
import { PlansPage } from './business/PlansPage';
import { SettingsPage } from './SettingsPage';
import { PagesPage } from './content/PagesPage';
import KnowledgeBasePage from './content/KnowledgeBasePage';
import KnowledgeBaseArticlePage from './content/KnowledgeBaseArticlePage';
import KnowledgeBaseAdminPage from './content/KnowledgeBaseAdminPage';
import { KnowledgeBaseArticleEditor } from '@/features/knowledge-base/components/KnowledgeBaseArticleEditor';
import MyFilesPage from './content/MyFilesPage';
import { UsersPage } from './UsersPage';
import { AuditLogsPage } from './AuditLogsPage';
import { ApiKeysPage } from './ApiKeysPage';
import { NotificationsPage } from './NotificationsPage';
import { MetricsPage } from './MetricsPage';
import { AnalyticsPage } from './business/AnalyticsPage';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { BarChart3, Users, CreditCard } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';

// Import individual pages directly (no more management page groupings)
import { CustomersPage } from './business/CustomersPage';
import { BillingPage } from './business/BillingPage';

// Import system pages
import WebhookManagementPage from '@/pages/app/WebhookManagementPage';

// Import marketplace pages
import { MarketplacePage } from '@/pages/app/marketplace/MarketplacePage';
import { ItemDetailPage } from '@/pages/app/marketplace/ItemDetailPage';

// Import admin pages
import { AdminSettingsPage } from '@/pages/app/admin/AdminSettingsPage';
import { AdminUsersPage } from '@/pages/app/admin/AdminUsersPage';
import { AdminRolesPage } from '@/pages/app/admin/AdminRolesPage';
import { WorkersPage as SystemWorkersPage } from '@/pages/app/system/WorkersPage';
import { ServicesPage } from '@/pages/app/system/ServicesPage';
import StorageProvidersPage from '@/pages/app/system/StorageProvidersPage';
import { AdminMaintenancePage } from '@/pages/app/admin/AdminMaintenancePage';
import { AdminMarketplacePage } from '@/pages/app/admin/AdminMarketplacePage';

// Test page
import { TestWebSocket } from '@/pages/app/TestWebSocket';

// AI Pages - Standalone navigation (no longer using AIOrchestrationPage wrapper)
import { AIOverviewPage } from './ai/AIOverviewPage';
import { AIProvidersPage } from './ai/AIProvidersPage';
import { AIAgentsPage } from './ai/AIAgentsPage';
import { WorkflowsPage } from './ai/WorkflowsPage';
import { AIConversationsPage } from './ai/AIConversationsPage';
import { WorkflowAnalyticsPage } from './ai/WorkflowAnalyticsPage';
import { AIMonitoringPage } from './ai/AIMonitoringPage';
import { McpBrowserPage } from './ai/McpBrowserPage';
// AI Sub-pages
import { CreateWorkflowPage, WorkflowTemplatesPage, AIDebugPage } from './ai';
import AgentTeamsPage from './ai/AgentTeamsPage';
import { WorkflowDetailPage } from './ai/WorkflowDetailPage';
import { WorkflowImportPage } from './ai/WorkflowImportPage';
import { WorkflowMonitoringPage } from './ai/WorkflowMonitoringPage';
import { WorkflowValidationStatisticsPage } from './ai/WorkflowValidationStatisticsPage';
import { AIAnalyticsPage } from './ai/AIAnalyticsPage';

// Dashboard overview page
const DashboardOverview: React.FC = () => {
  const navigate = useNavigate();
  const { user } = useSelector((state: RootState) => state.auth);
  const [hasPlans, setHasPlans] = useState(false);
  const [hasPaymentGateways, setHasPaymentGateways] = useState(false);
  const [loading, setLoading] = useState(true);
  
  // StrictMode-safe: prevent duplicate API calls
  const hasCheckedStatusRef = useRef(false);

  useEffect(() => {
    let mounted = true; // Track if component is still mounted
    
    const checkSetupStatus = async () => {
      try {
        // Check plans using public endpoint (no auth required)
        const plansResponse = await plansApi.getPublicPlans();
        
        // Check payment gateway status (requires admin.settings.payment permission)
        let hasConfiguredGateways = false;
        try {
          const gatewaysOverview = await paymentGatewaysApi.getOverview();
          // Consider gateways configured if either Stripe or PayPal is connected/configured
          const stripeConfigured = gatewaysOverview.gateways.stripe.enabled && 
            ['connected', 'configured'].includes(gatewaysOverview.status.stripe.status);
          const paypalConfigured = gatewaysOverview.gateways.paypal.enabled && 
            ['connected', 'configured'].includes(gatewaysOverview.status.paypal.status);
          hasConfiguredGateways = stripeConfigured || paypalConfigured;
        } catch (_gatewayError) {
          // If user doesn't have permission or API fails, assume no gateways configured
          hasConfiguredGateways = false;
        }
        
        // Only update state if component is still mounted
        if (mounted) {
          setHasPlans(plansResponse.data.plans.length > 0);
          setHasPaymentGateways(hasConfiguredGateways);
        }
      } catch (_error) {
        if (mounted) {
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
    
    // Only check status once to prevent duplicate API calls in StrictMode
    if (!hasCheckedStatusRef.current) {
      hasCheckedStatusRef.current = true;
      checkSetupStatus();
    } else {
      // If we've already checked status, immediately set loading to false
      setLoading(false);
    }
    
    // Cleanup function to prevent state updates on unmounted component
    return () => {
      mounted = false;
    };
    // StrictMode-safe: removed user dependency to prevent double calls
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

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
    // Only show Payment Setup button if payment setup is required
    ...((!hasPaymentGateways && !loading) ? [{
      id: 'payment-gateways',
      label: 'Payment Setup',
      onClick: () => navigate('/app/admin/settings/payment-gateways'),
      variant: 'secondary' as const,
      icon: CreditCard
    }] : [])
  ];

  const breadcrumbs = [
    { label: 'Dashboard', icon: '🏠' }
  ];
  
  return (
    <PageContainer
      title={`Welcome back, ${user?.name || 'User'}! 👋`}
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
                  <Button 
                    onClick={() => navigate('/verify-email')}
                    variant="primary"
                    size="xs"
                    className="mt-2"
                  >
                    Verify Email
                  </Button>
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
                  <Button 
                    onClick={() => navigate('/app/business/plans')}
                    variant="primary"
                    size="xs"
                    className="mt-2"
                  >
                    Create Plan
                  </Button>
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
                  <Button 
                    onClick={() => navigate('/app/admin/settings/payment-gateways')}
                    variant="primary"
                    size="xs"
                    className="mt-2"
                  >
                    Configure Payments
                  </Button>
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
            <Button 
              onClick={() => navigate('/app/business/customers')}
              variant="secondary"
              className="flex items-center justify-between p-4 text-left hover:bg-theme-surface-hover w-full"
            >
              <div className="flex items-center space-x-3">
                <span className="text-2xl">👥</span>
                <div className="text-left">
                  <p className="font-medium text-theme-primary">Manage Customers</p>
                  <p className="text-xs text-theme-tertiary">View and organize your customer base</p>
                </div>
              </div>
              <span className="text-theme-tertiary">→</span>
            </Button>

            <Button 
              onClick={() => navigate('/app/business/analytics')}
              variant="secondary"
              className="flex items-center justify-between p-4 text-left hover:bg-theme-surface-hover w-full"
            >
              <div className="flex items-center space-x-3">
                <span className="text-2xl">📊</span>
                <div className="text-left">
                  <p className="font-medium text-theme-primary">View Analytics</p>
                  <p className="text-xs text-theme-tertiary">Track revenue and growth metrics</p>
                </div>
              </div>
              <span className="text-theme-tertiary">→</span>
            </Button>

            {/* Only show Payment Gateways button in Quick Actions if setup is needed */}
            {!hasPaymentGateways && !loading && (
              <Button 
                onClick={() => navigate('/app/admin/settings/payment-gateways')}
                variant="secondary"
                className="flex items-center justify-between p-4 text-left hover:bg-theme-surface-hover w-full"
              >
                <div className="flex items-center space-x-3">
                  <span className="text-2xl">💳</span>
                  <div className="text-left">
                    <p className="font-medium text-theme-primary">Payment Gateways</p>
                    <p className="text-xs text-theme-tertiary">Configure Stripe and PayPal</p>
                  </div>
                </div>
                <span className="text-theme-tertiary">→</span>
              </Button>
            )}

            <Button 
              onClick={() => navigate('/app/profile')}
              variant="secondary"
              className="flex items-center justify-between p-4 text-left hover:bg-theme-surface-hover w-full"
            >
              <div className="flex items-center space-x-3">
                <span className="text-2xl">⚙️</span>
                <div className="text-left">
                  <p className="font-medium text-theme-primary">Account Settings</p>
                  <p className="text-xs text-theme-tertiary">Customize your account preferences</p>
                </div>
              </div>
              <span className="text-theme-tertiary">→</span>
            </Button>
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

        {/* Notifications Page */}
        <Route path="/notifications" element={<NotificationsPage />} />

        {/* Individual Pages - No More Management Page Groupings */}
        
        {/* Business Pages */}
        <Route path="/business/customers" element={<CustomersPage />} />
        <Route path="/business/billing/*" element={<BillingPage />} />
        
        {/* AI Pages - Standalone navigation */}
        <Route path="/ai" element={<AIOverviewPage />} />
        <Route path="/ai/providers" element={<AIProvidersPage />} />
        <Route path="/ai/agents" element={<AIAgentsPage />} />
        <Route path="/ai/workflows" element={<WorkflowsPage />} />
        <Route path="/ai/conversations" element={<AIConversationsPage />} />
        <Route path="/ai/analytics" element={<WorkflowAnalyticsPage />} />
        <Route path="/ai/monitoring" element={<AIMonitoringPage />} />
        <Route path="/ai/mcp" element={<McpBrowserPage />} />

        {/* AI Sub-pages (detail/utility routes) */}
        <Route path="/ai/workflows/new" element={<CreateWorkflowPage />} />
        <Route path="/ai/workflows/templates" element={<WorkflowTemplatesPage />} />
        <Route path="/ai/workflows/import" element={<WorkflowImportPage />} />
        <Route path="/ai/workflows/monitoring" element={<WorkflowMonitoringPage />} />
        <Route path="/ai/workflows/validation-stats" element={<WorkflowValidationStatisticsPage />} />
        <Route path="/ai/workflows/:id" element={<WorkflowDetailPage />} />
        <Route path="/ai/analytics/system" element={<AIAnalyticsPage />} />
        <Route path="/ai/debug" element={<AIDebugPage />} />
        <Route path="/ai/agent-teams" element={<AgentTeamsPage />} />
        
        {/* Core Pages */}
        <Route path="/content/pages" element={<PagesPage />} />

        {/* My Files Page */}
        <Route path="/content/files" element={<MyFilesPage />} />

        {/* Knowledge Base Pages */}
        <Route path="/content/kb" element={<KnowledgeBasePage />} />
        <Route path="/content/kb/articles/:id" element={<KnowledgeBaseArticlePage />} />
        <Route path="/content/kb/articles/new" element={<KnowledgeBaseArticleEditor />} />
        <Route path="/content/kb/articles/:id/edit" element={<KnowledgeBaseArticleEditor />} />
        <Route path="/content/kb/admin" element={<KnowledgeBaseAdminPage />} />
        <Route path="/content/kb/manage" element={<KnowledgeBaseAdminPage />} />
        <Route path="/business/plans/*" element={<PlansPage />} />
        
        
        {/* Reports Page */}
        <Route path="/business/reports/*" element={<ReportsPage />} />
        
        {/* System Pages */}
        <Route path="/profile/*" element={<SettingsPage />} />
        {/* Workers moved to admin routes */}
        
        {/* System Management Pages */}
        <Route path="/system/services" element={<ServicesPage />} />
        <Route path="/system/storage" element={<StorageProvidersPage />} />
        <Route path="/system/webhooks" element={<WebhookManagementPage />} />
        <Route path="/system/audit-logs" element={<AuditLogsPage />} />
        <Route path="/system/api-keys" element={<ApiKeysPage />} />
        
        {/* Business Analytics Pages */}
        <Route path="/business/analytics/*" element={<AnalyticsPage />} />
        <Route path="/metrics" element={<MetricsPage />} />
        
        {/* Marketplace Pages - Unified Interface */}
        <Route path="/marketplace" element={<MarketplacePage />} />
        <Route path="/marketplace/:type/:id" element={<ItemDetailPage />} />
        
        {/* Admin routes - consistent with navigation */}
        <Route path="/users" element={<UsersPage />} />
        
        {/* Admin management routes */}
        <Route path="/admin/settings/*" element={<AdminSettingsPage />} />
        <Route path="/admin/users" element={<AdminUsersPage />} />
        <Route path="/admin/roles" element={<AdminRolesPage />} />
        <Route path="/admin/marketplace" element={<AdminMarketplacePage />} />
        <Route path="/system/workers/*" element={<SystemWorkersPage />} />
        <Route path="/admin/maintenance/*" element={<AdminMaintenancePage />} />
        <Route path="/admin" element={<Navigate to="/app/admin/settings" replace />} />
        
        {/* Redirect old admin settings to new services page */}
        <Route path="/admin/settings/reverse-proxy" element={<Navigate to="/app/system/services" replace />} />
        
        {/* Test route */}
        <Route path="/test-websocket" element={<TestWebSocket />} />
      </Routes>
    </DashboardLayout>
  );
};

export { DashboardPage };