import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import {
  Play,
  Plus,
  Filter,
  Upload,
  Copy,
  Trash2,
  Edit,
  Eye,
  CheckCircle,
  Pause,
  Archive,
  Workflow,
  ChevronUp,
  ChevronDown,
  ArrowUpDown,
  SortAsc,
  SortDesc,
  Calendar,
  User,
  Hash,
  FileText,
  Activity,
  FileStack
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { DataTable } from '@/shared/components/ui/DataTable';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { SearchInput } from '@/shared/components/ui/SearchInput';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import { workflowsApi } from '@/shared/services/ai';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useAiOrchestrationWebSocket } from '@/shared/hooks/useAiOrchestrationWebSocket';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import { AiWorkflow } from '@/shared/types/workflow';
import type { WorkflowFilters } from '@/shared/services/ai/types/workflow-api-types';
import { WorkflowCreateModal } from '@/features/ai/workflows/components/WorkflowCreateModal';
import { WorkflowDetailModal } from '@/features/ai/workflows/components/WorkflowDetailModal';
import { WorkflowBuilderModal } from '@/shared/components/workflow/WorkflowBuilderModal';
import { AiErrorBoundary } from '@/shared/components/error/AiErrorBoundary';

export const WorkflowsPage: React.FC = () => {
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const { currentUser } = useAuth();
  const { addNotification } = useNotifications();

  // WebSocket for real-time workflow updates
  useAiOrchestrationWebSocket({
    onWorkflowEvent: (event) => {
      // Refresh workflow list when workflows are created, updated, or deleted
      if (['workflow_created', 'workflow_updated', 'workflow_deleted'].includes(event.type)) {
        loadWorkflows(pagination.current_page, perPage, true);
      }
    },
  });

  // Get initial type filter from URL query param
  const getInitialTypeFilter = (): 'all' | 'workflows' | 'templates' => {
    const typeParam = searchParams.get('type');
    if (typeParam === 'templates') return 'templates';
    if (typeParam === 'workflows') return 'workflows';
    return 'all';
  };

  const [workflows, setWorkflows] = useState<AiWorkflow[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [typeFilter, setTypeFilter] = useState<'all' | 'workflows' | 'templates'>(getInitialTypeFilter());
  const [filters, setFilters] = useState<WorkflowFilters>({});
  const [sortBy, setSortBy] = useState<string>('name');
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('asc');
  const [perPage, setPerPage] = useState(25); // Separate state for items per page
  const [isInitialMount, setIsInitialMount] = useState(true); // Track initial mount
  const [hasSearched, setHasSearched] = useState(false); // Track if user has searched
  const [pagination, setPagination] = useState({
    current_page: 1,
    total_pages: 1,
    total_count: 0,
    per_page: 25
  });
  const [isCreateModalOpen, setIsCreateModalOpen] = useState(false);
  const [selectedWorkflowId, setSelectedWorkflowId] = useState<string | null>(null);
  const [selectedWorkflowInitialTab, setSelectedWorkflowInitialTab] = useState<'overview' | 'execute'>('overview');
  const [builderWorkflowId, setBuilderWorkflowId] = useState<string | null>(null);

  // Check permissions
  const canCreateWorkflows = currentUser?.permissions?.includes('ai.workflows.create') || false;
  const canExecuteWorkflows = currentUser?.permissions?.includes('ai.workflows.execute') || false;
  const canDeleteWorkflows = currentUser?.permissions?.includes('ai.workflows.delete') || false;

  const { refreshAction } = useRefreshAction({
    onRefresh: () => loadWorkflows(pagination.current_page, perPage),
    loading,
  });

  // Load workflows function with useCallback for optimization
  const loadWorkflows = useCallback(async (page = 1, perPage = 25, skipLoading = false) => {
    try {
      if (!skipLoading) setLoading(true);

      const searchFilters: WorkflowFilters = {
        ...filters,
        search: searchQuery || undefined,
        sort_by: sortBy,
        sort_order: sortOrder,
        page: page,
        per_page: perPage,
        // Add is_template filter based on typeFilter
        is_template: typeFilter === 'templates' ? true : typeFilter === 'workflows' ? false : undefined
      };

      const response = await workflowsApi.getWorkflows(searchFilters);
      setWorkflows(response.items);
      setPagination(response.pagination);
      // Sync perPage if server returns a different value
      if (response.pagination.per_page && response.pagination.per_page !== perPage) {
        setPerPage(response.pagination.per_page);
      }
    } catch (error) {
      console.error('Failed to load workflows:', error);
      // Reset to empty state on error
      setWorkflows([]);
      setPagination({
        current_page: 1,
        total_pages: 1,
        total_count: 0,
        per_page: perPage
      });
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to load workflows. Please try again.'
      });
    } finally {
      if (!skipLoading) setLoading(false);
    }
  }, [filters, searchQuery, sortBy, sortOrder, typeFilter, addNotification]);

  // Initial load - only runs once on mount
  useEffect(() => {
    loadWorkflows(1, perPage);
    // Mark that initial mount is complete
    setIsInitialMount(false);
  }, []);  

  // Handle search
  const handleSearch = useCallback((query: string) => {
    setSearchQuery(query);
    if (query && !hasSearched) {
      setHasSearched(true);
    }
  }, [hasSearched]);

  // Debounced effect for search
  useEffect(() => {
    // Skip empty search only if user hasn't searched yet
    if (searchQuery === '' && !hasSearched) return;

    const timeoutId = setTimeout(() => {
      loadWorkflows(1, perPage);
    }, 300);

    return () => clearTimeout(timeoutId);
  }, [searchQuery, perPage, hasSearched]);  

  // Handle filter changes
   
  const handleFilterChange = useCallback((key: keyof WorkflowFilters, value: any) => {
    setFilters(prev => ({
      ...prev,
      [key]: value
    }));
  }, []);

  // Effect to reload workflows when filters change
  useEffect(() => {
    // Only reload if filters actually have values (skip initial empty state)
    if (Object.keys(filters).length > 0 || Object.values(filters).some(v => v !== undefined && v !== '')) {
      loadWorkflows(1, perPage);
    }
  }, [filters, perPage]);  

  // Effect to reload workflows when type filter changes
  useEffect(() => {
    if (isInitialMount) return;
    loadWorkflows(1, perPage);
    // Sync URL with type filter
    if (typeFilter === 'all') {
      searchParams.delete('type');
    } else {
      searchParams.set('type', typeFilter);
    }
    setSearchParams(searchParams, { replace: true });
  }, [typeFilter]);  

  // Debounced effect to reload workflows when sorting changes
  useEffect(() => {
    // Skip only on initial mount, not when user changes sort
    if (isInitialMount) return;

    const timeoutId = setTimeout(() => {
      loadWorkflows(1, perPage, true); // Skip loading indicator for sort changes
    }, 100); // Short debounce for immediate visual feedback

    return () => clearTimeout(timeoutId);
  }, [sortBy, sortOrder, perPage, isInitialMount]);  

  // Handle sorting change
  const handleSort = useCallback((field: string) => {
    if (sortBy === field) {
      // Toggle sort order for the same column
      setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc');
    } else {
      // Keep the same sort order when changing columns
      setSortBy(field);
      // Sort order is maintained - no change to setSortOrder
    }
  }, [sortBy, sortOrder]);

  // Render sort indicator with enhanced styling
  const renderSortIndicator = (field: string) => {
    if (sortBy !== field) {
      return <ArrowUpDown className="h-3.5 w-3.5 inline-block ml-1.5 opacity-40 transition-opacity group-hover:opacity-60" />;
    }
    return sortOrder === 'asc' ?
      <ChevronUp className="h-3.5 w-3.5 inline-block ml-1.5 text-theme-interactive-primary transition-colors" /> :
      <ChevronDown className="h-3.5 w-3.5 inline-block ml-1.5 text-theme-interactive-primary transition-colors" />;
  };

  // Get sort icon for dropdowns
  const getSortIcon = (field: string) => {
    switch (field) {
      case 'name': return FileText;
      case 'created_at': case 'updated_at': return Calendar;
      case 'status': return CheckCircle;
      case 'creator': return User;
      case 'version': return Hash;
      default: return ArrowUpDown;
    }
  };

  // Get enhanced sort label
  const getSortLabel = (field: string, order: 'asc' | 'desc') => {
    const labels = {
      name: order === 'asc' ? 'Name (A → Z)' : 'Name (Z → A)',
      created_at: order === 'asc' ? 'Oldest First' : 'Newest First',
      updated_at: order === 'asc' ? 'Oldest Updates' : 'Recent Updates',
      status: order === 'asc' ? 'Status (A → Z)' : 'Status (Z → A)',
      creator: order === 'asc' ? 'Creator (A → Z)' : 'Creator (Z → A)',
      version: order === 'asc' ? 'Version (Low → High)' : 'Version (High → Low)'
    };
    return labels[field as keyof typeof labels] || `${field} (${order.toUpperCase()})`;
  };

  // Handle workflow execution - open modal instead of direct execution
  const handleExecuteWorkflow = async (workflow: AiWorkflow) => {
    if (!canExecuteWorkflows) {
      addNotification({
        type: 'error',
        title: 'Permission Denied',
        message: 'You do not have permission to execute workflows.'
      });
      return;
    }

    // Open the workflow detail modal with Execute tab active
    setSelectedWorkflowInitialTab('execute');
    setSelectedWorkflowId(workflow.id);
  };


  // Handle workflow duplication
  const handleDuplicateWorkflow = async (workflow: AiWorkflow) => {
    if (!canCreateWorkflows) {
      addNotification({
        type: 'error',
        title: 'Permission Denied',
        message: 'You do not have permission to create workflows.'
      });
      return;
    }

    try {
      await workflowsApi.duplicateWorkflow(workflow.id, `${workflow.name} (Copy)`);
      addNotification({
        type: 'success',
        title: 'Workflow Duplicated',
        message: `Workflow "${workflow.name}" has been duplicated successfully.`
      });
      // Refresh workflow list after duplication
      loadWorkflows(1, perPage);
    } catch (error) {
      console.error('Failed to duplicate workflow:', error);
      addNotification({
        type: 'error',
        title: 'Duplication Failed',
        message: 'Failed to duplicate workflow. Please try again.'
      });
    }
  };

  // Handle workflow deletion
  const handleDeleteWorkflow = async (workflow: AiWorkflow) => {
    if (!canDeleteWorkflows) {
      addNotification({
        type: 'error',
        title: 'Permission Denied',
        message: 'You do not have permission to delete workflows.'
      });
      return;
    }

    if (!confirm(`Are you sure you want to delete "${workflow.name}"? This action cannot be undone.`)) {
      return;
    }

    try {
      await workflowsApi.deleteWorkflow(workflow.id);
      addNotification({
        type: 'success',
        title: 'Workflow Deleted',
        message: `Workflow "${workflow.name}" has been deleted successfully.`
      });
      // Refresh workflow list after deletion
      loadWorkflows(1, perPage);
    } catch (error) {
      console.error('Failed to delete workflow:', error);
      addNotification({
        type: 'error',
        title: 'Deletion Failed',
        message: 'Failed to delete workflow. Please check if it has active runs.'
      });
    }
  };

  // Handle workflow creation
  const handleWorkflowCreated = (workflowId: string) => {
    // Refresh the workflow list to show the new workflow
    loadWorkflows(1, perPage);
    // Open the workflow detail modal to view the new workflow
    setSelectedWorkflowInitialTab('overview');
    setSelectedWorkflowId(workflowId);
  };

  // Handle workflow detail view
  const handleViewWorkflow = (workflow: AiWorkflow) => {
    setSelectedWorkflowInitialTab('overview');
    setSelectedWorkflowId(workflow.id);
  };

  const handleBuilderSuccess = (_workflow: AiWorkflow) => {
    // Refresh the workflow list to show updated workflow
    loadWorkflows(pagination.current_page, perPage);
    // Note: Modal stays open after save - user must explicitly close it
    // Note: WorkflowBuilderModal handles its own success notification
    // to prevent duplicate notifications
  };

  // Status badge rendering with theme-aware variants
  const renderStatusBadge = (status: string) => {
    const statusConfig = {
      draft: { variant: 'warning' as const, icon: Edit },
      active: { variant: 'success' as const, icon: CheckCircle },
      inactive: { variant: 'secondary' as const, icon: Archive },
      archived: { variant: 'secondary' as const, icon: Archive },
      paused: { variant: 'info' as const, icon: Pause }
    };

    const config = statusConfig[status as keyof typeof statusConfig] || statusConfig.draft;
    const IconComponent = config.icon;

    return (
      <Badge variant={config.variant} size="sm" className="min-w-fit whitespace-nowrap">
        <div className="flex items-center gap-1.5">
          <IconComponent className="h-3 w-3 flex-shrink-0" />
          <span className="flex-shrink-0">{status.charAt(0).toUpperCase() + status.slice(1)}</span>
        </div>
      </Badge>
    );
  };

  // Table columns
  const columns = [
    {
      key: 'name',
      header: (
        <button
          onClick={() => handleSort('name')}
          className="group flex items-center font-semibold text-theme-primary hover:text-theme-interactive-primary transition-colors"
          title="Sort by name"
        >
          Name
          {renderSortIndicator('name')}
        </button>
      ),
      width: '40%',
      render: (workflow: AiWorkflow) => (
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            <button
              onClick={() => navigate(`/app/ai/workflows/${workflow.id}`)}
              className="font-semibold text-lg text-theme-primary hover:text-theme-interactive-primary hover:underline whitespace-normal text-left transition-colors"
              title="View workflow details"
            >
              {workflow.name}
            </button>
            {workflow.is_template && (
              <Badge variant="info" size="sm" className="flex-shrink-0">
                <FileStack className="h-3 w-3 mr-1" />
                Template
              </Badge>
            )}
          </div>
          <div className="text-sm text-theme-muted leading-relaxed whitespace-normal">
            {workflow.description}
          </div>
        </div>
      )
    },
    {
      key: 'status',
      header: (
        <button
          onClick={() => handleSort('status')}
          className="group flex items-center font-semibold text-theme-primary hover:text-theme-interactive-primary transition-colors"
          title="Sort by status"
        >
          Status
          {renderSortIndicator('status')}
        </button>
      ),
      width: '10%',
      render: (workflow: AiWorkflow) => renderStatusBadge(workflow.status)
    },
    {
      key: 'stats',
      header: 'Stats',
      width: '10%',
      render: (workflow: AiWorkflow) => (
        <div className="text-sm">
          <div className="text-theme-primary">{workflow.stats?.nodes_count || 0} nodes</div>
          <div className="text-theme-muted">{workflow.stats?.runs_count || 0} runs</div>
        </div>
      )
    },
    {
      key: 'createdBy',
      header: (
        <button
          onClick={() => handleSort('creator')}
          className="group flex items-center font-semibold text-theme-primary hover:text-theme-interactive-primary transition-colors"
          title="Sort by creator"
        >
          Created By
          {renderSortIndicator('creator')}
        </button>
      ),
      width: '15%',
      render: (workflow: AiWorkflow) => (
        <div className="text-sm">
          <div className="text-theme-primary">{workflow.created_by?.name || 'System Admin'}</div>
          <div className="text-theme-muted">
            <button
              onClick={() => handleSort('created_at')}
              className="group flex items-center text-theme-muted hover:text-theme-interactive-primary transition-colors"
              title="Sort by creation date"
            >
              {workflow.created_at ? new Date(workflow.created_at).toLocaleDateString() : 'No date'}
              {sortBy === 'created_at' ? (
                renderSortIndicator('created_at')
              ) : (
                <ArrowUpDown className="h-3 w-3 inline-block ml-1 opacity-0 group-hover:opacity-40 transition-opacity" />
              )}
            </button>
          </div>
        </div>
      )
    },
    {
      key: 'actions',
      header: 'Actions',
      width: '25%',
      render: (workflow: AiWorkflow) => (
        <div className="flex items-center gap-2">
          <Button
            variant="ghost"
            size="sm"
            onClick={() => handleViewWorkflow(workflow)}
            title="View Details"
          >
            <Eye className="h-4 w-4" />
          </Button>
          {canExecuteWorkflows && workflow.status === 'active' && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => handleExecuteWorkflow(workflow)}
              title="Execute Workflow"
              className="text-theme-success hover:text-theme-success/80"
            >
              <Play className="h-4 w-4" />
            </Button>
          )}
          {currentUser?.permissions?.includes('ai.workflows.update') && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setBuilderWorkflowId(workflow.id)}
              title="Design Workflow"
              className="text-theme-interactive-primary hover:text-theme-interactive-primary/80"
            >
              <Workflow className="h-4 w-4" />
            </Button>
          )}
          {canCreateWorkflows && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => handleDuplicateWorkflow(workflow)}
              title="Duplicate Workflow"
            >
              <Copy className="h-4 w-4" />
            </Button>
          )}
          {canDeleteWorkflows && (
            <Button
              variant="ghost"
              size="sm"
              onClick={() => handleDeleteWorkflow(workflow)}
              title="Delete Workflow"
              className="text-theme-danger hover:text-theme-danger/80"
            >
              <Trash2 className="h-4 w-4" />
            </Button>
          )}
        </div>
      )
    }
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
        actions={[
          refreshAction,
          {
            id: 'monitoring',
            label: 'Monitoring',
            onClick: () => navigate('/app/ai/monitoring/workflows'),
            icon: Activity,
            variant: 'outline'
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
        ]}
    >
      <div className="space-y-4">
        {/* Search and Controls */}
        <div className="space-y-4">
          {/* Search Bar */}
          <div className="w-full">
            <SearchInput
              placeholder="Search workflows by name or description..."
              value={searchQuery}
              onChange={handleSearch}
              className="w-full"
            />
          </div>

          {/* Filters and Sorting on Same Line */}
          <div className="flex flex-wrap items-center gap-4">
            {/* Sort Controls */}
            <div className="flex items-center gap-2">
              <div className="flex items-center gap-1.5 text-sm font-medium text-theme-muted shrink-0">
                <ArrowUpDown className="h-4 w-4" />
                <span>Sort:</span>
              </div>
              <EnhancedSelect
                placeholder="Choose field"
                value={sortBy}
                onChange={(value) => setSortBy(value || 'created_at')}
                options={[
                  { value: 'name', label: 'Name', icon: FileText },
                  { value: 'created_at', label: 'Created', icon: Calendar },
                  { value: 'updated_at', label: 'Updated', icon: Calendar },
                  { value: 'status', label: 'Status', icon: CheckCircle },
                  { value: 'creator', label: 'Creator', icon: User },
                  { value: 'version', label: 'Version', icon: Hash }
                ]}
                className="w-32"
              />
              <button
                onClick={() => setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc')}
                className="flex items-center gap-2 px-3 py-2 text-sm font-medium border border-theme rounded-md bg-theme-surface hover:bg-theme-surface-elevated transition-colors min-w-fit"
                title={`Currently: ${getSortLabel(sortBy, sortOrder)}`}
              >
                {sortOrder === 'asc' ? (
                  <SortAsc className="h-4 w-4 text-theme-interactive-primary" />
                ) : (
                  <SortDesc className="h-4 w-4 text-theme-interactive-primary" />
                )}
                <span className="hidden sm:inline text-theme-primary">
                  {sortOrder === 'asc' ? 'A→Z' : 'Z→A'}
                </span>
              </button>
            </div>

            {/* Type Filter - Workflows vs Templates */}
            <div className="flex items-center gap-1 bg-theme-surface border border-theme rounded-lg p-1">
              <button
                onClick={() => setTypeFilter('all')}
                className={`px-3 py-1.5 text-sm font-medium rounded-md transition-colors ${
                  typeFilter === 'all'
                    ? 'bg-theme-interactive-primary text-theme-on-primary'
                    : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-elevated'
                }`}
              >
                All
              </button>
              <button
                onClick={() => setTypeFilter('workflows')}
                className={`px-3 py-1.5 text-sm font-medium rounded-md transition-colors flex items-center gap-1.5 ${
                  typeFilter === 'workflows'
                    ? 'bg-theme-interactive-primary text-theme-on-primary'
                    : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-elevated'
                }`}
              >
                <Workflow className="h-3.5 w-3.5" />
                Workflows
              </button>
              <button
                onClick={() => setTypeFilter('templates')}
                className={`px-3 py-1.5 text-sm font-medium rounded-md transition-colors flex items-center gap-1.5 ${
                  typeFilter === 'templates'
                    ? 'bg-theme-interactive-primary text-theme-on-primary'
                    : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-elevated'
                }`}
              >
                <FileStack className="h-3.5 w-3.5" />
                Templates
              </button>
            </div>

            {/* Filter Controls */}
            <div className="flex items-center gap-2">
              <div className="flex items-center gap-1.5 text-sm font-medium text-theme-muted shrink-0">
                <Filter className="h-4 w-4" />
                <span>Filter:</span>
              </div>
              <EnhancedSelect
                placeholder="All Statuses"
                value={filters.status || ''}
                onChange={(value) => handleFilterChange('status', value || undefined)}
                options={[
                  { value: '', label: 'All Statuses' },
                  { value: 'draft', label: 'Draft' },
                  { value: 'active', label: 'Active' },
                  { value: 'inactive', label: 'Inactive' },
                  { value: 'paused', label: 'Paused' },
                  { value: 'archived', label: 'Archived' }
                ]}
                className="w-32"
              />
              <EnhancedSelect
                placeholder="All Visibility"
                value={filters.visibility || ''}
                onChange={(value) => handleFilterChange('visibility', value || undefined)}
                options={[
                  { value: '', label: 'All Visibility' },
                  { value: 'private', label: 'Private' },
                  { value: 'account', label: 'Account' },
                  { value: 'public', label: 'Public' }
                ]}
                className="w-32"
              />
            </div>

            {/* Current Sort Display */}
            {(sortBy !== 'created_at' || sortOrder !== 'desc') && (
              <div className="flex items-center gap-2 px-3 py-2 bg-theme-interactive-primary/10 border border-theme-interactive-primary/20 rounded-md text-sm">
                <div className="flex items-center gap-1.5 text-theme-interactive-primary">
                  {React.createElement(getSortIcon(sortBy), { className: "h-4 w-4" })}
                  <span className="font-medium">
                    Sorted by {getSortLabel(sortBy, sortOrder)}
                  </span>
                </div>
                <button
                  onClick={() => {
                    setSortBy('created_at');
                    setSortOrder('desc');
                  }}
                  className="text-theme-muted hover:text-theme-primary transition-colors"
                  title="Reset to default sort"
                >
                  ×
                </button>
              </div>
            )}
          </div>
        </div>

        {/* Data Table */}
        <DataTable
          columns={columns}
          data={workflows || []}
          loading={loading}
          pagination={pagination}
          onPageChange={(page) => loadWorkflows(page, perPage)}
          emptyState={{
            icon: Play,
            title: 'No workflows found',
            description: canCreateWorkflows 
              ? 'Get started by creating your first AI workflow.'
              : 'No workflows have been created yet.',
            action: canCreateWorkflows ? {
              label: 'Create Workflow',
              onClick: () => setIsCreateModalOpen(true)
            } : undefined
          }}
        />
      </div>

      {/* Create Workflow Modal */}
      <WorkflowCreateModal
        isOpen={isCreateModalOpen}
        onClose={() => setIsCreateModalOpen(false)}
        onWorkflowCreated={handleWorkflowCreated}
      />

      {/* Workflow Detail Modal (includes Execute and Execution History tabs) */}
      <WorkflowDetailModal
        isOpen={!!selectedWorkflowId}
        onClose={() => setSelectedWorkflowId(null)}
        workflowId={selectedWorkflowId || ''}
        initialTab={selectedWorkflowInitialTab}
      />

      {/* Workflow Builder Modal */}
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