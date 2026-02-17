import React, { useCallback, Suspense } from 'react';
import { Routes, Route, useNavigate } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { DashboardLayout } from '@/shared/components/layout/DashboardLayout';
import { MetricCard } from '@/shared/components/ui/Card';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { featureRegistry } from '@/shared/services/featureRegistry';

// Import all dashboard pages
import { ProfilePage } from './account/ProfilePage';
import { PagesPage } from './content/PagesPage';
import KnowledgeBasePage from './content/KnowledgeBasePage';
import KnowledgeBaseArticlePage from './content/KnowledgeBaseArticlePage';
import KnowledgeBaseAdminPage from './content/KnowledgeBaseAdminPage';
import { KnowledgeBaseArticleEditor } from '@/features/content/knowledge-base/components/KnowledgeBaseArticleEditor';
import MyFilesPage from './content/MyFilesPage';
import { UsersPage } from './account/UsersPage';
import { AuditLogsPage } from './admin/AuditLogsPage';
import PrivacyDashboardPage from './privacy/PrivacyDashboardPage';
import { NotificationsPage } from './account/NotificationsPage';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { BarChart3, Users } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';

// Import marketplace pages
import { MarketplacePage } from '@/pages/app/marketplace/MarketplacePage';
import { ItemDetailPage } from '@/pages/app/marketplace/ItemDetailPage';
import { MySubscriptionsPage } from '@/pages/app/marketplace/MySubscriptionsPage';

// Import admin pages
import { AdminSettingsPage } from '@/pages/app/admin/AdminSettingsPage';
import { AdminUsersPage } from '@/pages/app/admin/AdminUsersPage';
import { AdminRolesPage } from '@/pages/app/admin/AdminRolesPage';
import { WorkersPage as AdminWorkersPage } from '@/pages/app/admin/WorkersPage';
import AdminStoragePage from '@/pages/app/admin/StorageProvidersPage';

// Provider Pages
import { AIProvidersPage } from './ai/AIProvidersPage';
import { GitProvidersPage } from './devops/GitProvidersPage';
import { AdminMaintenancePage } from '@/pages/app/admin/AdminMaintenancePage';
import { AdminMarketplacePage } from '@/pages/app/admin/AdminMarketplacePage';
// AI Pages - Primary navigation
import { AIOverviewPage } from './ai/AIOverviewPage';
import { AIAgentsPage } from './ai/AIAgentsPage';
import { WorkflowsPage } from './ai/WorkflowsPage';
import { AIMonitoringPage } from './ai/AIMonitoringPage';
import GovernancePage from './ai/GovernancePage';
import SandboxPage from './ai/SandboxPage';

// AI Pages - New tabbed wrappers
import { ExecutionPage } from './ai/ExecutionPage';
import { KnowledgePage } from './ai/KnowledgePage';
import { InfrastructurePage } from './ai/InfrastructurePage';
import { AiBillingPage } from './ai/AiBillingPage';

// AI Sub-pages
import { CreateWorkflowPage, AIDebugPage } from './ai';
import { AgentDetailPage } from './ai/AgentDetailPage';
import { WorkflowDetailPage } from './ai/WorkflowDetailPage';
import { WorkflowImportPage } from './ai/WorkflowImportPage';
import { WorkflowMonitoringPage } from './ai/WorkflowMonitoringPage';
import { WorkflowValidationStatisticsPage } from './ai/WorkflowValidationStatisticsPage';
import { AIAnalyticsPage } from './ai/AIAnalyticsPage';
import { AgentMemoryPage } from './ai/AgentMemoryPage';
import { ContextDetailPage } from './ai/ContextDetailPage';
// AI Hidden pages (no nav, still accessible)
import { SelfHealingDashboard } from '@/features/ai/self-healing/SelfHealingDashboard';
import { RecommendationsDashboard } from '@/features/ai/learning/RecommendationsDashboard';
import { TrajectoryInsights } from '@/features/ai/learning/TrajectoryInsights';

// AI Agent Orchestration pages
import { SandboxDashboardPage } from '@/features/ai/sandboxes';
import { AutonomyDashboardPage } from '@/features/ai/autonomy';
import CompoundLearningPage from './ai/CompoundLearningPage';
import { AuditDashboardPage } from '@/features/ai/audit';
import { SecurityDashboardPage } from '@/features/ai/security';
import { EvaluationDashboardPage } from '@/features/ai/evaluation';
// AI Communication hub
import { CommunicationPage } from './ai/CommunicationPage';
// AI Code Factory
import { CodeFactoryPage } from '@/features/ai/code-factory';

// Container Orchestration (Sandboxed AI execution)
import { ContainersPage } from '@/features/devops/containers/pages/ContainersPage';

// Docker Swarm detail routes
import { ClusterProvider } from '@/features/devops/swarm/context/ClusterContext';
import { ClusterDashboardPage } from '@/features/devops/swarm/pages/ClusterDashboardPage';
import { SwarmNodesPage } from '@/features/devops/swarm/pages/SwarmNodesPage';
import { SwarmServiceDetailPage } from '@/features/devops/swarm/pages/SwarmServiceDetailPage';

// Docker Host detail routes
import { HostProvider } from '@/features/devops/docker/context/HostContext';
import { HostDashboardPage } from '@/features/devops/docker/pages/HostDashboardPage';
import { ContainerDetailPage } from '@/features/devops/docker/pages/ContainerDetailPage';

// AI Feature Pages (standalone)
import TeamsPage from './ai/TeamsPage';
import DevOpsTemplatesPage from './ai/DevOpsTemplatesPage';
import { WorkflowAnalyticsPage } from './ai/WorkflowAnalyticsPage';

// Integration detail routes
import {
  IntegrationDetailPage,
  NewIntegrationPage,
} from '@/pages/app/devops/integrations';

// DevOps Pages
import { DevOpsOverviewPage } from '@/pages/app/devops/DevOpsOverviewPage';
import { PipelineCreatePage } from '@/pages/app/devops/PipelineCreatePage';
import { PipelineDetailPage } from '@/pages/app/devops/PipelineDetailPage';
import { PipelineEditPage } from '@/pages/app/devops/PipelineEditPage';
import { RunnerDetailPage } from '@/pages/app/devops/RunnerDetailPage';

// DevOps Hub Pages
import { SourceControlPage } from '@/pages/app/devops/SourceControlPage';
import { CiCdPage } from '@/pages/app/devops/CiCdPage';
import { ConnectionsPage } from '@/pages/app/devops/ConnectionsPage';
import { SwarmHubPage } from '@/pages/app/devops/SwarmHubPage';
import { DockerHubPage } from '@/pages/app/devops/DockerHubPage';

// Marketing Pages
import { MarketingCampaignsPage } from '@/pages/app/marketing/MarketingCampaignsPage';
import { MarketingCampaignDetailPage } from '@/pages/app/marketing/MarketingCampaignDetailPage';
import { MarketingCalendarPage } from '@/pages/app/marketing/MarketingCalendarPage';
import { MarketingEmailListsPage } from '@/pages/app/marketing/MarketingEmailListsPage';
import { MarketingSocialPage } from '@/pages/app/marketing/MarketingSocialPage';
import { MarketingAnalyticsPage } from '@/pages/app/marketing/MarketingAnalyticsPage';

// Supply Chain Pages
import {
  SupplyChainDashboardPage,
  SbomsPage,
  SbomDetailPage,
  SbomDiffPage,
  ContainerImagesPage,
  ContainerImageDetailPage,
  AttestationsPage,
  AttestationDetailPage,
  VendorsPage,
  VendorDetailPage,
  VendorRiskDashboardPage,
  AssessmentDetailPage,
  QuestionnaireDetailPage,
  LicensePoliciesPage,
  LicensePolicyFormPage,
  LicensePolicyDetailPage,
  LicenseViolationsPage,
  LicenseViolationDetailPage,
} from '@/features/supply-chain/pages';

// Dashboard overview page
const DashboardOverview: React.FC = () => {
  const navigate = useNavigate();
  const { user } = useSelector((state: RootState) => state.auth);
  // Handle websocket data updates
  const handleDataUpdate = useCallback(() => {
    // Refresh data when receiving real-time updates
  }, []);

  // WebSocket connection for real-time dashboard updates
  usePageWebSocket({
    pageType: 'dashboard',
    onDataUpdate: handleDataUpdate,
    onSubscriptionUpdate: handleDataUpdate,
    onAnalyticsUpdate: handleDataUpdate,
    onNotification: handleDataUpdate
  });

  // Calculate completion status
  const completedTasks = [
    true, // Account created (always true if user is logged in)
    user?.email_verified || false, // Email verification
  ];
  const completedCount = completedTasks.filter(Boolean).length;
  const totalTasks = completedTasks.length;

  const pageActions: PageAction[] = [
    {
      id: 'ai-overview',
      label: 'AI Overview',
      onClick: () => navigate('/app/ai'),
      variant: 'secondary',
      icon: BarChart3
    },
    {
      id: 'devops',
      label: 'DevOps',
      onClick: () => navigate('/app/devops'),
      variant: 'secondary',
      icon: Users
    }
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
            title="System Health"
            value="100%"
            icon="✅"
            description="All systems operational"
          />

          <MetricCard
            title="AI Agents"
            value={0}
            icon="🤖"
            description="Configure AI agents"
          />

          <MetricCard
            title="Pipelines"
            value={0}
            icon="🔄"
            description="Set up CI/CD pipelines"
          />

          <MetricCard
            title="Repositories"
            value={0}
            icon="📦"
            description="Connect your repos"
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
              {`${completedCount} of ${totalTasks} complete`}
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


          </div>
        </div>

        {/* Quick Actions Card */}
        <div className="card-theme-elevated p-6">
          <h3 className="text-xl font-semibold text-theme-primary mb-6">
            Quick Actions
          </h3>
          
          <div className="grid grid-cols-1 gap-3">
            <Button
              onClick={() => navigate('/app/ai')}
              variant="secondary"
              className="flex items-center justify-between p-4 text-left hover:bg-theme-surface-hover w-full"
            >
              <div className="flex items-center space-x-3">
                <span className="text-2xl">🤖</span>
                <div className="text-left">
                  <p className="font-medium text-theme-primary">AI Workflows</p>
                  <p className="text-xs text-theme-tertiary">Manage AI agents and workflows</p>
                </div>
              </div>
              <span className="text-theme-tertiary">→</span>
            </Button>

            <Button
              onClick={() => navigate('/app/devops')}
              variant="secondary"
              className="flex items-center justify-between p-4 text-left hover:bg-theme-surface-hover w-full"
            >
              <div className="flex items-center space-x-3">
                <span className="text-2xl">🔧</span>
                <div className="text-left">
                  <p className="font-medium text-theme-primary">DevOps</p>
                  <p className="text-xs text-theme-tertiary">Pipelines, containers, and infrastructure</p>
                </div>
              </div>
              <span className="text-theme-tertiary">→</span>
            </Button>

            <Button
              onClick={() => navigate('/app/supply-chain')}
              variant="secondary"
              className="flex items-center justify-between p-4 text-left hover:bg-theme-surface-hover w-full"
            >
              <div className="flex items-center space-x-3">
                <span className="text-2xl">🔗</span>
                <div className="text-left">
                  <p className="font-medium text-theme-primary">Supply Chain</p>
                  <p className="text-xs text-theme-tertiary">SBOMs, attestations, and compliance</p>
                </div>
              </div>
              <span className="text-theme-tertiary">→</span>
            </Button>

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
              Your self-hosted platform is set up and ready. Start by connecting AI providers and setting up your first workflow!
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
        
        {/* AI Pages - Primary navigation */}
        <Route path="/ai" element={<AIOverviewPage />} />
        <Route path="/ai/agents/list" element={<AIAgentsPage />} />
        <Route path="/ai/agents/cards" element={<AIAgentsPage />} />
        <Route path="/ai/agents/marketplace" element={<AIAgentsPage />} />
        <Route path="/ai/agents/community" element={<AIAgentsPage />} />
        <Route path="/ai/agents/:agentId/memory/*" element={<AgentMemoryPage />} />
        <Route path="/ai/agents/:agentId/*" element={<AgentDetailPage />} />
        <Route path="/ai/agents/*" element={<AIAgentsPage />} />
        <Route path="/ai/teams" element={<TeamsPage />} />
        <Route path="/ai/workflows/new" element={<CreateWorkflowPage />} />
        <Route path="/ai/workflows/import" element={<WorkflowImportPage />} />
        <Route path="/ai/workflows/monitoring" element={<WorkflowMonitoringPage />} />
        <Route path="/ai/workflows/validation-stats" element={<WorkflowValidationStatisticsPage />} />
        <Route path="/ai/workflows/templates" element={<WorkflowsPage />} />
        <Route path="/ai/workflows/:id" element={<WorkflowDetailPage />} />
        <Route path="/ai/workflows/*" element={<WorkflowsPage />} />
        <Route path="/ai/communication/*" element={<CommunicationPage />} />
        <Route path="/ai/governance" element={<GovernancePage />} />
        <Route path="/ai/sandbox" element={<SandboxPage />} />

        {/* AI Pages - Tabbed wrappers */}
        <Route path="/ai/execution/*" element={<ExecutionPage />} />
        <Route path="/ai/contexts/:id" element={<ContextDetailPage />} />
        <Route path="/ai/knowledge/contexts/:id" element={<ContextDetailPage />} />
        <Route path="/ai/knowledge/*" element={<KnowledgePage />} />
        <Route path="/ai/infrastructure/providers/new" element={<AIProvidersPage />} />
        <Route path="/ai/infrastructure/providers/:id" element={<AIProvidersPage />} />
        <Route path="/ai/infrastructure/*" element={<InfrastructurePage />} />
        <Route path="/ai/billing/*" element={<AiBillingPage />} />
        <Route path="/ai/monitoring/*" element={<AIMonitoringPage />} />

        {/* AI Pages - Agent Orchestration */}
        <Route path="/ai/sandboxes" element={<SandboxDashboardPage />} />
        <Route path="/ai/autonomy" element={<AutonomyDashboardPage />} />
        <Route path="/ai/learning" element={<CompoundLearningPage />} />
        <Route path="/ai/audit" element={<AuditDashboardPage />} />
        <Route path="/ai/security" element={<SecurityDashboardPage />} />

        {/* AI Code Factory */}
        <Route path="/ai/code-factory/*" element={<CodeFactoryPage />} />

        {/* AI Pages - Hidden (no nav, still accessible) */}
        <Route path="/ai/evaluation" element={<EvaluationDashboardPage />} />
        <Route path="/ai/self-healing" element={<SelfHealingDashboard />} />
        <Route path="/ai/learning/recommendations" element={<RecommendationsDashboard />} />
        <Route path="/ai/learning/insights" element={<TrajectoryInsights />} />
        <Route path="/ai/analytics/system" element={<AIAnalyticsPage />} />
        <Route path="/ai/analytics/workflows" element={<WorkflowAnalyticsPage />} />
        <Route path="/ai/devops/templates" element={<DevOpsTemplatesPage />} />
        <Route path="/ai/debug" element={<AIDebugPage />} />

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
        {/* Business routes handled by featureRegistry (enterprise) */}
        
        {/* System Pages */}
        <Route path="/profile/*" element={<ProfilePage />} />

        {/* Privacy Page */}
        <Route path="/privacy" element={<PrivacyDashboardPage />} />
        {/* Workers moved to admin routes */}
        

        {/* DevOps Pages */}
        <Route path="/devops" element={<DevOpsOverviewPage />} />

        {/* Source Control - detail routes before catch-all */}
        <Route path="/devops/source-control/providers/new" element={<GitProvidersPage />} />
        <Route path="/devops/source-control/providers/:id" element={<GitProvidersPage />} />
        <Route path="/devops/source-control/*" element={<SourceControlPage />} />

        {/* CI/CD - detail routes before catch-all */}
        <Route path="/devops/ci-cd/pipelines/new" element={<PipelineCreatePage />} />
        <Route path="/devops/ci-cd/pipelines/:id/edit" element={<PipelineEditPage />} />
        <Route path="/devops/ci-cd/pipelines/:id/runs/:runId" element={<PipelineDetailPage />} />
        <Route path="/devops/ci-cd/pipelines/:id/runs" element={<PipelineDetailPage />} />
        <Route path="/devops/ci-cd/pipelines/:id" element={<PipelineDetailPage />} />
        <Route path="/devops/ci-cd/runners/:id" element={<RunnerDetailPage />} />
        <Route path="/devops/ci-cd/*" element={<CiCdPage />} />

        {/* Connections - detail routes before catch-all */}
        <Route path="/devops/connections/integrations/new/:templateId" element={<NewIntegrationPage />} />
        <Route path="/devops/connections/integrations/new" element={<NewIntegrationPage />} />
        <Route path="/devops/connections/integrations/:id/*" element={<IntegrationDetailPage />} />
        <Route path="/devops/connections/*" element={<ConnectionsPage />} />

        {/* Sandboxes */}
        <Route path="/devops/sandboxes/*" element={<ContainersPage />} />

        {/* Swarm - static tab routes before :clusterId to prevent "services" etc. matching as an ID */}
        <Route path="/devops/swarm/services" element={<SwarmHubPage />} />
        <Route path="/devops/swarm/stacks" element={<SwarmHubPage />} />
        <Route path="/devops/swarm/networks" element={<SwarmHubPage />} />
        <Route path="/devops/swarm/secrets" element={<SwarmHubPage />} />
        <Route path="/devops/swarm/operations" element={<SwarmHubPage />} />
        {/* Swarm - detail routes before catch-all */}
        <Route path="/devops/swarm/:clusterId/services/:serviceId/*" element={<ClusterProvider><SwarmServiceDetailPage /></ClusterProvider>} />
        <Route path="/devops/swarm/:clusterId/nodes" element={<ClusterProvider><SwarmNodesPage /></ClusterProvider>} />
        <Route path="/devops/swarm/:clusterId" element={<ClusterProvider><ClusterDashboardPage /></ClusterProvider>} />
        <Route path="/devops/swarm/*" element={<SwarmHubPage />} />

        {/* Docker - static tab routes before :hostId to prevent "containers" etc. matching as an ID */}
        <Route path="/devops/docker/containers" element={<DockerHubPage />} />
        <Route path="/devops/docker/images" element={<DockerHubPage />} />
        <Route path="/devops/docker/networks" element={<DockerHubPage />} />
        <Route path="/devops/docker/volumes" element={<DockerHubPage />} />
        <Route path="/devops/docker/monitoring" element={<DockerHubPage />} />
        {/* Docker - detail routes before catch-all */}
        <Route path="/devops/docker/:hostId/containers/:containerId/*" element={<HostProvider><ContainerDetailPage /></HostProvider>} />
        <Route path="/devops/docker/:hostId" element={<HostProvider><HostDashboardPage /></HostProvider>} />
        <Route path="/devops/docker/*" element={<DockerHubPage />} />

        {/* Audit Logs */}
        <Route path="/admin/audit-logs/*" element={<AuditLogsPage />} />

        {/* Supply Chain Routes */}
        <Route path="/supply-chain" element={<SupplyChainDashboardPage />} />
        <Route path="/supply-chain/sboms" element={<SbomsPage />} />
        <Route path="/supply-chain/sboms/:id" element={<SbomDetailPage />} />
        <Route path="/supply-chain/sboms/:id/diff/:diffId" element={<SbomDiffPage />} />
        <Route path="/supply-chain/containers" element={<ContainerImagesPage />} />
        <Route path="/supply-chain/containers/:id/*" element={<ContainerImageDetailPage />} />
        <Route path="/supply-chain/attestations" element={<AttestationsPage />} />
        <Route path="/supply-chain/attestations/:id/*" element={<AttestationDetailPage />} />
        <Route path="/supply-chain/vendors" element={<VendorsPage />} />
        <Route path="/supply-chain/vendors/risk-dashboard" element={<VendorRiskDashboardPage />} />
        <Route path="/supply-chain/vendors/:id" element={<VendorDetailPage />} />
        <Route path="/supply-chain/vendors/:id/assessments/:assessmentId" element={<AssessmentDetailPage />} />
        <Route path="/supply-chain/vendors/:id/questionnaires/:questionnaireId" element={<QuestionnaireDetailPage />} />
        <Route path="/supply-chain/licenses" element={<LicensePoliciesPage />} />
        <Route path="/supply-chain/licenses/policies" element={<LicensePoliciesPage />} />
        <Route path="/supply-chain/licenses/policies/new" element={<LicensePolicyFormPage />} />
        <Route path="/supply-chain/licenses/policies/:id/edit" element={<LicensePolicyFormPage />} />
        <Route path="/supply-chain/licenses/policies/:id" element={<LicensePolicyDetailPage />} />
        <Route path="/supply-chain/licenses/violations" element={<LicenseViolationsPage />} />
        <Route path="/supply-chain/licenses/violations/:id" element={<LicenseViolationDetailPage />} />

        {/* Marketing Pages */}
        <Route path="/marketing/campaigns" element={<MarketingCampaignsPage />} />
        <Route path="/marketing/campaigns/:id" element={<MarketingCampaignDetailPage />} />
        <Route path="/marketing/calendar" element={<MarketingCalendarPage />} />
        <Route path="/marketing/email-lists" element={<MarketingEmailListsPage />} />
        <Route path="/marketing/social" element={<MarketingSocialPage />} />
        <Route path="/marketing/analytics" element={<MarketingAnalyticsPage />} />

        {/* Business analytics + metrics routes handled by featureRegistry (enterprise) */}

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
        <Route path="/admin/maintenance/*" element={<AdminMaintenancePage />} />
        <Route path="/admin/workers/*" element={<AdminWorkersPage />} />
        <Route path="/admin/storage" element={<AdminStoragePage />} />

        {/* Enterprise routes (dynamically registered via featureRegistry) */}
        {featureRegistry.getRoutes().map((route) => (
          <Route
            key={route.path}
            path={route.path}
            element={
              <Suspense fallback={<div className="p-8 text-theme-secondary">Loading...</div>}>
                <route.component />
              </Suspense>
            }
          />
        ))}
      </Routes>
    </DashboardLayout>
  );
};

export { DashboardPage };