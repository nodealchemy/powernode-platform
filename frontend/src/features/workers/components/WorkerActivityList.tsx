import React, { useState, useEffect, useCallback } from 'react';
import { workerApi, WorkerActivity, ActivityListResponse } from '@/features/workers/services/workerApi';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { formatDistanceToNow, format } from 'date-fns';

interface WorkerActivityListProps {
  workerId: string;
}

interface ActivityFilters {
  action?: string;
  status?: 'success' | 'failed';
  page: number;
  per_page: number;
}

export const WorkerActivityList: React.FC<WorkerActivityListProps> = ({ workerId }) => {
  const [data, setData] = useState<ActivityListResponse | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [filters, setFilters] = useState<ActivityFilters>({
    page: 1,
    per_page: 20
  });

  const loadActivities = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await workerApi.getWorkerActivities(workerId, filters);
      setData(response);
    } catch (error: any) {
      setError(error.message || 'Failed to load activities');
    } finally {
      setLoading(false);
    }
  }, [workerId, filters]);

  useEffect(() => {
    loadActivities();
  }, [loadActivities]);

  // Auto-refresh every 30 seconds
  useEffect(() => {
    // TEMPORARILY DISABLED - Causing automatic page refreshes
    // const interval = setInterval(() => {
    //   if (!loading) {
    //     loadActivities();
    //   }
    // }, 30000);

    // return () => clearInterval(interval);
  }, [loadActivities, loading]);

  const handleFilterChange = (newFilters: Partial<ActivityFilters>) => {
    setFilters(prev => ({
      ...prev,
      ...newFilters,
      page: 1 // Reset to first page when filtering
    }));
  };

  const handlePageChange = (page: number) => {
    setFilters(prev => ({ ...prev, page }));
  };

  const getActionIcon = (action: string) => {
    const iconMap: Record<string, string> = {
      authentication: '🔐',
      job_enqueue: '⚡',
      api_request: '📡',
      health_check: '❤️',
      web_interface_access: '🌐',
      admin_action: '👨‍💼',
      error_occurred: '❌',
      service_setup: '⚙️',
      service_created: '✅',
      service_updated: '✏️',
      service_deleted: '🗑️',
      token_regenerated: '🔑',
      service_suspended: '⏸️',
      service_activated: '▶️',
      service_revoked: '🚫'
    };
    return iconMap[action] || '📝';
  };

  const getStatusBadge = (activity: WorkerActivity) => {
    if (activity.successful) {
      return (
        <span className="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-theme-success-background text-theme-success">
          Success
        </span>
      );
    } else if (activity.failed) {
      return (
        <span className="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-theme-error-background text-theme-error">
          Failed
        </span>
      );
    }
    return (
      <span className="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-theme-info-background text-theme-info">
        Pending
      </span>
    );
  };

  if (loading) {
    return (
      <div className="flex justify-center py-8">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="text-center py-8">
        <div className="bg-theme-error-background rounded-lg p-4 max-w-md mx-auto">
          <p className="text-theme-error font-medium">Error Loading Activities</p>
          <p className="text-theme-error text-sm mt-1">{error}</p>
          <button
            onClick={loadActivities}
            className="btn-theme btn-theme-danger mt-3"
          >
            Try Again
          </button>
        </div>
      </div>
    );
  }

  if (!data) {
    return null;
  }

  const { activities, pagination, summary, worker } = data;

  return (
    <div className="space-y-6">
      {/* Header and Summary */}
      <div className="bg-theme-background rounded-lg p-4">
        <div className="flex justify-between items-start mb-4">
          <div>
            <h3 className="text-lg font-semibold text-theme-primary">Recent Activity</h3>
            <p className="text-theme-secondary text-sm">{worker.name}</p>
          </div>
          <div className="flex items-center space-x-2">
            <button
              onClick={loadActivities}
              className="px-3 py-1 bg-theme-interactive-primary text-white rounded text-sm hover:bg-theme-interactive-primary/80 transition-colors"
              disabled={loading}
            >
              {loading ? 'Refreshing...' : 'Refresh'}
            </button>
          </div>
        </div>
        
        {/* Quick Stats */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mb-4">
          <div className="text-center">
            <div className="text-2xl font-bold text-theme-primary">{summary.total_recent}</div>
            <div className="text-theme-secondary text-sm">Recent</div>
          </div>
          <div className="text-center">
            <div className="text-2xl font-bold text-theme-success">{summary.successful_recent}</div>
            <div className="text-theme-secondary text-sm">Success</div>
          </div>
          <div className="text-center">
            <div className="text-2xl font-bold text-theme-error">{summary.failed_recent}</div>
            <div className="text-theme-secondary text-sm">Failed</div>
          </div>
          <div className="text-center">
            <div className="text-2xl font-bold text-theme-info">{Object.keys(summary.actions).length}</div>
            <div className="text-theme-secondary text-sm">Actions</div>
          </div>
        </div>
      </div>

      {/* Filters */}
      <div className="flex flex-wrap gap-3 items-center">
        <select
          value={filters.action || ''}
          onChange={(e) => handleFilterChange({ action: e.target.value || undefined })}
          className="px-3 py-2 bg-theme-surface border border-theme rounded-md text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
        >
          <option value="">All Actions</option>
          {Object.keys(summary.actions).map(action => (
            <option key={action} value={action}>
              {getActionIcon(action)} {action.replace(/_/g, ' ')}
            </option>
          ))}
        </select>

        <select
          value={filters.status || ''}
          onChange={(e) => handleFilterChange({ status: (e.target.value as 'success' | 'failed') || undefined })}
          className="px-3 py-2 bg-theme-surface border border-theme rounded-md text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
        >
          <option value="">All Status</option>
          <option value="success">Success</option>
          <option value="failed">Failed</option>
        </select>

        <select
          value={filters.per_page}
          onChange={(e) => handleFilterChange({ per_page: parseInt(e.target.value) })}
          className="px-3 py-2 bg-theme-surface border border-theme rounded-md text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
        >
          <option value="10">10 per page</option>
          <option value="20">20 per page</option>
          <option value="50">50 per page</option>
          <option value="100">100 per page</option>
        </select>

        {(filters.action || filters.status) && (
          <button
            onClick={() => setFilters({ page: 1, per_page: filters.per_page })}
            className="px-3 py-2 bg-theme-surface border border-theme rounded-md text-theme-secondary hover:text-theme-primary transition-colors"
          >
            Clear Filters
          </button>
        )}
      </div>

      {/* Activities List */}
      {activities.length === 0 ? (
        <div className="text-center py-12">
          <div className="text-6xl mb-4">📝</div>
          <h3 className="text-lg font-medium text-theme-primary mb-2">No Activities Found</h3>
          <p className="text-theme-secondary">
            {filters.action || filters.status 
              ? 'No activities match your current filters.' 
              : 'This worker has no recorded activities yet.'}
          </p>
        </div>
      ) : (
        <div className="space-y-3">
          {activities.map((activity) => (
            <div
              key={activity.id}
              className="bg-theme-surface rounded-lg p-4 border border-theme hover:bg-theme-background transition-colors"
            >
              <div className="flex items-start justify-between">
                <div className="flex items-start space-x-3 flex-1">
                  <div className="text-2xl">{getActionIcon(activity.action)}</div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center space-x-2 mb-1">
                      <h4 className="font-medium text-theme-primary">
                        {activity.action.replace(/_/g, ' ')}
                      </h4>
                      {getStatusBadge(activity)}
                      {activity.duration && (
                        <span className="text-xs text-theme-secondary">
                          {activity.duration}ms
                        </span>
                      )}
                    </div>
                    
                    <div className="text-sm text-theme-secondary space-y-1">
                      <div className="flex items-center space-x-4">
                        <span>
                          {format(new Date(activity.performed_at), 'MMM d, yyyy HH:mm:ss')}
                        </span>
                        <span className="text-theme-info">
                          {formatDistanceToNow(new Date(activity.performed_at), { addSuffix: true })}
                        </span>
                      </div>
                      
                      {activity.ip_address && (
                        <div className="text-xs">IP: {activity.ip_address}</div>
                      )}
                      
                      {activity.request_path && (
                        <div className="text-xs">Path: {activity.request_path}</div>
                      )}
                      
                      {activity.error_message && (
                        <div className="text-xs text-theme-error mt-2 p-2 bg-theme-error-background rounded">
                          {activity.error_message}
                        </div>
                      )}
                    </div>
                  </div>
                </div>

                {activity.response_status && (
                  <div className={`px-2 py-1 rounded text-xs font-mono ${
                    activity.response_status >= 200 && activity.response_status < 300
                      ? 'bg-theme-success-background text-theme-success'
                      : activity.response_status >= 400
                      ? 'bg-theme-error-background text-theme-error'
                      : 'bg-theme-warning-background text-theme-warning'
                  }`}>
                    {activity.response_status}
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Pagination */}
      {pagination.total_pages > 1 && (
        <div className="flex items-center justify-between">
          <div className="text-sm text-theme-secondary">
            Showing {((pagination.page - 1) * pagination.per_page) + 1} to{' '}
            {Math.min(pagination.page * pagination.per_page, pagination.total)} of{' '}
            {pagination.total} activities
          </div>
          
          <div className="flex items-center space-x-2">
            <button
              onClick={() => handlePageChange(pagination.page - 1)}
              disabled={pagination.page <= 1}
              className="px-3 py-2 bg-theme-surface border border-theme rounded-md text-theme-primary disabled:opacity-50 disabled:cursor-not-allowed hover:bg-theme-background transition-colors"
            >
              Previous
            </button>
            
            <div className="flex items-center space-x-1">
              {Array.from({ length: Math.min(5, pagination.total_pages) }, (_, i) => {
                const pageNum = i + Math.max(1, pagination.page - 2);
                if (pageNum > pagination.total_pages) return null;
                
                return (
                  <button
                    key={pageNum}
                    onClick={() => handlePageChange(pageNum)}
                    className={`px-3 py-2 rounded-md text-sm font-medium transition-colors ${
                      pageNum === pagination.page
                        ? 'bg-theme-interactive-primary text-white'
                        : 'bg-theme-surface border border-theme text-theme-primary hover:bg-theme-background'
                    }`}
                  >
                    {pageNum}
                  </button>
                );
              })}
            </div>
            
            <button
              onClick={() => handlePageChange(pagination.page + 1)}
              disabled={pagination.page >= pagination.total_pages}
              className="px-3 py-2 bg-theme-surface border border-theme rounded-md text-theme-primary disabled:opacity-50 disabled:cursor-not-allowed hover:bg-theme-background transition-colors"
            >
              Next
            </button>
          </div>
        </div>
      )}
    </div>
  );
};

