import React, { useState, useEffect, useCallback } from 'react';
import { useSelector } from 'react-redux';
import { Navigate, useLocation } from 'react-router-dom';
import { RootState } from '@/shared/services';
import { hasPermissions } from '@/shared/utils/permissionUtils';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { workerApi, Worker } from '@/features/system/workers/services/workerApi';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer } from '@/shared/components/ui/TabContainer';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { FlexBetween, FlexItemsCenter } from '@/shared/components/ui/FlexContainer';
import { CreateWorkerModal } from '@/features/system/workers/components/CreateWorkerModal';
import { useNotifications } from '@/shared/hooks/useNotifications';
import {
  WorkerOverviewTab,
  WorkerManagementTab,
  WorkerActivityTab,
  WorkerSecurityTab,
  WorkerSettingsTab,
  WorkerFiltersState,
  WorkersPageState,
  WorkerStats
} from './workers-tabs';
import {
  Users,
  Settings,
  Activity,
  Shield,
  Plus,
  RefreshCw,
  Download,
  CheckCircle,
  UserCheck,
  Eye
} from 'lucide-react';

export type { WorkerFiltersState } from './workers-tabs';

type TabType = 'overview' | 'workers' | 'activity' | 'security' | 'settings';

const initialFilters: WorkerFiltersState = {
  search: '',
  status: 'all',
  roleType: 'all',
  roles: [],
  permissions: [],
  sortBy: 'created_at',
  sortOrder: 'desc'
};

const initialState: WorkersPageState = {
  workers: [],
  filteredWorkers: [],
  selectedWorkers: new Set(),
  selectedWorker: null,
  loading: true,
  error: null,
  showCreateModal: false,
  showDetailsPanel: false,
  viewMode: 'grid',
  filters: initialFilters,
  pagination: {
    page: 1,
    pageSize: 12,
    total: 0
  }
};

export const WorkersPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const location = useLocation();
  const { showNotification } = useNotifications();
  usePageWebSocket({ pageType: 'system' });
  const [state, setState] = useState<WorkersPageState>(initialState);

  // Initialize active tab from URL
  const getTabFromUrl = useCallback(() => {
    const path = location.pathname;
    if (path.includes('/management')) return 'workers';
    if (path.includes('/activity')) return 'activity';
    if (path.includes('/security')) return 'security';
    if (path.includes('/settings')) return 'settings';
    return 'overview';
  }, [location.pathname]);

  const [activeTab, setActiveTab] = useState<TabType>(() => {
    const path = location.pathname;
    if (path.includes('/management')) return 'workers';
    if (path.includes('/activity')) return 'activity';
    if (path.includes('/security')) return 'security';
    if (path.includes('/settings')) return 'settings';
    return 'overview';
  });
  const [stats, setStats] = useState<WorkerStats>({
    total: 0,
    active: 0,
    suspended: 0,
    revoked: 0,
    systemWorkers: 0,
    accountWorkers: 0,
    recentlyActive: 0
  });

  // Permission checks
  const canViewWorkers = hasPermissions(user, ['system.workers.read']);
  const canManageWorkers = hasPermissions(user, [
    'system.workers.create',
    'system.workers.update',
    'system.workers.delete'
  ]);

  // Calculate worker stats
  const calculateStats = useCallback((workers: Worker[]): WorkerStats => {
    return {
      total: workers.length,
      active: workers.filter(w => w.status === 'active').length,
      suspended: workers.filter(w => w.status === 'suspended').length,
      revoked: workers.filter(w => w.status === 'revoked').length,
      systemWorkers: workers.filter(w => w.account_name === 'System').length,
      accountWorkers: workers.filter(w => w.account_name !== 'System').length,
      recentlyActive: workers.filter(w => w.active_recently).length
    };
  }, []);

  // Load workers data
  const loadWorkers = useCallback(async () => {
    setState(prev => ({ ...prev, loading: true, error: null }));
    try {
      const response = await workerApi.getWorkers();
      const workers = response.workers || [];
      const workerStats = calculateStats(workers);

      setState(prev => ({
        ...prev,
        workers,
        loading: false,
        pagination: {
          ...prev.pagination,
          total: response.total || 0
        }
      }));
      setStats(workerStats);
    } catch {
      const errorMessage = error instanceof Error ? error.message : 'Failed to load workers';
      showNotification(errorMessage, 'error');
      setState(prev => ({
        ...prev,
        workers: [],
        loading: false
      }));
      setStats({ total: 0, active: 0, suspended: 0, revoked: 0, systemWorkers: 0, accountWorkers: 0, recentlyActive: 0 });
    }
   
  }, [calculateStats]);

  // Filter and sort workers
  const applyFilters = useCallback((workers: Worker[], filters: WorkerFiltersState) => {
    let filtered = [...workers];

    // Search filter
    if (filters.search) {
      const searchLower = filters.search.toLowerCase();
      filtered = filtered.filter(worker =>
        worker.name.toLowerCase().includes(searchLower) ||
        worker.description?.toLowerCase().includes(searchLower) ||
        worker.account_name.toLowerCase().includes(searchLower) ||
        worker.masked_token.toLowerCase().includes(searchLower) ||
        worker.permissions.some(p => p.toLowerCase().includes(searchLower))
      );
    }

    // Status filter
    if (filters.status !== 'all') {
      filtered = filtered.filter(worker => worker.status === filters.status);
    }

    // Role type filter
    if (filters.roleType !== 'all') {
      if (filters.roleType === 'system') {
        filtered = filtered.filter(worker => worker.account_name === 'System');
      } else {
        filtered = filtered.filter(worker => worker.account_name !== 'System');
      }
    }

    // Role filter
    if (filters.roles.length > 0) {
      filtered = filtered.filter(worker =>
        filters.roles.some(role => worker.roles.includes(role))
      );
    }

    // Permission filter
    if (filters.permissions.length > 0) {
      filtered = filtered.filter(worker =>
        filters.permissions.some(permission => worker.permissions.includes(permission))
      );
    }

    // Sort with System workers first
    filtered.sort((a, b) => {
      // System workers always come first
      const aIsSystem = a.account_name === 'System';
      const bIsSystem = b.account_name === 'System';

      if (aIsSystem && !bIsSystem) return -1;
      if (!aIsSystem && bIsSystem) return 1;

      // Within the same category (system or account), sort by the selected criteria
      let comparison = 0;

      switch (filters.sortBy) {
        case 'name':
          comparison = a.name.localeCompare(b.name);
          break;
        case 'created_at':
          comparison = new Date(a.created_at).getTime() - new Date(b.created_at).getTime();
          break;
        case 'last_seen_at': {
          const aTime = a.last_seen_at ? new Date(a.last_seen_at).getTime() : 0;
          const bTime = b.last_seen_at ? new Date(b.last_seen_at).getTime() : 0;
          comparison = aTime - bTime;
          break;
        }
        case 'request_count':
          comparison = a.request_count - b.request_count;
          break;
      }

      return filters.sortOrder === 'desc' ? -comparison : comparison;
    });

    return filtered;
  }, []);

  // Update filtered workers when workers or filters change
  useEffect(() => {
    const filtered = applyFilters(state.workers, state.filters);
    setState(prev => ({ ...prev, filteredWorkers: filtered }));
  }, [state.workers, state.filters, applyFilters]);

  // Initial load
  useEffect(() => {
    if (canViewWorkers) {
      loadWorkers();
    }
  }, [canViewWorkers, loadWorkers]);

  // Update active tab from URL changes
  useEffect(() => {
    const newTab = getTabFromUrl();
    setActiveTab(prev => prev !== newTab ? newTab : prev);
  }, [getTabFromUrl]);

  // Event handlers
  const handleFiltersChange = useCallback((newFilters: Partial<WorkerFiltersState>) => {
    setState(prev => ({
      ...prev,
      filters: { ...prev.filters, ...newFilters },
      pagination: { ...prev.pagination, page: 1 }
    }));
  }, []);

  const handleWorkerSelect = useCallback((workerId: string, selected: boolean) => {
    setState(prev => {
      const newSelected = new Set(prev.selectedWorkers);
      if (selected) {
        newSelected.add(workerId);
      } else {
        newSelected.delete(workerId);
      }
      return { ...prev, selectedWorkers: newSelected };
    });
  }, []);

  const handleWorkerView = useCallback((worker: Worker) => {
    setState(prev => {
      // If clicking the same worker that's already expanded, collapse it
      if (prev.showDetailsPanel && prev.selectedWorker?.id === worker.id) {
        return {
          ...prev,
          selectedWorker: null,
          showDetailsPanel: false
        };
      }
      // Otherwise, expand with the new worker
      return {
        ...prev,
        selectedWorker: worker,
        showDetailsPanel: true
      };
    });
  }, []);

  const handleCreateWorker = useCallback(async (workerData: unknown) => {
    try {
      await workerApi.createWorker(workerData as Parameters<typeof workerApi.createWorker>[0]);
      await loadWorkers();
      setState(prev => ({ ...prev, showCreateModal: false }));
    } catch {
      const errorMessage = error instanceof Error ? error.message : 'Failed to create worker';
      throw new Error(errorMessage);
    }
  }, [loadWorkers]);

  const handleBulkAction = useCallback(async (action: string, workerIds: string[]) => {
    try {
      switch (action) {
        case 'activate':
          await Promise.all(workerIds.map(id => workerApi.activateWorker(id)));
          break;
        case 'suspend':
          await Promise.all(workerIds.map(id => workerApi.suspendWorker(id)));
          break;
        case 'delete':
          await Promise.all(workerIds.map(id => workerApi.deleteWorker(id)));
          break;
      }
      await loadWorkers();
      setState(prev => ({ ...prev, selectedWorkers: new Set() }));
    } catch {
      const errorMessage = error instanceof Error ? error.message : 'Failed to perform bulk action';
      showNotification(errorMessage, 'error');
    }
   
  }, [loadWorkers]);

  // Redirect if no permission
  if (!canViewWorkers) {
    return <Navigate to="/app" replace />;
  }

  if (state.loading) {
    return (
      <PageContainer
        title="Worker Management"
        description="Manage authentication workers, monitor activity, and control access permissions"
        breadcrumbs={[
          { label: 'Dashboard', href: '/app' },
          { label: 'System' },
          { label: 'Workers' }
        ]}
      >
        <FlexItemsCenter justify="center" className="py-12">
          <LoadingSpinner size="lg" />
          <span className="ml-3 text-theme-secondary">Loading worker configuration...</span>
        </FlexItemsCenter>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="Worker Management"
      description="Manage authentication workers, monitor activity, and control access permissions"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'System' },
        { label: 'Workers' }
      ]}
    >
      <div className="space-y-6">
        {/* Header Actions */}
        <FlexBetween>
          <div />

          <FlexItemsCenter gap="sm">
            <Button
              onClick={loadWorkers}
              variant="secondary"
              size="sm"
            >
              <RefreshCw className="w-4 h-4 mr-2" />
              Refresh
            </Button>

            <Button
              onClick={() => {
                // Implement export functionality
              }}
              variant="secondary"
              size="sm"
            >
              <Download className="w-4 h-4 mr-2" />
              Export
            </Button>

            {canManageWorkers && (
              <Button
                onClick={() => setState(prev => ({ ...prev, showCreateModal: true }))}
                variant="primary"
                size="sm"
              >
                <Plus className="w-4 h-4 mr-2" />
                Create Worker
              </Button>
            )}
          </FlexItemsCenter>
        </FlexBetween>

        {/* Stats Overview */}
        <Card className="p-4">
          <FlexBetween className="mb-4">
            <h3 className="text-lg font-medium text-theme-primary">Worker Status Overview</h3>
            <Badge
              variant={stats.active > 0 ? 'success' : 'secondary'}
              className="px-3 py-1"
            >
              {stats.recentlyActive} Online
            </Badge>
          </FlexBetween>

          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <div className="p-3 bg-theme-surface rounded-lg">
              <FlexItemsCenter className="mb-2">
                <Users className="w-4 h-4 text-theme-primary mr-2" />
                <span className="text-sm text-theme-secondary">Total Workers</span>
              </FlexItemsCenter>
              <div className="text-2xl font-bold text-theme-primary">{stats.total}</div>
            </div>

            <div className="p-3 bg-theme-surface rounded-lg">
              <FlexItemsCenter className="mb-2">
                <CheckCircle className="w-4 h-4 text-theme-success mr-2" />
                <span className="text-sm text-theme-secondary">Active</span>
              </FlexItemsCenter>
              <div className="text-2xl font-bold text-theme-success">{stats.active}</div>
            </div>

            <div className="p-3 bg-theme-surface rounded-lg">
              <FlexItemsCenter className="mb-2">
                <Settings className="w-4 h-4 text-theme-info mr-2" />
                <span className="text-sm text-theme-secondary">System Workers</span>
              </FlexItemsCenter>
              <div className="text-2xl font-bold text-theme-info">{stats.systemWorkers}</div>
            </div>

            <div className="p-3 bg-theme-surface rounded-lg">
              <FlexItemsCenter className="mb-2">
                <UserCheck className="w-4 h-4 text-theme-warning mr-2" />
                <span className="text-sm text-theme-secondary">Account Workers</span>
              </FlexItemsCenter>
              <div className="text-2xl font-bold text-theme-warning">{stats.accountWorkers}</div>
            </div>
          </div>
        </Card>

        {/* Tab Navigation and Content */}
        <TabContainer
          basePath="/app/system/workers"
          tabs={[
            {
              id: 'overview',
              label: 'Overview',
              icon: <Eye className="w-4 h-4" />,
              path: '/overview',
              content: (
                <WorkerOverviewTab
                  workers={state.workers}
                  stats={stats}
                  onRefresh={loadWorkers}
                  loading={state.loading}
                />
              )
            },
            {
              id: 'workers',
              label: 'Worker Management',
              icon: <Users className="w-4 h-4" />,
              path: '/management',
              badge: stats.total,
              content: (
                <WorkerManagementTab
                  state={state}
                  setState={setState}
                  canManageWorkers={canManageWorkers}
                  handleFiltersChange={handleFiltersChange}
                  handleWorkerSelect={handleWorkerSelect}
                  handleWorkerView={handleWorkerView}
                  handleBulkAction={handleBulkAction}
                  loadWorkers={loadWorkers}
                />
              )
            },
            {
              id: 'activity',
              label: 'Activity Monitoring',
              icon: <Activity className="w-4 h-4" />,
              path: '/activity',
              content: (
                <WorkerActivityTab
                  workers={state.workers}
                  onRefresh={loadWorkers}
                />
              )
            },
            {
              id: 'security',
              label: 'Security & Permissions',
              icon: <Shield className="w-4 h-4" />,
              path: '/security',
              content: (
                <WorkerSecurityTab
                  workers={state.workers}
                  canManageWorkers={canManageWorkers}
                  onRefresh={loadWorkers}
                />
              )
            },
            {
              id: 'settings',
              label: 'Configuration',
              icon: <Settings className="w-4 h-4" />,
              path: '/settings',
              content: (
                <WorkerSettingsTab
                  workers={state.workers}
                  canManageWorkers={canManageWorkers}
                  onRefresh={loadWorkers}
                />
              )
            }
          ]}
          activeTab={activeTab}
          onTabChange={(tabId) => setActiveTab(tabId as TabType)}
          variant="underline"
        />

        {/* Create Worker Modal */}
        {state.showCreateModal && (
          <CreateWorkerModal
            isOpen={state.showCreateModal}
            onClose={() => setState(prev => ({ ...prev, showCreateModal: false }))}
            onCreate={handleCreateWorker}
          />
        )}
      </div>
    </PageContainer>
  );
};

export default WorkersPage;
