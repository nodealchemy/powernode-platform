import React, { useState, useEffect } from 'react';
import { 
  Shield, 
  Eye, 
  AlertTriangle, 
  TrendingUp, 
  Users, 
  Clock, 
  Activity,
  Download,
  RefreshCw,
  Filter,
  BarChart3
} from 'lucide-react';
import { AuditLogFilters } from '../../components/audit-logs/AuditLogFilters';
import { AuditLogTable } from '../../components/audit-logs/AuditLogTable';
import { AuditLogAnalytics } from '../../components/audit-logs/AuditLogAnalytics';
import { AuditLogMetrics } from '../../components/audit-logs/AuditLogMetrics';
import { AuditLogExport } from '../../components/audit-logs/AuditLogExport';
import { auditLogsApi, AuditLog, AuditLogFilters as FilterType } from '../../services/auditLogsApi';
import { LoadingSpinner } from '../../components/ui/LoadingSpinner';
import { useNotification } from '../../hooks/useNotification';

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
  const [view, setView] = useState<'table' | 'analytics'>('table');
  const [showFilters, setShowFilters] = useState(false);
  const [showExport, setShowExport] = useState(false);
  const [selectedLog, setSelectedLog] = useState<AuditLog | null>(null);
  const [refreshInterval, setRefreshInterval] = useState<NodeJS.Timer | null>(null);
  
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
  
  const { showNotification } = useNotification();

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
      
    } catch (error) {
      console.error('Failed to load audit logs:', error);
      setState(prev => ({
        ...prev,
        loading: false,
        error: 'Failed to load audit logs. Please try again.'
      }));
      showNotification('Failed to load audit logs', 'error');
    }
  };

  // Load security metrics
  const loadMetrics = async () => {
    try {
      const response = await auditLogsApi.getSecuritySummary();
      setMetrics(response);
    } catch (error) {
      console.error('Failed to load security metrics:', error);
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

  // Toggle auto-refresh
  const toggleAutoRefresh = () => {
    if (refreshInterval) {
      clearInterval(refreshInterval);
      setRefreshInterval(null);
      showNotification('Auto-refresh disabled', 'info');
    } else {
      const interval = setInterval(() => {
        loadAuditLogs();
        loadMetrics();
      }, 30000); // Refresh every 30 seconds
      setRefreshInterval(interval);
      showNotification('Auto-refresh enabled (30s)', 'success');
    }
  };

  // Load data on component mount
  useEffect(() => {
    loadAuditLogs();
    loadMetrics();
    
    // Cleanup interval on unmount
    return () => {
      if (refreshInterval) {
        clearInterval(refreshInterval);
      }
    };
  }, []);

  // Calculate summary stats
  const summaryStats = {
    total: state.total,
    securityEvents: metrics?.securityEvents || 0,
    highRisk: metrics?.highRiskEvents || 0,
    failed: metrics?.failedEvents || 0
  };

  return (
    <div className="min-h-screen bg-theme-background">
      {/* Header */}
      <div className="bg-theme-surface border-b border-theme px-4 sm:px-6 lg:px-8 py-6">
        <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-theme-interactive-primary bg-opacity-10 rounded-lg">
              <Shield className="w-6 h-6 text-theme-interactive-primary" />
            </div>
            <div>
              <h1 className="text-2xl font-bold text-theme-primary">Audit Logs</h1>
              <p className="text-theme-secondary">Security monitoring and compliance tracking</p>
            </div>
          </div>
          
          <div className="flex items-center gap-2">
            <button
              onClick={() => setView(view === 'table' ? 'analytics' : 'table')}
              className={`flex items-center gap-2 px-3 py-2 text-sm rounded-md transition-colors duration-200 ${
                view === 'analytics'
                  ? 'bg-theme-interactive-primary text-white'
                  : 'bg-theme-background text-theme-primary hover:bg-theme-surface-hover'
              }`}
            >
              {view === 'table' ? (
                <>
                  <BarChart3 className="w-4 h-4" />
                  Analytics
                </>
              ) : (
                <>
                  <Eye className="w-4 h-4" />
                  Table View
                </>
              )}
            </button>
            
            <button
              onClick={() => setShowFilters(!showFilters)}
              className={`flex items-center gap-2 px-3 py-2 text-sm rounded-md transition-colors duration-200 ${
                showFilters
                  ? 'bg-theme-interactive-primary text-white'
                  : 'bg-theme-background text-theme-primary hover:bg-theme-surface-hover'
              }`}
            >
              <Filter className="w-4 h-4" />
              Filters
            </button>
            
            <button
              onClick={() => setShowExport(!showExport)}
              className="flex items-center gap-2 px-3 py-2 text-sm bg-theme-background text-theme-primary hover:bg-theme-surface-hover rounded-md transition-colors duration-200"
            >
              <Download className="w-4 h-4" />
              Export
            </button>
            
            <button
              onClick={toggleAutoRefresh}
              className={`flex items-center gap-2 px-3 py-2 text-sm rounded-md transition-colors duration-200 ${
                refreshInterval
                  ? 'bg-green-100 text-green-700 hover:bg-green-200'
                  : 'bg-theme-background text-theme-primary hover:bg-theme-surface-hover'
              }`}
            >
              <Activity className={`w-4 h-4 ${refreshInterval ? 'animate-pulse' : ''}`} />
              {refreshInterval ? 'Auto-refresh ON' : 'Auto-refresh OFF'}
            </button>
            
            <button
              onClick={handleRefresh}
              disabled={state.loading}
              className="flex items-center gap-2 px-3 py-2 text-sm bg-theme-interactive-primary text-white rounded-md hover:bg-theme-interactive-primary-hover transition-colors duration-200 disabled:opacity-50"
            >
              <RefreshCw className={`w-4 h-4 ${state.loading ? 'animate-spin' : ''}`} />
              Refresh
            </button>
          </div>
        </div>
      </div>

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

        {/* Main Content */}
        {view === 'table' ? (
          <div className="space-y-6">
            {state.error && (
              <div className="bg-red-50 border border-red-200 rounded-lg p-4">
                <div className="flex items-center gap-2">
                  <AlertTriangle className="w-5 h-5 text-red-600" />
                  <span className="text-sm font-medium text-red-800">{state.error}</span>
                </div>
              </div>
            )}
            
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
        ) : (
          <AuditLogAnalytics
            metrics={metrics}
            filters={filters}
            onFiltersChange={handleFiltersChange}
            refreshData={() => { loadAuditLogs(); loadMetrics(); }}
          />
        )}
      </div>
    </div>
  );
};