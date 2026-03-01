import React, { useState } from 'react';
import { AppWindow, Search, Eye, Pencil, Trash2 } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { Card } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useListMcpApps, useDeleteMcpApp } from '../api/mcpAppsApi';
import type { McpApp, McpAppStatus, McpAppType, McpAppFilterParams } from '../types/mcpApps';

const STATUS_VARIANTS: Record<McpAppStatus, 'default' | 'success' | 'secondary'> = {
  draft: 'default',
  published: 'success',
  archived: 'secondary',
};

const TYPE_VARIANTS: Record<McpAppType, 'info' | 'primary' | 'warning'> = {
  custom: 'info',
  template: 'primary',
  system: 'warning',
};

const STATUS_OPTIONS: McpAppStatus[] = ['draft', 'published', 'archived'];
const TYPE_OPTIONS: McpAppType[] = ['custom', 'template', 'system'];

interface McpAppGalleryProps {
  onSelectApp: (app: McpApp) => void;
  onEditApp: (app: McpApp) => void;
  selectedAppId: string | null;
}

export const McpAppGallery: React.FC<McpAppGalleryProps> = ({
  onSelectApp,
  onEditApp,
  selectedAppId,
}) => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();
  const [filters, setFilters] = useState<McpAppFilterParams>({});
  const [searchInput, setSearchInput] = useState('');

  const { data: apps, isLoading } = useListMcpApps(filters);
  const deleteApp = useDeleteMcpApp();

  const canManage = hasPermission('ai.agents.manage');

  const handleSearch = () => {
    setFilters((prev) => ({ ...prev, search: searchInput || undefined }));
  };

  const handleSearchKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') handleSearch();
  };

  const handleStatusFilter = (status: McpAppStatus | undefined) => {
    setFilters((prev) => ({ ...prev, status }));
  };

  const handleTypeFilter = (app_type: McpAppType | undefined) => {
    setFilters((prev) => ({ ...prev, app_type }));
  };

  const handleDelete = (e: React.MouseEvent, appId: string) => {
    e.stopPropagation();
    deleteApp.mutate(appId, {
      onSuccess: () => {
        addNotification({ type: 'success', message: 'App deleted' });
      },
      onError: () => {
        addNotification({ type: 'error', message: 'Failed to delete app' });
      },
    });
  };

  if (isLoading) {
    return <LoadingSpinner size="sm" className="py-8" />;
  }

  const appList = apps || [];

  return (
    <div className="space-y-4">
      {/* Search */}
      <div className="flex items-center gap-2">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-theme-muted" />
          <input
            type="text"
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            onKeyDown={handleSearchKeyDown}
            placeholder="Search apps..."
            className="w-full pl-9 pr-3 py-2 text-sm border border-theme rounded-lg bg-theme-bg text-theme-primary placeholder:text-theme-muted focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
          />
        </div>
        <Button variant="secondary" size="sm" onClick={handleSearch}>
          Search
        </Button>
      </div>

      {/* Filters */}
      <div className="flex flex-wrap items-center gap-4">
        <div className="flex items-center gap-2">
          <span className="text-xs text-theme-tertiary">Status:</span>
          <Button
            variant={filters.status === undefined ? 'primary' : 'outline'}
            size="xs"
            onClick={() => handleStatusFilter(undefined)}
          >
            All
          </Button>
          {STATUS_OPTIONS.map((status) => (
            <Button
              key={status}
              variant={filters.status === status ? 'primary' : 'outline'}
              size="xs"
              onClick={() => handleStatusFilter(status)}
            >
              {status}
            </Button>
          ))}
        </div>
        <div className="flex items-center gap-2">
          <span className="text-xs text-theme-tertiary">Type:</span>
          <Button
            variant={filters.app_type === undefined ? 'primary' : 'outline'}
            size="xs"
            onClick={() => handleTypeFilter(undefined)}
          >
            All
          </Button>
          {TYPE_OPTIONS.map((type) => (
            <Button
              key={type}
              variant={filters.app_type === type ? 'primary' : 'outline'}
              size="xs"
              onClick={() => handleTypeFilter(type)}
            >
              {type}
            </Button>
          ))}
        </div>
      </div>

      {/* App Grid */}
      {appList.length === 0 ? (
        <div className="text-center py-12">
          <AppWindow className="h-10 w-10 text-theme-muted mx-auto mb-3 opacity-50" />
          <p className="text-theme-secondary text-sm">No MCP apps found.</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          {appList.map((app) => {
            const isSelected = selectedAppId === app.id;

            return (
              <Card
                key={app.id}
                className={`p-4 cursor-pointer transition-colors hover:bg-theme-surface-hover ${
                  isSelected ? 'ring-2 ring-theme-interactive-primary' : ''
                }`}
                onClick={() => onSelectApp(app)}
              >
                <div className="flex items-start justify-between mb-2">
                  <div className="flex items-center gap-2 min-w-0">
                    <AppWindow className="h-5 w-5 text-theme-interactive-primary flex-shrink-0" />
                    <h4 className="text-sm font-semibold text-theme-primary truncate">
                      {app.name}
                    </h4>
                  </div>
                  <div className="flex items-center gap-1 flex-shrink-0">
                    <Badge variant={STATUS_VARIANTS[app.status]} size="xs">
                      {app.status}
                    </Badge>
                    <Badge variant={TYPE_VARIANTS[app.app_type]} size="xs">
                      {app.app_type}
                    </Badge>
                  </div>
                </div>
                {app.description && (
                  <p className="text-xs text-theme-secondary line-clamp-2 mb-3">
                    {app.description}
                  </p>
                )}
                <div className="flex items-center justify-between">
                  <span className="text-xs text-theme-muted">v{app.version}</span>
                  <div className="flex items-center gap-1">
                    <Button
                      variant="ghost"
                      size="xs"
                      onClick={(e) => {
                        e.stopPropagation();
                        onSelectApp(app);
                      }}
                      title="View"
                    >
                      <Eye className="h-3.5 w-3.5" />
                    </Button>
                    {canManage && (
                      <>
                        <Button
                          variant="ghost"
                          size="xs"
                          onClick={(e) => {
                            e.stopPropagation();
                            onEditApp(app);
                          }}
                          title="Edit"
                        >
                          <Pencil className="h-3.5 w-3.5" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="xs"
                          onClick={(e) => handleDelete(e, app.id)}
                          loading={deleteApp.isPending}
                          title="Delete"
                        >
                          <Trash2 className="h-3.5 w-3.5" />
                        </Button>
                      </>
                    )}
                  </div>
                </div>
              </Card>
            );
          })}
        </div>
      )}
    </div>
  );
};
