/**
 * Unified Marketplace Type System
 *
 * Core types for the unified marketplace supporting apps, plugins, and templates.
 * Clean foundational implementation without backwards compatibility.
 */

export type MarketplaceItemType = 'app' | 'plugin' | 'template';

export interface MarketplaceItem {
  id: string;
  type: MarketplaceItemType;
  name: string;
  slug: string;
  description: string;
  category: string;
  tags: string[];
  icon?: string;
  version: string;
  rating: number;
  install_count: number;
  is_verified: boolean;
  status: 'published' | 'draft';
  created_at: string;
}

export interface MarketplaceFilters {
  types?: MarketplaceItemType[];
  search?: string;
  category?: string;
  verified?: boolean;
}

export interface MarketplaceMeta {
  total_count: number;
  current_page: number;
  per_page: number;
  total_pages: number;
}
