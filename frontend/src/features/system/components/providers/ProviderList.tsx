import React, { useState, useEffect, useCallback } from 'react';
import {
  Cloud,
  Search,
  Plus,
  Eye,
  Edit,
  Trash2,
  Globe,
  Lock,
  MoreVertical,
  RefreshCw,
  Filter,
  Server,
  MapPin
} from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { systemApi } from '@/features/system/services/systemApi';
import type { SystemProvider } from '@/features/system/types/system.types';

interface ProviderListFilters {
  search: string;
  providerType: string;
  enabled: 'all' | 'enabled' | 'disabled';
}

interface ProviderListProps {
  onView?: (provider: SystemProvider) => void;
  onEdit?: (provider: SystemProvider) => void;
  onDelete?: (providerId: string) => void;
  onCreate?: () => void;
  className?: string;
}

const providerTypeIcons: Record<string, string> = {
  aws: '☁️',
  openstack: '🔶',
  gcp: '🌐',
  azure: '🔷',
  digitalocean: '💧',
  custom: '⚙️'
};

const providerTypeLabels: Record<string, string> = {
  aws: 'Amazon Web Services',
  openstack: 'OpenStack',
  gcp: 'Google Cloud Platform',
  azure: 'Microsoft Azure',
  digitalocean: 'DigitalOcean',
  custom: 'Custom Provider'
};

/**
 * ProviderList - Displays a list of infrastructure providers
 */
export const ProviderList: React.FC<ProviderListProps> = ({
  onView,
  onEdit,
  onDelete,
  onCreate,
  className = ''
}) => {
  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();

  const canCreate = hasPermission('system.providers.create');
  const canUpdate = hasPermission('system.providers.update');
  const canDelete = hasPermission('system.providers.delete');

  const [providers, setProviders] = useState<SystemProvider[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [filters, setFilters] = useState<ProviderListFilters>({
    search: '',
    providerType: 'all',
    enabled: 'all'
  });
  const [dropdownOpen, setDropdownOpen] = useState<string | null>(null);

  const fetchProviders = useCallback(async () => {
    try {
      const data = await systemApi.getProviders();
      setProviders(data);
    } catch (error) {
      addNotification({
        type: 'error',
        message: 'Failed to load providers'
      });
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [addNotification]);

  useEffect(() => {
    fetchProviders();
  }, [fetchProviders]);

  const handleRefresh = () => {
    setRefreshing(true);
    fetchProviders();
  };

  // Get unique provider types for filter dropdown
  const providerTypes = [...new Set(providers.map(p => p.provider_type))];

  const filteredProviders = providers.filter(provider => {
    if (filters.search) {
      const searchLower = filters.search.toLowerCase();
      if (
        !provider.name.toLowerCase().includes(searchLower) &&
        !provider.description?.toLowerCase().includes(searchLower) &&
        !provider.provider_type.toLowerCase().includes(searchLower)
      ) {
        return false;
      }
    }

    if (filters.providerType !== 'all' && provider.provider_type !== filters.providerType) {
      return false;
    }

    if (filters.enabled !== 'all') {
      if (filters.enabled === 'enabled' && !provider.enabled) return false;
      if (filters.enabled === 'disabled' && provider.enabled) return false;
    }

    return true;
  });

  useEffect(() => {
    const handleClickOutside = () => setDropdownOpen(null);
    document.addEventListener('click', handleClickOutside);
    return () => document.removeEventListener('click', handleClickOutside);
  }, []);

  if (loading && providers.length === 0) {
    return (
      <div className={`bg-theme-surface rounded-lg border border-theme p-8 ${className}`}>
        <div className="flex items-center justify-center">
          <LoadingSpinner size="lg" />
        </div>
      </div>
    );
  }

  if (!loading && providers.length === 0) {
    return (
      <div className={`bg-theme-surface rounded-lg border border-theme p-8 text-center ${className}`}>
        <Cloud className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
        <h3 className="text-lg font-medium text-theme-primary mb-2">No providers configured</h3>
        <p className="text-theme-secondary mb-4">
          Add cloud providers to manage infrastructure across multiple platforms
        </p>
        {canCreate && onCreate && (
          <Button variant="primary" onClick={onCreate}>
            <Plus className="w-4 h-4 mr-2" />
            Add Provider
          </Button>
        )}
      </div>
    );
  }

  return (
    <div className={`space-y-6 ${className}`}>
      {/* Filters */}
      <div className="bg-theme-surface rounded-lg border border-theme p-4">
        <div className="flex flex-col sm:flex-row gap-4">
          <div className="flex-1">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-tertiary w-4 h-4" />
              <input
                type="text"
                placeholder="Search providers..."
                value={filters.search}
                onChange={(e) => setFilters({ ...filters, search: e.target.value })}
                className="w-full pl-10 pr-4 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-focus"
              />
            </div>
          </div>

          <div className="sm:w-40">
            <select
              value={filters.providerType}
              onChange={(e) => setFilters({ ...filters, providerType: e.target.value })}
              className="w-full px-3 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus appearance-none"
            >
              <option value="all">All Types</option>
              {providerTypes.map(type => (
                <option key={type} value={type}>
                  {providerTypeLabels[type] || type}
                </option>
              ))}
            </select>
          </div>

          <div className="sm:w-32">
            <div className="relative">
              <Filter className="absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-tertiary w-4 h-4" />
              <select
                value={filters.enabled}
                onChange={(e) => setFilters({ ...filters, enabled: e.target.value as ProviderListFilters['enabled'] })}
                className="w-full pl-10 pr-4 py-2 rounded-lg border border-theme bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus appearance-none"
              >
                <option value="all">All Status</option>
                <option value="enabled">Enabled</option>
                <option value="disabled">Disabled</option>
              </select>
            </div>
          </div>

          <Button variant="outline" onClick={handleRefresh} disabled={refreshing} className="sm:w-auto">
            <RefreshCw className={`w-4 h-4 ${refreshing ? 'animate-spin' : ''}`} />
          </Button>

          {canCreate && onCreate && (
            <Button variant="primary" onClick={onCreate} className="sm:w-auto">
              <Plus className="w-4 h-4 mr-2" />
              Add Provider
            </Button>
          )}
        </div>

        {filteredProviders.length < providers.length && (
          <div className="mt-4 text-sm text-theme-secondary">
            Showing {filteredProviders.length} of {providers.length} providers
          </div>
        )}
      </div>

      {/* Providers Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {filteredProviders.map((provider) => (
          <div
            key={provider.id}
            className="bg-theme-surface rounded-lg border border-theme p-4 hover:border-theme-accent transition-colors"
          >
            <div className="flex items-start justify-between mb-3">
              <div className="flex items-center gap-3">
                <span className="text-2xl">
                  {providerTypeIcons[provider.provider_type] || '☁️'}
                </span>
                <div>
                  <h3
                    className="font-medium text-theme-primary hover:text-theme-link cursor-pointer"
                    onClick={() => onView?.(provider)}
                  >
                    {provider.name}
                  </h3>
                  <p className="text-sm text-theme-secondary">
                    {providerTypeLabels[provider.provider_type] || provider.provider_type}
                  </p>
                </div>
              </div>

              <div className="relative">
                <Button
                  variant="outline"
                  size="sm"
                  onClick={(e) => {
                    e.stopPropagation();
                    setDropdownOpen(dropdownOpen === provider.id ? null : provider.id);
                  }}
                >
                  <MoreVertical className="w-4 h-4" />
                </Button>

                {dropdownOpen === provider.id && (
                  <div className="absolute right-0 mt-1 w-48 bg-theme-surface border border-theme rounded-lg shadow-lg z-10">
                    <div className="py-1">
                      <button
                        onClick={() => { onView?.(provider); setDropdownOpen(null); }}
                        className="w-full text-left px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover flex items-center gap-2"
                      >
                        <Eye className="w-4 h-4" />
                        View Details
                      </button>
                      {canUpdate && onEdit && (
                        <button
                          onClick={() => { onEdit(provider); setDropdownOpen(null); }}
                          className="w-full text-left px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover flex items-center gap-2"
                        >
                          <Edit className="w-4 h-4" />
                          Edit Provider
                        </button>
                      )}
                      {canDelete && onDelete && (
                        <button
                          onClick={() => { onDelete(provider.id); setDropdownOpen(null); }}
                          className="w-full text-left px-4 py-2 text-sm text-theme-error hover:bg-theme-surface-hover flex items-center gap-2"
                        >
                          <Trash2 className="w-4 h-4" />
                          Delete Provider
                        </button>
                      )}
                    </div>
                  </div>
                )}
              </div>
            </div>

            {provider.description && (
              <p className="text-sm text-theme-secondary mb-3 line-clamp-2">
                {provider.description}
              </p>
            )}

            <div className="flex items-center gap-4 text-sm text-theme-secondary mb-3">
              <div className="flex items-center gap-1">
                <MapPin className="w-4 h-4" />
                <span>{provider.region_count || 0} regions</span>
              </div>
              <div className="flex items-center gap-1">
                <Server className="w-4 h-4" />
                <span>{provider.connection_count || 0} connections</span>
              </div>
            </div>

            <div className="flex items-center gap-2">
              <Badge variant={provider.enabled ? 'success' : 'secondary'} dot pulse={provider.enabled}>
                {provider.enabled ? 'Enabled' : 'Disabled'}
              </Badge>
              <Badge variant={provider.public ? 'info' : 'secondary'}>
                {provider.public ? (
                  <><Globe className="w-3 h-3 mr-1" />Public</>
                ) : (
                  <><Lock className="w-3 h-3 mr-1" />Private</>
                )}
              </Badge>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};

export default ProviderList;
