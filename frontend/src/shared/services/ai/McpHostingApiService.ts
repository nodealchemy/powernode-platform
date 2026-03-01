/**
 * MCP Hosting API Service - Managed MCP Server Operations
 *
 * Handles server creation, deployment, lifecycle, and marketplace.
 */

import { BaseApiService, QueryFilters } from '@/shared/services/ai/BaseApiService';

// ============================================================================
// Types
// ============================================================================

export interface McpHostedServer {
  id: string;
  name: string;
  description: string | null;
  server_type: string;
  status: 'pending' | 'building' | 'deploying' | 'running' | 'stopped' | 'failed' | 'deleted';
  visibility: 'private' | 'team' | 'public' | 'marketplace';
  health_status: string;
  runtime: string;
  runtime_version: string | null;
  deployment_region: string | null;
  current_version: string;
  current_instances: number;
  total_requests: number;
  success_rate: number;
  avg_latency_ms: number | null;
  total_cost_usd: number;
  tools_count: number;
  is_published: boolean;
  marketplace_installs: number;
  marketplace_rating: number | null;
  last_deployed_at: string | null;
  created_at: string;
}

export interface McpServerDetailed extends McpHostedServer {
  tools_manifest: Record<string, unknown>[];
  capabilities: string[];
  environment_variables: string[];
  build_config: Record<string, unknown>;
  memory_mb: number | null;
  cpu_millicores: number | null;
  max_instances: number | null;
  min_instances: number | null;
  timeout_seconds: number | null;
  source_type: string;
  source_url: string | null;
  entry_point: string;
  current_deployment: McpServerDeployment | null;
  recent_deployments: McpServerDeployment[];
  subscription_count: number;
}

export interface McpServerDeployment {
  id: string;
  version: string;
  status: 'pending' | 'building' | 'deploying' | 'running' | 'failed' | 'rolled_back' | 'superseded';
  deployment_type: string;
  source_commit: string | null;
  is_rollback: boolean;
  build_duration_seconds: number | null;
  deployment_duration_seconds: number | null;
  total_duration_seconds: number | null;
  error_message: string | null;
  deployed_by_id: string | null;
  created_at: string;
  deployment_completed_at: string | null;
}

export interface McpServerMetric {
  id: string;
  recorded_at: string;
  granularity: string;
  request_count: number;
  success_count: number;
  error_count: number;
  avg_latency_ms: number;
  p95_latency_ms: number | null;
  p99_latency_ms: number | null;
  error_rate: number;
  cpu_usage_percent: number | null;
  memory_usage_mb: number | null;
}

export interface McpServerSubscription {
  id: string;
  account_id: string;
  hosted_server_id: string;
  server_name: string;
  status: 'active' | 'paused' | 'cancelled' | 'expired';
  subscription_type: string;
  monthly_price_usd: number | null;
  monthly_request_limit: number | null;
  requests_used_this_month: number;
  usage_percentage: number;
  remaining_requests: number | null;
  current_period_start: string;
  current_period_end: string;
  subscribed_at: string;
  expires_at: string | null;
}

export interface McpMarketplaceListing {
  id: string;
  name: string;
  description: string | null;
  category: string | null;
  price_usd: number | null;
  server_type: string;
  tools_count: number;
  subscription_count: number;
  marketplace_rating: number | null;
  publisher_account_id: string;
  published_at: string;
}

export interface ServerCreateParams {
  name: string;
  description?: string;
  server_type?: string;
  source_type?: string;
  source_url?: string;
  source_branch?: string;
  source_path?: string;
  entry_point?: string;
  runtime?: string;
  environment_variables?: Record<string, string>;
  resource_limits?: {
    memory_mb?: number;
    cpu_millicores?: number;
    timeout_seconds?: number;
    max_concurrent_requests?: number;
  };
  capabilities?: string[];
  tool_manifest?: Record<string, unknown>;
  visibility?: string;
}

export interface ServerFilters extends QueryFilters {
  status?: string;
  visibility?: string;
}

export interface MarketplaceFilters extends QueryFilters {
  category?: string;
}

// ============================================================================
// Service
// ============================================================================

class McpHostingApiService extends BaseApiService {
  private basePath = '/mcp/hosting';

  // Server Management
  async listServers(filters?: ServerFilters): Promise<{
    servers: McpHostedServer[];
    total_count: number;
  }> {
    const queryString = this.buildQueryString(filters);
    return this.get(`${this.basePath}/servers${queryString}`);
  }

  async getServer(serverId: string): Promise<McpServerDetailed> {
    return this.get<McpServerDetailed>(`${this.basePath}/servers/${serverId}`);
  }

  async createServer(data: ServerCreateParams): Promise<McpHostedServer> {
    return this.post<McpHostedServer>(`${this.basePath}/servers`, data);
  }

  async updateServer(
    serverId: string,
    data: Partial<ServerCreateParams>
  ): Promise<McpHostedServer> {
    return this.patch<McpHostedServer>(
      `${this.basePath}/servers/${serverId}`,
      data
    );
  }

  async deleteServer(serverId: string): Promise<{ success: boolean }> {
    return this.delete(`${this.basePath}/servers/${serverId}`);
  }

  // Deployment Operations
  async deployServer(
    serverId: string,
    data?: { version?: string; commit_sha?: string }
  ): Promise<{ deployment: McpServerDeployment; server: McpHostedServer }> {
    return this.post(`${this.basePath}/servers/${serverId}/deploy`, data || {});
  }

  async rollbackDeployment(
    serverId: string,
    deploymentId?: string
  ): Promise<{ deployment: McpServerDeployment; rolled_back_from: string }> {
    return this.post(`${this.basePath}/servers/${serverId}/rollback`, {
      deployment_id: deploymentId,
    });
  }

  async getDeploymentHistory(
    serverId: string,
    limit?: number
  ): Promise<{
    server_id: string;
    deployments: McpServerDeployment[];
    current_deployment: McpServerDeployment | null;
  }> {
    const queryString = limit ? `?limit=${limit}` : '';
    return this.get(
      `${this.basePath}/servers/${serverId}/deployments${queryString}`
    );
  }

  // Lifecycle Operations
  async startServer(serverId: string): Promise<McpHostedServer> {
    return this.post<McpHostedServer>(
      `${this.basePath}/servers/${serverId}/start`
    );
  }

  async stopServer(serverId: string): Promise<McpHostedServer> {
    return this.post<McpHostedServer>(
      `${this.basePath}/servers/${serverId}/stop`
    );
  }

  async restartServer(serverId: string): Promise<McpHostedServer> {
    return this.post<McpHostedServer>(
      `${this.basePath}/servers/${serverId}/restart`
    );
  }

  // Monitoring
  async getServerMetrics(
    serverId: string,
    params?: { period_hours?: number; granularity?: string }
  ): Promise<{
    server_id: string;
    period_hours: number;
    granularity: string;
    metrics: McpServerMetric[];
    summary: {
      avg_request_count: number;
      total_requests: number;
      avg_latency_ms: number;
      avg_error_rate: number;
      avg_cpu_usage: number;
      avg_memory_usage: number;
    };
  }> {
    const queryString = this.buildQueryString(params);
    return this.get(
      `${this.basePath}/servers/${serverId}/metrics${queryString}`
    );
  }

  async getServerHealth(serverId: string): Promise<{
    server_id: string;
    status: string;
    health_status: string;
    last_health_check: string | null;
    uptime_percentage: number;
    consecutive_failures: number;
    current_deployment: McpServerDeployment | null;
  }> {
    return this.get(`${this.basePath}/servers/${serverId}/health`);
  }

  // Marketplace Operations
  async publishToMarketplace(
    serverId: string,
    data?: { category?: string; price_usd?: number; description?: string }
  ): Promise<McpHostedServer> {
    return this.post<McpHostedServer>(
      `${this.basePath}/servers/${serverId}/publish`,
      data || {}
    );
  }

  async unpublishFromMarketplace(serverId: string): Promise<McpHostedServer> {
    return this.post<McpHostedServer>(
      `${this.basePath}/servers/${serverId}/unpublish`
    );
  }

  async browseMarketplace(filters?: MarketplaceFilters): Promise<{
    servers: McpMarketplaceListing[];
    total_count: number;
  }> {
    const queryString = this.buildQueryString(filters);
    return this.get(`${this.basePath}/marketplace${queryString}`);
  }

  async subscribeToServer(
    serverId: string,
    subscriptionType?: string
  ): Promise<McpServerSubscription> {
    return this.post<McpServerSubscription>(
      `${this.basePath}/marketplace/${serverId}/subscribe`,
      { subscription_type: subscriptionType }
    );
  }

  // Subscriptions
  async getSubscriptions(filters?: QueryFilters): Promise<{
    subscriptions: McpServerSubscription[];
    total_count: number;
  }> {
    const queryString = this.buildQueryString(filters);
    return this.get(`${this.basePath}/subscriptions${queryString}`);
  }
}

export const mcpHostingApi = new McpHostingApiService();
export default mcpHostingApi;
