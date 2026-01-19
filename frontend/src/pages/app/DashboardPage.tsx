import React, { useState, useEffect, useCallback } from 'react';
import { Routes, Route, useNavigate, Navigate } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { plansApi } from '@/features/business/plans/services/plansApi';
import { paymentGatewaysApi } from '@/features/business/payment-gateways/services/paymentGatewaysApi';
import { DashboardLayout } from '@/shared/components/layout/DashboardLayout';
import { MetricCard } from '@/shared/components/ui/Card';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';

// Import all dashboard pages
import { ReportsPage } from './business/ReportsPage';
import { PlansPage } from './business/PlansPage';
import { ProfilePage } from './account/ProfilePage';
import { PagesPage } from './content/PagesPage';
import KnowledgeBasePage from './content/KnowledgeBasePage';
import KnowledgeBaseArticlePage from './content/KnowledgeBaseArticlePage';
import KnowledgeBaseAdminPage from './content/KnowledgeBaseAdminPage';
import { KnowledgeBaseArticleEditor } from '@/features/content/knowledge-base/components/KnowledgeBaseArticleEditor';
import MyFilesPage from './content/MyFilesPage';
import { UsersPage } from './account/UsersPage';
import { AuditLogsPage } from './system/AuditLogsPage';
import PrivacyDashboardPage from './privacy/PrivacyDashboardPage';
import { ApiKeysPage } from './devops/ApiKeysPage';
import { NotificationsPage } from './account/NotificationsPage';
import { MetricsPage } from './business/MetricsPage';
import { AnalyticsPage } from './business/AnalyticsPage';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { BarChart3, Users, CreditCard } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';

// Import individual pages directly (no more management page groupings)
import { CustomersPage } from './business/CustomersPage';
import { BillingPage } from './business/BillingPage';

// Import system pages
import WebhookManagementPage from '@/pages/app/devops/WebhooksPage';

// Import marketplace pages
import { MarketplacePage } from '@/pages/app/marketplace/MarketplacePage';
import { ItemDetailPage } from '@/pages/app/marketplace/ItemDetailPage';
import { MySubscriptionsPage } from '@/pages/app/marketplace/MySubscriptionsPage';

// Import admin pages
import { AdminSettingsPage } from '@/pages/app/admin/AdminSettingsPage';
import { AdminUsersPage } from '@/pages/app/admin/AdminUsersPage';
import { AdminRolesPage } from '@/pages/app/admin/AdminRolesPage';
import { WorkersPage as SystemWorkersPage } from '@/pages/app/system/WorkersPage';
import { ServicesPage } from '@/pages/app/system/ServicesPage';
import StorageProvidersPage from '@/pages/app/system/StorageProvidersPage';
// GitProvidersPage moved to Connections - route redirects to connections/git

// CI/CD Pages (used in System section for runners)
import {
  RunnersPage as AiPipelinesRunnersPage,
} from '@/features/devops/pipelines';

// Provider Pages
import { AIProvidersPage } from './ai/AIProvidersPage';
import { GitProvidersPage } from './devops/GitProvidersPage';
import { RepositoriesPage } from './devops/RepositoriesPage';
import { AdminMaintenancePage } from '@/pages/app/admin/AdminMaintenancePage';
import { AdminMarketplacePage } from '@/pages/app/admin/AdminMarketplacePage';
// AdminPluginsPage deprecated - now redirects to admin/marketplace
import { AdminImpersonationPage } from '@/pages/app/admin/AdminImpersonationPage';

// Test page
import { TestWebSocket } from '@/pages/app/TestWebSocket';

// AI Pages - Standalone navigation (no longer using AIOrchestrationPage wrapper)
import { AIOverviewPage } from './ai/AIOverviewPage';
// AIProvidersPage moved to Connections - route redirects to connections/ai
import { AIAgentsPage } from './ai/AIAgentsPage';
import { WorkflowsPage } from './ai/WorkflowsPage';
import { AIConversationsPage } from './ai/AIConversationsPage';
import { WorkflowAnalyticsPage } from './ai/WorkflowAnalyticsPage';
import { AIMonitoringPage } from './ai/AIMonitoringPage';
import { McpBrowserPage } from './ai/McpBrowserPage';
// AI Sub-pages
import { CreateWorkflowPage, AIDebugPage } from './ai';
import AgentTeamsPage from './ai/AgentTeamsPage';
import AgentMarketplacePage from './ai/AgentMarketplacePage';
import GovernancePage from './ai/GovernancePage';
import SandboxPage from './ai/SandboxPage';
import DevOpsTemplatesPage from './ai/DevOpsTemplatesPage';
import { WorkflowDetailPage } from './ai/WorkflowDetailPage';
import { WorkflowImportPage } from './ai/WorkflowImportPage';
import { WorkflowMonitoringPage } from './ai/WorkflowMonitoringPage';
import { WorkflowValidationStatisticsPage } from './ai/WorkflowValidationStatisticsPage';
import { AIAnalyticsPage } from './ai/AIAnalyticsPage';

// AI Context Pages
import { AgentMemoryPage } from './ai/AgentMemoryPage';
import { ContextsPage } from './ai/ContextsPage';
import { ContextDetailPage } from './ai/ContextDetailPage';

// Prompt Templates
import { PromptsPage } from '@/features/ai/prompts/pages/PromptsPage';

// Integration Pages
// IntegrationsMarketplacePage deprecated - now redirects to marketplace?types=integration
import {
  IntegrationsPage,
  IntegrationDetailPage,
  NewIntegrationPage,
} from '@/pages/app/devops/integrations';

// DevOps Pages
import { DevOpsOverviewPage } from '@/pages/app/devops/DevOpsOverviewPage';
import { PipelinesPage } from '@/pages/app/devops/PipelinesPage';
import { PipelineCreatePage } from '@/pages/app/devops/PipelineCreatePage';
import { PipelineDetailPage } from '@/pages/app/devops/PipelineDetailPage';
import { PipelineEditPage } from '@/pages/app/devops/PipelineEditPage';
import { RunnerDetailPage } from '@/pages/app/devops/RunnerDetailPage';

// Dashboard overview page
const DashboardOverview: React.FC = () => {
  const navigate = useNavigate();
  const { user } = useSelector((state: RootState) => state.auth);
  const [hasPlans, setHasPlans] = useState(false);
  const [hasPaymentGateways, setHasPaymentGateways] = useState(false);
  const [loading, setLoading] = useState(true);

  // Handle websocket data updates
  const handleDataUpdate = useCallback(() => {
    // Refresh data when receiving real-time updates
    // Could trigger a re-fetch of metrics here
  }, []);

  // WebSocket connection for real-time dashboard updates
  const { isConnected: _wsConnected } = usePageWebSocket({
    pageType: 'dashboard',
    onDataUpdate: handleDataUpdate,
    onSubscriptionUpdate: handleDataUpdate,
    onAnalyticsUpdate: handleDataUpdate,
    onNotification: handleDataUpdate
  });

  useEffect(() => {
    let mounted = true; // Track if component is still mounted
    
    const checkSetupStatus = async () => {
      try {
        // Check plans status using dedicated endpoint (counts all plans regardless of permissions)
        let hasPlansConfigured = false;
        try {
          const statusResponse = await plansApi.getStatus();
          hasPlansConfigured = statusResponse.data?.has_plans ?? statusResponse.data?.total_count > 0;
        } catch {
          // Fallback to checking public plans if status endpoint fails
          try {
            const publicPlansResponse = await plansApi.getPublicPlans();
            hasPlansConfigured = (publicPlansResponse.data?.plans?.length ?? 0) > 0;
          } catch {
            hasPlansConfigured = false;
          }
        }

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
          setHasPlans(hasPlansConfigured);
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
    
    // Run check on mount
    checkSetupStatus();

    // Cleanup function to prevent state updates on unmounted component
    return () => {
      mounted = false;
    };
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
    { label: 'Dashboard', href: '/app' },
    { label: 'Dashboard' }
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
        <Route path="/account/billing/*" element={<BillingPage />} />
        
        {/* AI Pages - Standalone navigation */}
        <Route path="/ai" element={<AIOverviewPage />} />
        <Route path="/ai/providers" element={<AIProvidersPage />} />
        <Route path="/ai/providers/new" element={<AIProvidersPage />} />
        <Route path="/ai/providers/:id" element={<AIProvidersPage />} />
        <Route path="/ai/agents" element={<AIAgentsPage />} />
        <Route path="/ai/workflows" element={<WorkflowsPage />} />
        <Route path="/ai/conversations" element={<AIConversationsPage />} />
        <Route path="/ai/analytics" element={<WorkflowAnalyticsPage />} />
        <Route path="/ai/monitoring/:tab?" element={<AIMonitoringPage />} />
        <Route path="/ai/mcp" element={<McpBrowserPage />} />

        {/* AI Sub-pages (detail/utility routes) */}
        <Route path="/ai/workflows/new" element={<CreateWorkflowPage />} />
        <Route path="/ai/workflows/import" element={<WorkflowImportPage />} />
        <Route path="/ai/workflows/monitoring" element={<WorkflowMonitoringPage />} />
        <Route path="/ai/workflows/validation-stats" element={<WorkflowValidationStatisticsPage />} />
        <Route path="/ai/workflows/:id" element={<WorkflowDetailPage />} />
        <Route path="/ai/analytics/system" element={<AIAnalyticsPage />} />
        <Route path="/ai/debug" element={<AIDebugPage />} />
        <Route path="/ai/agent-teams" element={<AgentTeamsPage />} />
        <Route path="/ai/contexts" element={<ContextsPage />} />
        <Route path="/ai/knowledge" element={<Navigate to="/app/ai/contexts" replace />} />
        <Route path="/ai/contexts/:id" element={<ContextDetailPage />} />
        <Route path="/ai/agents/:agentId/memory" element={<AgentMemoryPage />} />
        <Route path="/ai/prompts" element={<PromptsPage />} />
        <Route path="/ai/agent-marketplace" element={<AgentMarketplacePage />} />
        <Route path="/ai/governance" element={<GovernancePage />} />
        <Route path="/ai/sandbox" element={<SandboxPage />} />
        <Route path="/ai/devops-templates" element={<DevOpsTemplatesPage />} />
        <Route path="/ai/plugins" element={<Navigate to="/app/marketplace?types=plugin" replace />} />

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
        <Route path="/profile/*" element={<ProfilePage />} />

        {/* Privacy Page */}
        <Route path="/privacy" element={<PrivacyDashboardPage />} />
        {/* Workers moved to admin routes */}
        
        {/* System Management Pages */}
        <Route path="/system/services" element={<ServicesPage />} />
        <Route path="/system/storage" element={<StorageProvidersPage />} />

        {/* DevOps Pages - Git, Repositories, Runners, Webhooks, Integrations, API Keys */}
        <Route path="/devops" element={<DevOpsOverviewPage />} />
        <Route path="/devops/git" element={<GitProvidersPage />} />
        <Route path="/devops/git/new" element={<GitProvidersPage />} />
        <Route path="/devops/git/:id" element={<GitProvidersPage />} />
        <Route path="/devops/repositories" element={<RepositoriesPage />} />
        <Route path="/devops/runners" element={<AiPipelinesRunnersPage />} />
        <Route path="/devops/runners/:id" element={<RunnerDetailPage />} />
        <Route path="/devops/webhooks" element={<WebhookManagementPage />} />
        <Route path="/devops/integrations" element={<IntegrationsPage />} />
        <Route path="/devops/integrations/new" element={<NewIntegrationPage />} />
        <Route path="/devops/integrations/new/:templateId" element={<NewIntegrationPage />} />
        <Route path="/devops/integrations/:id" element={<IntegrationDetailPage />} />
        <Route path="/devops/api-keys" element={<ApiKeysPage />} />

        {/* System Pages - Infrastructure only */}
        <Route path="/system/audit-logs/*" element={<AuditLogsPage />} />

        {/* DevOps Pipelines */}
        <Route path="/devops/pipelines" element={<PipelinesPage />} />
        <Route path="/devops/pipelines/new" element={<PipelineCreatePage />} />
        <Route path="/devops/pipelines/:id" element={<PipelineDetailPage />} />
        <Route path="/devops/pipelines/:id/edit" element={<PipelineEditPage />} />
        <Route path="/devops/pipelines/:id/runs" element={<PipelineDetailPage />} />
        <Route path="/devops/pipelines/:id/runs/:runId" element={<PipelineDetailPage />} />

        {/* Business Analytics Pages */}
        <Route path="/business/analytics/*" element={<AnalyticsPage />} />
        <Route path="/metrics" element={<MetricsPage />} />
        
        {/* Marketplace Pages */}
        <Route path="/marketplace" element={<MarketplacePage />} />
        <Route path="/marketplace/:type/:id" element={<ItemDetailPage />} />
        <Route path="/marketplace/subscriptions" element={<MySubscriptionsPage />} />

        {/* Admin routes - consistent with navigation */}
        <Route path="/users" element={<UsersPage />} />
        
        {/* Admin management routes */}
        <Route path="/admin/settings/*" element={<AdminSettingsPage />} />
        <Route path="/admin/users" element={<AdminUsersPage />} />
        <Route path="/admin/roles" element={<AdminRolesPage />} />
        <Route path="/admin/marketplace" element={<AdminMarketplacePage />} />
        <Route path="/admin/marketplace/apps/:id/edit" element={<Navigate to="/app/admin/marketplace" replace />} />
        {/* Legacy: redirect to consolidated marketplace admin with plugin filter */}
        <Route path="/admin/plugins" element={<Navigate to="/app/admin/marketplace?types=plugin" replace />} />
        <Route path="/admin/impersonation" element={<AdminImpersonationPage />} />
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