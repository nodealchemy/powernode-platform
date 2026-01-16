import React, { useState, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { Plus, RefreshCw, Play, GitBranch } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { SearchInput } from '@/shared/components/ui/SearchInput';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePipelines } from '@/features/devops/pipelines/hooks/usePipelines';
import { PipelineList } from '@/features/devops/pipelines/components/PipelineList';

export const PipelinesPage: React.FC = () => {
  const navigate = useNavigate();
  const { currentUser } = useAuth();
  const { showNotification } = useNotifications();

  const [searchQuery, setSearchQuery] = useState('');
  const [activeFilter, setActiveFilter] = useState<'all' | 'active' | 'inactive'>('all');

  // Get filter params based on active filter
  const filterParams = activeFilter === 'all'
    ? {}
    : { is_active: activeFilter === 'active' };

  const {
    pipelines,
    meta,
    loading,
    refresh,
    triggerPipeline,
    duplicatePipeline,
    deletePipeline,
    exportPipelineYaml,
  } = usePipelines(filterParams);

  // Check permissions
  const canCreatePipelines = currentUser?.permissions?.includes('devops.pipelines.write') || false;

  // Filter pipelines by search query
  const filteredPipelines = pipelines.filter(pipeline => {
    if (!searchQuery) return true;
    const query = searchQuery.toLowerCase();
    return (
      pipeline.name.toLowerCase().includes(query) ||
      pipeline.slug.toLowerCase().includes(query) ||
      (pipeline.description?.toLowerCase().includes(query) ?? false)
    );
  });

  // Handle trigger pipeline
  const handleTrigger = useCallback(async (id: string) => {
    const result = await triggerPipeline(id);
    if (result) {
      navigate(`/app/devops/pipelines/${id}/runs/${result.id}`);
    }
  }, [triggerPipeline, navigate]);

  // Handle duplicate pipeline
  const handleDuplicate = useCallback(async (id: string) => {
    await duplicatePipeline(id);
  }, [duplicatePipeline]);

  // Handle delete pipeline
  const handleDelete = useCallback(async (id: string) => {
    const pipeline = pipelines.find(p => p.id === id);
    if (!pipeline) return;

    if (!confirm(`Are you sure you want to delete "${pipeline.name}"? This action cannot be undone.`)) {
      return;
    }

    await deletePipeline(id);
  }, [deletePipeline, pipelines]);

  // Handle export YAML
  const handleExportYaml = useCallback(async (id: string) => {
    const result = await exportPipelineYaml(id);
    if (result) {
      // Create a blob and download
      const blob = new Blob([result.yaml], { type: 'text/yaml' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `${result.pipeline_name.toLowerCase().replace(/\s+/g, '-')}.yaml`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      showNotification('Pipeline YAML exported successfully', 'success');
    }
  }, [exportPipelineYaml, showNotification]);

  return (
    <PageContainer
      title="CI/CD Pipelines"
      description="Create and manage automated deployment pipelines"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'DevOps', href: '/app/devops' },
        { label: 'Pipelines' }
      ]}
      actions={[
        {
          id: 'refresh',
          label: 'Refresh',
          onClick: refresh,
          icon: RefreshCw,
          variant: 'outline'
        },
        ...(canCreatePipelines ? [
          {
            id: 'create-pipeline',
            label: 'Create Pipeline',
            onClick: () => navigate('/app/devops/pipelines/new'),
            icon: Plus,
            variant: 'primary' as const
          }
        ] : [])
      ]}
    >
      <div className="space-y-6">
        {/* Stats Cards */}
        {meta && (
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div className="bg-theme-surface rounded-lg border border-theme p-4">
              <div className="flex items-center gap-3">
                <div className="p-2 bg-theme-primary/10 rounded-lg">
                  <GitBranch className="w-5 h-5 text-theme-primary" />
                </div>
                <div>
                  <div className="text-2xl font-bold text-theme-primary">{meta.total}</div>
                  <div className="text-sm text-theme-secondary">Total Pipelines</div>
                </div>
              </div>
            </div>
            <div className="bg-theme-surface rounded-lg border border-theme p-4">
              <div className="flex items-center gap-3">
                <div className="p-2 bg-theme-success/10 rounded-lg">
                  <Play className="w-5 h-5 text-theme-success" />
                </div>
                <div>
                  <div className="text-2xl font-bold text-theme-primary">{meta.active_count}</div>
                  <div className="text-sm text-theme-secondary">Active Pipelines</div>
                </div>
              </div>
            </div>
            <div className="bg-theme-surface rounded-lg border border-theme p-4">
              <div className="flex items-center gap-3">
                <div className="p-2 bg-theme-info/10 rounded-lg">
                  <RefreshCw className="w-5 h-5 text-theme-info" />
                </div>
                <div>
                  <div className="text-2xl font-bold text-theme-primary">{meta.total_runs}</div>
                  <div className="text-sm text-theme-secondary">Total Runs</div>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Search and Filter */}
        <div className="flex flex-col sm:flex-row gap-4">
          <div className="flex-1">
            <SearchInput
              placeholder="Search pipelines..."
              value={searchQuery}
              onChange={setSearchQuery}
              className="w-full"
            />
          </div>
          <div className="flex items-center gap-1 bg-theme-surface border border-theme rounded-lg p-1">
            <button
              onClick={() => setActiveFilter('all')}
              className={`px-3 py-1.5 text-sm font-medium rounded-md transition-colors ${
                activeFilter === 'all'
                  ? 'bg-theme-primary text-white'
                  : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover'
              }`}
            >
              All
            </button>
            <button
              onClick={() => setActiveFilter('active')}
              className={`px-3 py-1.5 text-sm font-medium rounded-md transition-colors ${
                activeFilter === 'active'
                  ? 'bg-theme-primary text-white'
                  : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover'
              }`}
            >
              Active
            </button>
            <button
              onClick={() => setActiveFilter('inactive')}
              className={`px-3 py-1.5 text-sm font-medium rounded-md transition-colors ${
                activeFilter === 'inactive'
                  ? 'bg-theme-primary text-white'
                  : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover'
              }`}
            >
              Inactive
            </button>
          </div>
        </div>

        {/* Pipeline List */}
        <PipelineList
          pipelines={filteredPipelines}
          loading={loading}
          onTrigger={handleTrigger}
          onDuplicate={handleDuplicate}
          onDelete={handleDelete}
          onExportYaml={handleExportYaml}
        />
      </div>
    </PageContainer>
  );
};

export default PipelinesPage;
