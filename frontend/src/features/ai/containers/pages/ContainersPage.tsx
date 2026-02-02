import React, { useState } from 'react';
import {
  Box,
  FileCode,
  Gauge,
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/shared/components/ui/Tabs';
import { ContainerList } from '../components/ContainerList';
import { TemplateList } from '../components/TemplateList';
import { QuotaDisplay } from '../components/QuotaDisplay';
import type { ContainerInstanceSummary, ContainerTemplateSummary } from '@/shared/services/ai';

interface ContainersPageProps {
  onSelectContainer?: (container: ContainerInstanceSummary) => void;
  onViewContainerLogs?: (container: ContainerInstanceSummary) => void;
  onSelectTemplate?: (template: ContainerTemplateSummary) => void;
  onExecuteTemplate?: (template: ContainerTemplateSummary) => void;
}

export const ContainersPage: React.FC<ContainersPageProps> = ({
  onSelectContainer,
  onViewContainerLogs,
  onSelectTemplate,
  onExecuteTemplate,
}) => {
  const [activeTab, setActiveTab] = useState('executions');

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'AI', href: '/app/ai' },
    { label: 'Container Execution' },
  ];

  return (
    <PageContainer
      title="Container Execution"
      description="Sandboxed container execution for AI agents"
      breadcrumbs={breadcrumbs}
    >
      {/* Quota Display */}
      <QuotaDisplay compact />

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
            onSelectContainer={onSelectContainer}
            onViewLogs={onViewContainerLogs}
          />
        </TabsContent>

        <TabsContent value="templates" className="mt-4">
          <TemplateList
            onSelectTemplate={onSelectTemplate}
            onExecuteTemplate={onExecuteTemplate}
          />
        </TabsContent>

        <TabsContent value="quotas" className="mt-4">
          <QuotaDisplay />
        </TabsContent>
      </Tabs>
    </PageContainer>
  );
};

export default ContainersPage;
