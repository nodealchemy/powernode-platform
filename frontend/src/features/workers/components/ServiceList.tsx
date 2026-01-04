import React, { useState } from 'react';
import { Service } from '@/shared/services/serviceApi';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface ServiceListProps {
  services: Service[];
  selectedService: Service | null;
  onServiceSelect: (service: Service) => void;
  onServiceDelete: (serviceId: string) => Promise<void>;
  onTokenRegenerate: (serviceId: string) => Promise<string>;
  onStatusChange: (serviceId: string, action: 'suspend' | 'activate' | 'revoke') => Promise<void>;
}

interface ServiceItemProps {
  service: Service;
  isSelected: boolean;
  onSelect: () => void;
  onDelete: () => Promise<void>;
  onTokenRegenerate: () => Promise<string>;
  onStatusChange: (action: 'suspend' | 'activate' | 'revoke') => Promise<void>;
}

const ServiceItem: React.FC<ServiceItemProps> = ({
  service,
  isSelected,
  onSelect,
  onDelete,
  onTokenRegenerate,
  onStatusChange
}) => {
  const { addNotification } = useNotifications();
  const { confirm, ConfirmationDialog } = useConfirmation();
  const [showActions, setShowActions] = useState(false);
  const [loading, setLoading] = useState<string | null>(null);

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'active':
        return 'bg-theme-success text-theme-success border border-theme';
      case 'suspended':
        return 'bg-theme-warning text-theme-warning border border-theme';
      case 'revoked':
        return 'bg-theme-error text-theme-error border border-theme';
      default:
        return 'bg-theme-background-secondary text-theme-secondary border border-theme';
    }
  };

  const getPermissionColor = (permission: string) => {
    switch (permission) {
      case 'readonly':
        return 'bg-theme-info text-theme-info border border-theme';
      case 'standard':
        return 'bg-theme-success text-theme-success border border-theme';
      case 'admin':
        return 'bg-theme-warning text-theme-warning border border-theme';
      case 'super_admin':
        return 'bg-theme-error text-theme-error border border-theme';
      default:
        return 'bg-theme-background-secondary text-theme-secondary border border-theme';
    }
  };

  const handleAction = async (action: () => Promise<void | string>, loadingKey: string) => {
    try {
      setLoading(loadingKey);
      await action();
      setShowActions(false);
    } catch (error: unknown) {
      const errorMessage = error instanceof Error ? error.message : 'Operation failed';
      addNotification({ type: 'error', message: errorMessage });
    } finally {
      setLoading(null);
    }
  };

  return (
    <div
      className={`p-4 border-b border-theme cursor-pointer hover:bg-theme-surface-hover relative ${
        isSelected ? 'bg-theme-surface-selected border-theme-focus' : ''
      }`}
      onClick={onSelect}
    >
      <div className="flex items-start justify-between">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-2">
            <h3 className="text-sm font-medium text-theme-primary truncate">
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
            <span className="text-xs text-theme-tertiary">•</span>
            <span className="text-xs text-theme-secondary">{service.account_name}</span>
          </div>
          
          {service.description && (
            <p className="text-xs text-theme-secondary mb-2 line-clamp-2">
              {service.description}
            </p>
          )}
          
          <div className="flex items-center gap-4 text-xs text-theme-secondary">
            <span>Requests: {service.request_count}</span>
            {service.active_recently ? (
              <span className="flex items-center gap-1 text-theme-success">
                <div className="w-2 h-2 bg-theme-success rounded-full"></div>
                Active
              </span>
            ) : (
              <span className="text-theme-tertiary">Inactive</span>
            )}
          </div>
        </div>
        
        <div className="relative">
          <button
            onClick={(e) => {
              e.stopPropagation();
              setShowActions(!showActions);
            }}className="p-1 text-theme-tertiary hover:text-theme-primary rounded transition-colors duration-200"
          >
            <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
              <path d="M10 6a2 2 0 110-4 2 2 0 010 4zM10 12a2 2 0 110-4 2 2 0 010 4zM10 18a2 2 0 110-4 2 2 0 010 4z" />
            </svg>
          </button>
          
          {showActions && (
            <div className="absolute right-0 mt-2 w-48 bg-theme-surface rounded-md shadow-lg border border-theme z-10">
              <div className="py-1">
                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    handleAction(() => onTokenRegenerate(), 'regenerate');
                  }}
                  disabled={loading === 'regenerate'}
                  className="block w-full text-left px-4 py-2 text-sm text-theme-primary hover:bg-theme-surface-hover disabled:opacity-50 transition-colors duration-150"
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
                    className="block w-full text-left px-4 py-2 text-sm text-theme-warning hover:bg-theme-surface-hover disabled:opacity-50 transition-colors duration-150"
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
                    className="block w-full text-left px-4 py-2 text-sm text-theme-success hover:bg-theme-surface-hover disabled:opacity-50 transition-colors duration-150"
                  >
                    {loading === 'activate' ? 'Activating...' : 'Activate'}
                  </button>
                )}
                
                {service.status !== 'revoked' && (
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      confirm({
                        title: 'Revoke Service',
                        message: `Are you sure you want to revoke "${service.name}"? This action cannot be undone.`,
                        confirmLabel: 'Revoke',
                        variant: 'danger',
                        onConfirm: async () => {
                          await handleAction(() => onStatusChange('revoke'), 'revoke');
                        }
                      });
                    }}
                    disabled={loading === 'revoke'}
                    className="block w-full text-left px-4 py-2 text-sm text-theme-error hover:bg-theme-surface-hover disabled:opacity-50 transition-colors duration-150"
                  >
                    {loading === 'revoke' ? 'Revoking...' : 'Revoke'}
                  </button>
                )}

                <div className="border-t border-theme my-1"></div>

                <button
                  onClick={(e) => {
                    e.stopPropagation();
                    confirm({
                      title: 'Delete Service',
                      message: `Are you sure you want to delete "${service.name}"? This action cannot be undone.`,
                      confirmLabel: 'Delete',
                      variant: 'danger',
                      onConfirm: async () => {
                        await handleAction(() => onDelete(), 'delete');
                      }
                    });
                  }}
                  disabled={loading === 'delete'}
                  className="block w-full text-left px-4 py-2 text-sm text-theme-error hover:bg-theme-surface-hover disabled:opacity-50"
                >
                  {loading === 'delete' ? 'Deleting...' : 'Delete'}
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
      
      {loading && (
        <div className="absolute inset-0 bg-theme-surface bg-opacity-75 flex items-center justify-center">
          <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-theme-interactive-primary"></div>
        </div>
      )}
      {ConfirmationDialog}
    </div>
  );
};

export const ServiceList: React.FC<ServiceListProps> = ({
  services,
  selectedService,
  onServiceSelect,
  onServiceDelete,
  onTokenRegenerate,
  onStatusChange
}) => {
  if (services.length === 0) {
    return (
      <div className="flex items-center justify-center h-64 text-theme-secondary">
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
      <div className="p-4 sm:p-6 lg:p-8 border-b border-theme bg-theme-background-secondary">
        <h2 className="text-lg font-medium text-theme-primary">Services ({services.length})</h2>
      </div>
      
      <div>
        {services.map((service) => (
          <ServiceItem
            key={service.id}
            service={service}
            isSelected={selectedService?.id === service.id}
            onSelect={() => onServiceSelect(service)}
            onDelete={() => onServiceDelete(service.id)}
            onTokenRegenerate={() => onTokenRegenerate(service.id)}
            onStatusChange={(action) => onStatusChange(service.id, action)}
          />
        ))}
      </div>
    </div>
  );
};

