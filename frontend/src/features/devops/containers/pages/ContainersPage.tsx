import React, { useState, useEffect, useCallback } from 'react';
import { useLocation } from 'react-router-dom';
import {
  Box,
  FileCode,
  Gauge,
  Plus,
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import { ContainerList } from '../components/ContainerList';
import { TemplateList } from '../components/TemplateList';
import { QuotaDisplay } from '../components/QuotaDisplay';
import { TemplateFormModal } from '../components/TemplateFormModal';
import { ExecuteContainerModal } from '../components/ExecuteContainerModal';
import type { ContainerInstanceSummary, ContainerTemplateSummary } from '@/shared/services/ai';

interface ContainersPageProps {
  onSelectContainer?: (container: ContainerInstanceSummary) => void;
  onViewContainerLogs?: (container: ContainerInstanceSummary) => void;
}

const tabs = [
  { id: 'executions', label: 'Executions', icon: <Box className="w-4 h-4" />, path: '/' },
  { id: 'templates', label: 'Templates', icon: <FileCode className="w-4 h-4" />, path: '/templates' },
  { id: 'quotas', label: 'Quotas', icon: <Gauge className="w-4 h-4" />, path: '/quotas' },
];

export const ContainersPage: React.FC<ContainersPageProps> = ({
  onSelectContainer,
  onViewContainerLogs,
}) => {
  const location = useLocation();
  const [refreshKey, setRefreshKey] = useState(0);

  // Modal states
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showEditModal, setShowEditModal] = useState(false);
  const [showExecuteModal, setShowExecuteModal] = useState(false);
  const [selectedTemplate, setSelectedTemplate] = useState<ContainerTemplateSummary | null>(null);

  const getActiveTab = () => {
    const path = location.pathname;
    if (path.includes('/templates')) return 'templates';
    if (path.includes('/quotas')) return 'quotas';
    return 'executions';
  };

  const [activeTab, setActiveTab] = useState(getActiveTab());

  useEffect(() => {
    const newTab = getActiveTab();
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname]);

  const handleRefresh = useCallback(async () => {
    setRefreshKey((k) => k + 1);
  }, []);

  const { refreshAction } = useRefreshAction({ onRefresh: handleRefresh });

  const handleSelectTemplate = useCallback((template: ContainerTemplateSummary) => {
    setSelectedTemplate(template);
    setShowEditModal(true);
  }, []);

  const handleExecuteTemplate = useCallback((template: ContainerTemplateSummary) => {
    setSelectedTemplate(template);
    setShowExecuteModal(true);
  }, []);

  const handleExecutionStarted = useCallback(() => {
    setActiveTab('executions');
    setRefreshKey((k) => k + 1);
  }, []);

  const handleTemplateSaved = useCallback(() => {
    setRefreshKey((k) => k + 1);
  }, []);

  const getBreadcrumbs = () => {
    const base: Array<{ label: string; href?: string }> = [
      { label: 'Dashboard', href: '/app' },
      { label: 'DevOps', href: '/app/devops' },
      { label: 'Container Execution' },
    ];
    const activeTabInfo = tabs.find(t => t.id === activeTab);
    if (activeTabInfo && activeTab !== 'executions') {
      base.push({ label: activeTabInfo.label });
    }
    return base;
  };

  const createTemplateAction = {
    label: 'Create Template',
    icon: Plus,
    onClick: () => setShowCreateModal(true),
    variant: 'primary' as const,
  };

  return (
    <PageContainer
      title="Container Execution"
      description="Sandboxed container execution for AI agents"
      breadcrumbs={getBreadcrumbs()}
      actions={[createTemplateAction, refreshAction]}
    >
      {/* Quota Display */}
      <QuotaDisplay key={`quota-compact-${refreshKey}`} compact />

      {/* Tabs */}
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        basePath="/app/devops/sandboxes"
        variant="underline"
        className="mb-6"
      >
        <TabPanel tabId="executions" activeTab={activeTab}>
          <ContainerList
            key={`containers-${refreshKey}`}
            onSelectContainer={onSelectContainer}
            onViewLogs={onViewContainerLogs}
          />
        </TabPanel>

        <TabPanel tabId="templates" activeTab={activeTab}>
          <TemplateList
            key={`templates-${refreshKey}`}
            onSelectTemplate={handleSelectTemplate}
            onExecuteTemplate={handleExecuteTemplate}
          />
        </TabPanel>

        <TabPanel tabId="quotas" activeTab={activeTab}>
          <QuotaDisplay key={`quota-full-${refreshKey}`} />
        </TabPanel>
      </TabContainer>

      {/* Modals */}
      <TemplateFormModal
        isOpen={showCreateModal}
        onClose={() => setShowCreateModal(false)}
        onSaved={handleTemplateSaved}
        mode="create"
      />

      <TemplateFormModal
        isOpen={showEditModal}
        onClose={() => {
          setShowEditModal(false);
          setSelectedTemplate(null);
        }}
        onSaved={handleTemplateSaved}
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
        onExecutionStarted={handleExecutionStarted}
      />
    </PageContainer>
  );
};

export default ContainersPage;
