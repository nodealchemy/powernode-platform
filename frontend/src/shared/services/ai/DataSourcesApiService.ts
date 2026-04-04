import { BaseApiService, QueryFilters, PaginatedResponse } from '@/shared/services/ai/BaseApiService';
import type { AiDataSource, AiDataSourceCredential, DataSourceQuota } from '@/shared/types/ai';
import type { ConnectionTestResult } from '@/shared/services/ai/ProvidersApiService';

/**
 * DataSourcesApiService - Data Sources Controller API Client
 *
 * Provides access to the Data Sources Controller endpoints.
 *
 * Endpoint structure:
 * - GET    /api/v1/ai/data_sources
 * - POST   /api/v1/ai/data_sources
 * - GET    /api/v1/ai/data_sources/:id
 * - PATCH  /api/v1/ai/data_sources/:id
 * - DELETE /api/v1/ai/data_sources/:id
 * - POST   /api/v1/ai/data_sources/:id/test_connection
 * - GET    /api/v1/ai/data_sources/:id/quota_status
 * - GET    /api/v1/ai/data_sources/:data_source_id/credentials
 * - POST   /api/v1/ai/data_sources/:data_source_id/credentials
 * - PATCH  /api/v1/ai/data_sources/:data_source_id/credentials/:id
 * - DELETE /api/v1/ai/data_sources/:data_source_id/credentials/:id
 * - POST   /api/v1/ai/data_sources/:data_source_id/credentials/:id/test
 * - POST   /api/v1/ai/data_sources/:data_source_id/credentials/:id/make_default
 */

export interface DataSourceQueryFilters extends QueryFilters {
  source_type?: string;
}

export interface CreateDataSourceRequest {
  name: string;
  source_type: string;
  slug?: string;
  description?: string;
  api_base_url?: string;
  capabilities?: string[];
  configuration?: Record<string, unknown>;
  rate_limits?: Record<string, number>;
  default_parameters?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
  is_active?: boolean;
  requires_auth?: boolean;
  priority_order?: number;
  documentation_url?: string;
}

export interface CreateDataSourceCredentialRequest {
  name: string;
  api_key: string;
  is_active?: boolean;
  is_default?: boolean;
  expires_at?: string;
}

class DataSourcesApiService extends BaseApiService {
  private resource = 'data_sources';

  // ===================================================================
  // Data Source CRUD Operations
  // ===================================================================

  /**
   * Get list of data sources with optional filters
   * GET /api/v1/ai/data_sources
   */
  async getDataSources(filters?: DataSourceQueryFilters): Promise<PaginatedResponse<AiDataSource>> {
    return this.getList<AiDataSource>(this.resource, filters);
  }

  /**
   * Get single data source by ID
   * GET /api/v1/ai/data_sources/:id
   * Returns { data_source: AiDataSource } from API, unwrapped to just AiDataSource
   */
  async getDataSource(id: string): Promise<AiDataSource> {
    const response = await this.getOne<{ data_source: AiDataSource }>(this.resource, id);
    return response.data_source;
  }

  /**
   * Create new data source
   * POST /api/v1/ai/data_sources
   */
  async createDataSource(data: CreateDataSourceRequest): Promise<AiDataSource> {
    return this.create<AiDataSource>(this.resource, { data_source: data });
  }

  /**
   * Update existing data source
   * PATCH /api/v1/ai/data_sources/:id
   */
  async updateDataSource(id: string, data: Partial<CreateDataSourceRequest>): Promise<AiDataSource> {
    return this.update<AiDataSource>(this.resource, id, { data_source: data });
  }

  /**
   * Delete data source
   * DELETE /api/v1/ai/data_sources/:id
   */
  async deleteDataSource(id: string): Promise<void> {
    return this.remove<void>(this.resource, id);
  }

  // ===================================================================
  // Data Source Actions
  // ===================================================================

  /**
   * Test data source connection
   * POST /api/v1/ai/data_sources/:id/test_connection
   */
  async testConnection(id: string): Promise<ConnectionTestResult> {
    return this.performAction<ConnectionTestResult>(this.resource, id, 'test_connection');
  }

  /**
   * Get current quota status
   * GET /api/v1/ai/data_sources/:id/quota_status
   */
  async getQuotaStatus(id: string): Promise<DataSourceQuota> {
    const path = this.buildPath(this.resource, id, undefined, undefined, 'quota_status');
    return this.get<DataSourceQuota>(path);
  }

  // ===================================================================
  // Data Source Credentials - Nested Resource
  // ===================================================================

  /**
   * Get list of data source credentials
   * GET /api/v1/ai/data_sources/:data_source_id/credentials
   */
  async getCredentials(dataSourceId: string): Promise<AiDataSourceCredential[]> {
    const path = this.buildPath(this.resource, dataSourceId, 'credentials');
    return this.get<AiDataSourceCredential[]>(path);
  }

  /**
   * Get single credential
   * GET /api/v1/ai/data_sources/:data_source_id/credentials/:id
   */
  async getCredential(dataSourceId: string, credentialId: string): Promise<AiDataSourceCredential> {
    return this.getNestedOne<AiDataSourceCredential>(
      this.resource,
      dataSourceId,
      'credentials',
      credentialId
    );
  }

  /**
   * Create new credential
   * POST /api/v1/ai/data_sources/:data_source_id/credentials
   */
  async createCredential(
    dataSourceId: string,
    data: CreateDataSourceCredentialRequest
  ): Promise<AiDataSourceCredential> {
    return this.createNested<AiDataSourceCredential>(this.resource, dataSourceId, 'credentials', {
      credential: data,
    });
  }

  /**
   * Update credential
   * PATCH /api/v1/ai/data_sources/:data_source_id/credentials/:id
   */
  async updateCredential(
    dataSourceId: string,
    credentialId: string,
    data: Partial<CreateDataSourceCredentialRequest>
  ): Promise<AiDataSourceCredential> {
    const path = this.buildPath(this.resource, dataSourceId, 'credentials', credentialId);
    return this.patch<AiDataSourceCredential>(path, { credential: data });
  }

  /**
   * Delete credential
   * DELETE /api/v1/ai/data_sources/:data_source_id/credentials/:id
   */
  async deleteCredential(dataSourceId: string, credentialId: string): Promise<void> {
    return this.removeNested<void>(this.resource, dataSourceId, 'credentials', credentialId);
  }

  /**
   * Test credential
   * POST /api/v1/ai/data_sources/:data_source_id/credentials/:id/test
   */
  async testCredential(dataSourceId: string, credentialId: string): Promise<ConnectionTestResult> {
    return this.performNestedAction<ConnectionTestResult>(
      this.resource,
      dataSourceId,
      'credentials',
      credentialId,
      'test'
    );
  }

  /**
   * Make credential default
   * POST /api/v1/ai/data_sources/:data_source_id/credentials/:id/make_default
   */
  async makeDefaultCredential(
    dataSourceId: string,
    credentialId: string
  ): Promise<AiDataSourceCredential> {
    return this.performNestedAction<AiDataSourceCredential>(
      this.resource,
      dataSourceId,
      'credentials',
      credentialId,
      'make_default'
    );
  }
}

// Export singleton instance
export const dataSourcesApi = new DataSourcesApiService();
export default dataSourcesApi;
