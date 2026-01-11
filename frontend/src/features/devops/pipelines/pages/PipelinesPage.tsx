import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Plus, RefreshCw } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { PageErrorBoundary } from '@/shared/components/error/ErrorBoundary';
import { PipelineList } from '../components/PipelineList';
import { usePipelines } from '../hooks/usePipelines';
import { useNotifications } from '@/shared/hooks/useNotifications';

const PipelinesPageContent: React.FC = () => {
  const navigate = useNavigate();
  const { showNotification } = useNotifications();
  const {
    pipelines,
    loading,
    refresh,
    triggerPipeline,
    duplicatePipeline,
    deletePipeline,
    exportPipelineYaml,
  } = usePipelines();

  const [filter, setFilter] = useState<'all' | 'active' | 'inactive'>('all');

  const filteredPipelines = pipelines.filter((p) => {
    if (filter === 'active') return p.is_active;
    if (filter === 'inactive') return !p.is_active;
    return true;
  });

  const handleExportYaml = async (id: string) => {
    const result = await exportPipelineYaml(id);
    if (result) {
      // Create a download
      const blob = new Blob([result.yaml], { type: 'text/yaml' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `${result.pipeline_name}.yml`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      showNotification('Pipeline YAML exported', 'success');
    }
  };

  const handleDelete = async (id: string) => {
    if (window.confirm('Are you sure you want to delete this pipeline? This action cannot be undone.')) {
      await deletePipeline(id);
    }
  };

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Automation', href: '/app/automation' },
    { label: 'Pipelines' }
  ];

  const actions = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: refresh,
      variant: 'secondary' as const,
      icon: RefreshCw
    },
    {
      id: 'create',
      label: 'Create Pipeline',
      onClick: () => navigate('/app/automation/pipelines/new'),
      variant: 'primary' as const,
      icon: Plus
    }
  ];

  return (
    <PageContainer
      title="Pipelines"
      description="Manage AI-powered CI/CD pipelines"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="space-y-6">
        {/* Filter Tabs */}
        <div className="flex items-center gap-2 border-b border-theme">
          {[
            { value: 'all', label: 'All Pipelines' },
            { value: 'active', label: 'Active' },
            { value: 'inactive', label: 'Inactive' },
          ].map((tab) => (
            <button
              key={tab.value}
              onClick={() => setFilter(tab.value as typeof filter)}
              className={`px-4 py-2 text-sm font-medium border-b-2 -mb-px transition-colors ${
                filter === tab.value
                  ? 'border-theme-primary text-theme-primary'
                  : 'border-transparent text-theme-secondary hover:text-theme-primary'
              }`}
            >
              {tab.label}
              {tab.value === 'all' && ` (${pipelines.length})`}
              {tab.value === 'active' && ` (${pipelines.filter(p => p.is_active).length})`}
              {tab.value === 'inactive' && ` (${pipelines.filter(p => !p.is_active).length})`}
            </button>
          ))}
        </div>

        {/* Pipeline List */}
        <PipelineList
          pipelines={filteredPipelines}
          loading={loading}
          onTrigger={triggerPipeline}
          onDuplicate={duplicatePipeline}
          onDelete={handleDelete}
          onExportYaml={handleExportYaml}
        />
      </div>
    </PageContainer>
  );
};

export const PipelinesPage: React.FC = () => (
  <PageErrorBoundary>
    <PipelinesPageContent />
  </PageErrorBoundary>
);

export default PipelinesPage;
