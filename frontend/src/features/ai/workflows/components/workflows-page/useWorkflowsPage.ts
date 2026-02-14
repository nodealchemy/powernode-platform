import { useState, useEffect, useCallback } from 'react';
import { useNavigate, useSearchParams, useLocation } from 'react-router-dom';
import { workflowsApi } from '@/shared/services/ai';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useAiOrchestrationWebSocket } from '@/shared/hooks/useAiOrchestrationWebSocket';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import { AiWorkflow } from '@/shared/types/workflow';
import type { WorkflowFilters } from '@/shared/services/ai/types/workflow-api-types';
import { logger } from '@/shared/utils/logger';

export function useWorkflowsPage() {
  const navigate = useNavigate();
  const location = useLocation();
  const [searchParams, setSearchParams] = useSearchParams();
  const { currentUser } = useAuth();
  const { addNotification } = useNotifications();

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
  const [perPage, setPerPage] = useState(25);
  const [isInitialMount, setIsInitialMount] = useState(true);
  const [hasSearched, setHasSearched] = useState(false);
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

  const canCreateWorkflows = currentUser?.permissions?.includes('ai.workflows.create') || false;
  const canExecuteWorkflows = currentUser?.permissions?.includes('ai.workflows.execute') || false;
  const canDeleteWorkflows = currentUser?.permissions?.includes('ai.workflows.delete') || false;
  const canUpdateWorkflows = currentUser?.permissions?.includes('ai.workflows.update') || false;

  const loadWorkflows = useCallback(async (page = 1, itemsPerPage = 25, skipLoading = false) => {
    try {
      if (!skipLoading) setLoading(true);
      const searchFilters: WorkflowFilters = {
        ...filters,
        search: searchQuery || undefined,
        sort_by: sortBy,
        sort_order: sortOrder,
        page: page,
        per_page: itemsPerPage,
        is_template: typeFilter === 'templates' ? true : typeFilter === 'workflows' ? false : undefined
      };
      const response = await workflowsApi.getWorkflows(searchFilters);
      setWorkflows(response.items);
      setPagination(response.pagination);
      if (response.pagination.per_page && response.pagination.per_page !== itemsPerPage) {
        setPerPage(response.pagination.per_page);
      }
    } catch (error) {
      logger.error('Failed to load workflows', error);
      setWorkflows([]);
      setPagination({ current_page: 1, total_pages: 1, total_count: 0, per_page: itemsPerPage });
      addNotification({ type: 'error', title: 'Error', message: 'Failed to load workflows. Please try again.' });
    } finally {
      if (!skipLoading) setLoading(false);
    }
  }, [filters, searchQuery, sortBy, sortOrder, typeFilter, addNotification]);

  // WebSocket for real-time updates
  useAiOrchestrationWebSocket({
    onWorkflowEvent: (event) => {
      if (['workflow_created', 'workflow_updated', 'workflow_deleted'].includes(event.type)) {
        loadWorkflows(pagination.current_page, perPage, true);
      }
    },
  });

  const { refreshAction } = useRefreshAction({
    onRefresh: () => loadWorkflows(pagination.current_page, perPage),
    loading,
  });

  // Tab routing
  const getActiveTab = () => {
    const path = location.pathname;
    if (path.includes('/workflows/templates')) return 'templates';
    return 'workflows';
  };

  const [activeTab, setActiveTab] = useState(getActiveTab());

  useEffect(() => {
    const newTab = getActiveTab();
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname]);

  // Initial load
  useEffect(() => {
    loadWorkflows(1, perPage);
    setIsInitialMount(false);
  }, []);

  // Search handler
  const handleSearch = useCallback((query: string) => {
    setSearchQuery(query);
    if (query && !hasSearched) setHasSearched(true);
  }, [hasSearched]);

  // Debounced search
  useEffect(() => {
    if (searchQuery === '' && !hasSearched) return;
    const timeoutId = setTimeout(() => { loadWorkflows(1, perPage); }, 300);
    return () => clearTimeout(timeoutId);
  }, [searchQuery, perPage, hasSearched]);

  // Filter changes
  const handleFilterChange = useCallback((key: keyof WorkflowFilters, value: WorkflowFilters[keyof WorkflowFilters]) => {
    setFilters(prev => ({ ...prev, [key]: value }) as WorkflowFilters);
  }, []);

  useEffect(() => {
    if (Object.keys(filters).length > 0 || Object.values(filters).some(v => v !== undefined && v !== '')) {
      loadWorkflows(1, perPage);
    }
  }, [filters, perPage]);

  // Type filter changes
  useEffect(() => {
    if (isInitialMount) return;
    loadWorkflows(1, perPage);
    if (typeFilter === 'all') {
      searchParams.delete('type');
    } else {
      searchParams.set('type', typeFilter);
    }
    setSearchParams(searchParams, { replace: true });
  }, [typeFilter]);

  // Sort changes
  useEffect(() => {
    if (isInitialMount) return;
    const timeoutId = setTimeout(() => { loadWorkflows(1, perPage, true); }, 100);
    return () => clearTimeout(timeoutId);
  }, [sortBy, sortOrder, perPage, isInitialMount]);

  const handleSort = useCallback((field: string) => {
    if (sortBy === field) {
      setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc');
    } else {
      setSortBy(field);
    }
  }, [sortBy, sortOrder]);

  const handleExecuteWorkflow = async (workflow: AiWorkflow) => {
    if (!canExecuteWorkflows) {
      addNotification({ type: 'error', title: 'Permission Denied', message: 'You do not have permission to execute workflows.' });
      return;
    }
    setSelectedWorkflowInitialTab('execute');
    setSelectedWorkflowId(workflow.id);
  };

  const handleDuplicateWorkflow = async (workflow: AiWorkflow) => {
    if (!canCreateWorkflows) {
      addNotification({ type: 'error', title: 'Permission Denied', message: 'You do not have permission to create workflows.' });
      return;
    }
    try {
      await workflowsApi.duplicateWorkflow(workflow.id, `${workflow.name} (Copy)`);
      addNotification({ type: 'success', title: 'Workflow Duplicated', message: `Workflow "${workflow.name}" has been duplicated successfully.` });
      loadWorkflows(1, perPage);
    } catch (error) {
      logger.error('Failed to duplicate workflow', error);
      addNotification({ type: 'error', title: 'Duplication Failed', message: 'Failed to duplicate workflow. Please try again.' });
    }
  };

  const handleDeleteWorkflow = async (workflow: AiWorkflow) => {
    if (!canDeleteWorkflows) {
      addNotification({ type: 'error', title: 'Permission Denied', message: 'You do not have permission to delete workflows.' });
      return;
    }
    if (!confirm(`Are you sure you want to delete "${workflow.name}"? This action cannot be undone.`)) return;
    try {
      await workflowsApi.deleteWorkflow(workflow.id);
      addNotification({ type: 'success', title: 'Workflow Deleted', message: `Workflow "${workflow.name}" has been deleted successfully.` });
      loadWorkflows(1, perPage);
    } catch (error) {
      logger.error('Failed to delete workflow', error);
      addNotification({ type: 'error', title: 'Deletion Failed', message: 'Failed to delete workflow. Please check if it has active runs.' });
    }
  };

  const handleWorkflowCreated = (workflowId: string) => {
    loadWorkflows(1, perPage);
    setSelectedWorkflowInitialTab('overview');
    setSelectedWorkflowId(workflowId);
  };

  const handleViewWorkflow = (workflow: AiWorkflow) => {
    setSelectedWorkflowInitialTab('overview');
    setSelectedWorkflowId(workflow.id);
  };

  const handleBuilderSuccess = (_workflow: AiWorkflow) => {
    loadWorkflows(pagination.current_page, perPage);
  };

  return {
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
  };
}
