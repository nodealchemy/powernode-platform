import React, { useState, useEffect, useCallback } from 'react';
import { Service, ServiceActivity, service_api } from '@/shared/services/serviceApi';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';

interface ServiceActivityListProps {
  service: Service;
}

export const ServiceActivityList: React.FC<ServiceActivityListProps> = ({ service }) => {
  const [activities, setActivities] = useState<ServiceActivity[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [pagination, setPagination] = useState({
    page: 1,
    per_page: 25,
    total: 0,
    total_pages: 0
  });
  const [filters, setFilters] = useState({
    action: '',
    status: '' as '' | 'success' | 'failed',
    from: '',
    to: ''
  });
  const [summary, setSummary] = useState<any>(null);

  const loadActivities = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      
      const params: {
        page: number;
        per_page: number;
        action?: string;
        status?: 'success' | 'failed';
        from?: string;
        to?: string;
      } = {
        page: pagination.page,
        per_page: pagination.per_page
      };
      
      if (filters.action) params.action = filters.action;
      if (filters.status) params.status = filters.status;
      if (filters.from) params.from = filters.from;
      if (filters.to) params.to = filters.to;
      
      const response = await service_api.getServiceActivities(service.id, params);
      
      setActivities(response.activities);
      setPagination(response.pagination);
      setSummary(response.summary);
    } catch (error: any) {
      setError(error.response?.data?.error || 'Failed to load activities');
    } finally {
      setLoading(false);
    }
  }, [service.id, pagination.page, pagination.per_page, filters]);

  useEffect(() => {
    loadActivities();
  }, [loadActivities]);

  const handleFilterChange = (key: string, value: string) => {
    setFilters(prev => ({ ...prev, [key]: value }));
    setPagination(prev => ({ ...prev, page: 1 })); // Reset to first page
  };

  const handlePageChange = (newPage: number) => {
    setPagination(prev => ({ ...prev, page: newPage }));
  };

  const getActionColor = (action: string) => {
    switch (action) {
      case 'authentication':
        return 'bg-theme-info text-theme-info border border-theme';
      case 'job_enqueue':
        return 'bg-theme-success text-theme-success border border-theme';
      case 'api_request':
        return 'bg-theme-info text-theme-info border border-theme';
      case 'health_check':
        return 'bg-theme-background-secondary text-theme-secondary border border-theme';
      case 'error_occurred':
        return 'bg-theme-error text-theme-error border border-theme';
      default:
        return 'bg-theme-background-secondary text-theme-secondary border border-theme';
    }
  };

  const formatDuration = (duration?: number) => {
    if (!duration) return '-';
    if (duration < 1000) return `${duration}ms`;
    return `${(duration / 1000).toFixed(2)}s`;
  };

  if (loading && activities.length === 0) {
    return <LoadingSpinner message="Loading activities..." />;
  }

  return (
    <div className="p-4 sm:p-6 lg:p-8">
      {/* Summary */}
      {summary && (
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
          <div className="bg-theme-surface p-4 rounded-lg border border-theme">
            <div className="text-2xl font-bold text-theme-link">{summary.total_recent}</div>
            <div className="text-sm text-theme-secondary">Recent Activities</div>
          </div>
          <div className="bg-theme-surface p-4 rounded-lg border border-theme">
            <div className="text-2xl font-bold text-theme-success">{summary.successful_recent}</div>
            <div className="text-sm text-theme-secondary">Successful</div>
          </div>
          <div className="bg-theme-surface p-4 rounded-lg border border-theme">
            <div className="text-2xl font-bold text-theme-error">{summary.failed_recent}</div>
            <div className="text-sm text-theme-secondary">Failed</div>
          </div>
          <div className="bg-theme-surface p-4 rounded-lg border border-theme">
            <div className="text-2xl font-bold text-theme-info">{Object.keys(summary.actions).length}</div>
            <div className="text-sm text-theme-secondary">Action Types</div>
          </div>
        </div>
      )}

      {/* Filters */}
      <div className="bg-theme-surface rounded-lg border border-theme p-4 mb-6">
        <h3 className="text-lg font-medium text-theme-primary mb-4">Filters</h3>
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Action</label>
            <select
              value={filters.action}
              onChange={(e) => handleFilterChange('action', e.target.value)}
              className="w-full px-3 py-2 border border-theme rounded-md text-sm bg-theme-surface text-theme-primary"
            >
              <option value="">All Actions</option>
              <option value="authentication">Authentication</option>
              <option value="job_enqueue">Job Enqueue</option>
              <option value="api_request">API Request</option>
              <option value="health_check">Health Check</option>
              <option value="error_occurred">Error Occurred</option>
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">Status</label>
            <select
              value={filters.status}
              onChange={(e) => handleFilterChange('status', e.target.value)}
              className="w-full px-3 py-2 border border-theme rounded-md text-sm bg-theme-surface text-theme-primary"
            >
              <option value="">All Statuses</option>
              <option value="success">Success</option>
              <option value="failed">Failed</option>
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">From</label>
            <input
              type="datetime-local"
              value={filters.from}
              onChange={(e) => handleFilterChange('from', e.target.value)}
              className="w-full px-3 py-2 border border-theme rounded-md text-sm bg-theme-surface text-theme-primary"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-1">To</label>
            <input
              type="datetime-local"
              value={filters.to}
              onChange={(e) => handleFilterChange('to', e.target.value)}
              className="w-full px-3 py-2 border border-theme rounded-md text-sm bg-theme-surface text-theme-primary"
            />
          </div>
        </div>
      </div>

      {/* Activities Table */}
      <div className="bg-theme-surface rounded-lg border border-theme overflow-hidden">
        <div className="px-4 sm:px-6 lg:px-8 py-3 border-b border-theme bg-theme-background-secondary">
          <h3 className="text-lg font-medium text-theme-primary">
            Activities ({pagination.total})
          </h3>
        </div>
        
        {error && (
          <div className="p-4 bg-theme-error-background border-b border-theme-error">
            <p className="text-theme-error text-sm">{error}</p>
            <button
              onClick={loadActivities}
              className="mt-2 text-theme-error hover:text-theme-error text-sm underline opacity-80 hover:opacity-100 transition-opacity duration-150"
            >
              Try again
            </button>
          </div>
        )}

        {loading ? (
          <div className="flex items-center justify-center p-8">
            <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-theme-interactive-primary"></div>
          </div>
        ) : activities.length === 0 ? (
          <div className="text-center py-8 text-theme-secondary">
            <div className="text-4xl mb-3">📊</div>
            <p className="text-lg font-medium">No activities found</p>
            <p className="text-sm mt-1">Try adjusting your filters or check back later</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-theme">
              <thead className="bg-theme-background-secondary">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">
                    Action
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">
                    Status
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">
                    Time
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">
                    Duration
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">
                    IP Address
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">
                    Details
                  </th>
                </tr>
              </thead>
              <tbody className="bg-theme-surface divide-y divide-theme">
                {activities.map((activity) => (
                  <tr key={activity.id} className="hover:bg-theme-surface-hover">
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={`px-2 py-1 text-xs rounded-full ${getActionColor(activity.action)}`}>
                        {activity.action}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="flex items-center">
                        <div className={`w-2 h-2 rounded-full mr-2 ${activity.successful ? 'bg-theme-success' : 'bg-theme-error'}`}></div>
                        <span className="text-sm text-theme-primary">
                          {activity.successful ? 'Success' : 'Failed'}
                        </span>
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-primary">
                      {new Date(activity.performed_at).toLocaleString()}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-primary">
                      {formatDuration(activity.duration)}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-primary">
                      {activity.ip_address || '-'}
                    </td>
                    <td className="px-6 py-4 text-sm text-theme-primary">
                      {activity.error_message && (
                        <div className="text-theme-error text-xs">
                          {activity.error_message}
                        </div>
                      )}
                      {activity.request_path && (
                        <div className="text-theme-secondary text-xs">
                          {activity.request_path}
                        </div>
                      )}
                      {activity.response_status && (
                        <div className="text-theme-secondary text-xs">
                          Status: {activity.response_status}
                        </div>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {/* Pagination */}
        {pagination.total_pages > 1 && (
          <div className="px-4 sm:px-6 lg:px-8 py-3 border-t border-theme bg-theme-background-secondary">
            <div className="flex items-center justify-between">
              <div className="text-sm text-theme-secondary">
                Showing {((pagination.page - 1) * pagination.per_page) + 1} to {Math.min(pagination.page * pagination.per_page, pagination.total)} of {pagination.total} results
              </div>
              <div className="flex gap-2">
                <button
                  onClick={() => handlePageChange(pagination.page - 1)}
                  disabled={pagination.page === 1}
                  className="px-3 py-1 text-sm border border-theme rounded disabled:opacity-50 disabled:cursor-not-allowed hover:bg-theme-surface-hover bg-theme-surface text-theme-primary"
                >
                  Previous
                </button>
                <span className="px-3 py-1 text-sm text-theme-primary">
                  Page {pagination.page} of {pagination.total_pages}
                </span>
                <button
                  onClick={() => handlePageChange(pagination.page + 1)}
                  disabled={pagination.page === pagination.total_pages}
                  className="px-3 py-1 text-sm border border-theme rounded disabled:opacity-50 disabled:cursor-not-allowed hover:bg-theme-surface-hover bg-theme-surface text-theme-primary"
                >
                  Next
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

