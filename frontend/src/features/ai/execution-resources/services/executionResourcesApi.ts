import { BaseApiService, QueryFilters, PaginatedResponse } from '@/shared/services/ai/BaseApiService';
import type { ExecutionResource, ResourceDetail, ResourceCounts, ResourceFilters } from '../types';

class ExecutionResourcesApiService extends BaseApiService {
  private resource = 'execution_resources';

  async getResources(filters?: ResourceFilters): Promise<PaginatedResponse<ExecutionResource>> {
    const queryString = this.buildQueryString(filters as QueryFilters);
    const path = this.buildPath(this.resource) + queryString;
    return this.get<PaginatedResponse<ExecutionResource>>(path);
  }

  async getResourceCounts(filters?: ResourceFilters): Promise<{ counts: ResourceCounts }> {
    const queryString = this.buildQueryString(filters as QueryFilters);
    const path = this.buildPath(this.resource) + '/counts' + queryString;
    return this.get<{ counts: ResourceCounts }>(path);
  }

  async getResourceDetail(resourceType: string, id: string): Promise<{ resource: ResourceDetail }> {
    const path = this.buildPath(this.resource) + `/${resourceType}/${id}`;
    return this.get<{ resource: ResourceDetail }>(path);
  }
}

export const executionResourcesApi = new ExecutionResourcesApiService();
