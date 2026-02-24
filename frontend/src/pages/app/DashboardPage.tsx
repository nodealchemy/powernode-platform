import React, { useCallback, Suspense } from 'react';
import { Routes, Route, useNavigate, Navigate } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { DashboardLayout } from '@/shared/components/layout/DashboardLayout';
import { MetricCard } from '@/shared/components/ui/Card';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { featureRegistry } from '@/shared/services/featureRegistry';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { BarChart3, Users } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';

// Context providers used inline in route elements (must be synchronous)
import { ClusterProvider } from '@/features/devops/swarm/context/ClusterContext';
import { HostProvider } from '@/features/devops/docker/context/HostContext';

// === Lazy-loaded page components ===

// Account & Content
const ProfilePage = React.lazy(() => import('./account/ProfilePage').then(m => ({ default: m.ProfilePage })));
const PagesPage = React.lazy(() => import('./content/PagesPage').then(m => ({ default: m.PagesPage })));
const KnowledgeBasePage = React.lazy(() => import('./content/KnowledgeBasePage'));
const KnowledgeBaseArticlePage = React.lazy(() => import('./content/KnowledgeBaseArticlePage'));
const KnowledgeBaseAdminPage = React.lazy(() => import('./content/KnowledgeBaseAdminPage'));
const KnowledgeBaseArticleEditor = React.lazy(() => import('@/features/content/knowledge-base/components/KnowledgeBaseArticleEditor').then(m => ({ default: m.KnowledgeBaseArticleEditor })));
const MyFilesPage = React.lazy(() => import('./content/MyFilesPage'));
const UsersPage = React.lazy(() => import('./account/UsersPage').then(m => ({ default: m.UsersPage })));
const AuditLogsPage = React.lazy(() => import('./admin/AuditLogsPage').then(m => ({ default: m.AuditLogsPage })));
const PrivacyDashboardPage = React.lazy(() => import('./privacy/PrivacyDashboardPage'));
const NotificationsPage = React.lazy(() => import('./account/NotificationsPage').then(m => ({ default: m.NotificationsPage })));

// Admin
const AdminSettingsPage = React.lazy(() => import('@/pages/app/admin/AdminSettingsPage').then(m => ({ default: m.AdminSettingsPage })));
const AdminUsersPage = React.lazy(() => import('@/pages/app/admin/AdminUsersPage').then(m => ({ default: m.AdminUsersPage })));
const AdminRolesPage = React.lazy(() => import('@/pages/app/admin/AdminRolesPage').then(m => ({ default: m.AdminRolesPage })));
const AdminWorkersPage = React.lazy(() => import('@/pages/app/admin/WorkersPage').then(m => ({ default: m.WorkersPage })));
const AdminStoragePage = React.lazy(() => import('@/pages/app/admin/StorageProvidersPage'));
const AdminMaintenancePage = React.lazy(() => import('@/pages/app/admin/AdminMaintenancePage').then(m => ({ default: m.AdminMaintenancePage })));
// AI Providers
const AIProvidersPage = React.lazy(() => import('./ai/AIProvidersPage').then(m => ({ default: m.AIProvidersPage })));
const GitProvidersPage = React.lazy(() => import('./devops/GitProvidersPage').then(m => ({ default: m.GitProvidersPage })));

// AI Primary navigation
const AIOverviewPage = React.lazy(() => import('./ai/AIOverviewPage').then(m => ({ default: m.AIOverviewPage })));
const AIAgentsPage = React.lazy(() => import('./ai/AIAgentsPage').then(m => ({ default: m.AIAgentsPage })));
const WorkflowsPage = React.lazy(() => import('./ai/WorkflowsPage').then(m => ({ default: m.WorkflowsPage })));
const AIMonitoringPage = React.lazy(() => import('./ai/AIMonitoringPage').then(m => ({ default: m.AIMonitoringPage })));
const GovernancePage = React.lazy(() => import('./ai/GovernancePage'));
// SandboxPage absorbed into Execution tabs

// AI Tabbed wrappers
const ExecutionPage = React.lazy(() => import('./ai/ExecutionPage').then(m => ({ default: m.ExecutionPage })));
const KnowledgePage = React.lazy(() => import('./ai/KnowledgePage').then(m => ({ default: m.KnowledgePage })));
const InfrastructurePage = React.lazy(() => import('./ai/InfrastructurePage').then(m => ({ default: m.InfrastructurePage })));
// AiBillingPage absorbed into Observability (Credits & FinOps tabs)

// AI Sub-pages
const CreateWorkflowPage = React.lazy(() => import('./ai').then(m => ({ default: m.CreateWorkflowPage })));
const AIDebugPage = React.lazy(() => import('./ai').then(m => ({ default: m.AIDebugPage })));
const AgentDetailPage = React.lazy(() => import('./ai/AgentDetailPage').then(m => ({ default: m.AgentDetailPage })));
const WorkflowDetailPage = React.lazy(() => import('./ai/WorkflowDetailPage').then(m => ({ default: m.WorkflowDetailPage })));
const WorkflowImportPage = React.lazy(() => import('./ai/WorkflowImportPage').then(m => ({ default: m.WorkflowImportPage })));
const WorkflowMonitoringPage = React.lazy(() => import('./ai/WorkflowMonitoringPage').then(m => ({ default: m.WorkflowMonitoringPage })));
const WorkflowValidationStatisticsPage = React.lazy(() => import('./ai/WorkflowValidationStatisticsPage').then(m => ({ default: m.WorkflowValidationStatisticsPage })));
const AIAnalyticsPage = React.lazy(() => import('./ai/AIAnalyticsPage').then(m => ({ default: m.AIAnalyticsPage })));
const AgentMemoryPage = React.lazy(() => import('./ai/AgentMemoryPage').then(m => ({ default: m.AgentMemoryPage })));
const ContextDetailPage = React.lazy(() => import('./ai/ContextDetailPage').then(m => ({ default: m.ContextDetailPage })));

// AI Hidden pages
// SelfHealingDashboard absorbed into Observability Overview
const RecommendationsDashboard = React.lazy(() => import('@/features/ai/learning/RecommendationsDashboard').then(m => ({ default: m.RecommendationsDashboard })));
const TrajectoryInsights = React.lazy(() => import('@/features/ai/learning/TrajectoryInsights').then(m => ({ default: m.TrajectoryInsights })));

// AI Orchestration
// SandboxDashboardPage → Execution/Containers, AutonomyDashboardPage → Agents/Autonomy, CompoundLearningPage → Knowledge/Learning
// AuditDashboardPage and SecurityDashboardPage absorbed into GovernancePage tabs
// EvaluationDashboardPage absorbed into Observability, CodeFactoryPage absorbed into Missions

// AI Missions
const MissionsPageWrapper = React.lazy(() => import('./ai/MissionsPage').then(m => ({ default: m.MissionsPageWrapper })));

// Containers
const ContainersPage = React.lazy(() => import('@/features/devops/containers/pages/ContainersPage').then(m => ({ default: m.ContainersPage })));

// Docker Swarm pages
const ClusterDashboardPage = React.lazy(() => import('@/features/devops/swarm/pages/ClusterDashboardPage').then(m => ({ default: m.ClusterDashboardPage })));
const SwarmNodesPage = React.lazy(() => import('@/features/devops/swarm/pages/SwarmNodesPage').then(m => ({ default: m.SwarmNodesPage })));
const SwarmServiceDetailPage = React.lazy(() => import('@/features/devops/swarm/pages/SwarmServiceDetailPage').then(m => ({ default: m.SwarmServiceDetailPage })));

// Docker Host pages
const HostDashboardPage = React.lazy(() => import('@/features/devops/docker/pages/HostDashboardPage').then(m => ({ default: m.HostDashboardPage })));
const ContainerDetailPage = React.lazy(() => import('@/features/devops/docker/pages/ContainerDetailPage').then(m => ({ default: m.ContainerDetailPage })));

// AI Feature Pages (standalone)
const TeamsPage = React.lazy(() => import('./ai/TeamsPage'));
const DevOpsTemplatesPage = React.lazy(() => import('./ai/DevOpsTemplatesPage'));
const WorkflowAnalyticsPage = React.lazy(() => import('./ai/WorkflowAnalyticsPage').then(m => ({ default: m.WorkflowAnalyticsPage })));

// Integration pages
const IntegrationDetailPage = React.lazy(() => import('@/pages/app/devops/integrations').then(m => ({ default: m.IntegrationDetailPage })));
const NewIntegrationPage = React.lazy(() => import('@/pages/app/devops/integrations').then(m => ({ default: m.NewIntegrationPage })));

// DevOps Pages
const DevOpsOverviewPage = React.lazy(() => import('@/pages/app/devops/DevOpsOverviewPage').then(m => ({ default: m.DevOpsOverviewPage })));
const PipelineCreatePage = React.lazy(() => import('@/pages/app/devops/PipelineCreatePage').then(m => ({ default: m.PipelineCreatePage })));
const PipelineDetailPage = React.lazy(() => import('@/pages/app/devops/PipelineDetailPage').then(m => ({ default: m.PipelineDetailPage })));
const PipelineEditPage = React.lazy(() => import('@/pages/app/devops/PipelineEditPage').then(m => ({ default: m.PipelineEditPage })));
const RunnerDetailPage = React.lazy(() => import('@/pages/app/devops/RunnerDetailPage').then(m => ({ default: m.RunnerDetailPage })));

// DevOps Hub Pages
const SourceControlPage = React.lazy(() => import('@/pages/app/devops/SourceControlPage').then(m => ({ default: m.SourceControlPage })));
const CiCdPage = React.lazy(() => import('@/pages/app/devops/CiCdPage').then(m => ({ default: m.CiCdPage })));
const ConnectionsPage = React.lazy(() => import('@/pages/app/devops/ConnectionsPage').then(m => ({ default: m.ConnectionsPage })));
const SwarmHubPage = React.lazy(() => import('@/pages/app/devops/SwarmHubPage').then(m => ({ default: m.SwarmHubPage })));
const DockerHubPage = React.lazy(() => import('@/pages/app/devops/DockerHubPage').then(m => ({ default: m.DockerHubPage })));

// Marketing routes handled by featureRegistry (marketing extension)

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
      <Suspense fallback={<div className="p-8 text-theme-secondary">Loading...</div>}>
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
        <Route path="/ai/agents/autonomy" element={<AIAgentsPage />} />
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
        <Route path="/ai/communication/conversations" element={<Navigate to="/app/ai/observability/conversations" replace />} />
        <Route path="/ai/communication/*" element={<Navigate to="/app/ai/teams" replace />} />
        <Route path="/ai/governance/*" element={<GovernancePage />} />
        <Route path="/ai/sandbox" element={<Navigate to="/app/ai/execution/testing" replace />} />

        {/* AI Pages - Tabbed wrappers */}
        <Route path="/ai/execution/*" element={<ExecutionPage />} />
        <Route path="/ai/contexts/:id" element={<ContextDetailPage />} />
        <Route path="/ai/knowledge/contexts/:id" element={<ContextDetailPage />} />
        <Route path="/ai/knowledge/*" element={<KnowledgePage />} />
        <Route path="/ai/infrastructure/providers/new" element={<AIProvidersPage />} />
        <Route path="/ai/infrastructure/providers/:id" element={<AIProvidersPage />} />
        <Route path="/ai/infrastructure/*" element={<InfrastructurePage />} />
        <Route path="/ai/billing/*" element={<Navigate to="/app/ai/observability/credits" replace />} />
        <Route path="/ai/observability/*" element={<AIMonitoringPage />} />
        <Route path="/ai/monitoring/*" element={<Navigate to="/app/ai/observability" replace />} />

        {/* AI Pages - Agent Orchestration */}
        <Route path="/ai/sandboxes" element={<Navigate to="/app/ai/execution/containers" replace />} />
        <Route path="/ai/autonomy" element={<Navigate to="/app/ai/agents/autonomy" replace />} />
        <Route path="/ai/learning" element={<Navigate to="/app/ai/knowledge/learning" replace />} />
        <Route path="/ai/audit" element={<Navigate to="/app/ai/governance/audit" replace />} />
        <Route path="/ai/security" element={<Navigate to="/app/ai/governance/security" replace />} />

        {/* AI Missions - code-factory before :missionId, static tabs before dynamic */}
        <Route path="/ai/missions/code-factory/*" element={<MissionsPageWrapper />} />
        <Route path="/ai/missions/completed" element={<MissionsPageWrapper />} />
        <Route path="/ai/missions/all" element={<MissionsPageWrapper />} />
        <Route path="/ai/missions/:missionId" element={<MissionsPageWrapper />} />
        <Route path="/ai/missions" element={<MissionsPageWrapper />} />

        {/* AI Redirects - Absorbed pages */}
        <Route path="/ai/code-factory/*" element={<Navigate to="/app/ai/missions/code-factory" replace />} />
        <Route path="/ai/evaluation" element={<Navigate to="/app/ai/observability/evaluation" replace />} />
        <Route path="/ai/self-healing" element={<Navigate to="/app/ai/observability" replace />} />
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

        {/* Supply Chain routes handled by featureRegistry (supply-chain extension) */}

        {/* Marketing routes handled by featureRegistry (marketing extension) */}

        {/* Business analytics + metrics routes handled by featureRegistry (enterprise) */}

        {/* Marketplace routes handled by featureRegistry (enterprise) */}

        {/* Admin routes - consistent with navigation */}
        <Route path="/users" element={<UsersPage />} />

        {/* Admin management routes */}
        <Route path="/admin/settings/*" element={<AdminSettingsPage />} />
        <Route path="/admin/users" element={<AdminUsersPage />} />
        <Route path="/admin/roles" element={<AdminRolesPage />} />
        <Route path="/admin/maintenance/*" element={<AdminMaintenancePage />} />
        <Route path="/admin/workers/*" element={<AdminWorkersPage />} />
        <Route path="/admin/storage" element={<AdminStoragePage />} />

        {/* Enterprise routes (dynamically registered via featureRegistry) */}
        {featureRegistry.getRoutes().map((route) => (
          <Route
            key={route.path}
            path={route.path}
            element={<route.component />}
          />
        ))}
      </Routes>
      </Suspense>
    </DashboardLayout>
  );
};

export { DashboardPage };
