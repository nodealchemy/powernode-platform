import { BaseApiService, QueryFilters, PaginatedResponse } from './BaseApiService';
import type { AiProvider, AiProviderCredential } from '../../types/ai';

/**
 * ProvidersApiService - Providers Controller API Client
 *
 * Provides access to the consolidated Providers Controller endpoints.
 * Replaces the following old controllers:
 * - ai_providers_controller
 * - ai_provider_credentials_controller
 *
 * New endpoint structure:
 * - GET    /api/v1/ai/providers
 * - POST   /api/v1/ai/providers
 * - GET    /api/v1/ai/providers/:id
 * - PATCH  /api/v1/ai/providers/:id
 * - DELETE /api/v1/ai/providers/:id
 * - POST   /api/v1/ai/providers/:id/test_connection
 * - POST   /api/v1/ai/providers/:id/sync_models
 * - GET    /api/v1/ai/providers/:id/models
 * - GET    /api/v1/ai/providers/:id/usage_summary
 * - GET    /api/v1/ai/providers/available
 * - GET    /api/v1/ai/providers/statistics
 * - GET    /api/v1/ai/providers/:provider_id/credentials
 * - POST   /api/v1/ai/providers/:provider_id/credentials
 * - GET    /api/v1/ai/providers/:provider_id/credentials/:id
 * - PATCH  /api/v1/ai/providers/:provider_id/credentials/:id
 * - DELETE /api/v1/ai/providers/:provider_id/credentials/:id
 * - POST   /api/v1/ai/providers/:provider_id/credentials/:id/test
 * - POST   /api/v1/ai/providers/:provider_id/credentials/:id/make_default
 * - POST   /api/v1/ai/providers/:provider_id/credentials/:id/rotate
 * - POST   /api/v1/ai/providers/:provider_id/credentials/test_all
 */

export interface ProviderFilters extends QueryFilters {
  provider_type?: string;
  status?: 'active' | 'inactive' | 'error';
}

export interface CreateProviderRequest {
  name: string;
  provider_type: string;
  slug?: string;
  description?: string;
  api_base_url?: string;
  api_endpoint?: string;
  capabilities?: string[];
  documentation_url?: string;
  status_url?: string;
  supported_models?: Array<Record<string, unknown>> | unknown[];
  configuration_schema?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
  is_active?: boolean;
}

export interface CreateCredentialRequest {
  name: string;
  credentials: Record<string, any>; // The actual credentials data (api_key, org_id, etc.)
  is_active?: boolean;
  is_default?: boolean;
  expires_at?: string;
}

export interface ModelInfo {
  id: string;
  name: string;
  version?: string;
  capabilities?: string[];
  cost_per_1k_tokens?: number;
}

export interface UsageSummary {
  total_requests: number;
  total_tokens: number;
  total_cost_usd: number;
  requests_by_model: Record<string, number>;
  tokens_by_model: Record<string, number>;
  cost_by_model: Record<string, number>;
  period_start: string;
  period_end: string;
}

export interface ProviderStatistics {
  total_providers: number;
  active_providers: number;
  inactive_providers: number;
  total_credentials: number;
  providers_by_type: Record<string, number>;
}

export interface ConnectionTestResult {
  success: boolean;
  message?: string;  // Success message
  error?: string;    // Error message (for failures)
  response_time_ms?: number;  // Response time in milliseconds
  error_code?: string;  // Error code
  provider_info?: Record<string, any>;  // Provider information
  model_info?: Record<string, any>;  // Model information
}

export interface ProviderAvailability {
  available: boolean;
  reason: string;
  is_active: boolean;
  is_healthy: boolean;
  has_credentials: boolean;
  has_models: boolean;
  health_status: string;
}

class ProvidersApiService extends BaseApiService {
  private resource = 'providers';

  // ===================================================================
  // Provider CRUD Operations
  // ===================================================================

  /**
   * Get list of providers with optional filters
   * GET /api/v1/ai/providers
   */
  async getProviders(filters?: ProviderFilters): Promise<PaginatedResponse<AiProvider>> {
    return this.getList<AiProvider>(this.resource, filters);
  }

  /**
   * Get single provider by ID
   * GET /api/v1/ai/providers/:id
   * Returns { provider: AiProvider } from API, unwrapped to just AiProvider
   */
  async getProvider(id: string): Promise<AiProvider> {
    const response = await this.getOne<{ provider: AiProvider }>(this.resource, id);
    return response.provider;
  }

  /**
   * Create new provider
   * POST /api/v1/ai/providers
   */
  async createProvider(data: CreateProviderRequest): Promise<AiProvider> {
    return this.create<AiProvider>(this.resource, { provider: data });
  }

  /**
   * Update existing provider
   * PATCH /api/v1/ai/providers/:id
   */
  async updateProvider(id: string, data: Partial<CreateProviderRequest>): Promise<AiProvider> {
    return this.update<AiProvider>(this.resource, id, { provider: data });
  }

  /**
   * Delete provider
   * DELETE /api/v1/ai/providers/:id
   */
  async deleteProvider(id: string): Promise<void> {
    return this.remove<void>(this.resource, id);
  }

  // ===================================================================
  // Provider Actions
  // ===================================================================

  /**
   * Test provider connection
   * POST /api/v1/ai/providers/:id/test_connection
   */
  async testConnection(id: string): Promise<ConnectionTestResult> {
    return this.performAction<ConnectionTestResult>(this.resource, id, 'test_connection');
  }

  /**
   * Sync available models from provider
   * POST /api/v1/ai/providers/:id/sync_models
   */
  async syncModels(id: string): Promise<{ models: ModelInfo[] }> {
    return this.performAction<{ models: ModelInfo[] }>(this.resource, id, 'sync_models');
  }

  /**
   * Get available models for provider
   * GET /api/v1/ai/providers/:id/models
   */
  async getModels(id: string): Promise<ModelInfo[]> {
    const path = this.buildPath(this.resource, id, undefined, undefined, 'models');
    return this.get<ModelInfo[]>(path);
  }

  /**
   * Get provider usage summary
   * GET /api/v1/ai/providers/:id/usage_summary
   */
  async getUsageSummary(id: string, timeRange?: string): Promise<UsageSummary> {
    const path = this.buildPath(this.resource, id, undefined, undefined, 'usage_summary');
    const queryString = timeRange ? `?time_range=${timeRange}` : '';
    return this.get<UsageSummary>(`${path}${queryString}`);
  }

  /**
   * Check provider availability (active, healthy, configured)
   * GET /api/v1/ai/providers/:id/check_availability
   */
  async checkAvailability(id: string): Promise<{ provider: { id: string; name: string; provider_type: string }, availability: ProviderAvailability }> {
    const path = this.buildPath(this.resource, id, undefined, undefined, 'check_availability');
    return this.get<{ provider: { id: string; name: string; provider_type: string }, availability: ProviderAvailability }>(path);
  }

  // ===================================================================
  // Provider Collection Actions
  // ===================================================================

  /**
   * Test individual provider
   * POST /api/v1/ai/providers/:id/test
   */
  async testProvider(id: string): Promise<ConnectionTestResult> {
    return this.performAction<ConnectionTestResult>(this.resource, id, 'test');
  }

  /**
   * Test all providers
   * POST /api/v1/ai/providers/test_all
   */
  async testAllProviders(): Promise<{
    results: Array<{
      id: string;
      name: string;
      provider_type: string;
      success: boolean;
      message?: string;
      response_time_ms?: number;
    }>;
    summary: {
      total: number;
      successful: number;
      failed: number;
    };
  }> {
    const path = this.buildPath(this.resource);
    return this.post<{
      results: Array<{
        id: string;
        name: string;
        provider_type: string;
        success: boolean;
        message?: string;
        response_time_ms?: number;
      }>;
      summary: {
        total: number;
        successful: number;
        failed: number;
      };
    }>(`${path}/test_all`);
  }

  /**
   * Setup default providers
   * POST /api/v1/ai/providers/setup_defaults
   */
  async setupDefaultProviders(providerTypes: string[]): Promise<{
    created_providers: string[];
  }> {
    const path = this.buildPath(this.resource);
    return this.post<{ created_providers: string[] }>(`${path}/setup_defaults`, {
      provider_types: providerTypes,
    });
  }

  /**
   * Get available provider types
   * GET /api/v1/ai/providers/available
   */
  async getAvailableProviders(): Promise<Array<{ type: string; name: string; description: string }>> {
    const path = this.buildPath(this.resource);
    return this.get<Array<{ type: string; name: string; description: string }>>(`${path}/available`);
  }

  /**
   * Get provider statistics
   * GET /api/v1/ai/providers/statistics
   */
  async getStatistics(): Promise<ProviderStatistics> {
    const path = this.buildPath(this.resource);
    return this.get<ProviderStatistics>(`${path}/statistics`);
  }

  // ===================================================================
  // Provider Credentials - Nested Resource
  // ===================================================================

  /**
   * Get list of provider credentials
   * GET /api/v1/ai/providers/:provider_id/credentials
   */
  async getCredentials(providerId: string): Promise<AiProviderCredential[]> {
    const path = this.buildPath(this.resource, providerId, 'credentials');
    return this.get<AiProviderCredential[]>(path);
  }

  /**
   * Get single credential
   * GET /api/v1/ai/providers/:provider_id/credentials/:id
   */
  async getCredential(providerId: string, credentialId: string): Promise<AiProviderCredential> {
    return this.getNestedOne<AiProviderCredential>(
      this.resource,
      providerId,
      'credentials',
      credentialId
    );
  }

  /**
   * Create new credential
   * POST /api/v1/ai/providers/:provider_id/credentials
   */
  async createCredential(
    providerId: string,
    data: CreateCredentialRequest
  ): Promise<AiProviderCredential> {
    return this.createNested<AiProviderCredential>(this.resource, providerId, 'credentials', {
      credential: data,
    });
  }

  /**
   * Update credential
   * PATCH /api/v1/ai/providers/:provider_id/credentials/:id
   */
  async updateCredential(
    providerId: string,
    credentialId: string,
    data: Partial<CreateCredentialRequest>
  ): Promise<AiProviderCredential> {
    const path = this.buildPath(this.resource, providerId, 'credentials', credentialId);
    return this.patch<AiProviderCredential>(path, { credential: data });
  }

  /**
   * Delete credential
   * DELETE /api/v1/ai/providers/:provider_id/credentials/:id
   */
  async deleteCredential(providerId: string, credentialId: string): Promise<void> {
    return this.removeNested<void>(this.resource, providerId, 'credentials', credentialId);
  }

  /**
   * Test credential
   * POST /api/v1/ai/providers/:provider_id/credentials/:id/test
   */
  async testCredential(providerId: string, credentialId: string): Promise<ConnectionTestResult> {
    return this.performNestedAction<ConnectionTestResult>(
      this.resource,
      providerId,
      'credentials',
      credentialId,
      'test'
    );
  }

  /**
   * Make credential default
   * POST /api/v1/ai/providers/:provider_id/credentials/:id/make_default
   */
  async makeCredentialDefault(
    providerId: string,
    credentialId: string
  ): Promise<AiProviderCredential> {
    return this.performNestedAction<AiProviderCredential>(
      this.resource,
      providerId,
      'credentials',
      credentialId,
      'make_default'
    );
  }

  /**
   * Rotate credential
   * POST /api/v1/ai/providers/:provider_id/credentials/:id/rotate
   */
  async rotateCredential(
    providerId: string,
    credentialId: string,
    newApiKey?: string
  ): Promise<AiProviderCredential> {
    return this.performNestedAction<AiProviderCredential>(
      this.resource,
      providerId,
      'credentials',
      credentialId,
      'rotate',
      { new_api_key: newApiKey }
    );
  }

  /**
   * Test all credentials for a provider
   * POST /api/v1/ai/providers/:provider_id/credentials/test_all
   */
  async testAllCredentials(providerId: string): Promise<Array<{
    credential_id: string;
    name: string;
    result: ConnectionTestResult;
  }>> {
    const path = this.buildPath(this.resource, providerId, 'credentials');
    return this.post<Array<{
      credential_id: string;
      name: string;
      result: ConnectionTestResult;
    }>>(`${path}/test_all`);
  }
}

// Export singleton instance
export const providersApi = new ProvidersApiService();
export default providersApi;
