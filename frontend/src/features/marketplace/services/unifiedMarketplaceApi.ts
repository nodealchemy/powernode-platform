/**
 * Unified Marketplace API Service
 *
 * Frontend API service for unified marketplace endpoints.
 * Handles apps, plugins, and templates through a single normalized interface.
 */

import { api } from '@/shared/services/api';
import type {
  MarketplaceItem,
  MarketplaceFilters,
  MarketplaceItemType,
  MarketplaceMeta
} from '../types/unified';

export interface GetItemsResponse {
  success: boolean;
  data: MarketplaceItem[];
  meta?: MarketplaceMeta;
}

export interface GetItemResponse {
  success: boolean;
  data: MarketplaceItem;
}

export interface InstallResponse {
  success: boolean;
  data: {
    id: string;
    item_id: string;
    item_type: string;
    item_name: string;
    status: string;
    installed_at: string;
  };
}

class UnifiedMarketplaceApi {
  /**
   * Get marketplace items with optional filters
   */
  async getItems(filters?: MarketplaceFilters): Promise<GetItemsResponse> {
    const params = new URLSearchParams();

    if (filters?.types && filters.types.length > 0) {
      params.append('types', filters.types.join(','));
    }

    if (filters?.search) {
      params.append('search', filters.search);
    }

    if (filters?.category) {
      params.append('category', filters.category);
    }

    if (filters?.verified !== undefined) {
      params.append('verified', String(filters.verified));
    }

    const queryString = params.toString();
    const url = `/marketplace/unified${queryString ? `?${queryString}` : ''}`;

    const response = await api.get(url);
    return response.data;
  }

  /**
   * Get a single marketplace item by type and ID
   */
  async getItem(type: MarketplaceItemType, id: string): Promise<GetItemResponse> {
    const response = await api.get(`/marketplace/unified/${type}/${id}`);
    return response.data;
  }

  /**
   * Install a marketplace item
   */
  async install(type: MarketplaceItemType, id: string): Promise<InstallResponse> {
    const response = await api.post(`/marketplace/unified/${type}/${id}/install`, {});
    return response.data;
  }
}

export const unifiedMarketplaceApi = new UnifiedMarketplaceApi();
