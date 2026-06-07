import { BaseApiService, QueryFilters, PaginatedResponse } from '@/shared/services/ai/BaseApiService';
import type {
  AiDataSource,
  AiDataSourceCredential,
  DataSourceQuota,
  AiDataSourceEndpoint,
  DataSourceEndpointRequest,
  DataSourceFetchEnvelope,
  DataSourceDiscoveryResponse,
  DataSourceSchemaHistoryResponse,
  DataSourceQualityResponse,
  DataSourceOpenApiImportRequest,
  DataSourceOpenApiImportResult,
  DataSourceContractVerdict,
} from '@/shared/types/ai';
import type { ConnectionTestResult } from '@/shared/services/ai/ProvidersApiService';

/**
 * DataSourcesApiService - Data Sources Controller API Client
 *
 * Provides access to the Data Sources Controller endpoints.
 *
 * Endpoint structure:
 * - GET    /api/v1/ai/data_sources
 * - POST   /api/v1/ai/data_sources
 * - POST   /api/v1/ai/data_sources/discover
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
   * Semantically discover data sources for a natural-language need.
   * POST /api/v1/ai/data_sources/discover
   *
   * Backed by Ai::DataSources::SemanticDiscoveryService (the same engine behind
   * the `data_source_discover` MCP action): query embedding → pgvector
   * nearest-neighbor over data_source knowledge-graph nodes, blended with each
   * source's effectiveness / health / recency signals, with a keyword-name
   * fallback when no embedding backend is available. Returns the ranked
   * candidates with their per-signal score breakdown.
   *
   * @param query - Natural-language description of the data need
   * @param options - Optional result cap and LLM-reranking toggle
   */
  async discover(
    query: string,
    options?: { limit?: number; rerank?: boolean }
  ): Promise<DataSourceDiscoveryResponse> {
    // Collection action: buildPath only appends an action when an id is present,
    // so the discover path is composed directly off the resource root.
    const path = `${this.baseNamespace}/${this.resource}/discover`;
    return this.post<DataSourceDiscoveryResponse>(path, {
      query,
      ...(options?.limit !== undefined ? { limit: options.limit } : {}),
      ...(options?.rerank !== undefined ? { rerank: options.rerank } : {}),
    });
  }

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

  // ===================================================================
  // Data Source Endpoints - Nested Resource
  //
  // The endpoint routes are keyed by :endpoint_id (not :id):
  // - GET    /api/v1/ai/data_sources/:data_source_id/endpoints
  // - POST   /api/v1/ai/data_sources/:data_source_id/endpoints
  // - PATCH  /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id
  // - DELETE /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id
  // - POST   /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id/query
  //
  // Phase 2b observability endpoints (read schema/quality, import, contract):
  // - GET    /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id/schema_history
  // - GET    /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id/quality
  // - GET    /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id/contract
  // - POST   /api/v1/ai/data_sources/:data_source_id/introspect   (OpenAPI import)
  // ===================================================================

  /**
   * List endpoints for a data source.
   * GET /api/v1/ai/data_sources/:data_source_id/endpoints
   * Server returns { items, count }; this returns just the endpoint array.
   */
  async getEndpoints(dataSourceId: string): Promise<AiDataSourceEndpoint[]> {
    const path = this.buildPath(this.resource, dataSourceId, 'endpoints');
    const response = await this.get<{ items: AiDataSourceEndpoint[]; count: number }>(path);
    return response.items ?? [];
  }

  /**
   * Create a new endpoint.
   * POST /api/v1/ai/data_sources/:data_source_id/endpoints
   * Server returns { endpoint }, unwrapped here to the endpoint.
   */
  async createEndpoint(
    dataSourceId: string,
    data: DataSourceEndpointRequest
  ): Promise<AiDataSourceEndpoint> {
    const path = this.buildPath(this.resource, dataSourceId, 'endpoints');
    const response = await this.post<{ endpoint: AiDataSourceEndpoint }>(path, { endpoint: data });
    return response.endpoint;
  }

  /**
   * Update an existing endpoint.
   * PATCH /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id
   * Server returns { endpoint }, unwrapped here to the endpoint.
   */
  async updateEndpoint(
    dataSourceId: string,
    endpointId: string,
    data: Partial<DataSourceEndpointRequest>
  ): Promise<AiDataSourceEndpoint> {
    const path = this.buildPath(this.resource, dataSourceId, 'endpoints', endpointId);
    const response = await this.patch<{ endpoint: AiDataSourceEndpoint }>(path, { endpoint: data });
    return response.endpoint;
  }

  /**
   * Delete an endpoint.
   * DELETE /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id
   */
  async deleteEndpoint(dataSourceId: string, endpointId: string): Promise<void> {
    const path = this.buildPath(this.resource, dataSourceId, 'endpoints', endpointId);
    return this.delete<void>(path);
  }

  /**
   * Run a governed query against an endpoint.
   * POST /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id/query
   * Returns the QueryService FetchEnvelope (data + provenance + status + metrics).
   */
  async runQuery(
    dataSourceId: string,
    endpointId: string,
    params: Record<string, unknown>
  ): Promise<DataSourceFetchEnvelope> {
    const path = this.buildPath(this.resource, dataSourceId, 'endpoints', endpointId, 'query');
    return this.post<DataSourceFetchEnvelope>(path, { params });
  }

  // ===================================================================
  // Data Source Endpoints - Phase 2b Observability
  // ===================================================================

  /**
   * Fetch the recorded response-schema version history for an endpoint.
   * GET /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id/schema_history
   *
   * Each version carries its drift classification (initial|none|additive|breaking)
   * vs the prior version plus the structural diff. Backed by the rows
   * Ai::DataSources::SchemaDriftService#record_version! appends. Requires
   * ai.data_sources.read.
   */
  async getSchemaHistory(
    dataSourceId: string,
    endpointId: string
  ): Promise<DataSourceSchemaHistoryResponse> {
    const path = this.buildPath(this.resource, dataSourceId, 'endpoints', endpointId, 'schema_history');
    return this.get<DataSourceSchemaHistoryResponse>(path);
  }

  /**
   * Fetch the latest data-quality outcome plus configured expectations for an
   * endpoint.
   * GET /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id/quality
   *
   * Returns the most recent quality-evaluated fetch's score / pass state /
   * quarantine flag alongside the endpoint's Ai::DataSourceExpectation rules.
   * Requires ai.data_sources.read.
   */
  async getEndpointQuality(
    dataSourceId: string,
    endpointId: string
  ): Promise<DataSourceQualityResponse> {
    const path = this.buildPath(this.resource, dataSourceId, 'endpoints', endpointId, 'quality');
    return this.get<DataSourceQualityResponse>(path);
  }

  /**
   * Fetch the aggregate contract verdict (schema + quality + freshness) for an
   * endpoint.
   * GET /api/v1/ai/data_sources/:data_source_id/endpoints/:endpoint_id/contract
   *
   * Runs Ai::DataSources::ContractService over a fresh/last-known fetch envelope.
   * Requires ai.data_sources.read.
   */
  async getEndpointContract(
    dataSourceId: string,
    endpointId: string
  ): Promise<DataSourceContractVerdict> {
    const path = this.buildPath(this.resource, dataSourceId, 'endpoints', endpointId, 'contract');
    return this.get<DataSourceContractVerdict>(path);
  }

  /**
   * Import endpoints from an OpenAPI 3 document (structural parse: paths ->
   * endpoints, components/schemas -> response_schema).
   * POST /api/v1/ai/data_sources/:data_source_id/introspect
   *
   * Supply either a parsed `spec` object or a `url` for the server to fetch
   * (SSRF-guarded server-side). With `dry_run: true` the service returns a
   * preview without persisting; `dry_run: false` (default) persists and returns
   * the created endpoints. Backed by Ai::DataSources::OpenApiImportService.
   * Because it creates endpoints, the server requires ai.data_sources.manage.
   */
  async importOpenApi(
    dataSourceId: string,
    request: DataSourceOpenApiImportRequest
  ): Promise<DataSourceOpenApiImportResult> {
    // Collection-style action on the data source: composed directly off the
    // resource root (buildPath only appends an action when an id is present).
    const path = `${this.baseNamespace}/${this.resource}/${dataSourceId}/introspect`;
    return this.post<DataSourceOpenApiImportResult>(path, request);
  }
}

// Export singleton instance
export const dataSourcesApi = new DataSourcesApiService();
export default dataSourcesApi;
