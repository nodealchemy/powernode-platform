import React, { useState } from 'react';
import { App, AppFilters, AppStatus } from '../../types';
import { useApps } from '../../hooks/useApps';
import { getAppStatusBadgeVariant } from '../../utils/themeHelpers';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { Button } from '@/shared/components/ui/Button';
import { Plus, Search } from 'lucide-react';

interface AppsListProps {
  onCreateApp?: () => void;
  onEditApp?: (app: App) => void;
  onViewApp?: (app: App) => void;
  filters?: AppFilters;
  showCreateButton?: boolean;
}

export const AppsList: React.FC<AppsListProps> = ({
AppsList.displayName = 'AppsList';
  onCreateApp,
  onEditApp,
  onViewApp,
  filters = {},
  showCreateButton = true
}) => {
  const { apps, loading, error, pagination, loadApps } = useApps(filters);
  const [searchTerm, setSearchTerm] = useState(filters.search || '');
  const [statusFilter, setStatusFilter] = useState(filters.status || '');

  const handleSearch = (e: React.FormEvent) => {
    e.preventDefault();
    loadApps({ ...filters, search: searchTerm, page: 1 });
  };

  const handleStatusFilter = (status: string) => {
    setStatusFilter(status);
    const validStatus = status === '' ? undefined : (status as AppStatus);
    loadApps({ ...filters, status: validStatus, page: 1 });
  };


  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleDateString();
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="text-center py-12">
        <p className="text-theme-error mb-4">{error}</p>
        <Button variant="secondary" onClick={() => loadApps(filters)}>
          Try Again
        </Button>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div className="flex items-center gap-4">
          <h2 className="text-2xl font-semibold text-theme-primary">Apps</h2>
          <Badge variant="outline" className="text-theme-secondary">
            {pagination.total_count} total
          </Badge>
        </div>
        
        {showCreateButton && onCreateApp && (
          <Button variant="primary" onClick={onCreateApp} className="inline-flex items-center gap-2">
            <Plus className="w-4 h-4" />
            Create App
          </Button>
        )}
      </div>

      {/* Filters */}
      <div className="flex flex-col sm:flex-row gap-4">
        <form onSubmit={handleSearch} className="flex flex-1 gap-2">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-tertiary w-4 h-4" />
            <input
              type="text"
              placeholder="Search apps..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="w-full pl-10 pr-4 py-2 border border-theme rounded-lg focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent bg-theme-surface text-theme-primary"
            />
          </div>
          <Button type="submit" variant="secondary">
            Search
          </Button>
        </form>

        <div className="flex gap-2">
          <select
            value={statusFilter}
            onChange={(e) => handleStatusFilter(e.target.value)}
            className="px-3 py-2 border border-theme rounded-lg focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent bg-theme-surface text-theme-primary"
          >
            <option value="">All Status</option>
            <option value="draft">Draft</option>
            <option value="under_review">Under Review</option>
            <option value="published">Published</option>
            <option value="inactive">Inactive</option>
          </select>
        </div>
      </div>

      {/* Apps Grid */}
      {apps.length === 0 ? (
        <div className="text-center py-12">
          <div className="mb-4">
            <div className="mx-auto w-16 h-16 bg-theme-interactive-primary rounded-full flex items-center justify-center mb-4">
              <Plus className="w-8 h-8 text-white" />
            </div>
            <h3 className="text-lg font-medium text-theme-primary mb-2">No Apps Found</h3>
            <p className="text-theme-secondary mb-6">
              {searchTerm || statusFilter ? 'No apps match your current filters.' : 'Get started by creating your first app.'}
            </p>
            {showCreateButton && onCreateApp && !searchTerm && !statusFilter && (
              <Button variant="primary" onClick={onCreateApp}>
                Create Your First App
              </Button>
            )}
          </div>
        </div>
      ) : (
        <div className="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {apps.map((app) => (
            <Card key={app.id} className="p-6 hover:shadow-lg transition-shadow cursor-pointer">
              <div className="flex items-start justify-between mb-4">
                <div className="flex items-center gap-3">
                  {app.icon && (
                    <div className="w-10 h-10 rounded-lg bg-theme-interactive-primary flex items-center justify-center text-white text-lg">
                      {app.icon}
                    </div>
                  )}
                  <div>
                    <h3 className="font-semibold text-theme-primary truncate max-w-40">{app.name}</h3>
                    <p className="text-sm text-theme-secondary">v{app.version}</p>
                  </div>
                </div>
                
                <Badge variant={getAppStatusBadgeVariant(app.status as AppStatus)}>
                  {app.status.replace('_', ' ')}
                </Badge>
              </div>

              <p className="text-theme-secondary text-sm mb-4 line-clamp-2">
                {app.short_description || app.description}
              </p>

              <div className="mb-4">
                <div className="flex flex-wrap gap-1">
                  {app.tags.slice(0, 3).map((tag) => (
                    <Badge key={tag} variant="outline" className="text-xs">
                      {tag}
                    </Badge>
                  ))}
                  {app.tags.length > 3 && (
                    <Badge variant="outline" className="text-xs">
                      +{app.tags.length - 3} more
                    </Badge>
                  )}
                </div>
              </div>

              <div className="flex items-center justify-between text-sm text-theme-tertiary mb-4">
                <span>Created {formatDate(app.created_at)}</span>
                {app.category && (
                  <span className="bg-theme-surface px-2 py-1 rounded text-xs">
                    {app.category}
                  </span>
                )}
              </div>

              {/* Stats */}
              <div className="grid grid-cols-3 gap-2 text-center text-xs text-theme-secondary border-t border-theme pt-3">
                <div>
                  <div className="font-medium text-theme-primary">{app.plans_count || 0}</div>
                  <div>Plans</div>
                </div>
                <div>
                  <div className="font-medium text-theme-primary">{app.features_count || 0}</div>
                  <div>Features</div>
                </div>
                <div>
                  <div className="font-medium text-theme-primary">{app.subscriptions_count || 0}</div>
                  <div>Subscribers</div>
                </div>
              </div>

              {/* Actions */}
              <div className="flex gap-2 mt-4">
                {onViewApp && (
                  <Button
                    variant="secondary"
                    size="sm"
                    onClick={() => onViewApp(app)}
                    className="flex-1"
                  >
                    View
                  </Button>
                )}
                {onEditApp && (
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => onEditApp(app)}
                    className="flex-1"
                  >
                    Edit
                  </Button>
                )}
              </div>
            </Card>
          ))}
        </div>
      )}

      {/* Pagination */}
      {pagination.total_pages > 1 && (
        <div className="flex items-center justify-between pt-6 border-t border-theme">
          <div className="text-sm text-theme-secondary">
            Showing {((pagination.current_page - 1) * pagination.per_page) + 1} to{' '}
            {Math.min(pagination.current_page * pagination.per_page, pagination.total_count)} of{' '}
            {pagination.total_count} apps
          </div>
          
          <div className="flex gap-2">
            <Button
              variant="outline"
              size="sm"
              disabled={pagination.current_page <= 1}
              onClick={() => loadApps({ ...filters, page: pagination.current_page - 1 })}
            >
              Previous
            </Button>
            <Button
              variant="outline"
              size="sm"
              disabled={pagination.current_page >= pagination.total_pages}
              onClick={() => loadApps({ ...filters, page: pagination.current_page + 1 })}
            >
              Next
            </Button>
          </div>
        </div>
      )}
    </div>
  );
};