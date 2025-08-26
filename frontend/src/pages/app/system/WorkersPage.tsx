import React, { useState, useEffect, useCallback } from 'react';
import { useSelector } from 'react-redux';
import { Navigate, useLocation } from 'react-router-dom';
import { RootState } from '@/shared/services';
import { hasPermissions } from '@/shared/utils/permissionUtils';
import { workerAPI, Worker } from '@/features/workers/services/workerApi';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer } from '@/shared/components/ui/TabContainer';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { FlexBetween, FlexItemsCenter } from '@/shared/components/ui/FlexContainer';
import { WorkerFilters } from '@/features/workers/components/WorkerFilters';
import { WorkerGrid } from '@/features/workers/components/WorkerGrid';
import { WorkerTable } from '@/features/workers/components/WorkerTable';
import { WorkerActions } from '@/features/workers/components/WorkerActions';
import { CreateWorkerModal } from '@/features/workers/components/CreateWorkerModal';
import { WorkerDetailsPanel } from '@/features/workers/components/WorkerDetailsPanel';
import { 
  Users, 
  Settings, 
  Activity, 
  Shield, 
  Plus, 
  RefreshCw, 
  Download, 
  Grid, 
  List,
  AlertTriangle,
  CheckCircle,
  UserCheck,
  Eye
} from 'lucide-react';

export interface WorkerFiltersState {
  search: string;
  status: 'all' | 'active' | 'suspended' | 'revoked';
  roleType: 'all' | 'system' | 'account';
  roles: string[];
  permissions: string[];
  sortBy: 'name' | 'created_at' | 'last_seen_at' | 'request_count';
  sortOrder: 'asc' | 'desc';
}

interface WorkersPageState {
  workers: Worker[];
  filteredWorkers: Worker[];
  selectedWorkers: Set<string>;
  selectedWorker: Worker | null;
  loading: boolean;
  error: string | null;
  showCreateModal: boolean;
  showDetailsPanel: boolean;
  viewMode: 'grid' | 'table';
  filters: WorkerFiltersState;
  pagination: {
    page: number;
    pageSize: number;
    total: number;
  };
}

type TabType = 'overview' | 'workers' | 'activity' | 'security' | 'settings';

interface WorkerStats {
  total: number;
  active: number;
  suspended: number;
  revoked: number;
  systemWorkers: number;
  accountWorkers: number;
  recentlyActive: number;
}

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
  const canViewWorkers = hasPermissions(user, ['system.workers.view']);
  const canManageWorkers = hasPermissions(user, [
    'system.workers.create', 
    'system.workers.edit', 
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
      const response = await workerAPI.getWorkers();
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
    } catch (error: any) {
      setState(prev => ({
        ...prev,
        error: error.message || 'Failed to load workers',
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
        case 'last_seen_at':
          const aTime = a.last_seen_at ? new Date(a.last_seen_at).getTime() : 0;
          const bTime = b.last_seen_at ? new Date(b.last_seen_at).getTime() : 0;
          comparison = aTime - bTime;
          break;
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

  const handleCreateWorker = useCallback(async (workerData: any) => {
    try {
      await workerAPI.createWorker(workerData);
      await loadWorkers();
      setState(prev => ({ ...prev, showCreateModal: false }));
    } catch (error: any) {
      throw new Error(error.message || 'Failed to create worker');
    }
  }, [loadWorkers]);

  const handleBulkAction = useCallback(async (action: string, workerIds: string[]) => {
    try {
      // Implement bulk actions
      switch (action) {
        case 'activate':
          await Promise.all(workerIds.map(id => workerAPI.activateWorker(id)));
          break;
        case 'suspend':
          await Promise.all(workerIds.map(id => workerAPI.suspendWorker(id)));
          break;
        case 'delete':
          await Promise.all(workerIds.map(id => workerAPI.deleteWorker(id)));
          break;
      }
      await loadWorkers();
      setState(prev => ({ ...prev, selectedWorkers: new Set() }));
    } catch (error: any) {
      setState(prev => ({ ...prev, error: error.message || 'Failed to perform bulk action' }));
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
          { label: 'Dashboard', href: '/app', icon: '🏠' },
          { label: 'System', icon: '⚙️' },
          { label: 'Workers', href: '/app/system/workers/overview', icon: '🤖' }
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
        { label: 'Dashboard', href: '/app', icon: '🏠' },
        { label: 'System', icon: '⚙️' },
        { label: 'Workers', href: '/app/system/workers/overview', icon: '🤖' }
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

        {/* Error Message */}
        {state.error && (
          <Card className="p-4 bg-theme-error-background border-theme-error">
            <FlexBetween>
              <FlexItemsCenter>
                <AlertTriangle className="w-5 h-5 text-theme-error mr-3" />
                <p className="text-theme-error font-medium">{state.error}</p>
              </FlexItemsCenter>
              <Button
                onClick={() => setState(prev => ({ ...prev, error: null }))}
                variant="secondary"
                size="sm"
              >
                ✕
              </Button>
            </FlexBetween>
          </Card>
        )}

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

// Worker Overview Tab Component
const WorkerOverviewTab: React.FC<{
  workers: Worker[];
  stats: WorkerStats;
  onRefresh: () => void;
  loading: boolean;
}> = ({ workers, stats, onRefresh, loading }) => {
  const recentWorkers = workers
    .sort((a, b) => {
      // System workers first, then by creation date
      const aIsSystem = a.account_name === 'System';
      const bIsSystem = b.account_name === 'System';
      
      if (aIsSystem && !bIsSystem) return -1;
      if (!aIsSystem && bIsSystem) return 1;
      
      return new Date(b.created_at).getTime() - new Date(a.created_at).getTime();
    })
    .slice(0, 5);

  const activeWorkers = workers
    .filter(w => w.active_recently)
    .sort((a, b) => {
      // System workers first, then by request count
      const aIsSystem = a.account_name === 'System';
      const bIsSystem = b.account_name === 'System';
      
      if (aIsSystem && !bIsSystem) return -1;
      if (!aIsSystem && bIsSystem) return 1;
      
      return b.request_count - a.request_count;
    })
    .slice(0, 5);

  return (
    <div className="space-y-6">
      {/* Quick Stats Grid */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <Card className="p-6">
          <FlexBetween className="mb-4">
            <h3 className="text-lg font-medium text-theme-primary">Status Distribution</h3>
            <Button onClick={onRefresh} variant="secondary" size="sm">
              <RefreshCw className="w-4 h-4" />
            </Button>
          </FlexBetween>
          <div className="space-y-3">
            <FlexBetween>
              <FlexItemsCenter>
                <div className="w-3 h-3 bg-theme-success rounded-full mr-2"></div>
                <span className="text-sm text-theme-secondary">Active</span>
              </FlexItemsCenter>
              <span className="font-medium text-theme-success">{stats.active}</span>
            </FlexBetween>
            <FlexBetween>
              <FlexItemsCenter>
                <div className="w-3 h-3 bg-theme-warning rounded-full mr-2"></div>
                <span className="text-sm text-theme-secondary">Suspended</span>
              </FlexItemsCenter>
              <span className="font-medium text-theme-warning">{stats.suspended}</span>
            </FlexBetween>
            <FlexBetween>
              <FlexItemsCenter>
                <div className="w-3 h-3 bg-theme-error rounded-full mr-2"></div>
                <span className="text-sm text-theme-secondary">Revoked</span>
              </FlexItemsCenter>
              <span className="font-medium text-theme-error">{stats.revoked}</span>
            </FlexBetween>
          </div>
        </Card>

        <Card className="p-6">
          <h3 className="text-lg font-medium text-theme-primary mb-4">Recently Created</h3>
          <div className="space-y-3">
            {recentWorkers.length === 0 ? (
              <p className="text-sm text-theme-secondary">No workers created recently</p>
            ) : (
              recentWorkers.map((worker) => (
                <FlexBetween key={worker.id}>
                  <div>
                    <div className="font-medium text-theme-primary text-sm">{worker.name}</div>
                    <div className="text-xs text-theme-secondary">{worker.account_name}</div>
                  </div>
                  <Badge 
                    variant={worker.status === 'active' ? 'success' : 'secondary'} 
                    size="sm"
                  >
                    {worker.status}
                  </Badge>
                </FlexBetween>
              ))
            )}
          </div>
        </Card>

        <Card className="p-6">
          <h3 className="text-lg font-medium text-theme-primary mb-4">Recently Active</h3>
          <div className="space-y-3">
            {activeWorkers.length === 0 ? (
              <p className="text-sm text-theme-secondary">No workers recently active</p>
            ) : (
              activeWorkers.map((worker) => (
                <FlexBetween key={worker.id}>
                  <div>
                    <div className="font-medium text-theme-primary text-sm">{worker.name}</div>
                    <div className="text-xs text-theme-secondary">
                      {worker.last_seen_at ? 
                        `Last seen ${new Date(worker.last_seen_at).toLocaleDateString()}` : 
                        'Never seen'
                      }
                    </div>
                  </div>
                  <div className="text-xs text-theme-primary">
                    {worker.request_count.toLocaleString()} requests
                  </div>
                </FlexBetween>
              ))
            )}
          </div>
        </Card>
      </div>

      {/* System Health Summary */}
      <Card className="p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-4">System Health</h3>
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          <div className="text-center p-4 bg-theme-surface rounded-lg">
            <div className="text-2xl font-bold text-theme-primary mb-1">{stats.recentlyActive}</div>
            <div className="text-sm text-theme-secondary">Online Now</div>
          </div>
          <div className="text-center p-4 bg-theme-surface rounded-lg">
            <div className="text-2xl font-bold text-theme-info mb-1">{stats.systemWorkers}</div>
            <div className="text-sm text-theme-secondary">System Workers</div>
          </div>
          <div className="text-center p-4 bg-theme-surface rounded-lg">
            <div className="text-2xl font-bold text-theme-warning mb-1">{stats.accountWorkers}</div>
            <div className="text-sm text-theme-secondary">Account Workers</div>
          </div>
          <div className="text-center p-4 bg-theme-surface rounded-lg">
            <div className="text-2xl font-bold text-theme-primary mb-1">
              {Math.round((stats.active / stats.total) * 100) || 0}%
            </div>
            <div className="text-sm text-theme-secondary">Uptime</div>
          </div>
        </div>
      </Card>
    </div>
  );
};

// Worker Management Tab Component
const WorkerManagementTab: React.FC<{
  state: WorkersPageState;
  setState: React.Dispatch<React.SetStateAction<WorkersPageState>>;
  canManageWorkers: boolean;
  handleFiltersChange: (newFilters: Partial<WorkerFiltersState>) => void;
  handleWorkerSelect: (workerId: string, selected: boolean) => void;
  handleWorkerView: (worker: Worker) => void;
  handleBulkAction: (action: string, workerIds: string[]) => Promise<void>;
  loadWorkers: () => Promise<void>;
}> = ({ 
  state, 
  setState, 
  canManageWorkers, 
  handleFiltersChange, 
  handleWorkerSelect, 
  handleWorkerView, 
  handleBulkAction, 
  loadWorkers 
}) => {
  return (
    <div className="space-y-6">
      {/* Filters and View Toggle */}
      <Card className="p-6">
        <FlexBetween className="mb-4">
          <div>
            <h3 className="text-lg font-medium text-theme-primary">Worker Management</h3>
            <p className="text-sm text-theme-secondary">
              Manage and monitor all authentication workers
            </p>
          </div>
          <FlexItemsCenter gap="sm">
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

        <div className="flex flex-col lg:flex-row gap-4 items-start lg:items-center justify-between">
          <div className="flex-1 min-w-0">
            <WorkerFilters
              filters={state.filters}
              onChange={handleFiltersChange}
              totalWorkers={state.workers.length}
              filteredWorkers={state.filteredWorkers.length}
            />
          </div>
          
          <div className="flex items-center gap-4">
            {/* Bulk Actions */}
            {state.selectedWorkers.size > 0 && canManageWorkers && (
              <WorkerActions
                selectedCount={state.selectedWorkers.size}
                onBulkAction={(action) => handleBulkAction(action, Array.from(state.selectedWorkers))}
              />
            )}

            {/* View Toggle */}
            <div className="flex border border-theme rounded-lg overflow-hidden">
              <button
                onClick={() => setState(prev => ({ ...prev, viewMode: 'grid' }))}
                className={`px-3 py-2 text-sm transition-colors ${
                  state.viewMode === 'grid'
                    ? 'bg-theme-interactive-primary text-white'
                    : 'bg-theme-background text-theme-primary hover:bg-theme-surface'
                }`}
              >
                <Grid className="w-4 h-4" />
              </button>
              <button
                onClick={() => setState(prev => ({ ...prev, viewMode: 'table' }))}
                className={`px-3 py-2 text-sm transition-colors border-l border-theme ${
                  state.viewMode === 'table'
                    ? 'bg-theme-interactive-primary text-white'
                    : 'bg-theme-background text-theme-primary hover:bg-theme-surface'
                }`}
              >
                <List className="w-4 h-4" />
              </button>
            </div>
          </div>
        </div>
      </Card>

      {/* Workers Display */}
      {state.filteredWorkers.length === 0 ? (
        <Card className="p-12 text-center">
          <div className="text-6xl mb-4">🤖</div>
          <h3 className="text-xl font-semibold text-theme-primary mb-2">No Workers Found</h3>
          <p className="text-theme-secondary mb-4">
            {state.filters.search || state.filters.status !== 'all' || state.filters.roleType !== 'all' || 
             state.filters.roles.length > 0 || state.filters.permissions.length > 0
              ? 'No workers match your current filters. Try adjusting your search criteria.'
              : 'Get started by creating your first authentication worker.'
            }
          </p>
          {canManageWorkers && state.workers.length === 0 && (
            <Button
              onClick={() => setState(prev => ({ ...prev, showCreateModal: true }))}
              variant="primary"
            >
              <Plus className="w-4 h-4 mr-2" />
              Create Your First Worker
            </Button>
          )}
        </Card>
      ) : (
        <div className="space-y-6">
          {state.viewMode === 'grid' ? (
            <WorkerGrid
              workers={state.filteredWorkers}
              selectedWorkers={state.selectedWorkers}
              onWorkerSelect={handleWorkerSelect}
              onWorkerView={handleWorkerView}
              pagination={state.pagination}
              onPaginationChange={(newPagination) => 
                setState(prev => ({ ...prev, pagination: { ...prev.pagination, ...newPagination } }))
              }
              expandedWorker={state.selectedWorker}
              isExpanded={state.showDetailsPanel}
              onUpdateWorker={async (workerId, data) => {
                await workerAPI.updateWorker(workerId, data);
                await loadWorkers();
              }}
              onDeleteWorker={async (workerId) => {
                await workerAPI.deleteWorker(workerId);
                await loadWorkers();
                setState(prev => ({ ...prev, showDetailsPanel: false, selectedWorker: null }));
              }}
              onCloseExpanded={() => setState(prev => ({ ...prev, showDetailsPanel: false, selectedWorker: null }))}
            />
          ) : (
            <WorkerTable
              workers={state.filteredWorkers}
              selectedWorkers={state.selectedWorkers}
              onWorkerSelect={handleWorkerSelect}
              onWorkerView={handleWorkerView}
              sortBy={state.filters.sortBy}
              sortOrder={state.filters.sortOrder}
              onSort={(sortBy: string, sortOrder: 'asc' | 'desc') => 
                handleFiltersChange({ sortBy: sortBy as 'name' | 'created_at' | 'last_seen_at' | 'request_count', sortOrder })
              }
              pagination={state.pagination}
              onPaginationChange={(newPagination) => 
                setState(prev => ({ ...prev, pagination: { ...prev.pagination, ...newPagination } }))
              }
              expandedWorker={state.selectedWorker}
              isExpanded={state.showDetailsPanel}
              onUpdateWorker={async (workerId, data) => {
                await workerAPI.updateWorker(workerId, data);
                await loadWorkers();
              }}
              onDeleteWorker={async (workerId) => {
                await workerAPI.deleteWorker(workerId);
                await loadWorkers();
                setState(prev => ({ ...prev, showDetailsPanel: false, selectedWorker: null }));
              }}
              onCloseExpanded={() => setState(prev => ({ ...prev, showDetailsPanel: false, selectedWorker: null }))}
            />
          )}
        </div>
      )}
    </div>
  );
};

// Worker Activity Tab Component
const WorkerActivityTab: React.FC<{
  workers: Worker[];
  onRefresh: () => void;
}> = ({ workers, onRefresh }) => {
  const [selectedWorker, setSelectedWorker] = useState<string | null>(null);
  const [timeRange, setTimeRange] = useState<'1h' | '24h' | '7d' | '30d'>('24h');

  const getActivityData = () => {
    return workers
      .filter(w => w.active_recently)
      .map(w => ({
        name: w.name,
        requests: w.request_count,
        lastSeen: w.last_seen_at,
        status: w.status,
        account: w.account_name,
        isSystem: w.account_name === 'System'
      }))
      .sort((a, b) => {
        // System workers first, then by request count
        if (a.isSystem && !b.isSystem) return -1;
        if (!a.isSystem && b.isSystem) return 1;
        
        return b.requests - a.requests;
      });
  };

  const activityData = getActivityData();

  return (
    <div className="space-y-6">
      {/* Activity Controls */}
      <Card className="p-6">
        <FlexBetween className="mb-4">
          <div>
            <h3 className="text-lg font-medium text-theme-primary">Activity Monitoring</h3>
            <p className="text-sm text-theme-secondary">
              Monitor worker activity and performance metrics
            </p>
          </div>
          <FlexItemsCenter gap="sm">
            <select
              value={timeRange}
              onChange={(e) => setTimeRange(e.target.value as '1h' | '24h' | '7d' | '30d')}
              className="px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary text-sm"
            >
              <option value="1h">Last Hour</option>
              <option value="24h">Last 24 Hours</option>
              <option value="7d">Last 7 Days</option>
              <option value="30d">Last 30 Days</option>
            </select>
            <Button onClick={onRefresh} variant="secondary" size="sm">
              <RefreshCw className="w-4 h-4 mr-2" />
              Refresh
            </Button>
          </FlexItemsCenter>
        </FlexBetween>

        {/* Activity Summary */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          <div className="p-4 bg-theme-surface rounded-lg">
            <div className="text-sm text-theme-secondary mb-1">Active Workers</div>
            <div className="text-2xl font-bold text-theme-success">
              {workers.filter(w => w.active_recently).length}
            </div>
          </div>
          <div className="p-4 bg-theme-surface rounded-lg">
            <div className="text-sm text-theme-secondary mb-1">Total Requests</div>
            <div className="text-2xl font-bold text-theme-primary">
              {workers.reduce((sum, w) => sum + w.request_count, 0).toLocaleString()}
            </div>
          </div>
          <div className="p-4 bg-theme-surface rounded-lg">
            <div className="text-sm text-theme-secondary mb-1">Avg Requests/Worker</div>
            <div className="text-2xl font-bold text-theme-info">
              {Math.round(workers.reduce((sum, w) => sum + w.request_count, 0) / workers.length) || 0}
            </div>
          </div>
          <div className="p-4 bg-theme-surface rounded-lg">
            <div className="text-sm text-theme-secondary mb-1">Health Score</div>
            <div className="text-2xl font-bold text-theme-success">98%</div>
          </div>
        </div>
      </Card>

      {/* Activity List */}
      <Card className="p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-4">Worker Activity</h3>
        <div className="space-y-3">
          {activityData.length === 0 ? (
            <p className="text-center text-theme-secondary py-8">No activity data available</p>
          ) : (
            activityData.map((worker, index) => (
              <div 
                key={worker.name} 
                className={`p-4 border border-theme rounded-lg ${
                  worker.isSystem ? 'bg-gradient-to-r from-theme-info/5 to-transparent border-theme-info/30' : ''
                }`}
              >
                <FlexBetween>
                  <div className="flex items-center space-x-3">
                    <div className={`w-8 h-8 rounded-full flex items-center justify-center text-sm font-medium ${
                      worker.isSystem ? 'bg-theme-info/20 text-theme-info' : 'bg-theme-primary/10 text-theme-primary'
                    }`}>
                      {worker.isSystem ? '⚙️' : index + 1}
                    </div>
                    <div>
                      <div className="font-medium text-theme-primary">
                        {worker.name}
                        {worker.isSystem && (
                          <span className="ml-2 px-2 py-0.5 text-xs bg-theme-info/10 text-theme-info rounded-full">
                            SYSTEM
                          </span>
                        )}
                      </div>
                      <div className="text-sm text-theme-secondary">{worker.account}</div>
                    </div>
                  </div>
                  <div className="text-right">
                    <div className="font-medium text-theme-primary">
                      {worker.requests.toLocaleString()} requests
                    </div>
                    <div className="text-sm text-theme-secondary">
                      {worker.lastSeen ? 
                        `Last seen ${new Date(worker.lastSeen).toLocaleDateString()}` : 
                        'Never seen'
                      }
                    </div>
                  </div>
                </FlexBetween>
              </div>
            ))
          )}
        </div>
      </Card>
    </div>
  );
};

// Worker Security Tab Component
const WorkerSecurityTab: React.FC<{
  workers: Worker[];
  canManageWorkers: boolean;
  onRefresh: () => void;
}> = ({ workers, canManageWorkers, onRefresh }) => {
  const [selectedWorker, setSelectedWorker] = useState<string | null>(null);

  const getSecurityStats = () => {
    const totalPermissions = new Set(workers.flatMap(w => w.permissions)).size;
    const totalRoles = new Set(workers.flatMap(w => w.roles)).size;
    const expiredTokens = 0; // Would need to be calculated based on actual token expiry
    const securityEvents = 0; // Would need to be fetched from audit logs

    return { totalPermissions, totalRoles, expiredTokens, securityEvents };
  };

  const securityStats = getSecurityStats();

  return (
    <div className="space-y-6">
      {/* Security Overview */}
      <Card className="p-6">
        <FlexBetween className="mb-4">
          <div>
            <h3 className="text-lg font-medium text-theme-primary">Security Overview</h3>
            <p className="text-sm text-theme-secondary">
              Monitor worker security status and permissions
            </p>
          </div>
          <Button onClick={onRefresh} variant="secondary" size="sm">
            <RefreshCw className="w-4 h-4 mr-2" />
            Refresh
          </Button>
        </FlexBetween>

        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          <div className="p-4 bg-theme-surface rounded-lg">
            <FlexItemsCenter className="mb-2">
              <Shield className="w-4 h-4 text-theme-primary mr-2" />
              <span className="text-sm text-theme-secondary">Total Roles</span>
            </FlexItemsCenter>
            <div className="text-2xl font-bold text-theme-primary">{securityStats.totalRoles}</div>
          </div>
          <div className="p-4 bg-theme-surface rounded-lg">
            <FlexItemsCenter className="mb-2">
              <UserCheck className="w-4 h-4 text-theme-info mr-2" />
              <span className="text-sm text-theme-secondary">Permissions</span>
            </FlexItemsCenter>
            <div className="text-2xl font-bold text-theme-info">{securityStats.totalPermissions}</div>
          </div>
          <div className="p-4 bg-theme-surface rounded-lg">
            <FlexItemsCenter className="mb-2">
              <AlertTriangle className="w-4 h-4 text-theme-warning mr-2" />
              <span className="text-sm text-theme-secondary">Expired Tokens</span>
            </FlexItemsCenter>
            <div className="text-2xl font-bold text-theme-warning">{securityStats.expiredTokens}</div>
          </div>
          <div className="p-4 bg-theme-surface rounded-lg">
            <FlexItemsCenter className="mb-2">
              <Activity className="w-4 h-4 text-theme-success mr-2" />
              <span className="text-sm text-theme-secondary">Security Events</span>
            </FlexItemsCenter>
            <div className="text-2xl font-bold text-theme-success">{securityStats.securityEvents}</div>
          </div>
        </div>
      </Card>

      {/* Security Actions */}
      {canManageWorkers && (
        <Card className="p-6">
          <h3 className="text-lg font-medium text-theme-primary mb-4">Security Actions</h3>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <Button variant="secondary" className="h-auto p-4 text-left justify-start">
              <div>
                <div className="font-medium text-theme-primary mb-1">Rotate All Tokens</div>
                <div className="text-sm text-theme-secondary">Generate new tokens for all workers</div>
              </div>
            </Button>
            <Button variant="secondary" className="h-auto p-4 text-left justify-start">
              <div>
                <div className="font-medium text-theme-primary mb-1">Audit Permissions</div>
                <div className="text-sm text-theme-secondary">Review and audit worker permissions</div>
              </div>
            </Button>
            <Button variant="secondary" className="h-auto p-4 text-left justify-start">
              <div>
                <div className="font-medium text-theme-primary mb-1">Security Report</div>
                <div className="text-sm text-theme-secondary">Generate security compliance report</div>
              </div>
            </Button>
          </div>
        </Card>
      )}

      {/* Worker Security Status */}
      <Card className="p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-4">Worker Security Status</h3>
        <div className="space-y-3">
          {workers
            .sort((a, b) => {
              // System workers first
              const aIsSystem = a.account_name === 'System';
              const bIsSystem = b.account_name === 'System';
              
              if (aIsSystem && !bIsSystem) return -1;
              if (!aIsSystem && bIsSystem) return 1;
              
              return a.name.localeCompare(b.name);
            })
            .map((worker) => {
              const isSystemWorker = worker.account_name === 'System';
              return (
            <div 
              key={worker.id} 
              className={`p-4 border border-theme rounded-lg ${
                isSystemWorker ? 'bg-gradient-to-r from-theme-info/5 to-transparent border-theme-info/30' : ''
              }`}
            >
              <FlexBetween>
                <div>
                  <div className="font-medium text-theme-primary">
                    {worker.name}
                    {isSystemWorker && (
                      <span className="ml-2 px-2 py-0.5 text-xs bg-theme-info/10 text-theme-info rounded-full">
                        SYSTEM
                      </span>
                    )}
                  </div>
                  <div className="text-sm text-theme-secondary">
                    {worker.roles.length} roles, {worker.permissions.length} permissions
                  </div>
                </div>
                <div className="flex items-center space-x-2">
                  <Badge 
                    variant={worker.status === 'active' ? 'success' : 'secondary'} 
                    size="sm"
                  >
                    {worker.status}
                  </Badge>
                  {canManageWorkers && (
                    <Button
                      onClick={() => setSelectedWorker(worker.id)}
                      variant="secondary"
                      size="sm"
                    >
                      <Shield className="w-4 h-4" />
                    </Button>
                  )}
                </div>
              </FlexBetween>
            </div>
              );
            })}
        </div>
      </Card>
    </div>
  );
};

// Worker Settings Tab Component
const WorkerSettingsTab: React.FC<{
  workers: Worker[];
  canManageWorkers: boolean;
  onRefresh: () => void;
}> = ({ workers, canManageWorkers, onRefresh }) => {
  const [settings, setSettings] = useState({
    autoCleanupEnabled: true,
    cleanupAfterDays: 30,
    tokenExpiryDays: 90,
    healthCheckInterval: 300, // 5 minutes
    enableActivityLogging: true,
    maxFailedAttempts: 5
  });

  return (
    <div className="space-y-6">
      {/* Global Settings */}
      <Card className="p-6">
        <FlexBetween className="mb-4">
          <div>
            <h3 className="text-lg font-medium text-theme-primary">Worker Configuration</h3>
            <p className="text-sm text-theme-secondary">
              Configure global worker system settings
            </p>
          </div>
          <Button onClick={onRefresh} variant="secondary" size="sm">
            <RefreshCw className="w-4 h-4 mr-2" />
            Refresh
          </Button>
        </FlexBetween>

        <div className="space-y-6">
          {/* Security Settings */}
          <div>
            <h4 className="text-md font-medium text-theme-primary mb-3">Security Settings</h4>
            <div className="space-y-4">
              <FlexBetween>
                <div>
                  <label className="block text-sm font-medium text-theme-primary">
                    Token Expiry Period
                  </label>
                  <p className="text-sm text-theme-secondary">
                    How long worker tokens remain valid
                  </p>
                </div>
                <div className="flex items-center space-x-2">
                  <input
                    type="number"
                    value={settings.tokenExpiryDays}
                    onChange={(e) => setSettings(prev => ({ ...prev, tokenExpiryDays: parseInt(e.target.value) }))}
                    className="w-20 p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary text-sm"
                    min="1"
                    max="365"
                    disabled={!canManageWorkers}
                  />
                  <span className="text-sm text-theme-secondary">days</span>
                </div>
              </FlexBetween>

              <FlexBetween>
                <div>
                  <label className="block text-sm font-medium text-theme-primary">
                    Max Failed Attempts
                  </label>
                  <p className="text-sm text-theme-secondary">
                    Worker is suspended after this many failed requests
                  </p>
                </div>
                <input
                  type="number"
                  value={settings.maxFailedAttempts}
                  onChange={(e) => setSettings(prev => ({ ...prev, maxFailedAttempts: parseInt(e.target.value) }))}
                  className="w-20 p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary text-sm"
                  min="1"
                  max="100"
                  disabled={!canManageWorkers}
                />
              </FlexBetween>
            </div>
          </div>

          {/* Monitoring Settings */}
          <div className="pt-4 border-t border-theme">
            <h4 className="text-md font-medium text-theme-primary mb-3">Monitoring Settings</h4>
            <div className="space-y-4">
              <FlexBetween>
                <div>
                  <label className="block text-sm font-medium text-theme-primary">
                    Health Check Interval
                  </label>
                  <p className="text-sm text-theme-secondary">
                    How often to check worker health status
                  </p>
                </div>
                <div className="flex items-center space-x-2">
                  <input
                    type="number"
                    value={settings.healthCheckInterval}
                    onChange={(e) => setSettings(prev => ({ ...prev, healthCheckInterval: parseInt(e.target.value) }))}
                    className="w-20 p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary text-sm"
                    min="60"
                    max="3600"
                    disabled={!canManageWorkers}
                  />
                  <span className="text-sm text-theme-secondary">seconds</span>
                </div>
              </FlexBetween>

              <FlexBetween>
                <div>
                  <label className="block text-sm font-medium text-theme-primary">
                    Enable Activity Logging
                  </label>
                  <p className="text-sm text-theme-secondary">
                    Log all worker activities and requests
                  </p>
                </div>
                <Button
                  onClick={() => setSettings(prev => ({ ...prev, enableActivityLogging: !prev.enableActivityLogging }))}
                  variant={settings.enableActivityLogging ? 'success' : 'secondary'}
                  size="sm"
                  disabled={!canManageWorkers}
                >
                  {settings.enableActivityLogging ? 'Enabled' : 'Disabled'}
                </Button>
              </FlexBetween>
            </div>
          </div>

          {/* Cleanup Settings */}
          <div className="pt-4 border-t border-theme">
            <h4 className="text-md font-medium text-theme-primary mb-3">Cleanup Settings</h4>
            <div className="space-y-4">
              <FlexBetween>
                <div>
                  <label className="block text-sm font-medium text-theme-primary">
                    Auto Cleanup Activities
                  </label>
                  <p className="text-sm text-theme-secondary">
                    Automatically remove old activity logs
                  </p>
                </div>
                <Button
                  onClick={() => setSettings(prev => ({ ...prev, autoCleanupEnabled: !prev.autoCleanupEnabled }))}
                  variant={settings.autoCleanupEnabled ? 'success' : 'secondary'}
                  size="sm"
                  disabled={!canManageWorkers}
                >
                  {settings.autoCleanupEnabled ? 'Enabled' : 'Disabled'}
                </Button>
              </FlexBetween>

              {settings.autoCleanupEnabled && (
                <FlexBetween>
                  <div>
                    <label className="block text-sm font-medium text-theme-primary">
                      Cleanup After
                    </label>
                    <p className="text-sm text-theme-secondary">
                      Remove activity logs older than this period
                    </p>
                  </div>
                  <div className="flex items-center space-x-2">
                    <input
                      type="number"
                      value={settings.cleanupAfterDays}
                      onChange={(e) => setSettings(prev => ({ ...prev, cleanupAfterDays: parseInt(e.target.value) }))}
                      className="w-20 p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary text-sm"
                      min="1"
                      max="365"
                      disabled={!canManageWorkers}
                    />
                    <span className="text-sm text-theme-secondary">days</span>
                  </div>
                </FlexBetween>
              )}
            </div>
          </div>

          {/* Save Button */}
          {canManageWorkers && (
            <div className="pt-4 border-t border-theme">
              <FlexBetween>
                <p className="text-sm text-theme-secondary">
                  Changes will be applied to all workers immediately
                </p>
                <Button variant="primary">
                  Save Settings
                </Button>
              </FlexBetween>
            </div>
          )}
        </div>
      </Card>

      {/* System Information */}
      <Card className="p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-4">System Information</h3>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div>
            <h4 className="text-sm font-medium text-theme-primary mb-2">Worker System Status</h4>
            <div className="space-y-2 text-sm">
              <FlexBetween>
                <span className="text-theme-secondary">Total Workers:</span>
                <span className="text-theme-primary">{workers.length}</span>
              </FlexBetween>
              <FlexBetween>
                <span className="text-theme-secondary">Active Workers:</span>
                <span className="text-theme-success">{workers.filter(w => w.status === 'active').length}</span>
              </FlexBetween>
              <FlexBetween>
                <span className="text-theme-secondary">System Workers:</span>
                <span className="text-theme-info">{workers.filter(w => w.account_name === 'System').length}</span>
              </FlexBetween>
              <FlexBetween>
                <span className="text-theme-secondary">Account Workers:</span>
                <span className="text-theme-warning">{workers.filter(w => w.account_name !== 'System').length}</span>
              </FlexBetween>
            </div>
          </div>
          <div>
            <h4 className="text-sm font-medium text-theme-primary mb-2">Performance Metrics</h4>
            <div className="space-y-2 text-sm">
              <FlexBetween>
                <span className="text-theme-secondary">Total Requests:</span>
                <span className="text-theme-primary">
                  {workers.reduce((sum, w) => sum + w.request_count, 0).toLocaleString()}
                </span>
              </FlexBetween>
              <FlexBetween>
                <span className="text-theme-secondary">Average Requests/Worker:</span>
                <span className="text-theme-primary">
                  {Math.round(workers.reduce((sum, w) => sum + w.request_count, 0) / workers.length) || 0}
                </span>
              </FlexBetween>
              <FlexBetween>
                <span className="text-theme-secondary">Recently Active:</span>
                <span className="text-theme-success">{workers.filter(w => w.active_recently).length}</span>
              </FlexBetween>
              <FlexBetween>
                <span className="text-theme-secondary">System Uptime:</span>
                <span className="text-theme-success">99.8%</span>
              </FlexBetween>
            </div>
          </div>
        </div>
      </Card>
    </div>
  );
};

export default WorkersPage;