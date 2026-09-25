import React, { useEffect, useState, Suspense } from 'react';
import { Routes, Route } from 'react-router-dom';
import { DashboardLayout } from '@/shared/components/layout/DashboardLayout';
import { featureRegistry } from '@/shared/services/featureRegistry';
import { ProtectedRoute } from '@/shared/components/ui/ProtectedRoute';
import { CONTROL_PERMISSIONS } from '@/features/ai/control/controlPaths';
import { MCP_PERMISSIONS } from '@/shared/constants/mcpPermissions';
import { DashboardOverview } from '@/pages/app/dashboard/DashboardOverview';

// Context providers used inline in route elements (must be synchronous)

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
// SandboxPage absorbed into Execution tabs

// AI Tabbed wrappers
const ExecutionPage = React.lazy(() => import('./ai/ExecutionPage').then(m => ({ default: m.ExecutionPage })));
const KnowledgePage = React.lazy(() => import('./ai/KnowledgePage').then(m => ({ default: m.KnowledgePage })));
// AI Platform (fc-43: the former Infrastructure hub, split into its own items)
const ProvidersPage = React.lazy(() => import('./ai/ProvidersPage').then(m => ({ default: m.ProvidersPage })));
const DataSourcesPage = React.lazy(() => import('./ai/DataSourcesPage').then(m => ({ default: m.DataSourcesPage })));
const ModelRouterPage = React.lazy(() => import('./ai/ModelRouterPage'));
const McpPage = React.lazy(() => import('./ai/McpPage').then(m => ({ default: m.McpPage })));
// Credits, FinOps, ROI, and Outcome Billing are consolidated into CostPage
// (above); Execution Traces is rendered inside ObservabilityPage.
const DeveloperPortal = React.lazy(() => import('@/features/developer/pages/DeveloperPortal').then(m => ({ default: m.DeveloperPortal })));

// AI Sub-pages
const AgentDetailPage = React.lazy(() => import('./ai/AgentDetailPage').then(m => ({ default: m.AgentDetailPage })));
const AIAnalyticsPage = React.lazy(() => import('./ai/AIAnalyticsPage').then(m => ({ default: m.AIAnalyticsPage })));
const ControlPage = React.lazy(() => import('@/features/ai/control/pages/ControlPage').then(m => ({ default: m.ControlPage })));
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
// fc-43: Learning Insights (RecommendationsDashboard + TrajectoryInsights)
// folded into Knowledge › Learning beside Compound Learning.

// fc-43: Skills and Prompts left the Knowledge hub for their own AI Agents items.
const SkillsPage = React.lazy(() => import('./ai/SkillsPage').then(m => ({ default: m.SkillsPage })));
const PromptsPage = React.lazy(() => import('@/features/ai/prompts/pages/PromptsPage').then(m => ({ default: m.PromptsPage })));

// AI Orchestration
// SandboxDashboardPage → Execution/Containers, CompoundLearningPage → Knowledge/Learning
// Autonomy, Governance (with its audit and security views), Approval Chains and
// Budgets → AI → Control (/ai/control/*)
// EvaluationDashboardPage absorbed into Observability, CodeFactoryPage absorbed into Missions

// AI Missions
const MissionsPageWrapper = React.lazy(() => import('./ai/MissionsPage').then(m => ({ default: m.MissionsPageWrapper })));

// AI Improvement Campaigns
const CampaignsPageWrapper = React.lazy(() => import('./ai/CampaignsPage').then(m => ({ default: m.CampaignsPageWrapper })));

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
const IntegrationsWebhooksPage = React.lazy(() => import('@/pages/app/devops/IntegrationsWebhooksPage').then(m => ({ default: m.IntegrationsWebhooksPage })));
const ApiKeysPage = React.lazy(() => import('@/pages/app/devops/ApiKeysPage').then(m => ({ default: m.ApiKeysPage })));
const ContainersHubPage = React.lazy(() => import('@/pages/app/devops/ContainersHubPage').then(m => ({ default: m.ContainersHubPage })));

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
        {/* `/*`: the Community tab has its own sub-paths (`/community/federation`).
            Without it, `/ai/agents/community/federation` fell through past this
            exact route to `/ai/agents/:agentId/*` below with agentId="community",
            opening AgentDetailPage instead of the Community tab (fc-46 review). */}
        <Route path="/ai/agents/community/*" element={<AIAgentsPage />} />
        <Route path="/ai/agents/:agentId/*" element={<AgentDetailPage />} />
        <Route path="/ai/agents/*" element={<AIAgentsPage />} />
        <Route path="/ai/teams/*" element={<TeamsPage />} />
        {/* AI → Control — approvals, policies, budgets, safety, trust & lineage,
            goals and compliance audit on one page. Guarded on every permission
            some part of it is gated on; each leaf and tab re-checks its own. */}
        <Route path="/ai/control/*" element={<ProtectedRoute requiredPermissions={CONTROL_PERMISSIONS}><ControlPage /></ProtectedRoute>} />

        {/* AI Pages - Tabbed wrappers */}
        <Route path="/ai/execution/*" element={<ExecutionPage />} />
        <Route path="/ai/knowledge/contexts/:id" element={<ContextDetailPage />} />
        <Route path="/ai/knowledge/*" element={<KnowledgePage />} />
        {/* AI → Platform, each gated like its endpoints (ProvidersController
            ai.providers.read, DataSourcesController ai.data_sources.read,
            ModelRouterController ai.routing.read; MCP opens on any of its
            tabs' permissions). */}
        <Route path="/ai/providers" element={<ProtectedRoute requiredPermissions={['ai.providers.read']}><ProvidersPage /></ProtectedRoute>} />
        <Route path="/ai/data-sources" element={<ProtectedRoute requiredPermissions={['ai.data_sources.read']}><DataSourcesPage /></ProtectedRoute>} />
        <Route path="/ai/model-router/*" element={<ProtectedRoute requiredPermissions={['ai.routing.read']}><ModelRouterPage /></ProtectedRoute>} />
        <Route path="/ai/mcp/*" element={<ProtectedRoute requiredPermissions={MCP_PERMISSIONS}><McpPage /></ProtectedRoute>} />
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
        {/* Skills (SkillsController: ai.skills.read) and Prompts
            (PromptTemplatesController: ai.prompt_templates.read). Skills keeps
            its own sub-paths (/graph, …), hence `/*`. */}
        <Route path="/ai/skills/*" element={<ProtectedRoute requiredPermissions={['ai.skills.read']}><SkillsPage /></ProtectedRoute>} />
        <Route path="/ai/prompts" element={<ProtectedRoute requiredPermissions={['ai.prompt_templates.read']}><PromptsPage /></ProtectedRoute>} />
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

        {/* Integrations & Webhooks - static routes before :id */}
        <Route path="/devops/integrations/new/:templateId" element={<NewIntegrationPage />} />
        <Route path="/devops/integrations/new" element={<NewIntegrationPage />} />
        <Route path="/devops/integrations/webhook-endpoints" element={<IntegrationsWebhooksPage />} />
        <Route path="/devops/integrations/:id/*" element={<IntegrationDetailPage />} />
        <Route path="/devops/integrations" element={<IntegrationsWebhooksPage />} />

        {/* Sandboxes: merged into AI Execution's Containers tab —
            /app/ai/execution/containers. Deliberately no redirect route. */}

        <Route path="/devops/api-keys" element={<ApiKeysPage />} />

        {/* Containers hub: Docker, Swarm and Kubernetes leaves (and their
            detail routes) are nested routes inside ContainersHubPage, each
            behind its own permission gate. */}
        <Route path="/devops/containers/*" element={<ContainersHubPage />} />

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
