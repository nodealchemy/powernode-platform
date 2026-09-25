import React, { useEffect, useState, Suspense } from 'react';
import { Routes, Route } from 'react-router-dom';
import { DashboardLayout } from '@/shared/components/layout/DashboardLayout';
import { featureRegistry } from '@/shared/services/featureRegistry';
import { ProtectedRoute } from '@/shared/components/ui/ProtectedRoute';
import { DashboardOverview } from '@/pages/app/dashboard/DashboardOverview';

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
const AuditLogsPage = React.lazy(() => import('./admin/AuditLogsPage').then(m => ({ default: m.AuditLogsPage })));
const PrivacyDashboardPage = React.lazy(() => import('./privacy/PrivacyDashboardPage'));
const NotificationsPage = React.lazy(() => import('./account/NotificationsPage').then(m => ({ default: m.NotificationsPage })));

// Admin
const AdminSettingsPage = React.lazy(() => import('@/pages/app/admin/AdminSettingsPage').then(m => ({ default: m.AdminSettingsPage })));
const AdminUsersPage = React.lazy(() => import('@/pages/app/admin/AdminUsersPage').then(m => ({ default: m.AdminUsersPage })));
const AdminRolesPage = React.lazy(() => import('@/pages/app/admin/AdminRolesPage').then(m => ({ default: m.AdminRolesPage })));
const AdminAccountsPage = React.lazy(() => import('@/pages/app/admin/AdminAccountsPage').then(m => ({ default: m.AdminAccountsPage })));
const AdminWorkersPage = React.lazy(() => import('@/pages/app/admin/WorkersPage').then(m => ({ default: m.WorkersPage })));
const AdminStoragePage = React.lazy(() => import('@/pages/app/admin/StorageProvidersPage'));
const AdminStorageAssignmentsPage = React.lazy(() => import('@/pages/app/admin/StorageProviderAssignmentsPage'));
const AdminMaintenancePage = React.lazy(() => import('@/pages/app/admin/AdminMaintenancePage').then(m => ({ default: m.AdminMaintenancePage })));
// AI Providers
const GitProvidersPage = React.lazy(() => import('./devops/GitProvidersPage').then(m => ({ default: m.GitProvidersPage })));

// AI Primary navigation
const AIOverviewPage = React.lazy(() => import('./ai/AIOverviewPage').then(m => ({ default: m.AIOverviewPage })));
const AIAgentsPage = React.lazy(() => import('./ai/AIAgentsPage').then(m => ({ default: m.AIAgentsPage })));
const ObservabilityPage = React.lazy(() => import('./ai/ObservabilityPage').then(m => ({ default: m.ObservabilityPage })));
const CostPage = React.lazy(() => import('./ai/CostPage').then(m => ({ default: m.CostPage })));
const GovernancePage = React.lazy(() => import('./ai/GovernancePage'));
// SandboxPage absorbed into Execution tabs

// AI Tabbed wrappers
const ExecutionPage = React.lazy(() => import('./ai/ExecutionPage').then(m => ({ default: m.ExecutionPage })));
const KnowledgePage = React.lazy(() => import('./ai/KnowledgePage').then(m => ({ default: m.KnowledgePage })));
const InfrastructurePage = React.lazy(() => import('./ai/InfrastructurePage').then(m => ({ default: m.InfrastructurePage })));
// Credits, FinOps, ROI, and Outcome Billing are consolidated into CostPage
// (above); Execution Traces is rendered inside ObservabilityPage.
const DeveloperPortal = React.lazy(() => import('@/features/developer/pages/DeveloperPortal').then(m => ({ default: m.DeveloperPortal })));

// AI Sub-pages
const AgentDetailPage = React.lazy(() => import('./ai/AgentDetailPage').then(m => ({ default: m.AgentDetailPage })));
const AIAnalyticsPage = React.lazy(() => import('./ai/AIAnalyticsPage').then(m => ({ default: m.AIAnalyticsPage })));
const AgentMemoryPage = React.lazy(() => import('./ai/AgentMemoryPage').then(m => ({ default: m.AgentMemoryPage })));
const ApprovalChainsPage = React.lazy(() => import('./ai/ApprovalChainsPage').then(m => ({ default: m.ApprovalChainsPage })));
const BudgetsPage = React.lazy(() => import('./ai/BudgetsPage').then(m => ({ default: m.BudgetsPage })));
const ContextDetailPage = React.lazy(() => import('./ai/ContextDetailPage').then(m => ({ default: m.ContextDetailPage })));
// The only operator screen for either capability — previously unrouted.
// AIConversationsPage: CRUD/filter/export/detail over ai conversations, only
// partly covered by the floating chat window (filter-by-agent, duplicate,
// export, unarchive, and the detail modal have no other entry point).
// ChatChannelsPage: management for external chat platform integrations,
// which the server still serves with no other consumer anywhere.
const AIConversationsPage = React.lazy(() => import('./ai/AIConversationsPage').then(m => ({ default: m.AIConversationsPage })));
const ChatChannelsPage = React.lazy(() => import('@/features/ai/chat-channels/pages/ChatChannelsPage'));

// SelfHealingDashboard absorbed into Observability Overview
// fc-26: RecommendationsDashboard + TrajectoryInsights were each their own
// undiscoverable standalone route (no nav entry, no in-app link) — merged
// into LearningPage as two tabs of one hub (see that file).
const LearningPage = React.lazy(() => import('@/pages/app/ai/LearningPage'));

// AI Orchestration
// SandboxDashboardPage → Execution/Containers, AutonomyDashboardPage → Agents/Autonomy, CompoundLearningPage → Knowledge/Learning
// AuditDashboardPage and SecurityDashboardPage absorbed into GovernancePage tabs
// EvaluationDashboardPage absorbed into Observability, CodeFactoryPage absorbed into Missions

// AI Missions
const MissionsPageWrapper = React.lazy(() => import('./ai/MissionsPage').then(m => ({ default: m.MissionsPageWrapper })));

// AI Improvement Campaigns
const CampaignsPageWrapper = React.lazy(() => import('./ai/CampaignsPage').then(m => ({ default: m.CampaignsPageWrapper })));

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
// Integration pages
const IntegrationDetailPage = React.lazy(() => import('@/pages/app/devops/integrations').then(m => ({ default: m.IntegrationDetailPage })));
const NewIntegrationPage = React.lazy(() => import('@/pages/app/devops/integrations').then(m => ({ default: m.NewIntegrationPage })));

// DevOps Pages
const PipelineCreatePage = React.lazy(() => import('@/pages/app/devops/PipelineCreatePage').then(m => ({ default: m.PipelineCreatePage })));
const PipelineDetailPage = React.lazy(() => import('@/pages/app/devops/PipelineDetailPage').then(m => ({ default: m.PipelineDetailPage })));
const PipelineEditPage = React.lazy(() => import('@/pages/app/devops/PipelineEditPage').then(m => ({ default: m.PipelineEditPage })));
const RunnerDetailPage = React.lazy(() => import('@/pages/app/devops/RunnerDetailPage').then(m => ({ default: m.RunnerDetailPage })));

// DevOps Hub Pages
const DevOpsHubPage = React.lazy(() => import('@/pages/app/devops/DevOpsHubPage').then(m => ({ default: m.DevOpsHubPage })));
const SourceControlPage = React.lazy(() => import('@/pages/app/devops/SourceControlPage').then(m => ({ default: m.SourceControlPage })));
const CiCdPage = React.lazy(() => import('@/pages/app/devops/CiCdPage').then(m => ({ default: m.CiCdPage })));
const ConnectionsPage = React.lazy(() => import('@/pages/app/devops/ConnectionsPage').then(m => ({ default: m.ConnectionsPage })));
const SwarmHubPage = React.lazy(() => import('@/pages/app/devops/SwarmHubPage').then(m => ({ default: m.SwarmHubPage })));
const DockerHubPage = React.lazy(() => import('@/pages/app/devops/DockerHubPage').then(m => ({ default: m.DockerHubPage })));
const KubernetesHubPage = React.lazy(() => import('@/pages/app/devops/KubernetesHubPage').then(m => ({ default: m.KubernetesHubPage })));

// Component status plane (campaign 01a08c9b, design §6)
const StatusPage = React.lazy(() => import('@/features/platform/status/pages/StatusPage').then(m => ({ default: m.StatusPage })));

// Marketing routes handled by featureRegistry (marketing extension)

const DashboardPage: React.FC = () => {
  // Re-render when extension routes are registered (e.g., business, supply-chain)
  const [, setRegistryVersion] = useState(() => featureRegistry.getVersion());
  useEffect(() => {
    return featureRegistry.subscribe(() => setRegistryVersion(featureRegistry.getVersion()));
  }, []);

  return (
    <DashboardLayout>
      <Suspense fallback={<div className="p-8 text-theme-secondary">Loading...</div>}>
      <Routes>
        {/* Dashboard Overview */}
        <Route path="/" element={<DashboardOverview />} />

        {/* Notifications Page */}
        <Route path="/notifications" element={<NotificationsPage />} />

        {/* Component status plane — one screen for what is unhealthy, why, and
            what is being done about it. Gated on platform.status.read
            (defense-in-depth; Api::V1::Platform::ComponentStatusesController
            enforces the same permission, and each row's actions carry their own). */}
        <Route path="/status" element={<ProtectedRoute requiredPermissions={['platform.status.read']}><StatusPage /></ProtectedRoute>} />

        {/* Individual Pages - No More Management Page Groupings */}

        {/* AI Pages - Primary navigation */}
        <Route path="/ai" element={<AIOverviewPage />} />
        <Route path="/ai/agents/cards" element={<AIAgentsPage />} />
        <Route path="/ai/agents/community" element={<AIAgentsPage />} />
        {/* `/*` so an Autonomy section (`/ai/agents/autonomy/approvals`, etc.) is
            URL-addressable. This DOES win over `/ai/agents/:agentId/*` below —
            verified with `matchRoutes`: React Router ranks this literal
            "autonomy" segment over that route's dynamic `:agentId` segment at
            the same depth, so a sub-path here never falls through to
            AgentDetailPage. It does NOT win over `/ai/agents/:agentId/memory/*`
            for an `/autonomy/memory/...` path specifically — that route has one
            MORE literal segment ("memory"), which outranks a shorter route
            regardless of the dynamic `:agentId`, so such a path would route to
            AgentMemoryPage instead (verified the same way). Harmless today: no
            Autonomy sidebar item is named "memory" (AutonomyDashboardPage's
            SIDEBAR_ITEMS). If one ever is, this collision needs revisiting. */}
        <Route path="/ai/agents/autonomy/*" element={<AIAgentsPage />} />
        <Route path="/ai/agents/:agentId/memory/*" element={<AgentMemoryPage />} />
        <Route path="/ai/agents/:agentId/*" element={<AgentDetailPage />} />
        <Route path="/ai/agents/*" element={<AIAgentsPage />} />
        <Route path="/ai/teams" element={<TeamsPage />} />
        <Route path="/ai/governance/*" element={<GovernancePage />} />
        {/* Approval chains — gated on ai.approval_chains.manage (defense-in-depth;
            Api::V1::Ai::ApprovalChainsController enforces the same permission). */}
        <Route path="/ai/approval-chains" element={<ProtectedRoute requiredPermissions={['ai.approval_chains.manage']}><ApprovalChainsPage /></ProtectedRoute>} />
        {/* Budgets — gated on ai.agents.read, which GET /api/v1/ai/autonomy/budgets
            checks; the panel gates its writes on ai.autonomy.manage. */}
        <Route path="/ai/control/budgets" element={<ProtectedRoute requiredPermissions={['ai.agents.read']}><BudgetsPage /></ProtectedRoute>} />

        {/* AI Pages - Tabbed wrappers */}
        <Route path="/ai/execution/*" element={<ExecutionPage />} />
        <Route path="/ai/knowledge/contexts/:id" element={<ContextDetailPage />} />
        <Route path="/ai/knowledge/*" element={<KnowledgePage />} />
        <Route path="/ai/infrastructure/*" element={<InfrastructurePage />} />
        {/* fc-42: Observability = monitoring + AIOps + circuit breakers + alerts
            + conversations + traces + evaluation (merged); Cost = billing/finops/roi. */}
        <Route path="/ai/observability/*" element={<ObservabilityPage />} />

        {/* AI Missions - code-factory before :missionId, static tabs before dynamic */}
        <Route path="/ai/missions/code-factory/*" element={<MissionsPageWrapper />} />
        <Route path="/ai/missions/:missionId" element={<MissionsPageWrapper />} />
        <Route path="/ai/missions" element={<MissionsPageWrapper />} />

        {/* AI Improvement Campaigns */}
        <Route path="/ai/campaigns" element={<ProtectedRoute requiredPermissions={['ai.campaigns.read']}><CampaignsPageWrapper /></ProtectedRoute>} />

        {/* AI Pages - Additional standalone routes */}
        {/* Learning Insights — gated on ai.analytics.read (defense-in-depth;
            backend LearningController#validate_permissions also enforces it
            for recommendations/agent_trends/cache_metrics). No standalone
            /ai/learning/recommendations route: recommendations is the
            default tab at the bare hub path. */}
        <Route path="/ai/learning" element={<ProtectedRoute requiredPermissions={['ai.analytics.read']}><LearningPage /></ProtectedRoute>} />
        <Route path="/ai/learning/insights" element={<ProtectedRoute requiredPermissions={['ai.analytics.read']}><LearningPage /></ProtectedRoute>} />
        <Route path="/ai/analytics/system" element={<AIAnalyticsPage />} />
        <Route path="/ai/conversations" element={<ProtectedRoute requiredPermissions={['ai.conversations.read']}><AIConversationsPage /></ProtectedRoute>} />
        <Route path="/ai/chat-channels" element={<ProtectedRoute requiredPermissions={['chat.channels.read']}><ChatChannelsPage /></ProtectedRoute>} />

        {/* Cost hub — Overview / Credits / FinOps / ROI / Outcome Billing (sub-sidebar) */}
        <Route path="/ai/cost/*" element={<CostPage />} />

        {/* Developer Portal (now under DevOps nav) */}
        <Route path="/developer" element={<DeveloperPortal />} />

        {/* Core Pages */}
        <Route path="/content/pages" element={<PagesPage />} />

        {/* My Files Page */}
        <Route path="/content/files" element={<MyFilesPage />} />

        {/* Knowledge Base Pages */}
        <Route path="/content/kb" element={<KnowledgeBasePage />} />
        <Route path="/content/kb/articles/:id" element={<KnowledgeBaseArticlePage />} />
        <Route path="/content/kb/articles/new" element={<KnowledgeBaseArticleEditor />} />
        <Route path="/content/kb/articles/:id/edit" element={<KnowledgeBaseArticleEditor />} />
        <Route path="/content/kb/manage" element={<KnowledgeBaseAdminPage />} />
        {/* Business routes handled by featureRegistry (business) */}

        {/* System Pages */}
        <Route path="/profile/*" element={<ProfilePage />} />

        {/* Privacy Page */}
        <Route path="/privacy" element={<PrivacyDashboardPage />} />
        {/* Workers moved to admin routes */}


        {/* DevOps Pages */}
        <Route path="/devops" element={<DevOpsHubPage />} />

        {/* Source Control - detail routes before catch-all */}
        <Route path="/devops/source-control/providers/:id" element={<GitProvidersPage />} />
        <Route path="/devops/source-control/*" element={<SourceControlPage />} />

        {/* CI/CD - detail routes before catch-all */}
        <Route path="/devops/ci-cd/pipelines/new" element={<PipelineCreatePage />} />
        <Route path="/devops/ci-cd/pipelines/:id/edit" element={<PipelineEditPage />} />
        <Route path="/devops/ci-cd/pipelines/:id/runs/:runId" element={<PipelineDetailPage />} />
        <Route path="/devops/ci-cd/pipelines/:id/runs" element={<PipelineDetailPage />} />
        <Route path="/devops/ci-cd/pipelines/:id" element={<PipelineDetailPage />} />
        <Route path="/devops/ci-cd/runners/:id" element={<RunnerDetailPage />} />
        {/* fc-34: /devops/ci-cd/module-builds[/...] is now the system
            extension's own registered route (featureRegistry.getRoutes()
            below) — its detail view is a modal (BatchDetailModal), not a
            separate route, so there is no ":id" path to carry over. */}
        <Route path="/devops/ci-cd/*" element={<CiCdPage />} />

        {/* Connections - detail routes before catch-all */}
        <Route path="/devops/connections/integrations/new/:templateId" element={<NewIntegrationPage />} />
        <Route path="/devops/connections/integrations/new" element={<NewIntegrationPage />} />
        <Route path="/devops/connections/integrations/:id/*" element={<IntegrationDetailPage />} />
        <Route path="/devops/connections/*" element={<ConnectionsPage />} />

        {/* Sandboxes */}
        <Route path="/devops/sandboxes/*" element={<ContainersPage />} />

        {/* Swarm - gated on devops.swarm.read (defense-in-depth; backend API also enforces).
            Static tab routes before :clusterId to prevent "services" etc. matching as an ID. */}
        <Route path="/devops/swarm/services" element={<ProtectedRoute requiredPermissions={['devops.swarm.read']}><SwarmHubPage /></ProtectedRoute>} />
        <Route path="/devops/swarm/stacks" element={<ProtectedRoute requiredPermissions={['devops.swarm.read']}><SwarmHubPage /></ProtectedRoute>} />
        <Route path="/devops/swarm/networks" element={<ProtectedRoute requiredPermissions={['devops.swarm.read']}><SwarmHubPage /></ProtectedRoute>} />
        <Route path="/devops/swarm/secrets" element={<ProtectedRoute requiredPermissions={['devops.swarm.read']}><SwarmHubPage /></ProtectedRoute>} />
        <Route path="/devops/swarm/operations" element={<ProtectedRoute requiredPermissions={['devops.swarm.read']}><SwarmHubPage /></ProtectedRoute>} />
        {/* Swarm - detail routes before catch-all */}
        <Route path="/devops/swarm/:clusterId/services/:serviceId/*" element={<ProtectedRoute requiredPermissions={['devops.swarm.read']}><ClusterProvider><SwarmServiceDetailPage /></ClusterProvider></ProtectedRoute>} />
        <Route path="/devops/swarm/:clusterId/nodes" element={<ProtectedRoute requiredPermissions={['devops.swarm.read']}><ClusterProvider><SwarmNodesPage /></ClusterProvider></ProtectedRoute>} />
        <Route path="/devops/swarm/:clusterId" element={<ProtectedRoute requiredPermissions={['devops.swarm.read']}><ClusterProvider><ClusterDashboardPage /></ClusterProvider></ProtectedRoute>} />
        <Route path="/devops/swarm/*" element={<ProtectedRoute requiredPermissions={['devops.swarm.read']}><SwarmHubPage /></ProtectedRoute>} />

        {/* Docker - gated on devops.docker.read (defense-in-depth; backend API also enforces).
            Static tab routes before :hostId to prevent "containers" etc. matching as an ID. */}
        <Route path="/devops/docker/containers" element={<ProtectedRoute requiredPermissions={['devops.docker.read']}><DockerHubPage /></ProtectedRoute>} />
        <Route path="/devops/docker/images" element={<ProtectedRoute requiredPermissions={['devops.docker.read']}><DockerHubPage /></ProtectedRoute>} />
        <Route path="/devops/docker/networks" element={<ProtectedRoute requiredPermissions={['devops.docker.read']}><DockerHubPage /></ProtectedRoute>} />
        <Route path="/devops/docker/volumes" element={<ProtectedRoute requiredPermissions={['devops.docker.read']}><DockerHubPage /></ProtectedRoute>} />
        <Route path="/devops/docker/monitoring" element={<ProtectedRoute requiredPermissions={['devops.docker.read']}><DockerHubPage /></ProtectedRoute>} />
        {/* Docker - detail routes before catch-all */}
        <Route path="/devops/docker/:hostId/containers/:containerId/*" element={<ProtectedRoute requiredPermissions={['devops.docker.read']}><HostProvider><ContainerDetailPage /></HostProvider></ProtectedRoute>} />
        <Route path="/devops/docker/:hostId" element={<ProtectedRoute requiredPermissions={['devops.docker.read']}><HostProvider><HostDashboardPage /></HostProvider></ProtectedRoute>} />
        <Route path="/devops/docker/*" element={<ProtectedRoute requiredPermissions={['devops.docker.read']}><DockerHubPage /></ProtectedRoute>} />

        {/* Kubernetes (Phase 2 — K3s today, kubeadm in Phase 3) — gated on devops.kubernetes.read */}
        <Route path="/devops/kubernetes/*" element={<ProtectedRoute requiredPermissions={['devops.kubernetes.read']}><KubernetesHubPage /></ProtectedRoute>} />

        {/* Audit Logs */}
        <Route path="/admin/audit-logs/*" element={<AuditLogsPage />} />

        {/* Supply Chain routes handled by featureRegistry (supply-chain extension) */}

        {/* Marketing routes handled by featureRegistry (marketing extension) */}

        {/* Business analytics + metrics routes handled by featureRegistry (business) */}

        {/* Marketplace routes handled by featureRegistry (business) */}

        {/* Admin management routes */}
        <Route path="/admin/settings/*" element={<AdminSettingsPage />} />
        <Route path="/admin/users" element={<AdminUsersPage />} />
        <Route path="/admin/roles" element={<AdminRolesPage />} />
        <Route path="/admin/accounts" element={<AdminAccountsPage />} />
        <Route path="/admin/maintenance/*" element={<AdminMaintenancePage />} />
        <Route path="/admin/workers/*" element={<AdminWorkersPage />} />
        <Route path="/admin/storage" element={<AdminStoragePage />} />
        <Route path="/admin/storage/:storageId/assignments" element={<AdminStorageAssignmentsPage />} />

        {/* Extension routes (dynamically registered via featureRegistry) */}
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
