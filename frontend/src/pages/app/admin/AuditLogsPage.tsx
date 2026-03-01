import React, { useState, useEffect } from 'react';
import { useSelector } from 'react-redux';
import { useLocation, useNavigate } from 'react-router-dom';
import {
  Shield,
  Eye,
  AlertTriangle,
  Download,
  RefreshCw,
  Filter,
  Activity
} from 'lucide-react';
import { AuditLogFilters } from '@/features/admin/audit-logs/components/AuditLogFilters';
import { AuditLogTable } from '@/features/admin/audit-logs/components/AuditLogTable';
import { AuditLogAnalytics } from '@/features/admin/audit-logs/components/AuditLogAnalytics';
import { AuditLogMetrics } from '@/features/admin/audit-logs/components/AuditLogMetrics';
import { AuditLogExport } from '@/features/admin/audit-logs/components/AuditLogExport';
import { auditLogsApi, AuditLog, AuditLogFilters as FilterType } from '@/features/admin/audit-logs/services/auditLogsApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { hasPermissions } from '@/shared/utils/permissionUtils';
import { RootState } from '@/shared/services';

interface AuditLogsState {
  logs: AuditLog[];
  loading: boolean;
  error: string | null;
  total: number;
  currentPage: number;
  totalPages: number;
}

interface SecurityMetrics {
  totalEvents: number;
  securityEvents: number;
  failedEvents: number;
  highRiskEvents: number;
  suspiciousEvents: number;
  uniqueUsers: number;
  uniqueIps: number;
}

export const AuditLogsPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const location = useLocation();
  const navigate = useNavigate();
  usePageWebSocket({ pageType: 'system' });

  // Determine active tab from URL path
  const getTabFromPath = (): 'table' | 'analytics' => {
    if (location.pathname.endsWith('/analytics')) {
      return 'analytics';
    }
    return 'table';
  };

  const [activeTab, setActiveTab] = useState<'table' | 'analytics'>(getTabFromPath());

  // Sync tab state with URL
  useEffect(() => {
    setActiveTab(getTabFromPath());
  }, [location.pathname]);

  // Check if user has audit log permissions
  const canReadAuditLogs = hasPermissions(user, ['audit.read']);
  const canExportAuditLogs = hasPermissions(user, ['audit.export']);

  // Handle tab changes with proper type casting and URL update
  const handleTabChange = (tabId: string) => {
    const newTab = tabId as 'table' | 'analytics';
    setActiveTab(newTab);
    // Update URL when tab changes
    if (newTab === 'analytics') {
      navigate('/app/system/audit-logs/analytics');
    } else {
      navigate('/app/system/audit-logs');
    }
  };
  const [showFilters, setShowFilters] = useState(false);
  const [showExport, setShowExport] = useState(false);
  const [selectedLog, setSelectedLog] = useState<AuditLog | null>(null);
  
  // State management
  const [state, setState] = useState<AuditLogsState>({
    logs: [],
    loading: true,
    error: null,
    total: 0,
    currentPage: 1,
    totalPages: 0
  });
  
  const [filters, setFilters] = useState<FilterType>({
    page: 1,
    per_page: 25
  });
  
  const [metrics, setMetrics] = useState<SecurityMetrics | null>(null);
  
  const { showNotification } = useNotifications();

  // Load audit logs
  const loadAuditLogs = async (newFilters?: FilterType) => {
    try {
      setState(prev => ({ ...prev, loading: true, error: null }));
      
      const filtersToUse = newFilters || filters;
      const response = await auditLogsApi.getAuditLogs(filtersToUse);
      
      setState(prev => ({
        ...prev,
        logs: response.data,
        total: response.meta.total,
        currentPage: response.meta.current_page,
        totalPages: response.meta.total_pages,
        loading: false
      }));
      
    } catch (_error) {
      setState(prev => ({
        ...prev,
        loading: false
      }));
      showNotification('Failed to load audit logs. Please try again.', 'error');
    }
  };

  // Load security metrics
  const loadMetrics = async () => {
    try {
      const response = await auditLogsApi.getSecuritySummary();
      setMetrics(response);
    } catch (_error) {
    // Error silently ignored
  }
  };

  // Handle filter changes
  const handleFiltersChange = (newFilters: FilterType) => {
    const updatedFilters = { ...newFilters, page: 1 };
    setFilters(updatedFilters);
    loadAuditLogs(updatedFilters);
  };

  // Clear all filters
  const handleClearFilters = () => {
    const clearedFilters = { page: 1, per_page: 25 };
    setFilters(clearedFilters);
    loadAuditLogs(clearedFilters);
  };

  // Handle pagination
  const handlePageChange = (page: number) => {
    const newFilters = { ...filters, page };
    setFilters(newFilters);
    loadAuditLogs(newFilters);
  };

  // Manual refresh
  const handleRefresh = () => {
    loadAuditLogs();
    loadMetrics();
    showNotification('Audit logs refreshed', 'success');
  };

  // Load data on component mount
  useEffect(() => {
    // Only load data if user has audit read permissions
    if (canReadAuditLogs) {
      loadAuditLogs();
      loadMetrics();
    }
  }, [canReadAuditLogs]);

  // Calculate summary stats
  const summaryStats = {
    total: state.total,
    securityEvents: metrics?.securityEvents || 0,
    highRisk: metrics?.highRiskEvents || 0,
    failed: metrics?.failedEvents || 0
  };

  // Get page actions
  const getPageActions = (): PageAction[] => {
    // No actions if user can't read audit logs
    if (!canReadAuditLogs) return [];

    const actions: PageAction[] = [
      {
        id: 'filters',
        label: 'Filters',
        onClick: () => setShowFilters(!showFilters),
        variant: showFilters ? 'primary' : 'secondary',
        icon: Filter
      },
      {
        id: 'refresh',
        label: 'Refresh',
        onClick: handleRefresh,
        variant: 'primary',
        icon: RefreshCw,
        disabled: state.loading
      }
    ];

    // Add export action only if user has export permission
    if (canExportAuditLogs) {
      actions.splice(1, 0, {
        id: 'export',
        label: 'Export',
        onClick: () => setShowExport(!showExport),
        variant: 'secondary',
        icon: Download
      });
    }

    return actions;
  };

  // Define tabs
  const tabs = [
    { id: 'table', label: 'Table View', icon: '📋', path: '/' },
    { id: 'analytics', label: 'Analytics', icon: '📊', path: '/analytics' }
  ];

  // Get breadcrumbs with dynamic tab support
  const getBreadcrumbs = () => {
    const baseBreadcrumbs: { label: string; href?: string }[] = [
      { label: 'Dashboard', href: '/app' },
      { label: 'System' },
      { label: 'Audit Logs' }
    ];

    // Add active tab to breadcrumbs if not the default table view
    const activeTabInfo = tabs.find(tab => tab.id === activeTab);
    if (activeTabInfo && activeTab !== 'table') {
      baseBreadcrumbs.push({
        label: activeTabInfo.label
      });
    }
    
    return baseBreadcrumbs;
  };

  return (
    <PageContainer
      title="Audit Logs"
      description="Security monitoring and compliance tracking"
      breadcrumbs={getBreadcrumbs()}
      actions={getPageActions()}
    >
      {/* Permission Check */}
      {!canReadAuditLogs ? (
        <div className="text-center py-16">
          <div className="mx-auto w-24 h-24 bg-theme-warning/10 rounded-full flex items-center justify-center mb-6">
            <Shield className="w-12 h-12 text-theme-warning" />
          </div>
          <h3 className="text-xl font-semibold text-theme-primary mb-2">Access Restricted</h3>
          <p className="text-theme-secondary mb-4 max-w-md mx-auto">
            You don't have permission to view audit logs. Contact your system administrator to request access.
          </p>
          <p className="text-sm text-theme-tertiary">
            Required permission: <code className="px-2 py-1 bg-theme-background-secondary rounded">audit.read</code>
          </p>
        </div>
      ) : (
        <>
          {/* Content */}
      <div className="px-4 sm:px-6 lg:px-8 py-6">
        {/* Quick Metrics */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
          <AuditLogMetrics
            title="Total Events"
            value={summaryStats.total}
            icon={<Activity className="w-5 h-5" />}
            trend="+12% from last week"
            color="blue"
          />
          <AuditLogMetrics
            title="Security Events"
            value={summaryStats.securityEvents}
            icon={<Shield className="w-5 h-5" />}
            trend="-5% from last week"
            color="green"
          />
          <AuditLogMetrics
            title="High Risk"
            value={summaryStats.highRisk}
            icon={<AlertTriangle className="w-5 h-5" />}
            trend="+8% from last week"
            color="red"
          />
          <AuditLogMetrics
            title="Failed Events"
            value={summaryStats.failed}
            icon={<Eye className="w-5 h-5" />}
            trend="-2% from last week"
            color="yellow"
          />
        </div>

        {/* Filters */}
        {showFilters && (
          <div className="mb-6">
            <AuditLogFilters
              filters={filters}
              onFiltersChange={handleFiltersChange}
              onClearFilters={handleClearFilters}
              isLoading={state.loading}
            />
          </div>
        )}

        {/* Export Panel */}
        {showExport && (
          <div className="mb-6">
            <AuditLogExport
              filters={filters}
              onClose={() => setShowExport(false)}
            />
          </div>
        )}

        {/* Tab Content */}
        <TabContainer
          tabs={tabs}
          activeTab={activeTab}
          onTabChange={handleTabChange}
          basePath="/app/system/audit-logs"
          variant="underline"
          className="mb-6"
        >
          <TabPanel tabId="table" activeTab={activeTab}>
            <div className="space-y-6">
              <AuditLogTable
                logs={state.logs}
                loading={state.loading}
                onLogSelect={setSelectedLog}
                selectedLogId={selectedLog?.id}
              />
              
              {/* Pagination */}
              {state.totalPages > 1 && (
                <div className="flex items-center justify-between bg-theme-surface rounded-lg border border-theme px-4 py-3">
                  <div className="text-sm text-theme-secondary">
                    Showing {((state.currentPage - 1) * 25) + 1} to {Math.min(state.currentPage * 25, state.total)} of {state.total} results
                  </div>
                  
                  <div className="flex items-center gap-2">
                    <button
                      onClick={() => handlePageChange(state.currentPage - 1)}
                      disabled={state.currentPage === 1 || state.loading}
                      className="px-3 py-2 text-sm bg-theme-background text-theme-primary rounded-md hover:bg-theme-surface-hover disabled:opacity-50 disabled:cursor-not-allowed transition-colors duration-200"
                    >
                      Previous
                    </button>
                    
                    <span className="text-sm text-theme-secondary">
                      Page {state.currentPage} of {state.totalPages}
                    </span>
                    
                    <button
                      onClick={() => handlePageChange(state.currentPage + 1)}
                      disabled={state.currentPage === state.totalPages || state.loading}
                      className="px-3 py-2 text-sm bg-theme-background text-theme-primary rounded-md hover:bg-theme-surface-hover disabled:opacity-50 disabled:cursor-not-allowed transition-colors duration-200"
                    >
                      Next
                    </button>
                  </div>
                </div>
              )}
            </div>
          </TabPanel>

          <TabPanel tabId="analytics" activeTab={activeTab}>
            <AuditLogAnalytics
              metrics={metrics ?? undefined}
              filters={filters}
              onFiltersChange={handleFiltersChange}
              refreshData={() => { loadAuditLogs(); loadMetrics(); }}
            />
          </TabPanel>
        </TabContainer>
      </div>
        </>
      )}
    </PageContainer>
  );
};

export default AuditLogsPage;