import React, { useState, useEffect } from 'react';
import { serviceAPI, Service } from '../../services/serviceApi';
import { LoadingSpinner } from '../../components/ui/LoadingSpinner';

interface ServicesPageState {
  services: Service[];
  selectedService: Service | null;
  loading: boolean;
  error: string | null;
  showCreateModal: boolean;
  showDetailsModal: boolean;
  showDeleteModal: boolean;
  searchTerm: string;
  filterStatus: 'all' | 'active' | 'suspended' | 'revoked';
  viewMode: 'grid' | 'list';
  stats: {
    total: number;
    account_services: number;
    active_count: number;
    suspended_count: number;
    revoked_count: number;
    recent_activity_count: number;
  };
}

// Service Card Component
interface ServiceCardProps {
  service: Service;
  onView: (service: Service) => void;
  onEdit: (service: Service) => void;
  onDelete: (service: Service) => void;
  onStatusChange: (service: Service, action: 'suspend' | 'activate' | 'revoke') => void;
  onTokenRegenerate: (service: Service) => void;
}

const ServiceCard: React.FC<ServiceCardProps> = ({ 
  service, 
  onView, 
  onEdit, 
  onDelete, 
  onStatusChange, 
  onTokenRegenerate 
}) => {
  const getStatusConfig = (status: string) => {
    switch (status) {
      case 'active':
        return { 
          color: 'bg-theme-success', 
          textColor: 'text-theme-success', 
          bgColor: 'bg-theme-success-background', 
          icon: '✅',
          label: 'Active'
        };
      case 'suspended':
        return { 
          color: 'bg-theme-warning', 
          textColor: 'text-theme-warning', 
          bgColor: 'bg-theme-warning-background', 
          icon: '⏸️',
          label: 'Suspended'
        };
      case 'revoked':
        return { 
          color: 'bg-theme-error', 
          textColor: 'text-theme-error', 
          bgColor: 'bg-theme-error-background', 
          icon: '🚫',
          label: 'Revoked'
        };
      default:
        return { 
          color: 'bg-theme-background-secondary', 
          textColor: 'text-theme-secondary', 
          bgColor: 'bg-theme-background-secondary', 
          icon: '❓',
          label: 'Unknown'
        };
    }
  };

  const getPermissionConfig = (permission: string) => {
    switch (permission) {
      case 'readonly':
        return { color: 'bg-blue-100 text-blue-800', label: 'Read Only', icon: '👁️' };
      case 'standard':
        return { color: 'bg-green-100 text-green-800', label: 'Standard', icon: '🔧' };
      case 'admin':
        return { color: 'bg-orange-100 text-orange-800', label: 'Admin', icon: '⚙️' };
      case 'super_admin':
        return { color: 'bg-red-100 text-red-800', label: 'Super Admin', icon: '👑' };
      default:
        return { color: 'bg-gray-100 text-gray-800', label: 'Unknown', icon: '❓' };
    }
  };

  const statusConfig = getStatusConfig(service.status);
  const permissionConfig = getPermissionConfig(service.permissions);
  const lastSeen = service.last_seen_at ? new Date(service.last_seen_at).toLocaleDateString() : 'Never';
  const isRecentlyActive = service.active_recently;

  return (
    <div className="bg-theme-surface rounded-xl border border-theme hover:shadow-lg transition-all duration-200 overflow-hidden group">
      {/* Header */}
      <div className="p-6 pb-4">
        <div className="flex items-start justify-between mb-4">
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-3 mb-2">
              <h3 className="text-lg font-semibold text-theme-primary truncate">
                {service.name}
              </h3>
              {isRecentlyActive && (
                <div className="w-2 h-2 bg-green-400 rounded-full animate-pulse" title="Recently Active" />
              )}
            </div>
            <p className="text-theme-secondary text-sm line-clamp-2">
              {service.description || 'No description provided'}
            </p>
          </div>
          
          {/* Status Badge */}
          <div className={`px-3 py-1 rounded-full text-xs font-medium flex items-center gap-1 ${statusConfig.bgColor} ${statusConfig.textColor}`}>
            <span>{statusConfig.icon}</span>
            <span>{statusConfig.label}</span>
          </div>
        </div>

        {/* Permission and Account Info */}
        <div className="flex items-center justify-between text-sm mb-4">
          <div className={`px-2 py-1 rounded-lg text-xs font-medium flex items-center gap-1 ${permissionConfig.color}`}>
            <span>{permissionConfig.icon}</span>
            <span>{permissionConfig.label}</span>
          </div>
          <span className="text-theme-tertiary">{service.account_name}</span>
        </div>

        {/* Statistics */}
        <div className="grid grid-cols-2 gap-4 mb-4">
          <div className="text-center p-3 bg-theme-background rounded-lg">
            <div className="text-lg font-bold text-theme-primary">{service.request_count.toLocaleString()}</div>
            <div className="text-xs text-theme-secondary">Total Requests</div>
          </div>
          <div className="text-center p-3 bg-theme-background rounded-lg">
            <div className="text-lg font-bold text-theme-primary">{lastSeen}</div>
            <div className="text-xs text-theme-secondary">Last Seen</div>
          </div>
        </div>

        {/* Token Preview */}
        <div className="bg-theme-background rounded-lg p-3 mb-4">
          <div className="flex items-center justify-between">
            <code className="text-xs font-mono text-theme-secondary truncate flex-1">
              {service.masked_token}
            </code>
            <button
              onClick={() => onTokenRegenerate(service)}
              className="ml-2 text-theme-link hover:text-theme-link-hover text-xs"
              title="Regenerate Token"
            >
              🔄
            </button>
          </div>
        </div>
      </div>

      {/* Actions */}
      <div className="border-t border-theme bg-theme-background-secondary px-6 py-4">
        <div className="flex items-center justify-between">
          <button
            onClick={() => onView(service)}
            className="text-theme-link hover:text-theme-link-hover text-sm font-medium flex items-center gap-1"
          >
            <span>👁️</span>
            <span>View Details</span>
          </button>
          
          <div className="flex items-center gap-2">
            <button
              onClick={() => onEdit(service)}
              className="p-2 text-theme-secondary hover:text-theme-primary hover:bg-theme-surface rounded-lg transition-colors"
              title="Edit Service"
            >
              ✏️
            </button>
            
            {service.status === 'active' ? (
              <button
                onClick={() => onStatusChange(service, 'suspend')}
                className="p-2 text-yellow-600 hover:text-yellow-700 hover:bg-yellow-50 rounded-lg transition-colors"
                title="Suspend Service"
              >
                ⏸️
              </button>
            ) : service.status === 'suspended' ? (
              <button
                onClick={() => onStatusChange(service, 'activate')}
                className="p-2 text-green-600 hover:text-green-700 hover:bg-green-50 rounded-lg transition-colors"
                title="Activate Service"
              >
                ▶️
              </button>
            ) : null}
            
            <button
              onClick={() => onDelete(service)}
              className="p-2 text-red-600 hover:text-red-700 hover:bg-red-50 rounded-lg transition-colors"
              title="Delete Service"
            >
              🗑️
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

// Create Service Modal Component
interface CreateServiceModalProps {
  onClose: () => void;
  onCreate: (data: any) => Promise<void>;
}

const CreateServiceModal: React.FC<CreateServiceModalProps> = ({ onClose, onCreate }) => {
  const [formData, setFormData] = useState({
    name: '',
    description: '',
    permissions: 'standard' as const
  });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError(null);

    try {
      await onCreate(formData);
      onClose();
    } catch (error: any) {
      setError(error.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 overflow-y-auto bg-black bg-opacity-50 flex items-center justify-center p-4">
      <div className="bg-theme-surface rounded-xl max-w-md w-full p-6 shadow-2xl">
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-xl font-semibold text-theme-primary">Create New Service</h2>
          <button
            onClick={onClose}
            className="p-2 text-theme-secondary hover:text-theme-primary hover:bg-theme-background rounded-lg transition-colors"
          >
            ✕
          </button>
        </div>

        {error && (
          <div className="mb-4 p-3 bg-red-50 border border-red-200 rounded-lg text-red-700 text-sm">
            {error}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Service Name
            </label>
            <input
              type="text"
              required
              value={formData.name}
              onChange={(e) => setFormData(prev => ({ ...prev, name: e.target.value }))}
              className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-focus focus:border-transparent"
              placeholder="Enter service name"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Description
            </label>
            <textarea
              value={formData.description}
              onChange={(e) => setFormData(prev => ({ ...prev, description: e.target.value }))}
              className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-focus focus:border-transparent"
              rows={3}
              placeholder="Enter service description"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Permissions
            </label>
            <select
              value={formData.permissions}
              onChange={(e) => setFormData(prev => ({ ...prev, permissions: e.target.value as any }))}
              className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-focus focus:border-transparent"
            >
              <option value="readonly">👁️ Read Only</option>
              <option value="standard">🔧 Standard</option>
              <option value="admin">⚙️ Admin</option>
              <option value="super_admin">👑 Super Admin</option>
            </select>
          </div>

          <div className="flex items-center gap-3 pt-4">
            <button
              type="submit"
              disabled={loading}
              className="flex-1 bg-theme-interactive-primary text-white py-2 px-4 rounded-lg font-medium hover:bg-theme-interactive-primary-hover disabled:opacity-50 transition-colors"
            >
              {loading ? 'Creating...' : '✨ Create Service'}
            </button>
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 text-theme-secondary hover:text-theme-primary transition-colors"
            >
              Cancel
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

export const ServicesPage: React.FC = () => {
  const [state, setState] = useState<ServicesPageState>({
    services: [],
    selectedService: null,
    loading: true,
    error: null,
    showCreateModal: false,
    showDetailsModal: false,
    showDeleteModal: false,
    searchTerm: '',
    filterStatus: 'all',
    viewMode: 'grid',
    stats: {
      total: 0,
      account_services: 0,
      active_count: 0,
      suspended_count: 0,
      revoked_count: 0,
      recent_activity_count: 0
    }
  });

  const loadServices = async () => {
    try {
      setState(prev => ({ ...prev, loading: true, error: null }));
      const response = await serviceAPI.getServices();
      
      // Calculate additional statistics
      const active_count = response.services.filter(s => s.status === 'active').length;
      const suspended_count = response.services.filter(s => s.status === 'suspended').length;
      const revoked_count = response.services.filter(s => s.status === 'revoked').length;
      const recent_activity_count = response.services.filter(s => s.active_recently).length;

      setState(prev => ({
        ...prev,
        services: response.services,
        stats: {
          total: response.total,
          account_services: response.account_services,
          active_count,
          suspended_count,
          revoked_count,
          recent_activity_count
        },
        loading: false
      }));
    } catch (error: any) {
      setState(prev => ({
        ...prev,
        error: error.response?.data?.error || 'Failed to load services',
        loading: false
      }));
    }
  };

  useEffect(() => {
    loadServices();
  }, []);

  const handleServiceCreate = async (serviceData: any) => {
    try {
      await serviceAPI.createService(serviceData);
      await loadServices();
      setState(prev => ({ ...prev, showCreateModal: false }));
    } catch (error: any) {
      throw new Error(error.response?.data?.error || 'Failed to create service');
    }
  };

  const handleServiceEdit = (service: Service) => {
    setState(prev => ({ ...prev, selectedService: service, showDetailsModal: true }));
  };

  const handleServiceView = (service: Service) => {
    setState(prev => ({ ...prev, selectedService: service, showDetailsModal: true }));
  };

  const handleServiceDelete = (service: Service) => {
    setState(prev => ({ ...prev, selectedService: service, showDeleteModal: true }));
  };

  const confirmDelete = async () => {
    if (!state.selectedService) return;
    
    try {
      await serviceAPI.deleteService(state.selectedService.id);
      await loadServices();
      setState(prev => ({ ...prev, showDeleteModal: false, selectedService: null }));
    } catch (error: any) {
      console.error('Failed to delete service:', error);
    }
  };

  const handleStatusChange = async (service: Service, action: 'suspend' | 'activate' | 'revoke') => {
    try {
      switch (action) {
        case 'suspend':
          await serviceAPI.suspendService(service.id);
          break;
        case 'activate':
          await serviceAPI.activateService(service.id);
          break;
        case 'revoke':
          await serviceAPI.revokeService(service.id);
          break;
      }
      await loadServices();
    } catch (error: any) {
      console.error(`Failed to ${action} service:`, error);
    }
  };

  const handleTokenRegenerate = async (service: Service) => {
    try {
      const response = await serviceAPI.regenerateToken(service.id);
      await loadServices();
      // Show success notification with new token
      alert(`Token regenerated successfully! New token: ${response.new_token}`);
    } catch (error: any) {
      console.error('Failed to regenerate token:', error);
    }
  };

  // Filter services based on search and status
  const filteredServices = state.services.filter(service => {
    const matchesSearch = service.name.toLowerCase().includes(state.searchTerm.toLowerCase()) ||
                         service.description?.toLowerCase().includes(state.searchTerm.toLowerCase()) ||
                         service.account_name.toLowerCase().includes(state.searchTerm.toLowerCase());
    
    const matchesStatus = state.filterStatus === 'all' || service.status === state.filterStatus;
    
    return matchesSearch && matchesStatus;
  });

  if (state.loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <LoadingSpinner message="Loading services..." />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-theme-primary">Services Management</h1>
          <p className="text-theme-secondary mt-1">
            Manage authentication services for background jobs and integrations
          </p>
        </div>
        <button
          onClick={() => setState(prev => ({ ...prev, showCreateModal: true }))}
          className="bg-theme-interactive-primary text-white px-6 py-3 rounded-lg font-medium hover:bg-theme-interactive-primary-hover transition-colors flex items-center gap-2 shadow-lg"
        >
          <span>✨</span>
          <span>Create Service</span>
        </button>
      </div>

      {/* Statistics Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <div className="bg-theme-surface rounded-xl p-6 border border-theme">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-theme-secondary text-sm">Total Services</p>
              <p className="text-2xl font-bold text-theme-primary">{state.stats.total}</p>
            </div>
            <div className="w-12 h-12 bg-blue-100 rounded-lg flex items-center justify-center">
              <span className="text-xl">🔧</span>
            </div>
          </div>
        </div>

        <div className="bg-theme-surface rounded-xl p-6 border border-theme">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-theme-secondary text-sm">Active Services</p>
              <p className="text-2xl font-bold text-green-600">{state.stats.active_count}</p>
            </div>
            <div className="w-12 h-12 bg-green-100 rounded-lg flex items-center justify-center">
              <span className="text-xl">✅</span>
            </div>
          </div>
        </div>

        <div className="bg-theme-surface rounded-xl p-6 border border-theme">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-theme-secondary text-sm">Recently Active</p>
              <p className="text-2xl font-bold text-blue-600">{state.stats.recent_activity_count}</p>
            </div>
            <div className="w-12 h-12 bg-blue-100 rounded-lg flex items-center justify-center">
              <span className="text-xl">⚡</span>
            </div>
          </div>
        </div>

        <div className="bg-theme-surface rounded-xl p-6 border border-theme">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-theme-secondary text-sm">Account Services</p>
              <p className="text-2xl font-bold text-theme-link">{state.stats.account_services}</p>
            </div>
            <div className="w-12 h-12 bg-purple-100 rounded-lg flex items-center justify-center">
              <span className="text-xl">👥</span>
            </div>
          </div>
        </div>
      </div>

      {/* Filters and Search */}
      <div className="bg-theme-surface rounded-xl p-6 border border-theme">
        <div className="flex flex-col lg:flex-row lg:items-center gap-4">
          <div className="flex-1">
            <input
              type="text"
              placeholder="Search services by name, description, or account..."
              value={state.searchTerm}
              onChange={(e) => setState(prev => ({ ...prev, searchTerm: e.target.value }))}
              className="w-full px-4 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-focus focus:border-transparent"
            />
          </div>
          
          <div className="flex items-center gap-4">
            <select
              value={state.filterStatus}
              onChange={(e) => setState(prev => ({ ...prev, filterStatus: e.target.value as any }))}
              className="px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-focus focus:border-transparent"
            >
              <option value="all">All Statuses</option>
              <option value="active">Active</option>
              <option value="suspended">Suspended</option>
              <option value="revoked">Revoked</option>
            </select>

            <div className="flex items-center border border-theme rounded-lg bg-theme-background">
              <button
                onClick={() => setState(prev => ({ ...prev, viewMode: 'grid' }))}
                className={`p-2 ${state.viewMode === 'grid' ? 'bg-theme-interactive-primary text-white' : 'text-theme-secondary'} rounded-l-lg transition-colors`}
              >
                ⊞
              </button>
              <button
                onClick={() => setState(prev => ({ ...prev, viewMode: 'list' }))}
                className={`p-2 ${state.viewMode === 'list' ? 'bg-theme-interactive-primary text-white' : 'text-theme-secondary'} rounded-r-lg transition-colors`}
              >
                ☰
              </button>
            </div>
          </div>
        </div>
      </div>

      {/* Error Display */}
      {state.error && (
        <div className="bg-red-50 border border-red-200 rounded-xl p-4">
          <div className="flex items-center gap-3">
            <span className="text-red-500 text-xl">⚠️</span>
            <div>
              <p className="text-red-700 font-medium">Error Loading Services</p>
              <p className="text-red-600 text-sm">{state.error}</p>
            </div>
            <button
              onClick={loadServices}
              className="ml-auto bg-red-100 text-red-700 px-3 py-1 rounded-lg text-sm hover:bg-red-200 transition-colors"
            >
              Retry
            </button>
          </div>
        </div>
      )}

      {/* Services Grid/List */}
      {filteredServices.length === 0 ? (
        <div className="bg-theme-surface rounded-xl p-12 text-center border border-theme">
          <div className="text-6xl mb-4">🔧</div>
          <h3 className="text-xl font-semibold text-theme-primary mb-2">No Services Found</h3>
          <p className="text-theme-secondary mb-6">
            {state.searchTerm || state.filterStatus !== 'all' 
              ? 'No services match your current filters' 
              : 'Get started by creating your first service'}
          </p>
          {!state.searchTerm && state.filterStatus === 'all' && (
            <button
              onClick={() => setState(prev => ({ ...prev, showCreateModal: true }))}
              className="bg-theme-interactive-primary text-white px-6 py-3 rounded-lg font-medium hover:bg-theme-interactive-primary-hover transition-colors"
            >
              ✨ Create Your First Service
            </button>
          )}
        </div>
      ) : (
        <div className={`grid gap-6 ${
          state.viewMode === 'grid' 
            ? 'grid-cols-1 lg:grid-cols-2 xl:grid-cols-3' 
            : 'grid-cols-1'
        }`}>
          {filteredServices.map((service) => (
            <ServiceCard
              key={service.id}
              service={service}
              onView={handleServiceView}
              onEdit={handleServiceEdit}
              onDelete={handleServiceDelete}
              onStatusChange={handleStatusChange}
              onTokenRegenerate={handleTokenRegenerate}
            />
          ))}
        </div>
      )}

      {/* Create Service Modal */}
      {state.showCreateModal && (
        <CreateServiceModal
          onClose={() => setState(prev => ({ ...prev, showCreateModal: false }))}
          onCreate={handleServiceCreate}
        />
      )}

      {/* Delete Confirmation Modal */}
      {state.showDeleteModal && state.selectedService && (
        <div className="fixed inset-0 z-50 overflow-y-auto bg-black bg-opacity-50 flex items-center justify-center p-4">
          <div className="bg-theme-surface rounded-xl max-w-md w-full p-6 shadow-2xl">
            <div className="text-center">
              <div className="text-4xl mb-4">🗑️</div>
              <h2 className="text-xl font-semibold text-theme-primary mb-2">Delete Service</h2>
              <p className="text-theme-secondary mb-6">
                Are you sure you want to delete "{state.selectedService.name}"? This action cannot be undone.
              </p>
              <div className="flex items-center gap-3">
                <button
                  onClick={confirmDelete}
                  className="flex-1 bg-red-600 text-white py-2 px-4 rounded-lg font-medium hover:bg-red-700 transition-colors"
                >
                  Delete Service
                </button>
                <button
                  onClick={() => setState(prev => ({ ...prev, showDeleteModal: false, selectedService: null }))}
                  className="flex-1 bg-theme-background text-theme-primary py-2 px-4 rounded-lg font-medium hover:bg-theme-surface transition-colors border border-theme"
                >
                  Cancel
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default ServicesPage;