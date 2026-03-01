import { api } from '@/shared/services/api';
import type {
  DockerHostSummary,
  DockerHost,
  HostFormData,
  HostHealthSummary,
  HostFilters,
  DockerContainerSummary,
  DockerContainer,
  ContainerCreateData,
  ContainerStats,
  ContainerFilters,
  ContainerLogEntry,
  ContainerLogOptions,
  DockerImageSummary,
  DockerImage,
  ImagePullData,
  ImageTagData,
  ImageFilters,
  DockerActivitySummary,
  DockerActivity,
  ActivityFilters,
  DockerEventSummary,
  DockerEvent,
  EventFilters,
  DockerNetwork,
  NetworkFormData,
  DockerVolume,
  VolumeFormData,
  RegistryInfo,
  AvailableDockerContainer,
  AvailableDockerImage,
  ApiResponse,
  Pagination,
  HostStatus,
  ContainerState,
  ActivityStatus,
  EventSeverity,
} from '../types';

const handleApiError = (error: unknown, defaultMessage: string): string => {
  if (error && typeof error === 'object' && 'response' in error) {
    return (error as { response?: { data?: { error?: string } } }).response?.data?.error || defaultMessage;
  }
  return defaultMessage;
};

const buildParams = (params: Record<string, unknown>): URLSearchParams => {
  const searchParams = new URLSearchParams();
  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && value !== null && value !== '') {
      searchParams.set(key, String(value));
    }
  });
  return searchParams;
};

export const dockerApi = {
  // ==================== Hosts ====================

  async getHosts(
    page = 1,
    perPage = 20,
    filters?: HostFilters
  ): Promise<ApiResponse<{ items: DockerHostSummary[]; pagination: Pagination }>> {
    try {
      const params = buildParams({
        page,
        per_page: perPage,
        ...filters,
      });
      const response = await api.get(`/devops/docker/hosts?${params}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch hosts') };
    }
  },

  async getHost(id: string): Promise<ApiResponse<{ host: DockerHost }>> {
    try {
      const response = await api.get(`/devops/docker/hosts/${id}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch host') };
    }
  },

  async createHost(data: HostFormData): Promise<ApiResponse<{ host: DockerHost }>> {
    try {
      const response = await api.post('/devops/docker/hosts', { host: data });
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to create host') };
    }
  },

  async updateHost(id: string, data: Partial<HostFormData>): Promise<ApiResponse<{ host: DockerHost }>> {
    try {
      const response = await api.patch(`/devops/docker/hosts/${id}`, { host: data });
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to update host') };
    }
  },

  async deleteHost(id: string): Promise<ApiResponse<{ message: string }>> {
    try {
      const response = await api.delete(`/devops/docker/hosts/${id}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to delete host') };
    }
  },

  async testHostConnection(id: string): Promise<ApiResponse<{ connected: boolean; message: string; response_time_ms: number }>> {
    try {
      const response = await api.post(`/devops/docker/hosts/${id}/test_connection`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to test connection') };
    }
  },

  async syncHost(id: string): Promise<ApiResponse<{ message: string; synced_at: string }>> {
    try {
      const response = await api.post(`/devops/docker/hosts/${id}/sync`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to sync host') };
    }
  },

  async getHostHealth(id: string): Promise<ApiResponse<{ health: HostHealthSummary }>> {
    try {
      const response = await api.get(`/devops/docker/hosts/${id}/health`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch host health') };
    }
  },

  // ==================== Containers ====================

  async getContainers(
    hostId: string,
    filters?: ContainerFilters
  ): Promise<ApiResponse<{ items: DockerContainerSummary[] }>> {
    try {
      const params = buildParams({ ...filters });
      const response = await api.get(`/devops/docker/hosts/${hostId}/containers?${params}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch containers') };
    }
  },

  async getAvailableContainers(hostId: string): Promise<ApiResponse<{ items: AvailableDockerContainer[] }>> {
    try {
      const response = await api.get(`/devops/docker/hosts/${hostId}/containers/available`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch available containers') };
    }
  },

  async importContainers(hostId: string, dockerContainerIds: string[]): Promise<ApiResponse<{ items: DockerContainerSummary[]; imported_count: number }>> {
    try {
      const response = await api.post(`/devops/docker/hosts/${hostId}/containers/import`, { docker_container_ids: dockerContainerIds });
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to import containers') };
    }
  },

  async getContainer(hostId: string, containerId: string): Promise<ApiResponse<{ container: DockerContainer }>> {
    try {
      const response = await api.get(`/devops/docker/hosts/${hostId}/containers/${containerId}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch container') };
    }
  },

  async createContainer(hostId: string, data: ContainerCreateData): Promise<ApiResponse<{ container: DockerContainer }>> {
    try {
      const response = await api.post(`/devops/docker/hosts/${hostId}/containers`, { container: data });
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to create container') };
    }
  },

  async deleteContainer(hostId: string, containerId: string): Promise<ApiResponse<{ message: string }>> {
    try {
      const response = await api.delete(`/devops/docker/hosts/${hostId}/containers/${containerId}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to delete container') };
    }
  },

  async startContainer(hostId: string, containerId: string): Promise<ApiResponse<{ container: DockerContainer }>> {
    try {
      const response = await api.post(`/devops/docker/hosts/${hostId}/containers/${containerId}/start`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to start container') };
    }
  },

  async stopContainer(hostId: string, containerId: string): Promise<ApiResponse<{ container: DockerContainer }>> {
    try {
      const response = await api.post(`/devops/docker/hosts/${hostId}/containers/${containerId}/stop`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to stop container') };
    }
  },

  async restartContainer(hostId: string, containerId: string): Promise<ApiResponse<{ container: DockerContainer }>> {
    try {
      const response = await api.post(`/devops/docker/hosts/${hostId}/containers/${containerId}/restart`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to restart container') };
    }
  },

  async getContainerLogs(
    hostId: string,
    containerId: string,
    options?: ContainerLogOptions
  ): Promise<ApiResponse<{ items: ContainerLogEntry[] }>> {
    try {
      const params = buildParams({ ...options });
      const response = await api.get(`/devops/docker/hosts/${hostId}/containers/${containerId}/logs?${params}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch container logs') };
    }
  },

  async getContainerStats(hostId: string, containerId: string): Promise<ApiResponse<{ stats: ContainerStats }>> {
    try {
      const response = await api.get(`/devops/docker/hosts/${hostId}/containers/${containerId}/stats`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch container stats') };
    }
  },

  // ==================== Images ====================

  async getImages(
    hostId: string,
    filters?: ImageFilters
  ): Promise<ApiResponse<{ items: DockerImageSummary[] }>> {
    try {
      const params = buildParams({ ...filters });
      const response = await api.get(`/devops/docker/hosts/${hostId}/images?${params}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch images') };
    }
  },

  async getAvailableImages(hostId: string): Promise<ApiResponse<{ items: AvailableDockerImage[] }>> {
    try {
      const response = await api.get(`/devops/docker/hosts/${hostId}/images/available`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch available images') };
    }
  },

  async importImages(hostId: string, dockerImageIds: string[]): Promise<ApiResponse<{ items: DockerImageSummary[]; imported_count: number }>> {
    try {
      const response = await api.post(`/devops/docker/hosts/${hostId}/images/import`, { docker_image_ids: dockerImageIds });
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to import images') };
    }
  },

  async getImage(hostId: string, imageId: string): Promise<ApiResponse<{ image: DockerImage }>> {
    try {
      const response = await api.get(`/devops/docker/hosts/${hostId}/images/${imageId}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch image') };
    }
  },

  async deleteImage(hostId: string, imageId: string): Promise<ApiResponse<{ message: string }>> {
    try {
      const response = await api.delete(`/devops/docker/hosts/${hostId}/images/${imageId}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to delete image') };
    }
  },

  async pullImage(hostId: string, data: ImagePullData): Promise<ApiResponse<{ activity: DockerActivitySummary }>> {
    try {
      const response = await api.post(`/devops/docker/hosts/${hostId}/images/pull`, data);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to pull image') };
    }
  },

  async tagImage(hostId: string, imageId: string, data: ImageTagData): Promise<ApiResponse<{ image: DockerImage }>> {
    try {
      const response = await api.post(`/devops/docker/hosts/${hostId}/images/${imageId}/tag`, data);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to tag image') };
    }
  },

  async getRegistries(hostId: string): Promise<ApiResponse<{ items: RegistryInfo[] }>> {
    try {
      const response = await api.get(`/devops/docker/hosts/${hostId}/registries`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch registries') };
    }
  },

  // ==================== Networks ====================

  async getNetworks(hostId: string): Promise<ApiResponse<{ items: DockerNetwork[] }>> {
    try {
      const response = await api.get(`/devops/docker/hosts/${hostId}/networks`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch networks') };
    }
  },

  async createNetwork(hostId: string, data: NetworkFormData): Promise<ApiResponse<{ network: DockerNetwork }>> {
    try {
      const response = await api.post(`/devops/docker/hosts/${hostId}/networks`, { network: data });
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to create network') };
    }
  },

  async deleteNetwork(hostId: string, networkId: string): Promise<ApiResponse<{ message: string }>> {
    try {
      const response = await api.delete(`/devops/docker/hosts/${hostId}/networks/${networkId}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to delete network') };
    }
  },

  // ==================== Volumes ====================

  async getVolumes(hostId: string): Promise<ApiResponse<{ items: DockerVolume[] }>> {
    try {
      const response = await api.get(`/devops/docker/hosts/${hostId}/volumes`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch volumes') };
    }
  },

  async createVolume(hostId: string, data: VolumeFormData): Promise<ApiResponse<{ volume: DockerVolume }>> {
    try {
      const response = await api.post(`/devops/docker/hosts/${hostId}/volumes`, { volume: data });
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to create volume') };
    }
  },

  async deleteVolume(hostId: string, volumeName: string): Promise<ApiResponse<{ message: string }>> {
    try {
      const response = await api.delete(`/devops/docker/hosts/${hostId}/volumes/${volumeName}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to delete volume') };
    }
  },

  // ==================== Activities ====================

  async getActivities(
    hostId: string,
    page = 1,
    perPage = 20,
    filters?: ActivityFilters
  ): Promise<ApiResponse<{ items: DockerActivitySummary[]; pagination: Pagination }>> {
    try {
      const params = buildParams({
        page,
        per_page: perPage,
        ...filters,
      });
      const response = await api.get(`/devops/docker/hosts/${hostId}/activities?${params}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch activities') };
    }
  },

  async getActivity(hostId: string, activityId: string): Promise<ApiResponse<{ activity: DockerActivity }>> {
    try {
      const response = await api.get(`/devops/docker/hosts/${hostId}/activities/${activityId}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch activity') };
    }
  },

  // ==================== Events ====================

  async getEvents(
    hostId: string,
    page = 1,
    perPage = 50,
    filters?: EventFilters
  ): Promise<ApiResponse<{ items: DockerEventSummary[]; pagination: Pagination }>> {
    try {
      const params = buildParams({
        page,
        per_page: perPage,
        ...filters,
      });
      const response = await api.get(`/devops/docker/hosts/${hostId}/events?${params}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch events') };
    }
  },

  async getEvent(hostId: string, eventId: string): Promise<ApiResponse<{ event: DockerEvent }>> {
    try {
      const response = await api.get(`/devops/docker/hosts/${hostId}/events/${eventId}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch event') };
    }
  },

  async acknowledgeEvent(hostId: string, eventId: string): Promise<ApiResponse<{ event: DockerEvent }>> {
    try {
      const response = await api.post(`/devops/docker/hosts/${hostId}/events/${eventId}/acknowledge`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to acknowledge event') };
    }
  },

  // ==================== Helpers ====================

  getHostStatusColor(status: HostStatus): string {
    switch (status) {
      case 'connected':
        return 'bg-theme-success bg-opacity-10 text-theme-success';
      case 'pending':
        return 'bg-theme-warning bg-opacity-10 text-theme-warning';
      case 'disconnected':
        return 'bg-theme-surface text-theme-tertiary';
      case 'error':
        return 'bg-theme-error bg-opacity-10 text-theme-error';
      case 'maintenance':
        return 'bg-theme-info bg-opacity-10 text-theme-info';
      default:
        return 'bg-theme-surface text-theme-secondary';
    }
  },

  getContainerStateColor(state: ContainerState): string {
    switch (state) {
      case 'running':
        return 'bg-theme-success bg-opacity-10 text-theme-success';
      case 'paused':
        return 'bg-theme-warning bg-opacity-10 text-theme-warning';
      case 'restarting':
        return 'bg-theme-info bg-opacity-10 text-theme-info';
      case 'created':
        return 'bg-theme-info bg-opacity-10 text-theme-info';
      case 'exited':
        return 'bg-theme-surface text-theme-tertiary';
      case 'removing':
        return 'bg-theme-warning bg-opacity-10 text-theme-warning';
      case 'dead':
        return 'bg-theme-error bg-opacity-10 text-theme-error';
      default:
        return 'bg-theme-surface text-theme-secondary';
    }
  },

  getActivityStatusColor(status: ActivityStatus): string {
    switch (status) {
      case 'completed':
        return 'bg-theme-success bg-opacity-10 text-theme-success';
      case 'running':
        return 'bg-theme-info bg-opacity-10 text-theme-info';
      case 'pending':
        return 'bg-theme-warning bg-opacity-10 text-theme-warning';
      case 'failed':
        return 'bg-theme-error bg-opacity-10 text-theme-error';
      default:
        return 'bg-theme-surface text-theme-secondary';
    }
  },

  getEventSeverityColor(severity: EventSeverity): string {
    switch (severity) {
      case 'critical':
        return 'bg-theme-error bg-opacity-20 text-theme-error';
      case 'error':
        return 'bg-theme-error bg-opacity-10 text-theme-error';
      case 'warning':
        return 'bg-theme-warning bg-opacity-10 text-theme-warning';
      case 'info':
        return 'bg-theme-info bg-opacity-10 text-theme-info';
      default:
        return 'bg-theme-surface text-theme-secondary';
    }
  },

  formatDuration(ms: number): string {
    if (ms < 1000) return `${ms}ms`;
    if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
    return `${(ms / 60000).toFixed(1)}m`;
  },

  formatBytes(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1048576) return `${(bytes / 1024).toFixed(1)} KB`;
    if (bytes < 1073741824) return `${(bytes / 1048576).toFixed(1)} MB`;
    return `${(bytes / 1073741824).toFixed(1)} GB`;
  },
};
