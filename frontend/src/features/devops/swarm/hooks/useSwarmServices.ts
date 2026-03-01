import { useState, useEffect, useCallback } from 'react';
import { swarmApi } from '../services/swarmApi';
import type {
  SwarmServiceSummary,
  SwarmService,
  ServiceFormData,
  ServiceScaleData,
  ServiceFilters,
} from '../types';

interface UseSwarmServicesOptions {
  clusterId: string;
  filters?: ServiceFilters;
  autoLoad?: boolean;
}

interface UseSwarmServicesResult {
  services: SwarmServiceSummary[];
  isLoading: boolean;
  error: string | null;
  refetch: () => Promise<void>;
  createService: (data: ServiceFormData) => Promise<SwarmService | null>;
  updateService: (serviceId: string, data: Partial<ServiceFormData>) => Promise<SwarmService | null>;
  deleteService: (serviceId: string) => Promise<boolean>;
  scaleService: (serviceId: string, data: ServiceScaleData) => Promise<boolean>;
  rollbackService: (serviceId: string) => Promise<boolean>;
}

export function useSwarmServices(options: UseSwarmServicesOptions): UseSwarmServicesResult {
  const { clusterId, filters, autoLoad = true } = options;
  const [services, setServices] = useState<SwarmServiceSummary[]>([]);
  const [isLoading, setIsLoading] = useState(autoLoad);
  const [error, setError] = useState<string | null>(null);

  const fetchServices = useCallback(async () => {
    if (!clusterId) return;

    setIsLoading(true);
    setError(null);

    const response = await swarmApi.getServices(clusterId, filters);

    if (response.success && response.data) {
      setServices(response.data.items ?? []);
    } else {
      setError(response.error || 'Failed to fetch services');
    }

    setIsLoading(false);
  }, [clusterId, filters]);

  useEffect(() => {
    if (autoLoad) {
      fetchServices();
    }
  }, [fetchServices, autoLoad]);

  const createService = useCallback(async (data: ServiceFormData): Promise<SwarmService | null> => {
    const response = await swarmApi.createService(clusterId, data);
    if (response.success && response.data) {
      await fetchServices();
      return response.data.service;
    }
    setError(response.error || 'Failed to create service');
    return null;
  }, [clusterId, fetchServices]);

  const updateService = useCallback(async (serviceId: string, data: Partial<ServiceFormData>): Promise<SwarmService | null> => {
    const response = await swarmApi.updateService(clusterId, serviceId, data);
    if (response.success && response.data) {
      await fetchServices();
      return response.data.service;
    }
    setError(response.error || 'Failed to update service');
    return null;
  }, [clusterId, fetchServices]);

  const deleteService = useCallback(async (serviceId: string): Promise<boolean> => {
    const response = await swarmApi.deleteService(clusterId, serviceId);
    if (response.success) {
      await fetchServices();
      return true;
    }
    setError(response.error || 'Failed to delete service');
    return false;
  }, [clusterId, fetchServices]);

  const scaleService = useCallback(async (serviceId: string, data: ServiceScaleData): Promise<boolean> => {
    const response = await swarmApi.scaleService(clusterId, serviceId, data);
    if (response.success) {
      await fetchServices();
      return true;
    }
    setError(response.error || 'Failed to scale service');
    return false;
  }, [clusterId, fetchServices]);

  const rollbackService = useCallback(async (serviceId: string): Promise<boolean> => {
    const response = await swarmApi.rollbackService(clusterId, serviceId);
    if (response.success) {
      await fetchServices();
      return true;
    }
    setError(response.error || 'Failed to rollback service');
    return false;
  }, [clusterId, fetchServices]);

  return {
    services,
    isLoading,
    error,
    refetch: fetchServices,
    createService,
    updateService,
    deleteService,
    scaleService,
    rollbackService,
  };
}
