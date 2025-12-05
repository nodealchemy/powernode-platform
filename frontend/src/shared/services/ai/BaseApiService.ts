import { api } from '../api';
import { AxiosRequestConfig, AxiosResponse } from 'axios';

/**
 * BaseApiService - Foundation for all AI Orchestration API services
 *
 * Provides standardized methods for interacting with the consolidated
 * AI Orchestration controllers following RESTful nested resource patterns.
 *
 * Architecture:
 * - Workflows: /api/v1/ai/workflows/:id/runs
 * - Agents: /api/v1/ai/agents/:id/executions
 * - Providers: /api/v1/ai/providers/:id/credentials
 * - Monitoring: /api/v1/ai/monitoring/*
 * - Analytics: /api/v1/ai/analytics/*
 * - Marketplace: /api/v1/ai/marketplace/*
 */

export interface ApiResponse<T> {
  success: boolean;
  data: T;
  error?: string;
  message?: string;
}

export interface PaginatedResponse<T> {
  items: T[];
  pagination: {
    current_page: number;
    total_pages: number;
    total_count: number;
    per_page: number;
  };
}

export interface QueryFilters {
  page?: number;
  per_page?: number;
  search?: string;
  status?: string;
  sort_by?: string;
  sort_order?: 'asc' | 'desc';
  [key: string]: any;
}

/**
 * Base API Service class providing common functionality for all AI services
 */
export abstract class BaseApiService {
  protected client = api;
  protected baseNamespace = '/ai';

  /**
   * Build a resource path with optional parent resource
   *
   * @param resource - Primary resource (e.g., 'workflows', 'agents')
   * @param id - Optional resource ID
   * @param nestedResource - Optional nested resource (e.g., 'runs', 'executions')
   * @param nestedId - Optional nested resource ID
   * @param action - Optional action path (e.g., 'cancel', 'retry')
   * @returns Full API path
   *
   * Examples:
   * - buildPath('workflows') → '/ai/workflows'
   * - buildPath('workflows', '123') → '/ai/workflows/123'
   * - buildPath('workflows', '123', 'runs') → '/ai/workflows/123/runs'
   * - buildPath('workflows', '123', 'runs', '456') → '/ai/workflows/123/runs/456'
   * - buildPath('workflows', '123', 'runs', '456', 'cancel') → '/ai/workflows/123/runs/456/cancel'
   */
  protected buildPath(
    resource: string,
    id?: string,
    nestedResource?: string,
    nestedId?: string,
    action?: string
  ): string {
    let path = `${this.baseNamespace}/${resource}`;

    if (id) {
      path += `/${id}`;

      if (nestedResource) {
        path += `/${nestedResource}`;

        if (nestedId) {
          path += `/${nestedId}`;

          if (action) {
            path += `/${action}`;
          }
        }
      } else if (action) {
        // Action on primary resource
        path += `/${action}`;
      }
    }

    return path;
  }

  /**
   * Build query string from filters object
   *
   * @param filters - Query parameters object
   * @returns URL query string (without leading '?')
   */
  protected buildQueryString(filters?: QueryFilters): string {
    if (!filters) return '';

    const params = new URLSearchParams();

    Object.entries(filters).forEach(([key, value]) => {
      if (value !== undefined && value !== null && value !== '') {
        if (Array.isArray(value)) {
          params.append(key, value.join(','));
        } else {
          params.append(key, String(value));
        }
      }
    });

    const queryString = params.toString();
    return queryString ? `?${queryString}` : '';
  }

  /**
   * Extract data from API response
   * Handles both wrapped ({ success, data }) and unwrapped responses
   */
  protected extractData<T>(response: AxiosResponse<ApiResponse<T> | T>): T {
    const data = response.data;

    // Check if response is wrapped in standard API format
    if (data && typeof data === 'object' && 'data' in data) {
      return (data as ApiResponse<T>).data;
    }

    // Return unwrapped data
    return data as T;
  }

  /**
   * GET request with automatic data extraction
   */
  protected async get<T>(url: string, config?: AxiosRequestConfig): Promise<T> {
    const response = await this.client.get<ApiResponse<T> | T>(url, config);
    return this.extractData(response);
  }

  /**
   * POST request with automatic data extraction
   */
  protected async post<T>(
    url: string,
    data?: any,
    config?: AxiosRequestConfig
  ): Promise<T> {
    const response = await this.client.post<ApiResponse<T> | T>(url, data, config);
    return this.extractData(response);
  }

  /**
   * PUT request with automatic data extraction
   */
  protected async put<T>(
    url: string,
    data?: any,
    config?: AxiosRequestConfig
  ): Promise<T> {
    const response = await this.client.put<ApiResponse<T> | T>(url, data, config);
    return this.extractData(response);
  }

  /**
   * PATCH request with automatic data extraction
   */
  protected async patch<T>(
    url: string,
    data?: any,
    config?: AxiosRequestConfig
  ): Promise<T> {
    const response = await this.client.patch<ApiResponse<T> | T>(url, data, config);
    return this.extractData(response);
  }

  /**
   * DELETE request with automatic data extraction
   */
  protected async delete<T>(url: string, config?: AxiosRequestConfig): Promise<T> {
    const response = await this.client.delete<ApiResponse<T> | T>(url, config);
    return this.extractData(response);
  }

  /**
   * GET request for paginated list
   *
   * @param resource - Resource name (e.g., 'workflows')
   * @param filters - Query filters including pagination params
   * @returns Paginated response
   */
  protected async getList<T>(
    resource: string,
    filters?: QueryFilters
  ): Promise<PaginatedResponse<T>> {
    const queryString = this.buildQueryString(filters);
    const path = this.buildPath(resource) + queryString;
    return this.get<PaginatedResponse<T>>(path);
  }

  /**
   * GET request for single resource
   *
   * @param resource - Resource name
   * @param id - Resource ID
   * @returns Resource data
   */
  protected async getOne<T>(resource: string, id: string): Promise<T> {
    const path = this.buildPath(resource, id);
    return this.get<T>(path);
  }

  /**
   * POST request to create resource
   *
   * @param resource - Resource name
   * @param data - Resource data
   * @returns Created resource
   */
  protected async create<T>(resource: string, data: any): Promise<T> {
    const path = this.buildPath(resource);
    return this.post<T>(path, data);
  }

  /**
   * PATCH request to update resource
   *
   * @param resource - Resource name
   * @param id - Resource ID
   * @param data - Update data
   * @returns Updated resource
   */
  protected async update<T>(resource: string, id: string, data: any): Promise<T> {
    const path = this.buildPath(resource, id);
    return this.patch<T>(path, data);
  }

  /**
   * DELETE request to remove resource
   *
   * @param resource - Resource name
   * @param id - Resource ID
   * @returns Delete response
   */
  protected async remove<T = void>(resource: string, id: string): Promise<T> {
    const path = this.buildPath(resource, id);
    return this.delete<T>(path);
  }

  /**
   * POST request for resource action
   *
   * @param resource - Resource name
   * @param id - Resource ID
   * @param action - Action name (e.g., 'execute', 'cancel')
   * @param data - Optional action data
   * @returns Action response
   */
  protected async performAction<T>(
    resource: string,
    id: string,
    action: string,
    data?: any
  ): Promise<T> {
    const path = this.buildPath(resource, id, undefined, undefined, action);
    return this.post<T>(path, data);
  }

  /**
   * GET request for nested resource list
   *
   * @param parentResource - Parent resource name
   * @param parentId - Parent resource ID
   * @param nestedResource - Nested resource name
   * @param filters - Query filters
   * @returns Paginated nested resources
   */
  protected async getNestedList<T>(
    parentResource: string,
    parentId: string,
    nestedResource: string,
    filters?: QueryFilters
  ): Promise<PaginatedResponse<T>> {
    const queryString = this.buildQueryString(filters);
    const path = this.buildPath(parentResource, parentId, nestedResource) + queryString;
    return this.get<PaginatedResponse<T>>(path);
  }

  /**
   * GET request for single nested resource
   *
   * @param parentResource - Parent resource name
   * @param parentId - Parent resource ID
   * @param nestedResource - Nested resource name
   * @param nestedId - Nested resource ID
   * @returns Nested resource data
   */
  protected async getNestedOne<T>(
    parentResource: string,
    parentId: string,
    nestedResource: string,
    nestedId: string
  ): Promise<T> {
    const path = this.buildPath(parentResource, parentId, nestedResource, nestedId);
    return this.get<T>(path);
  }

  /**
   * POST request to create nested resource
   *
   * @param parentResource - Parent resource name
   * @param parentId - Parent resource ID
   * @param nestedResource - Nested resource name
   * @param data - Resource data
   * @returns Created nested resource
   */
  protected async createNested<T>(
    parentResource: string,
    parentId: string,
    nestedResource: string,
    data: any
  ): Promise<T> {
    const path = this.buildPath(parentResource, parentId, nestedResource);
    return this.post<T>(path, data);
  }

  /**
   * POST request for nested resource action
   *
   * @param parentResource - Parent resource name
   * @param parentId - Parent resource ID
   * @param nestedResource - Nested resource name
   * @param nestedId - Nested resource ID
   * @param action - Action name
   * @param data - Optional action data
   * @returns Action response
   */
  protected async performNestedAction<T>(
    parentResource: string,
    parentId: string,
    nestedResource: string,
    nestedId: string,
    action: string,
    data?: any
  ): Promise<T> {
    const path = this.buildPath(parentResource, parentId, nestedResource, nestedId, action);
    return this.post<T>(path, data);
  }

  /**
   * DELETE request for nested resource
   *
   * @param parentResource - Parent resource name
   * @param parentId - Parent resource ID
   * @param nestedResource - Nested resource name
   * @param nestedId - Nested resource ID
   * @returns Delete response
   */
  protected async removeNested<T = void>(
    parentResource: string,
    parentId: string,
    nestedResource: string,
    nestedId: string
  ): Promise<T> {
    const path = this.buildPath(parentResource, parentId, nestedResource, nestedId);
    return this.delete<T>(path);
  }
}

export default BaseApiService;
