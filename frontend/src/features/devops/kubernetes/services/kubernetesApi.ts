import { api } from '@/shared/services/api';
import type {
  ClusterFilters,
  DecommissionResponse,
  KubeconfigResponse,
  KubernetesClusterDetail,
  KubernetesClusterSummary,
  KubernetesNodeSummary,
  NodeFilters,
} from '../types';

interface ApiResult<T> {
  success: boolean;
  data?: T;
  error?: string;
}

const handleApiError = (error: unknown, defaultMessage: string): string => {
  if (error && typeof error === 'object' && 'response' in error) {
    const r = (error as { response?: { data?: { error?: string; message?: string } } }).response;
    return r?.data?.error || r?.data?.message || defaultMessage;
  }
  if (error && typeof error === 'object' && 'message' in error) {
    return (error as { message: string }).message;
  }
  return defaultMessage;
};

export const kubernetesApi = {
  // GET /api/v1/devops/kubernetes/clusters
  async getClusters(filters?: ClusterFilters): Promise<ApiResult<{ items: KubernetesClusterSummary[] }>> {
    try {
      const params = new URLSearchParams();
      if (filters?.status) params.set('status', filters.status);
      if (filters?.flavor) params.set('flavor', filters.flavor);
      if (filters?.environment) params.set('environment', filters.environment);
      const response = await api.get(`/devops/kubernetes/clusters?${params}`);
      return { success: true, data: response.data.data };
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch clusters') };
    }
  },

  // GET /api/v1/devops/kubernetes/clusters/:id
  async getCluster(id: string): Promise<ApiResult<{ cluster: KubernetesClusterDetail }>> {
    try {
      const response = await api.get(`/devops/kubernetes/clusters/${id}`);
      return { success: true, data: response.data.data };
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch cluster') };
    }
  },

  // DELETE /api/v1/devops/kubernetes/clusters/:id
  async decommissionCluster(id: string): Promise<ApiResult<DecommissionResponse>> {
    try {
      const response = await api.delete(`/devops/kubernetes/clusters/${id}`);
      return { success: true, data: response.data.data };
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to decommission cluster') };
    }
  },

  // GET /api/v1/devops/kubernetes/clusters/:id/kubeconfig
  // Returns the cluster admin kubeconfig YAML. SENSITIVE — surface
  // through a confirmation dialog in the UI.
  async getKubeconfig(id: string): Promise<ApiResult<KubeconfigResponse>> {
    try {
      const response = await api.get(`/devops/kubernetes/clusters/${id}/kubeconfig`);
      return { success: true, data: response.data.data };
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to retrieve kubeconfig') };
    }
  },

  // GET /api/v1/devops/kubernetes/clusters/:cluster_id/nodes
  async getNodes(
    clusterId: string,
    filters?: NodeFilters,
  ): Promise<ApiResult<{ cluster_id: string; items: KubernetesNodeSummary[] }>> {
    try {
      const params = new URLSearchParams();
      if (filters?.role) params.set('role', filters.role);
      if (filters?.status) params.set('status', filters.status);
      const response = await api.get(`/devops/kubernetes/clusters/${clusterId}/nodes?${params}`);
      return { success: true, data: response.data.data };
    } catch (error) {
      return { success: false, error: handleApiError(error, 'Failed to fetch nodes') };
    }
  },

  // ────────────────────────────────────────────────────────────────
  // Display helpers
  // ────────────────────────────────────────────────────────────────

  getClusterStatusColor(status: string): string {
    switch (status) {
      case 'active':         return 'bg-theme-success bg-opacity-10 text-theme-success';
      case 'bootstrapping':  return 'bg-theme-info bg-opacity-10 text-theme-info';
      case 'pending':        return 'bg-theme-warning bg-opacity-10 text-theme-warning';
      case 'degraded':       return 'bg-theme-warning bg-opacity-10 text-theme-warning';
      case 'disconnected':   return 'bg-theme-danger bg-opacity-10 text-theme-danger';
      case 'error':          return 'bg-theme-danger bg-opacity-10 text-theme-danger';
      default:               return 'bg-theme-surface text-theme-secondary';
    }
  },

  getNodeRoleLabel(role: string): string {
    switch (role) {
      case 'server':         return 'Server (k3s)';
      case 'agent':          return 'Agent (k3s)';
      case 'control_plane':  return 'Control Plane (kubeadm)';
      case 'worker':         return 'Worker (kubeadm)';
      default:               return role;
    }
  },
};
