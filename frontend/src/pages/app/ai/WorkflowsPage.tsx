import React from 'react';
import {
  Plus,
  Upload,
  Activity,
  Workflow,
  Boxes
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { TemplatesContent } from '@/pages/app/ai/DevOpsTemplatesPage';
import { WorkflowCreateModal } from '@/features/ai/workflows/components/WorkflowCreateModal';
import { WorkflowDetailModal } from '@/features/ai/workflows/components/WorkflowDetailModal';
import { WorkflowBuilderModal } from '@/shared/components/workflow/WorkflowBuilderModal';
import { AiErrorBoundary } from '@/shared/components/error/AiErrorBoundary';
import {
  useWorkflowsPage,
  WorkflowFiltersBar,
  WorkflowsTable,
} from '@/features/ai/workflows/components/workflows-page';

const workflowTabs = [
  { id: 'workflows', label: 'Workflows', icon: <Workflow size={16} />, path: '/' },
  { id: 'templates', label: 'Templates', icon: <Boxes size={16} />, path: '/templates' },
];

export const WorkflowsPage: React.FC = () => {
  const {
    navigate,
    workflows,
    loading,
    searchQuery,
    typeFilter,
    setTypeFilter,
    filters,
    sortBy,
    setSortBy,
    sortOrder,
    setSortOrder,
    perPage,
    pagination,
    activeTab,
    setActiveTab,
    isCreateModalOpen,
    setIsCreateModalOpen,
    selectedWorkflowId,
    setSelectedWorkflowId,
    selectedWorkflowInitialTab,
    builderWorkflowId,
    setBuilderWorkflowId,
    canCreateWorkflows,
    canExecuteWorkflows,
    canDeleteWorkflows,
    canUpdateWorkflows,
    refreshAction,
    handleSearch,
    handleFilterChange,
    handleSort,
    handleExecuteWorkflow,
    handleDuplicateWorkflow,
    handleDeleteWorkflow,
    handleWorkflowCreated,
    handleViewWorkflow,
    handleBuilderSuccess,
    loadWorkflows,
  } = useWorkflowsPage();

  const pageActions = [
    refreshAction,
    ...(activeTab === 'workflows' ? [
      {
        id: 'monitoring',
        label: 'Monitoring',
        onClick: () => navigate('/app/ai/monitoring/workflows'),
        icon: Activity,
        variant: 'outline' as const
      },
      ...(canCreateWorkflows ? [
        {
          id: 'import-workflow',
          label: 'Import',
          onClick: () => navigate('/app/ai/workflows/import'),
          icon: Upload,
          variant: 'outline' as const
        },
        {
          id: 'create-workflow',
          label: 'Create Workflow',
          onClick: () => setIsCreateModalOpen(true),
          icon: Plus,
          variant: 'primary' as const
        }
      ] : [])
    ] : [])
  ];

  return (
    <AiErrorBoundary>
      <PageContainer
        title="AI Workflows"
        description="Create, manage, and execute automated AI workflows and templates"
        breadcrumbs={[
          { label: 'Dashboard', href: '/app' },
          { label: 'AI', href: '/app/ai' },
          { label: 'Workflows' }
        ]}
        actions={pageActions}
      >
        <TabContainer
          tabs={workflowTabs}
          activeTab={activeTab}
          onTabChange={setActiveTab}
          basePath="/app/ai/workflows"
          variant="underline"
          className="mb-6"
        >
          <TabPanel tabId="workflows" activeTab={activeTab}>
            <div className="space-y-4">
              <WorkflowFiltersBar
                searchQuery={searchQuery}
                onSearch={handleSearch}
                sortBy={sortBy}
                onSortByChange={setSortBy}
                sortOrder={sortOrder}
                onSortOrderToggle={() => setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc')}
                typeFilter={typeFilter}
                onTypeFilterChange={setTypeFilter}
                filters={filters}
                onFilterChange={handleFilterChange}
                onSort={handleSort}
              />
              <WorkflowsTable
                workflows={workflows}
                loading={loading}
                pagination={pagination}
                sortBy={sortBy}
                sortOrder={sortOrder}
                canCreateWorkflows={canCreateWorkflows}
                canExecuteWorkflows={canExecuteWorkflows}
                canDeleteWorkflows={canDeleteWorkflows}
                canUpdateWorkflows={canUpdateWorkflows}
                onPageChange={(page) => loadWorkflows(page, perPage)}
                onSort={handleSort}
                onView={handleViewWorkflow}
                onExecute={handleExecuteWorkflow}
                onDesign={(id) => setBuilderWorkflowId(id)}
                onDuplicate={handleDuplicateWorkflow}
                onDelete={handleDeleteWorkflow}
                onNavigate={navigate}
                onCreateClick={() => setIsCreateModalOpen(true)}
              />
            </div>
          </TabPanel>

          <TabPanel tabId="templates" activeTab={activeTab}>
            <TemplatesContent />
          </TabPanel>
        </TabContainer>

        <WorkflowCreateModal
          isOpen={isCreateModalOpen}
          onClose={() => setIsCreateModalOpen(false)}
          onWorkflowCreated={handleWorkflowCreated}
        />
        <WorkflowDetailModal
          isOpen={!!selectedWorkflowId}
          onClose={() => setSelectedWorkflowId(null)}
          workflowId={selectedWorkflowId || ''}
          initialTab={selectedWorkflowInitialTab}
        />
        <WorkflowBuilderModal
          isOpen={!!builderWorkflowId}
          onClose={() => setBuilderWorkflowId(null)}
          workflowId={builderWorkflowId || ''}
          onSuccess={handleBuilderSuccess}
        />
      </PageContainer>
    </AiErrorBoundary>
  );
};
