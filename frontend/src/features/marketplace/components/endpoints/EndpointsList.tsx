import React, { useState } from 'react';
import { Search, Filter, Plus } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EndpointCard } from './EndpointCard';
import { EndpointFormModal } from './EndpointFormModal';
import { EndpointTestModal } from './EndpointTestModal';
import { EndpointAnalyticsModal } from './EndpointAnalyticsModal';
import { useAppEndpoints } from '../../hooks/useEndpoints';
import { AppEndpoint, AppEndpointFilters, HttpMethod } from '../../types';

interface EndpointsListProps {
  appId: string;
  className?: string;
  showCreateButton?: boolean;
  onEndpointAction?: (action: string, endpoint: AppEndpoint) => void;
}

const httpMethods: HttpMethod[] = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'];

export const EndpointsList: React.FC<EndpointsListProps> = ({
  appId,
  className = '',
  showCreateButton = true,
  onEndpointAction
}) => {
  const [filters, setFilters] = useState<AppEndpointFilters>({
    search: '',
    method: undefined,
    active: undefined,
    page: 1,
    per_page: 20
  });
  
  const [selectedEndpoint, setSelectedEndpoint] = useState<AppEndpoint | null>(null);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showEditModal, setShowEditModal] = useState(false);
  const [showTestModal, setShowTestModal] = useState(false);
  const [showAnalyticsModal, setShowAnalyticsModal] = useState(false);

  const {
    endpoints,
    loading,
    error,
    pagination,
    createEndpoint,
    updateEndpoint,
    activateEndpoint,
    deactivateEndpoint,
    testEndpoint,
    refresh
  } = useAppEndpoints(appId, filters);

  const handleSearch = (query: string) => {
    setFilters(prev => ({ ...prev, search: query, page: 1 }));
  };

  const handleMethodFilter = (method: HttpMethod | undefined) => {
    setFilters(prev => ({ ...prev, method, page: 1 }));
  };

  const handleStatusFilter = (active: boolean | undefined) => {
    setFilters(prev => ({ ...prev, active, page: 1 }));
  };

  const handleEdit = (endpoint: AppEndpoint) => {
    setSelectedEndpoint(endpoint);
    setShowEditModal(true);
    onEndpointAction?.('edit', endpoint);
  };

  const handleTest = (endpoint: AppEndpoint) => {
    setSelectedEndpoint(endpoint);
    setShowTestModal(true);
    onEndpointAction?.('test', endpoint);
  };

  const handleViewAnalytics = (endpoint: AppEndpoint) => {
    setSelectedEndpoint(endpoint);
    setShowAnalyticsModal(true);
    onEndpointAction?.('analytics', endpoint);
  };

  const handleToggleStatus = async (endpoint: AppEndpoint) => {
    if (endpoint.is_active) {
      await deactivateEndpoint(endpoint.id);
      onEndpointAction?.('deactivate', endpoint);
    } else {
      await activateEndpoint(endpoint.id);
      onEndpointAction?.('activate', endpoint);
    }
  };


  const handleCreateEndpoint = async (data: any) => {
    const endpoint = await createEndpoint(data);
    if (endpoint) {
      setShowCreateModal(false);
      onEndpointAction?.('create', endpoint);
      return endpoint;
    }
    return null;
  };

  const handleUpdateEndpoint = async (data: any) => {
    if (!selectedEndpoint) return null;
    
    const endpoint = await updateEndpoint(selectedEndpoint.id, data);
    if (endpoint) {
      setShowEditModal(false);
      setSelectedEndpoint(null);
      onEndpointAction?.('update', endpoint);
      return endpoint;
    }
    return null;
  };

  const loadMore = () => {
    if (pagination.current_page < pagination.total_pages) {
      setFilters(prev => ({ ...prev, page: prev.page! + 1 }));
    }
  };

  // Filter options for status
  const statusOptions = [
    { value: undefined, label: 'All Status', count: endpoints.length },
    { value: true, label: 'Active', count: endpoints.filter(e => e.is_active).length },
    { value: false, label: 'Inactive', count: endpoints.filter(e => !e.is_active).length }
  ];

  // Filter options for HTTP methods
  const methodOptions = [
    { value: undefined, label: 'All Methods', count: endpoints.length },
    ...httpMethods.map(method => ({
      value: method,
      label: method,
      count: endpoints.filter(e => e.http_method === method).length
    }))
  ];

  return (
    <div className={`space-y-6 ${className}`}>
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h2 className="text-2xl font-bold text-theme-primary">API Endpoints</h2>
          <p className="text-theme-secondary">Manage your app's API endpoints and monitor their performance</p>
        </div>
        
        {showCreateButton && (
          <Button
            onClick={() => setShowCreateModal(true)}
            className="flex items-center space-x-2"
          >
            <Plus className="w-4 h-4" />
            <span>Create Endpoint</span>
          </Button>
        )}
      </div>

      {/* Filters */}
      <div className="flex flex-col lg:flex-row gap-4">
        {/* Search */}
        <div className="relative flex-1">
          <Search className="w-5 h-5 absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-tertiary" />
          <input
            type="text"
            placeholder="Search endpoints by name, path, or description..."
            value={filters.search}
            onChange={(e) => handleSearch(e.target.value)}
            className="w-full pl-10 pr-4 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
          />
        </div>

        {/* Method Filter */}
        <div className="flex items-center space-x-2">
          <Filter className="w-4 h-4 text-theme-tertiary" />
          <div className="flex flex-wrap gap-2">
            {methodOptions.slice(0, 4).map((option) => (
              <button
                key={option.label}
                onClick={() => handleMethodFilter(option.value)}
                className={`px-3 py-1 rounded-full text-sm font-medium transition-colors ${
                  filters.method === option.value
                    ? 'bg-theme-interactive-primary text-white'
                    : 'bg-theme-surface text-theme-secondary hover:bg-theme-interactive-primary/10'
                }`}
              >
                {option.label}
                {option.count > 0 && (
                  <Badge variant="secondary" className="ml-1 text-xs">
                    {option.count}
                  </Badge>
                )}
              </button>
            ))}
          </div>
        </div>

        {/* Status Filter */}
        <div className="flex flex-wrap gap-2">
          {statusOptions.map((option) => (
            <button
              key={option.label}
              onClick={() => handleStatusFilter(option.value)}
              className={`px-3 py-1 rounded-full text-sm font-medium transition-colors ${
                filters.active === option.value
                  ? 'bg-theme-interactive-primary text-white'
                  : 'bg-theme-surface text-theme-secondary hover:bg-theme-interactive-primary/10'
              }`}
            >
              {option.label}
              {option.count > 0 && (
                <Badge variant="secondary" className="ml-1 text-xs">
                  {option.count}
                </Badge>
              )}
            </button>
          ))}
        </div>
      </div>

      {/* Loading State */}
      {loading && endpoints.length === 0 && (
        <div className="flex justify-center py-12">
          <LoadingSpinner size="lg" />
        </div>
      )}

      {/* Error State */}
      {error && (
        <div className="bg-theme-error-background border border-theme-error-border rounded-lg p-6 text-center">
          <p className="text-theme-error mb-4">{error}</p>
          <Button variant="outline" onClick={refresh}>
            Try Again
          </Button>
        </div>
      )}

      {/* Empty State */}
      {!loading && !error && endpoints.length === 0 && (
        <div className="text-center py-12">
          <div className="w-16 h-16 bg-theme-interactive-primary/10 rounded-full flex items-center justify-center mx-auto mb-4">
            <span className="text-2xl">🔌</span>
          </div>
          <h3 className="text-lg font-semibold text-theme-primary mb-2">
            No API endpoints yet
          </h3>
          <p className="text-theme-secondary mb-4">
            Create your first API endpoint to start building your app's functionality
          </p>
          {showCreateButton && (
            <Button onClick={() => setShowCreateModal(true)}>
              Create Your First Endpoint
            </Button>
          )}
        </div>
      )}

      {/* Endpoints Grid */}
      {!loading && !error && endpoints.length > 0 && (
        <div className="space-y-4">
          {endpoints.map((endpoint) => (
            <EndpointCard
              key={endpoint.id}
              endpoint={endpoint}
              onEdit={handleEdit}
              onToggleStatus={handleToggleStatus}
              onTest={handleTest}
              onViewAnalytics={handleViewAnalytics}
            />
          ))}
        </div>
      )}

      {/* Load More */}
      {pagination && pagination.current_page < pagination.total_pages && (
        <div className="text-center py-6">
          <Button
            variant="outline"
            onClick={loadMore}
            disabled={loading}
            className="flex items-center space-x-2"
          >
            <span>Load More</span>
            {loading && <LoadingSpinner size="sm" />}
          </Button>
        </div>
      )}

      {/* Stats Footer */}
      {pagination && (
        <div className="text-center text-sm text-theme-secondary">
          Showing {endpoints.length} of {pagination.total_count} endpoints
        </div>
      )}

      {/* Modals */}
      <EndpointFormModal
        isOpen={showCreateModal}
        onClose={() => setShowCreateModal(false)}
        onSubmit={handleCreateEndpoint}
        title="Create API Endpoint"
      />

      <EndpointFormModal
        isOpen={showEditModal}
        onClose={() => {
          setShowEditModal(false);
          setSelectedEndpoint(null);
        }}
        onSubmit={handleUpdateEndpoint}
        endpoint={selectedEndpoint}
        title="Edit API Endpoint"
      />

      <EndpointTestModal
        isOpen={showTestModal}
        onClose={() => {
          setShowTestModal(false);
          setSelectedEndpoint(null);
        }}
        endpoint={selectedEndpoint}
        appId={appId}
        onTest={testEndpoint}
      />

      <EndpointAnalyticsModal
        isOpen={showAnalyticsModal}
        onClose={() => {
          setShowAnalyticsModal(false);
          setSelectedEndpoint(null);
        }}
        endpoint={selectedEndpoint}
        appId={appId}
      />
    </div>
  );
};