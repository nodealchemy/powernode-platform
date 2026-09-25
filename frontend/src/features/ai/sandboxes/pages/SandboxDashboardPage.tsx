import React, { useState, useCallback, useEffect } from 'react';
import { useLocation } from 'react-router-dom';
import { Box, Play, Pause, CheckCircle, XCircle, Plus, FileCode, Gauge } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { containerExecutionApi } from '@/shared/services/ai';
import type { SandboxStats, ContainerTemplateSummary } from '@/shared/services/ai';
import { ContainerList } from '@/features/devops/containers/components/ContainerList';
import { TemplateList } from '@/features/devops/containers/components/TemplateList';
import { QuotaDisplay } from '@/features/devops/containers/components/QuotaDisplay';
import { TemplateFormModal } from '@/features/devops/containers/components/TemplateFormModal';
import { ExecuteContainerModal } from '@/features/devops/containers/components/ExecuteContainerModal';
import { CreateSandboxModal } from '@/features/ai/sandboxes/components/CreateSandboxModal';

const subTabs = [
  { id: 'executions', label: 'Executions', icon: <Box className="w-4 h-4" />, path: '/' },
  { id: 'templates', label: 'Templates', icon: <FileCode className="w-4 h-4" />, path: '/templates' },
  { id: 'quotas', label: 'Quotas', icon: <Gauge className="w-4 h-4" />, path: '/quotas' },
];

// One Sandboxes surface over Devops::ContainerInstance — merges what used to
// be two pages (AI Execution's "Containers" tab, and DevOps's
// /app/devops/sandboxes) into a single list backed by
// Api::V1::Devops::ContainersController (list/execute/cancel/logs/artifacts)
// plus the Ai::ContainerSandboxesController mutation actions
// (create/destroy/pause/resume) for rows flagged `sandbox`. ContainerList
// carries the sandbox filter; ContainerCard renders the union of both
// pages' row actions gated on that flag.
export const ContainerSandboxContent: React.FC<{ refreshKey?: number }> = ({ refreshKey: externalRefreshKey = 0 }) => {
  const location = useLocation();
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();

  const [stats, setStats] = useState<SandboxStats | null>(null);
  const [statsLoading, setStatsLoading] = useState(true);
  const [refreshKey, setRefreshKey] = useState(0);
  const [showCreateSandbox, setShowCreateSandbox] = useState(false);
  const [showCreateTemplate, setShowCreateTemplate] = useState(false);
  const [showEditTemplate, setShowEditTemplate] = useState(false);
  const [showExecuteModal, setShowExecuteModal] = useState(false);
  const [selectedTemplate, setSelectedTemplate] = useState<ContainerTemplateSummary | null>(null);

  const basePath = '/app/ai/execution/containers';

  const getActiveSubTab = () => {
    const path = location.pathname;
    if (path.includes(`${basePath}/templates`)) return 'templates';
    if (path.includes(`${basePath}/quotas`)) return 'quotas';
    return 'executions';
  };

  const [activeSubTab, setActiveSubTab] = useState(getActiveSubTab());

  useEffect(() => {
    const newTab = getActiveSubTab();
    if (newTab !== activeSubTab) setActiveSubTab(newTab);
  }, [location.pathname]);

  const loadStats = useCallback(async () => {
    try {
      setStatsLoading(true);
      const data = await containerExecutionApi.getSandboxStats();
      setStats(data);
    } catch (_error) {
      addNotification({ type: 'error', message: 'Failed to load sandbox stats' });
    } finally {
      setStatsLoading(false);
    }
  }, [addNotification]);

  useEffect(() => {
    loadStats();
  }, [loadStats, externalRefreshKey, refreshKey]);

  const canCreateSandbox = hasPermission('ai.agents.create');
  const canManageTemplates = hasPermission('devops.containers.read');

  const statCards = [
    { label: 'Total', value: stats?.total ?? 0, icon: Box, colorClass: 'text-theme-info-fg', bgClass: 'bg-theme-info-bg' },
    { label: 'Running', value: stats?.running ?? 0, icon: Play, colorClass: 'text-theme-success-fg', bgClass: 'bg-theme-success-bg' },
    { label: 'Paused', value: stats?.paused ?? 0, icon: Pause, colorClass: 'text-theme-warning-fg', bgClass: 'bg-theme-warning-bg' },
    { label: 'Completed', value: stats?.completed ?? 0, icon: CheckCircle, colorClass: 'text-theme-info-fg', bgClass: 'bg-theme-info-bg' },
    { label: 'Failed', value: stats?.failed ?? 0, icon: XCircle, colorClass: 'text-theme-error-fg', bgClass: 'bg-theme-error-bg' },
  ];

  const handleRefreshAll = useCallback(() => setRefreshKey((k) => k + 1), []);

  const handleExecuteTemplate = useCallback((template: ContainerTemplateSummary) => {
    setSelectedTemplate(template);
    setShowExecuteModal(true);
  }, []);

  const handleSelectTemplate = useCallback((template: ContainerTemplateSummary) => {
    setSelectedTemplate(template);
    setShowEditTemplate(true);
  }, []);

  return (
    <>
      {/* Sandbox stats (agent sandboxes only — the merged list below covers both sources) */}
      {statsLoading ? (
        <LoadingSpinner size="sm" className="py-4" />
      ) : (
        <div className="grid grid-cols-2 md:grid-cols-5 gap-4 mb-6">
          {statCards.map((stat) => {
            const Icon = stat.icon;
            return (
              <Card key={stat.label} className="p-4">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm text-theme-tertiary">{stat.label}</p>
                    <p className="text-2xl font-semibold text-theme-primary">{stat.value}</p>
                  </div>
                  <div className={`h-10 w-10 ${stat.bgClass} rounded-lg flex items-center justify-center`}>
                    <Icon className={`h-5 w-5 ${stat.colorClass}`} />
                  </div>
                </div>
              </Card>
            );
          })}
        </div>
      )}

      <div className="flex items-center justify-end gap-2 mb-4">
        {canManageTemplates && (
          <button type="button" className="btn-theme btn-theme-outline" onClick={() => setShowCreateTemplate(true)}>
            Create Template
          </button>
        )}
        {canCreateSandbox && (
          <button
            type="button"
            className="btn-theme btn-theme-primary flex items-center gap-1"
            onClick={() => setShowCreateSandbox(true)}
          >
            <Plus className="w-4 h-4" />
            Create Sandbox
          </button>
        )}
      </div>

      <TabContainer
        tabs={subTabs}
        activeTab={activeSubTab}
        onTabChange={setActiveSubTab}
        basePath={basePath}
        variant="pills"
        className="mb-4"
      >
        <TabPanel tabId="executions" activeTab={activeSubTab}>
          <ContainerList key={`sandbox-executions-${externalRefreshKey}-${refreshKey}`} />
        </TabPanel>

        <TabPanel tabId="templates" activeTab={activeSubTab}>
          {canManageTemplates && (
            <TemplateList
              key={`sandbox-templates-${externalRefreshKey}-${refreshKey}`}
              onSelectTemplate={handleSelectTemplate}
              onExecuteTemplate={handleExecuteTemplate}
            />
          )}
        </TabPanel>

        <TabPanel tabId="quotas" activeTab={activeSubTab}>
          <QuotaDisplay key={`sandbox-quotas-${externalRefreshKey}-${refreshKey}`} />
        </TabPanel>
      </TabContainer>

      <CreateSandboxModal
        isOpen={showCreateSandbox}
        onClose={() => setShowCreateSandbox(false)}
        onCreated={handleRefreshAll}
      />

      <TemplateFormModal
        isOpen={showCreateTemplate}
        onClose={() => setShowCreateTemplate(false)}
        onSaved={handleRefreshAll}
        mode="create"
      />

      <TemplateFormModal
        isOpen={showEditTemplate}
        onClose={() => {
          setShowEditTemplate(false);
          setSelectedTemplate(null);
        }}
        onSaved={handleRefreshAll}
        mode="edit"
        templateId={selectedTemplate?.id}
      />

      <ExecuteContainerModal
        isOpen={showExecuteModal}
        onClose={() => {
          setShowExecuteModal(false);
          setSelectedTemplate(null);
        }}
        template={selectedTemplate}
        onExecutionStarted={() => {
          setActiveSubTab('executions');
          handleRefreshAll();
        }}
      />
    </>
  );
};
