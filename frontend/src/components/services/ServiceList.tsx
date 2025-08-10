import React, { useState } from 'react';
import { Service } from '../../services/serviceApi';

interface ServiceListProps {
  services: Service[];
  selectedService: Service | null;
  onServiceSelect: (service: Service) => void;
  onServiceUpdate: (serviceId: string, data: any) => Promise<any>;
  onServiceDelete: (serviceId: string) => Promise<void>;
  onTokenRegenerate: (serviceId: string) => Promise<string>;
  onStatusChange: (serviceId: string, action: 'suspend' | 'activate' | 'revoke') => Promise<any>;
}

interface ServiceItemProps {
  service: Service;
  isSelected: boolean;
  onSelect: () => void;
  onUpdate: (data: any) => Promise<any>;
  onDelete: () => Promise<void>;
  onTokenRegenerate: () => Promise<string>;
  onStatusChange: (action: 'suspend' | 'activate' | 'revoke') => Promise<any>;
}

const ServiceItem: React.FC<ServiceItemProps> = ({
  service,
  isSelected,
  onSelect,
  onUpdate,
  onDelete,
  onTokenRegenerate,
  onStatusChange
}) => {
  const [showActions, setShowActions] = useState(false);
  const [loading, setLoading] = useState<string | null>(null);

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'active':
        return 'bg-green-100 text-green-800';
      case 'suspended':
        return 'bg-yellow-100 text-yellow-800';
      case 'revoked':
        return 'bg-red-100 text-red-800';
      default:
        return 'bg-gray-100 text-gray-800';
    }
  };

  const getPermissionColor = (permission: string) => {
    switch (permission) {
      case 'readonly':
        return 'bg-blue-100 text-blue-800';
      case 'standard':
        return 'bg-green-100 text-green-800';
      case 'admin':
        return 'bg-orange-100 text-orange-800';
      case 'super_admin':
        return 'bg-red-100 text-red-800';
      default:
        return 'bg-gray-100 text-gray-800';
    }
  };

  const handleAction = async (action: () => Promise<any>, loadingKey: string) => {
    try {
      setLoading(loadingKey);
      await action();
      setShowActions(false);
    } catch (error: any) {
      alert(error.message);
    } finally {
      setLoading(null);
    }
  };

  return (
    <div
      className={`p-4 border-b border-gray-200 cursor-pointer hover:bg-gray-50 relative ${
        isSelected ? 'bg-blue-50 border-blue-200' : ''
      }`}
      onClick={onSelect}
    >
      <div className="flex items-start justify-between">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-2">
            <h3 className="text-sm font-medium text-gray-900 truncate">
              {service.name}
            </h3>
            <span className={`px-2 py-1 text-xs rounded-full ${getStatusColor(service.status)}`}>
              {service.status}
            </span>
          </div>
          
          <div className="flex items-center gap-2 mb-1">
            <span className={`px-2 py-1 text-xs rounded ${getPermissionColor(service.permissions)}`}>
              {service.permissions}
            </span>
            <span className="text-xs text-gray-500">•</span>
            <span className="text-xs text-gray-500">{service.account_name}</span>
          </div>
          
          {service.description && (
            <p className="text-xs text-gray-600 mb-2 line-clamp-2">
              {service.description}
            </p>
          )}
          
          <div className="flex items-center gap-4 text-xs text-gray-500">
            <span>Requests: {service.request_count}</span>
            {service.active_recently ? (
              <span className="flex items-center gap-1 text-green-600">
                <div className="w-2 h-2 bg-green-500 rounded-full"></div>
                Active
              </span>
            ) : (
              <span className="text-gray-400">Inactive</span>
            )}
          </div>
        </div>
        
        <div className="relative">
          <button
            onClick={(e) => {
              e.stopPropagation();
              setShowActions(!showActions);
            }}
            className="p-1 text-gray-400 hover:text-gray-600 rounded"
          >
            <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
              <path d="M10 6a2 2 0 110-4 2 2 0 010 4zM10 12a2 2 0 110-4 2 2 0 010 4zM10 18a2 2 0 110-4 2 2 0 010 4z" />
            </svg>
          </button>
          
          {showActions && (
            <div className="absolute right-0 mt-2 w-48 bg-white rounded-md shadow-lg border border-gray-200 z-10">
              <div className="py-1">
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    handleAction(() => onTokenRegenerate(), 'regenerate');
                  }}
                  disabled={loading === 'regenerate'}
                  className="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 disabled:opacity-50"
                >
                  {loading === 'regenerate' ? 'Regenerating...' : 'Regenerate Token'}
                </button>
                
                {service.status === 'active' && (
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      handleAction(() => onStatusChange('suspend'), 'suspend');
                    }}
                    disabled={loading === 'suspend'}
                    className="block w-full text-left px-4 py-2 text-sm text-yellow-700 hover:bg-gray-50 disabled:opacity-50"
                  >
                    {loading === 'suspend' ? 'Suspending...' : 'Suspend'}
                  </button>
                )}
                
                {service.status === 'suspended' && (
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      handleAction(() => onStatusChange('activate'), 'activate');
                    }}
                    disabled={loading === 'activate'}
                    className="block w-full text-left px-4 py-2 text-sm text-green-700 hover:bg-gray-50 disabled:opacity-50"
                  >
                    {loading === 'activate' ? 'Activating...' : 'Activate'}
                  </button>
                )}
                
                {service.status !== 'revoked' && (
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      if (window.confirm(`Are you sure you want to revoke "${service.name}"? This action cannot be undone.`)) {
                        handleAction(() => onStatusChange('revoke'), 'revoke');
                      }
                    }}
                    disabled={loading === 'revoke'}
                    className="block w-full text-left px-4 py-2 text-sm text-red-700 hover:bg-gray-50 disabled:opacity-50"
                  >
                    {loading === 'revoke' ? 'Revoking...' : 'Revoke'}
                  </button>
                )}
                
                <div className="border-t border-gray-100 my-1"></div>
                
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    if (window.confirm(`Are you sure you want to delete "${service.name}"? This action cannot be undone.`)) {
                      handleAction(() => onDelete(), 'delete');
                    }
                  }}
                  disabled={loading === 'delete'}
                  className="block w-full text-left px-4 py-2 text-sm text-red-700 hover:bg-gray-50 disabled:opacity-50"
                >
                  {loading === 'delete' ? 'Deleting...' : 'Delete'}
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
      
      {loading && (
        <div className="absolute inset-0 bg-white bg-opacity-75 flex items-center justify-center">
          <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-blue-600"></div>
        </div>
      )}
    </div>
  );
};

export const ServiceList: React.FC<ServiceListProps> = ({
  services,
  selectedService,
  onServiceSelect,
  onServiceUpdate,
  onServiceDelete,
  onTokenRegenerate,
  onStatusChange
}) => {
  if (services.length === 0) {
    return (
      <div className="flex items-center justify-center h-64 text-gray-500">
        <div className="text-center">
          <div className="text-3xl mb-3">🔧</div>
          <p className="text-lg font-medium">No services found</p>
          <p className="text-sm mt-1">Create your first worker service to get started</p>
        </div>
      </div>
    );
  }

  return (
    <div className="h-full overflow-y-auto">
      <div className="p-4 border-b border-gray-200 bg-gray-50">
        <h2 className="text-lg font-medium text-gray-900">Services ({services.length})</h2>
      </div>
      
      <div>
        {services.map((service) => (
          <ServiceItem
            key={service.id}
            service={service}
            isSelected={selectedService?.id === service.id}
            onSelect={() => onServiceSelect(service)}
            onUpdate={(data) => onServiceUpdate(service.id, data)}
            onDelete={() => onServiceDelete(service.id)}
            onTokenRegenerate={() => onTokenRegenerate(service.id)}
            onStatusChange={(action) => onStatusChange(service.id, action)}
          />
        ))}
      </div>
    </div>
  );
};

export default ServiceList;