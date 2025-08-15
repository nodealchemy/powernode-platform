import React, { useEffect, useState, useCallback } from 'react';
import { auditLogsApi, AuditLog } from '../../services/auditLogsApi';
import { LoadingSpinner } from '../../components/ui/LoadingSpinner';
import { PageContainer, PageAction } from '../../components/layout/PageContainer';
import { Download, RefreshCw } from 'lucide-react';

export const AuditLogsPage: React.FC = () => {
  const [auditLogs, setAuditLogs] = useState<AuditLog[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [filters, setFilters] = useState({
    action_type: 'all',
    date_from: '',
    date_to: ''
  });
  const [pagination, setPagination] = useState({
    page: 1,
    limit: 10,
    total: 0
  });

  const loadAuditLogs = useCallback(async () => {
    try {
      setLoading(true);
      const response = await auditLogsApi.getAuditLogs({
        page: pagination.page,
        limit: pagination.limit,
        ...filters
      });
      
      if (response.success) {
        setAuditLogs(response.data);
        setPagination(prev => ({
          ...prev,
          total: response.meta.total
        }));
      } else {
        setError(response.error || 'Failed to load audit logs');
      }
    } catch (err) {
      setError('Failed to load audit logs');
      console.error('Audit logs error:', err);
    } finally {
      setLoading(false);
    }
  }, [pagination.page, pagination.limit, filters]);

  useEffect(() => {
    loadAuditLogs();
  }, [pagination.page, filters, loadAuditLogs]);

  const handleFilterChange = (key: string, value: string) => {
    setFilters(prev => ({ ...prev, [key]: value }));
    setPagination(prev => ({ ...prev, page: 1 }));
  };

  const formatTimestamp = (timestamp: string) => {
    return new Date(timestamp).toLocaleString();
  };

  const handleExportLogs = () => {
    auditLogsApi.exportLogs({
      format: 'csv',
      scope: 'filtered',
      includeMetadata: true,
      includeSensitiveData: false,
      maxRecords: 10000,
      filters
    });
  };

  const pageActions: PageAction[] = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: loadAuditLogs,
      variant: 'secondary',
      icon: RefreshCw
    },
    {
      id: 'export-logs',
      label: 'Export Logs',
      onClick: handleExportLogs,
      variant: 'outline',
      icon: Download
    }
  ];

  const breadcrumbs = [
    { label: 'Dashboard', href: '/dashboard', icon: '🏠' },
    { label: 'Audit Logs', icon: '📝' }
  ];

  return (
    <PageContainer
      title="Audit Logs"
      description="Track all system activities and changes"
      breadcrumbs={breadcrumbs}
      actions={pageActions}
    >
      {/* Filters */}
      <div className="card-theme p-4 mb-6">
        <div className="flex space-x-3">
            <select 
              className="px-3 py-2 border border-theme rounded-lg text-theme-primary bg-theme-background"
              value={filters.action_type}
              onChange={(e) => handleFilterChange('action_type', e.target.value)}
            >
              <option value="all">All Actions</option>
              <option value="authentication">Authentication</option>
              <option value="user_management">Users</option>
              <option value="billing">Billing</option>
              <option value="system_changes">System Changes</option>
            </select>
            <input
              type="date"
              className="px-3 py-2 border border-theme rounded-lg text-theme-primary bg-theme-background"
              value={filters.date_from}
              onChange={(e) => handleFilterChange('date_from', e.target.value)}
            />
            <input
              type="date"
              className="px-3 py-2 border border-theme rounded-lg text-theme-primary bg-theme-background"
              value={filters.date_to}
              onChange={(e) => handleFilterChange('date_to', e.target.value)}
              min={filters.date_from}
            />
        </div>
      </div>

      <div className="bg-theme-surface rounded-lg p-6">
        {loading ? (
          <div className="flex items-center justify-center py-8">
            <LoadingSpinner />
          </div>
        ) : error ? (
          <div className="bg-theme-error bg-opacity-10 border border-theme-error rounded-lg p-4">
            <p className="text-theme-error">{error}</p>
            <button 
              onClick={loadAuditLogs}
              className="mt-2 btn-theme btn-theme-secondary"
            >
              Retry
            </button>
          </div>
        ) : (
          <div className="bg-theme-background rounded-lg overflow-hidden">
            <table className="w-full">
              <thead className="bg-theme-surface border-b border-theme">
                <tr>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Action</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">User</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">IP Address</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Timestamp</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Status</th>
                  <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Details</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-theme">
                {auditLogs.length === 0 ? (
                  <tr>
                    <td colSpan={6} className="py-8 px-4 text-center text-theme-secondary">
                      No audit logs found
                    </td>
                  </tr>
                ) : (
                  auditLogs.map((log) => (
                    <tr key={log.id} className="hover:bg-theme-surface-hover">
                      <td className="py-3 px-4 text-theme-primary font-medium">{log.action}</td>
                      <td className="py-3 px-4 text-theme-secondary">{log.user?.email || 'System'}</td>
                      <td className="py-3 px-4 text-theme-secondary font-mono text-xs">{log.ip_address || 'N/A'}</td>
                      <td className="py-3 px-4 text-theme-secondary text-sm">{formatTimestamp(log.created_at)}</td>
                      <td className="py-3 px-4">
                        <span className={`text-xs px-2 py-1 rounded-full ${
                          log.status === 'success'
                            ? 'bg-theme-success bg-opacity-10 text-theme-success' 
                            : log.status === 'warning'
                            ? 'bg-theme-warning bg-opacity-10 text-theme-warning'
                            : 'bg-theme-error bg-opacity-10 text-theme-error'
                        }`}>
                          {log.status || 'unknown'}
                        </span>
                      </td>
                      <td className="py-3 px-4">
                        <button 
                          className="text-theme-link hover:text-theme-link-hover text-sm"
                          title={log.message}
                        >
                          View
                        </button>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        )}

        {!loading && !error && auditLogs.length > 0 && (
          <div className="mt-4 flex items-center justify-between">
            <p className="text-sm text-theme-secondary">
              Showing {((pagination.page - 1) * pagination.limit) + 1} to {Math.min(pagination.page * pagination.limit, pagination.total)} of {pagination.total} entries
            </p>
            <div className="flex space-x-2">
              <button 
                className="px-3 py-1 border border-theme rounded text-theme-primary hover:bg-theme-surface-hover disabled:opacity-50"
                onClick={() => setPagination(prev => ({ ...prev, page: prev.page - 1 }))}
                disabled={pagination.page <= 1}
              >
                Previous
              </button>
              
              {Array.from({ length: Math.min(5, Math.ceil(pagination.total / pagination.limit)) }, (_, i) => {
                const pageNum = pagination.page <= 3 ? i + 1 : pagination.page - 2 + i;
                return (
                  <button 
                    key={pageNum}
                    className={`px-3 py-1 rounded ${
                      pageNum === pagination.page
                        ? 'bg-theme-interactive-primary text-theme-interactive-primary-contrast'
                        : 'border border-theme text-theme-primary hover:bg-theme-surface-hover'
                    }`}
                    onClick={() => setPagination(prev => ({ ...prev, page: pageNum }))}
                  >
                    {pageNum}
                  </button>
                );
              })}
              
              <button 
                className="px-3 py-1 border border-theme rounded text-theme-primary hover:bg-theme-surface-hover disabled:opacity-50"
                onClick={() => setPagination(prev => ({ ...prev, page: prev.page + 1 }))}
                disabled={pagination.page >= Math.ceil(pagination.total / pagination.limit)}
              >
                Next
              </button>
            </div>
          </div>
        )}
      </div>
    </PageContainer>
  );
};