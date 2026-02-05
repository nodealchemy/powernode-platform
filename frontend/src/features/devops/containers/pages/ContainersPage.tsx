import React, { useState, useCallback } from 'react';
import {
  Box,
  FileCode,
  Gauge,
  Plus,
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/shared/components/ui/Tabs';
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

export const ContainersPage: React.FC<ContainersPageProps> = ({
  onSelectContainer,
  onViewContainerLogs,
}) => {
  const [activeTab, setActiveTab] = useState('executions');
  const [refreshKey, setRefreshKey] = useState(0);

  // Modal states
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showEditModal, setShowEditModal] = useState(false);
  const [showExecuteModal, setShowExecuteModal] = useState(false);
  const [selectedTemplate, setSelectedTemplate] = useState<ContainerTemplateSummary | null>(null);

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

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'DevOps', href: '/app/devops' },
    { label: 'Container Execution' },
  ];

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
      breadcrumbs={breadcrumbs}
      actions={[createTemplateAction, refreshAction]}
    >
      {/* Quota Display */}
      <QuotaDisplay key={`quota-compact-${refreshKey}`} compact />

      {/* Tabs */}
      <Tabs value={activeTab} onValueChange={setActiveTab}>
        <TabsList>
          <TabsTrigger value="executions" className="flex items-center gap-2">
            <Box className="w-4 h-4" />
            Executions
          </TabsTrigger>
          <TabsTrigger value="templates" className="flex items-center gap-2">
            <FileCode className="w-4 h-4" />
            Templates
          </TabsTrigger>
          <TabsTrigger value="quotas" className="flex items-center gap-2">
            <Gauge className="w-4 h-4" />
            Quotas
          </TabsTrigger>
        </TabsList>

        <TabsContent value="executions" className="mt-4">
          <ContainerList
            key={`containers-${refreshKey}`}
            onSelectContainer={onSelectContainer}
            onViewLogs={onViewContainerLogs}
          />
        </TabsContent>

        <TabsContent value="templates" className="mt-4">
          <TemplateList
            key={`templates-${refreshKey}`}
            onSelectTemplate={handleSelectTemplate}
            onExecuteTemplate={handleExecuteTemplate}
          />
        </TabsContent>

        <TabsContent value="quotas" className="mt-4">
          <QuotaDisplay key={`quota-full-${refreshKey}`} />
        </TabsContent>
      </Tabs>

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
