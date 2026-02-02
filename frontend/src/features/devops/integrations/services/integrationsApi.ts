import { api } from '@/shared/services/api';
import type {
  TemplatesResponse,
  TemplateResponse,
  InstancesResponse,
  InstanceResponse,
  CredentialsResponse,
  CredentialResponse,
  ExecutionsResponse,
  ExecutionResponse,
  ExecutionStatsResponse,
  TestConnectionResponse,
  ExecuteResponse,
  InstanceFormData,
  CredentialFormData,
  TemplateFilters,
  InstanceFilters,
  ExecutionFilters,
  IntegrationType,
  InstanceStatus,
  IntegrationInstanceSummary,
} from '../types';

const handleApiError = (error: unknown, defaultMessage: string): string => {
  if (error && typeof error === 'object' && 'response' in error) {
    return (error as { response?: { data?: { error?: string } } }).response?.data?.error || defaultMessage;
  }
  return defaultMessage;
};

export const integrationsApi = {
  // ==================== Templates ====================

  async getTemplates(
    page = 1,
    perPage = 20,
    filters?: TemplateFilters
  ): Promise<TemplatesResponse> {
    try {
      const params = new URLSearchParams({
        page: page.toString(),
        per_page: perPage.toString(),
      });

      if (filters?.type) params.append('type', filters.type);
      if (filters?.category) params.append('category', filters.category);
      if (filters?.featured) params.append('featured', 'true');

      const response = await api.get(`/devops/integration_templates?${params}`);
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to fetch templates'),
      };
    }
  },

  async searchTemplates(
    query: string,
    page = 1,
    perPage = 20,
    filters?: TemplateFilters
  ): Promise<TemplatesResponse> {
    try {
      const params = new URLSearchParams({
        q: query,
        page: page.toString(),
        per_page: perPage.toString(),
      });

      if (filters?.type) params.append('type', filters.type);
      if (filters?.category) params.append('category', filters.category);

      const response = await api.get(`/devops/integration_templates/search?${params}`);
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to search templates'),
      };
    }
  },

  async getTemplate(id: string): Promise<TemplateResponse> {
    try {
      const response = await api.get(`/devops/integration_templates/${id}`);
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to fetch template'),
      };
    }
  },

  async getTemplateCategories(): Promise<{ success: boolean; data?: { categories: Record<string, number> }; error?: string }> {
    try {
      const response = await api.get('/devops/integration_templates/categories');
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to fetch categories'),
      };
    }
  },

  async getTemplateTypes(): Promise<{ success: boolean; data?: { types: IntegrationType[] }; error?: string }> {
    try {
      const response = await api.get('/devops/integration_templates/types');
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to fetch types'),
      };
    }
  },

  // ==================== Instances ====================

  async getInstances(
    page = 1,
    perPage = 20,
    filters?: InstanceFilters
  ): Promise<InstancesResponse> {
    try {
      const params = new URLSearchParams({
        page: page.toString(),
        per_page: perPage.toString(),
      });

      if (filters?.status) params.append('status', filters.status);
      if (filters?.type) params.append('type', filters.type);

      const response = await api.get(`/devops/integration_instances?${params}`);
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to fetch instances'),
      };
    }
  },

  async getInstance(id: string): Promise<InstanceResponse> {
    try {
      const response = await api.get(`/devops/integration_instances/${id}`);
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to fetch instance'),
      };
    }
  },

  async createInstance(data: InstanceFormData): Promise<InstanceResponse> {
    try {
      const response = await api.post('/devops/integration_instances', {
        template_id: data.template_id,
        instance: {
          name: data.name,
          credential_id: data.credential_id,
          configuration: data.configuration,
        },
      });
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to create instance'),
      };
    }
  },

  async updateInstance(
    id: string,
    data: Partial<InstanceFormData>
  ): Promise<InstanceResponse> {
    try {
      const response = await api.patch(`/devops/integration_instances/${id}`, {
        instance: data,
      });
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to update instance'),
      };
    }
  },

  async deleteInstance(id: string): Promise<{ success: boolean; message?: string; error?: string }> {
    try {
      const response = await api.delete(`/devops/integration_instances/${id}`);
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to delete instance'),
      };
    }
  },

  async activateInstance(id: string): Promise<InstanceResponse> {
    try {
      const response = await api.post(`/devops/integration_instances/${id}/activate`);
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to activate instance'),
      };
    }
  },

  async deactivateInstance(id: string): Promise<InstanceResponse> {
    try {
      const response = await api.post(`/devops/integration_instances/${id}/deactivate`);
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to deactivate instance'),
      };
    }
  },

  async testInstance(id: string): Promise<TestConnectionResponse> {
    try {
      const response = await api.post(`/devops/integration_instances/${id}/test`);
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to test instance'),
      };
    }
  },

  async executeInstance(
    id: string,
    input: Record<string, unknown> = {}
  ): Promise<ExecuteResponse> {
    try {
      const response = await api.post(`/devops/integration_instances/${id}/execute`, input);
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to execute instance'),
      };
    }
  },

  async getInstanceHealth(id: string): Promise<{ success: boolean; data?: { health: Record<string, unknown> }; error?: string }> {
    try {
      const response = await api.get(`/devops/integration_instances/${id}/health`);
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to fetch health'),
      };
    }
  },

  async getInstanceStats(
    id: string,
    period = 30
  ): Promise<ExecutionStatsResponse> {
    try {
      const response = await api.get(`/devops/integration_instances/${id}/stats?period=${period}`);
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to fetch stats'),
      };
    }
  },

  // ==================== Credentials ====================

  async getCredentials(page = 1, perPage = 20): Promise<CredentialsResponse> {
    try {
      const response = await api.get(`/devops/integration_credentials?page=${page}&per_page=${perPage}`);
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to fetch credentials'),
      };
    }
  },

  async getCredential(id: string): Promise<CredentialResponse> {
    try {
      const response = await api.get(`/devops/integration_credentials/${id}`);
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to fetch credential'),
      };
    }
  },

  async createCredential(data: CredentialFormData): Promise<CredentialResponse> {
    try {
      const response = await api.post('/devops/integration_credentials', {
        credential: data,
      });
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to create credential'),
      };
    }
  },

  async updateCredential(
    id: string,
    data: Partial<CredentialFormData>
  ): Promise<CredentialResponse> {
    try {
      const response = await api.patch(`/devops/integration_credentials/${id}`, {
        credential: data,
      });
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to update credential'),
      };
    }
  },

  async deleteCredential(id: string): Promise<{ success: boolean; message?: string; error?: string }> {
    try {
      const response = await api.delete(`/devops/integration_credentials/${id}`);
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to delete credential'),
      };
    }
  },

  async rotateCredential(id: string): Promise<CredentialResponse> {
    try {
      const response = await api.post(`/devops/integration_credentials/${id}/rotate`);
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to rotate credential'),
      };
    }
  },

  // ==================== Executions ====================

  async getExecutions(
    page = 1,
    perPage = 20,
    filters?: ExecutionFilters
  ): Promise<ExecutionsResponse> {
    try {
      const params = new URLSearchParams({
        page: page.toString(),
        per_page: perPage.toString(),
      });

      if (filters?.instance_id) params.append('instance_id', filters.instance_id);
      if (filters?.status) params.append('status', filters.status);
      if (filters?.since) params.append('since', filters.since);
      if (filters?.until) params.append('until', filters.until);

      const response = await api.get(`/devops/integration_executions?${params}`);
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to fetch executions'),
      };
    }
  },

  async getExecution(id: string): Promise<ExecutionResponse> {
    try {
      const response = await api.get(`/devops/integration_executions/${id}`);
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to fetch execution'),
      };
    }
  },

  async retryExecution(id: string): Promise<ExecuteResponse> {
    try {
      const response = await api.post(`/devops/integration_executions/${id}/retry`);
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to retry execution'),
      };
    }
  },

  async cancelExecution(id: string): Promise<{ success: boolean; message?: string; error?: string }> {
    try {
      const response = await api.post(`/devops/integration_executions/${id}/cancel`);
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to cancel execution'),
      };
    }
  },

  async getExecutionStats(
    instanceId?: string,
    period = 30
  ): Promise<ExecutionStatsResponse> {
    try {
      const params = new URLSearchParams({ period: period.toString() });
      if (instanceId) params.append('instance_id', instanceId);

      const response = await api.get(`/devops/integration_executions/stats?${params}`);
      return response.data;
    } catch {
      return {
        success: false,
        error: handleApiError(error, 'Failed to fetch execution stats'),
      };
    }
  },

  // ==================== Helpers ====================

  getStatusColor(status: InstanceStatus): string {
    switch (status) {
      case 'active':
        return 'bg-theme-success bg-opacity-10 text-theme-success';
      case 'pending':
        return 'bg-theme-warning bg-opacity-10 text-theme-warning';
      case 'paused':
        return 'bg-theme-surface text-theme-tertiary';
      case 'error':
        return 'bg-theme-error bg-opacity-10 text-theme-error';
      default:
        return 'bg-theme-surface text-theme-secondary';
    }
  },

  getExecutionStatusColor(status: string): string {
    switch (status) {
      case 'completed':
        return 'bg-theme-success bg-opacity-10 text-theme-success';
      case 'running':
        return 'bg-theme-info bg-opacity-10 text-theme-info';
      case 'queued':
        return 'bg-theme-warning bg-opacity-10 text-theme-warning';
      case 'failed':
        return 'bg-theme-error bg-opacity-10 text-theme-error';
      case 'cancelled':
        return 'bg-theme-surface text-theme-tertiary';
      default:
        return 'bg-theme-surface text-theme-secondary';
    }
  },

  getTypeIcon(type: IntegrationType): string {
    switch (type) {
      case 'github_action':
        return '🔄';
      case 'webhook':
        return '🔔';
      case 'mcp_server':
        return '🤖';
      case 'rest_api':
        return '🌐';
      case 'custom':
        return '⚙️';
      default:
        return '📦';
    }
  },

  getTypeLabel(type: IntegrationType): string {
    switch (type) {
      case 'github_action':
        return 'GitHub Action';
      case 'webhook':
        return 'Webhook';
      case 'mcp_server':
        return 'MCP Server';
      case 'rest_api':
        return 'REST API';
      case 'custom':
        return 'Custom';
      default:
        return type;
    }
  },

  getSuccessRate(instance: IntegrationInstanceSummary): number {
    const total = instance.success_count + instance.failure_count;
    return total === 0 ? 0 : Math.round((instance.success_count / total) * 100);
  },

  formatDuration(ms: number): string {
    if (ms < 1000) return `${ms}ms`;
    if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
    return `${(ms / 60000).toFixed(1)}m`;
  },
};
