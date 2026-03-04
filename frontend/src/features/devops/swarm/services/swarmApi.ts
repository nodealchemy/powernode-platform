import { api } from '@/shared/services/api';
import type {
  SwarmClusterSummary,
  SwarmCluster,
  ClusterFormData,
  ClusterHealthSummary,
  ClusterFilters,
  SwarmNodeSummary,
  SwarmNode,
  NodeUpdateData,
  NodeFilters,
  SwarmServiceSummary,
  SwarmService,
  ServiceFormData,
  ServiceScaleData,
  ServiceFilters,
  SwarmStackSummary,
  SwarmStack,
  StackFormData,
  SwarmDeploymentSummary,
  SwarmDeployment,
  DeploymentFilters,
  SwarmEventSummary,
  SwarmEvent,
  EventFilters,
  SwarmNetwork,
  SwarmNetworkDetail,
  NetworkFormData,
  SwarmVolume,
  SwarmSecret,
  SecretFormData,
  SwarmConfig,
  ConfigFormData,
  SwarmTask,
  ApiResponse,
  Pagination,
  ClusterStatus,
  EventSeverity,
  DeploymentStatus,
  NodeStatus,
  StackStatus,
  ServiceLogEntry,
  ServiceLogOptions,
  AvailableSwarmService,
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

export const swarmApi = {
  // ==================== Clusters ====================

  async getClusters(
    page = 1,
    perPage = 20,
    filters?: ClusterFilters
  ): Promise<ApiResponse<{ items: SwarmClusterSummary[]; pagination: Pagination }>> {
    try {
      const params = buildParams({
        page,
        per_page: perPage,
        ...filters,
      });
      const response = await api.get(`/devops/swarm/clusters?${params}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch clusters') };
    }
  },

  async getCluster(id: string): Promise<ApiResponse<{ cluster: SwarmCluster }>> {
    try {
      const response = await api.get(`/devops/swarm/clusters/${id}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch cluster') };
    }
  },

  async createCluster(data: ClusterFormData): Promise<ApiResponse<{ cluster: SwarmCluster }>> {
    try {
      const response = await api.post('/devops/swarm/clusters', { cluster: data });
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to create cluster') };
    }
  },

  async updateCluster(id: string, data: Partial<ClusterFormData>): Promise<ApiResponse<{ cluster: SwarmCluster }>> {
    try {
      const response = await api.patch(`/devops/swarm/clusters/${id}`, { cluster: data });
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to update cluster') };
    }
  },

  async deleteCluster(id: string): Promise<ApiResponse<{ message: string }>> {
    try {
      const response = await api.delete(`/devops/swarm/clusters/${id}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to delete cluster') };
    }
  },

  async testClusterConnection(id: string): Promise<ApiResponse<{ connected: boolean; message: string; response_time_ms: number }>> {
    try {
      const response = await api.post(`/devops/swarm/clusters/${id}/test_connection`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to test connection') };
    }
  },

  async syncCluster(id: string): Promise<ApiResponse<{ message: string; synced_at: string }>> {
    try {
      const response = await api.post(`/devops/swarm/clusters/${id}/sync`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to sync cluster') };
    }
  },

  async getClusterHealth(id: string): Promise<ApiResponse<{ health: ClusterHealthSummary }>> {
    try {
      const response = await api.get(`/devops/swarm/clusters/${id}/health`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch cluster health') };
    }
  },

  // ==================== Nodes ====================

  async getNodes(
    clusterId: string,
    filters?: NodeFilters
  ): Promise<ApiResponse<{ items: SwarmNodeSummary[] }>> {
    try {
      const params = buildParams({ ...filters });
      const response = await api.get(`/devops/swarm/clusters/${clusterId}/nodes?${params}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch nodes') };
    }
  },

  async getNode(clusterId: string, nodeId: string): Promise<ApiResponse<{ node: SwarmNode }>> {
    try {
      const response = await api.get(`/devops/swarm/clusters/${clusterId}/nodes/${nodeId}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch node') };
    }
  },

  async updateNode(clusterId: string, nodeId: string, data: NodeUpdateData): Promise<ApiResponse<{ node: SwarmNode }>> {
    try {
      const response = await api.patch(`/devops/swarm/clusters/${clusterId}/nodes/${nodeId}`, { node: data });
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to update node') };
    }
  },

  async drainNode(clusterId: string, nodeId: string): Promise<ApiResponse<{ node: SwarmNode }>> {
    try {
      const response = await api.post(`/devops/swarm/clusters/${clusterId}/nodes/${nodeId}/drain`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to drain node') };
    }
  },

  async removeNode(clusterId: string, nodeId: string): Promise<ApiResponse<{ message: string }>> {
    try {
      const response = await api.delete(`/devops/swarm/clusters/${clusterId}/nodes/${nodeId}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to remove node') };
    }
  },

  // ==================== Services ====================

  async getServices(
    clusterId: string,
    filters?: ServiceFilters
  ): Promise<ApiResponse<{ items: SwarmServiceSummary[] }>> {
    try {
      const params = buildParams({ ...filters });
      const response = await api.get(`/devops/swarm/clusters/${clusterId}/services?${params}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch services') };
    }
  },

  async getService(clusterId: string, serviceId: string): Promise<ApiResponse<{ service: SwarmService }>> {
    try {
      const response = await api.get(`/devops/swarm/clusters/${clusterId}/services/${serviceId}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch service') };
    }
  },

  async createService(clusterId: string, data: ServiceFormData): Promise<ApiResponse<{ service: SwarmService }>> {
    try {
      const { replicas, ...rest } = data;
      const payload = { ...rest, desired_replicas: replicas };
      const response = await api.post(`/devops/swarm/clusters/${clusterId}/services`, { service: payload });
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to create service') };
    }
  },

  async updateService(clusterId: string, serviceId: string, data: Partial<ServiceFormData>): Promise<ApiResponse<{ service: SwarmService }>> {
    try {
      const { replicas, ...rest } = data;
      const payload = replicas !== undefined ? { ...rest, desired_replicas: replicas } : rest;
      const response = await api.patch(`/devops/swarm/clusters/${clusterId}/services/${serviceId}`, { service: payload });
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to update service') };
    }
  },

  async deleteService(clusterId: string, serviceId: string): Promise<ApiResponse<{ message: string }>> {
    try {
      const response = await api.delete(`/devops/swarm/clusters/${clusterId}/services/${serviceId}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to delete service') };
    }
  },

  async scaleService(clusterId: string, serviceId: string, data: ServiceScaleData): Promise<ApiResponse<{ service: SwarmService }>> {
    try {
      const response = await api.post(`/devops/swarm/clusters/${clusterId}/services/${serviceId}/scale`, data);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to scale service') };
    }
  },

  async rollbackService(clusterId: string, serviceId: string): Promise<ApiResponse<{ deployment: SwarmDeploymentSummary }>> {
    try {
      const response = await api.post(`/devops/swarm/clusters/${clusterId}/services/${serviceId}/rollback`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to rollback service') };
    }
  },

  async getAvailableServices(clusterId: string): Promise<ApiResponse<{ items: AvailableSwarmService[] }>> {
    try {
      const response = await api.get(`/devops/swarm/clusters/${clusterId}/services/available`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch available services') };
    }
  },

  async importServices(clusterId: string, dockerServiceIds: string[]): Promise<ApiResponse<{ items: SwarmServiceSummary[]; imported_count: number }>> {
    try {
      const response = await api.post(`/devops/swarm/clusters/${clusterId}/services/import`, { docker_service_ids: dockerServiceIds });
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to import services') };
    }
  },

  async getServiceTasks(clusterId: string, serviceId: string): Promise<ApiResponse<{ items: SwarmTask[] }>> {
    try {
      const response = await api.get(`/devops/swarm/clusters/${clusterId}/services/${serviceId}/tasks`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch service tasks') };
    }
  },

  async getServiceLogs(
    clusterId: string,
    serviceId: string,
    options?: ServiceLogOptions
  ): Promise<ApiResponse<{ items: ServiceLogEntry[] }>> {
    try {
      const params = buildParams({ ...options });
      const response = await api.get(`/devops/swarm/clusters/${clusterId}/services/${serviceId}/logs?${params}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch service logs') };
    }
  },

  // ==================== Stacks ====================

  async getStacks(clusterId: string): Promise<ApiResponse<{ items: SwarmStackSummary[] }>> {
    try {
      const response = await api.get(`/devops/swarm/clusters/${clusterId}/stacks`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch stacks') };
    }
  },

  async getStack(clusterId: string, stackId: string): Promise<ApiResponse<{ stack: SwarmStack }>> {
    try {
      const response = await api.get(`/devops/swarm/clusters/${clusterId}/stacks/${stackId}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch stack') };
    }
  },

  async createStack(clusterId: string, data: StackFormData): Promise<ApiResponse<{ stack: SwarmStack }>> {
    try {
      const response = await api.post(`/devops/swarm/clusters/${clusterId}/stacks`, { stack: data });
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to create stack') };
    }
  },

  async updateStack(clusterId: string, stackId: string, data: Partial<StackFormData>): Promise<ApiResponse<{ stack: SwarmStack }>> {
    try {
      const response = await api.patch(`/devops/swarm/clusters/${clusterId}/stacks/${stackId}`, { stack: data });
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to update stack') };
    }
  },

  async deleteStack(clusterId: string, stackId: string): Promise<ApiResponse<{ message: string }>> {
    try {
      const response = await api.delete(`/devops/swarm/clusters/${clusterId}/stacks/${stackId}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to delete stack') };
    }
  },

  async deployStack(clusterId: string, stackId: string): Promise<ApiResponse<{ deployment: SwarmDeploymentSummary }>> {
    try {
      const response = await api.post(`/devops/swarm/clusters/${clusterId}/stacks/${stackId}/deploy`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to deploy stack') };
    }
  },

  async removeStack(clusterId: string, stackId: string): Promise<ApiResponse<{ deployment: SwarmDeploymentSummary }>> {
    try {
      const response = await api.post(`/devops/swarm/clusters/${clusterId}/stacks/${stackId}/remove`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to remove stack') };
    }
  },

  // ==================== Deployments ====================

  async getDeployments(
    clusterId: string,
    page = 1,
    perPage = 20,
    filters?: DeploymentFilters
  ): Promise<ApiResponse<{ items: SwarmDeploymentSummary[]; pagination: Pagination }>> {
    try {
      const params = buildParams({
        page,
        per_page: perPage,
        ...filters,
      });
      const response = await api.get(`/devops/swarm/clusters/${clusterId}/deployments?${params}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch deployments') };
    }
  },

  async getDeployment(clusterId: string, deploymentId: string): Promise<ApiResponse<{ deployment: SwarmDeployment }>> {
    try {
      const response = await api.get(`/devops/swarm/clusters/${clusterId}/deployments/${deploymentId}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch deployment') };
    }
  },

  async cancelDeployment(clusterId: string, deploymentId: string): Promise<ApiResponse<{ deployment: SwarmDeployment }>> {
    try {
      const response = await api.post(`/devops/swarm/clusters/${clusterId}/deployments/${deploymentId}/cancel`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to cancel deployment') };
    }
  },

  // ==================== Events ====================

  async getEvents(
    clusterId: string,
    page = 1,
    perPage = 50,
    filters?: EventFilters
  ): Promise<ApiResponse<{ items: SwarmEventSummary[]; pagination: Pagination }>> {
    try {
      const params = buildParams({
        page,
        per_page: perPage,
        ...filters,
      });
      const response = await api.get(`/devops/swarm/clusters/${clusterId}/events?${params}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch events') };
    }
  },

  async getEvent(clusterId: string, eventId: string): Promise<ApiResponse<{ event: SwarmEvent }>> {
    try {
      const response = await api.get(`/devops/swarm/clusters/${clusterId}/events/${eventId}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch event') };
    }
  },

  async acknowledgeEvent(clusterId: string, eventId: string): Promise<ApiResponse<{ event: SwarmEvent }>> {
    try {
      const response = await api.post(`/devops/swarm/clusters/${clusterId}/events/${eventId}/acknowledge`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to acknowledge event') };
    }
  },

  async acknowledgeAllEvents(clusterId: string): Promise<ApiResponse<{ acknowledged_count: number }>> {
    try {
      const response = await api.post(`/devops/swarm/clusters/${clusterId}/events/acknowledge_all`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to acknowledge events') };
    }
  },

  // ==================== Secrets ====================

  async getSecrets(clusterId: string): Promise<ApiResponse<{ items: SwarmSecret[] }>> {
    try {
      const response = await api.get(`/devops/swarm/clusters/${clusterId}/secrets`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch secrets') };
    }
  },

  async createSecret(clusterId: string, data: SecretFormData): Promise<ApiResponse<{ secret: SwarmSecret }>> {
    try {
      const response = await api.post(`/devops/swarm/clusters/${clusterId}/secrets`, { secret: data });
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to create secret') };
    }
  },

  async deleteSecret(clusterId: string, secretId: string): Promise<ApiResponse<{ message: string }>> {
    try {
      const response = await api.delete(`/devops/swarm/clusters/${clusterId}/secrets/${secretId}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to delete secret') };
    }
  },

  // ==================== Configs ====================

  async getConfigs(clusterId: string): Promise<ApiResponse<{ items: SwarmConfig[] }>> {
    try {
      const response = await api.get(`/devops/swarm/clusters/${clusterId}/configs`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch configs') };
    }
  },

  async createConfig(clusterId: string, data: ConfigFormData): Promise<ApiResponse<{ config: SwarmConfig }>> {
    try {
      const response = await api.post(`/devops/swarm/clusters/${clusterId}/configs`, { config: data });
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to create config') };
    }
  },

  async deleteConfig(clusterId: string, configId: string): Promise<ApiResponse<{ message: string }>> {
    try {
      const response = await api.delete(`/devops/swarm/clusters/${clusterId}/configs/${configId}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to delete config') };
    }
  },

  // ==================== Networks ====================

  async getNetwork(clusterId: string, networkId: string): Promise<ApiResponse<{ network: SwarmNetworkDetail }>> {
    try {
      const response = await api.get(`/devops/swarm/clusters/${clusterId}/networks/${networkId}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch network') };
    }
  },

  async getNetworks(clusterId: string): Promise<ApiResponse<{ items: SwarmNetwork[] }>> {
    try {
      const response = await api.get(`/devops/swarm/clusters/${clusterId}/networks`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch networks') };
    }
  },

  async createNetwork(clusterId: string, data: NetworkFormData): Promise<ApiResponse<{ network: SwarmNetwork }>> {
    try {
      const response = await api.post(`/devops/swarm/clusters/${clusterId}/networks`, { network: data });
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to create network') };
    }
  },

  async deleteNetwork(clusterId: string, networkId: string): Promise<ApiResponse<{ message: string }>> {
    try {
      const response = await api.delete(`/devops/swarm/clusters/${clusterId}/networks/${networkId}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to delete network') };
    }
  },

  // ==================== Volumes ====================

  async getVolumes(clusterId: string): Promise<ApiResponse<{ items: SwarmVolume[] }>> {
    try {
      const response = await api.get(`/devops/swarm/clusters/${clusterId}/volumes`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch volumes') };
    }
  },

  async deleteVolume(clusterId: string, volumeName: string): Promise<ApiResponse<{ message: string }>> {
    try {
      const response = await api.delete(`/devops/swarm/clusters/${clusterId}/volumes/${volumeName}`);
      return response.data;
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to delete volume') };
    }
  },

  // ==================== Helpers ====================

  getClusterStatusColor(status: ClusterStatus): string {
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

  getNodeStatusColor(status: NodeStatus): string {
    switch (status) {
      case 'ready':
        return 'bg-theme-success bg-opacity-10 text-theme-success';
      case 'down':
        return 'bg-theme-error bg-opacity-10 text-theme-error';
      case 'disconnected':
        return 'bg-theme-warning bg-opacity-10 text-theme-warning';
      default:
        return 'bg-theme-surface text-theme-secondary';
    }
  },

  getDeploymentStatusColor(status: DeploymentStatus): string {
    switch (status) {
      case 'completed':
        return 'bg-theme-success bg-opacity-10 text-theme-success';
      case 'running':
        return 'bg-theme-info bg-opacity-10 text-theme-info';
      case 'pending':
        return 'bg-theme-warning bg-opacity-10 text-theme-warning';
      case 'failed':
        return 'bg-theme-error bg-opacity-10 text-theme-error';
      case 'cancelled':
        return 'bg-theme-surface text-theme-tertiary';
      default:
        return 'bg-theme-surface text-theme-secondary';
    }
  },

  getStackStatusColor(status: StackStatus): string {
    switch (status) {
      case 'deployed':
        return 'bg-theme-success bg-opacity-10 text-theme-success';
      case 'deploying':
      case 'removing':
        return 'bg-theme-info bg-opacity-10 text-theme-info';
      case 'draft':
        return 'bg-theme-warning bg-opacity-10 text-theme-warning';
      case 'failed':
        return 'bg-theme-error bg-opacity-10 text-theme-error';
      case 'removed':
        return 'bg-theme-surface text-theme-tertiary';
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

  getHealthPercentageColor(percentage: number): string {
    if (percentage >= 100) return 'text-theme-success';
    if (percentage >= 50) return 'text-theme-warning';
    return 'text-theme-error';
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
