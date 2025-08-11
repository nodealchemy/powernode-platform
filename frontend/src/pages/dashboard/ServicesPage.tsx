import React, { useState, useEffect } from 'react';
import { serviceAPI, Service } from '../../services/serviceApi';
import { ServiceList } from '../../components/services/ServiceList';
import { ServiceDetails } from '../../components/services/ServiceDetails';
import { CreateServiceModal } from '../../components/services/CreateServiceModal';
import { LoadingSpinner } from '../../components/common/LoadingSpinner';

interface ServicesPageState {
  services: Service[];
  selectedService: Service | null;
  loading: boolean;
  error: string | null;
  showCreateModal: boolean;
  stats: {
    total: number;
    account_services: number;
  };
}

export const ServicesPage: React.FC = () => {
  const [state, setState] = useState<ServicesPageState>({
    services: [],
    selectedService: null,
    loading: true,
    error: null,
    showCreateModal: false,
    stats: {
      total: 0,
      account_services: 0
    }
  });

  const loadServices = async () => {
    try {
      setState(prev => ({ ...prev, loading: true, error: null }));
      const response = await serviceAPI.getServices();
      setState(prev => ({
        ...prev,
        services: response.services,
        stats: {
          total: response.total,
          account_services: response.account_services
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

  const handleServiceSelect = (service: Service) => {
    setState(prev => ({ ...prev, selectedService: service }));
  };

  const handleServiceCreate = async (serviceData: any) => {
    try {
      await serviceAPI.createService(serviceData);
      await loadServices();
      setState(prev => ({ ...prev, showCreateModal: false }));
    } catch (error: any) {
      throw new Error(error.response?.data?.error || 'Failed to create service');
    }
  };

  const handleServiceUpdate = async (serviceId: string, data: any) => {
    try {
      const response = await serviceAPI.updateService(serviceId, data);
      setState(prev => ({
        ...prev,
        services: prev.services.map(s => s.id === serviceId ? response.service : s),
        selectedService: prev.selectedService?.id === serviceId ? response.service : prev.selectedService
      }));
      return response;
    } catch (error: any) {
      throw new Error(error.response?.data?.error || 'Failed to update service');
    }
  };

  const handleServiceDelete = async (serviceId: string) => {
    try {
      await serviceAPI.deleteService(serviceId);
      setState(prev => ({
        ...prev,
        services: prev.services.filter(s => s.id !== serviceId),
        selectedService: prev.selectedService?.id === serviceId ? null : prev.selectedService
      }));
    } catch (error: any) {
      throw new Error(error.response?.data?.error || 'Failed to delete service');
    }
  };

  const handleTokenRegenerate = async (serviceId: string) => {
    try {
      const response = await serviceAPI.regenerateToken(serviceId);
      setState(prev => ({
        ...prev,
        services: prev.services.map(s => s.id === serviceId ? response.service : s),
        selectedService: prev.selectedService?.id === serviceId ? response.service : prev.selectedService
      }));
      return response.new_token;
    } catch (error: any) {
      throw new Error(error.response?.data?.error || 'Failed to regenerate token');
    }
  };

  const handleStatusChange = async (serviceId: string, action: 'suspend' | 'activate' | 'revoke') => {
    try {
      let response: { service: Service; message: string };
      switch (action) {
        case 'suspend':
          response = await serviceAPI.suspendService(serviceId);
          break;
        case 'activate':
          response = await serviceAPI.activateService(serviceId);
          break;
        case 'revoke':
          response = await serviceAPI.revokeService(serviceId);
          break;
        default:
          throw new Error(`Unknown action: ${action}`);
      }
      
      setState(prev => ({
        ...prev,
        services: prev.services.map(s => s.id === serviceId ? response.service : s),
        selectedService: prev.selectedService?.id === serviceId ? response.service : prev.selectedService
      }));
      return response;
    } catch (error: any) {
      throw new Error(error.response?.data?.error || `Failed to ${action} service`);
    }
  };

  if (state.loading) {
    return <LoadingSpinner message="Loading services..." />;
  }

  return (
    <div className="min-h-screen bg-theme-background-secondary">
      {/* Header */}
      <div className="bg-theme-surface shadow">
        <div className="px-4 sm:px-6 lg:px-8 py-4">
          <div className="flex items-center justify-between">
            <div>
              <h1 className="text-2xl font-bold text-theme-primary">Services</h1>
              <p className="text-sm text-theme-secondary mt-1">
                Manage authentication services for background jobs and integrations
              </p>
            </div>
            <button
              onClick={() => setState(prev => ({ ...prev, showCreateModal: true }))}
              className="bg-theme-interactive-primary text-white px-4 py-2 rounded-md text-sm font-medium hover:bg-theme-interactive-primary-hover transition-colors duration-200"
            >
              Create Service
            </button>
          </div>
          
          {/* Stats */}
          <div className="flex gap-6 mt-4">
            <div className="text-sm">
              <span className="text-theme-secondary">Total Services:</span>
              <span className="ml-2 font-semibold text-theme-primary">{state.stats.total}</span>
            </div>
            <div className="text-sm">
              <span className="text-theme-secondary">Account Services:</span>
              <span className="ml-2 font-semibold text-theme-link">{state.stats.account_services}</span>
            </div>
          </div>
        </div>
      </div>

      {/* Error Display */}
      {state.error && (
        <div className="mx-4 sm:mx-6 lg:px-8 mt-4 p-4 bg-theme-error rounded-md border border-theme">
          <p className="text-theme-error text-sm">{state.error}</p>
          <button
            onClick={loadServices}
            className="mt-2 text-theme-error hover:text-theme-error text-sm underline opacity-80 hover:opacity-100 transition-opacity duration-150"
          >
            Try again
          </button>
        </div>
      )}

      {/* Main Content */}
      <div className="flex-1 flex">
        {/* Services List */}
        <div className="w-1/3 bg-theme-surface border-r border-theme">
          <ServiceList
            services={state.services}
            selectedService={state.selectedService}
            onServiceSelect={handleServiceSelect}
            onServiceUpdate={handleServiceUpdate}
            onServiceDelete={handleServiceDelete}
            onTokenRegenerate={handleTokenRegenerate}
            onStatusChange={handleStatusChange}
          />
        </div>

        {/* Service Details */}
        <div className="flex-1">
          {state.selectedService ? (
            <ServiceDetails
              service={state.selectedService}
              onServiceUpdate={handleServiceUpdate}
              onTokenRegenerate={handleTokenRegenerate}
              onStatusChange={handleStatusChange}
            />
          ) : (
            <div className="flex items-center justify-center h-full text-theme-secondary">
              <div className="text-center">
                <div className="text-4xl mb-4">🔧</div>
                <p className="text-lg font-medium">Select a service to view details</p>
                <p className="text-sm mt-2">Choose a service from the list to see its configuration and activity</p>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Create Service Modal */}
      {state.showCreateModal && (
        <CreateServiceModal
          onClose={() => setState(prev => ({ ...prev, showCreateModal: false }))}
          onCreate={handleServiceCreate}
        />
      )}
    </div>
  );
};

export default ServicesPage;