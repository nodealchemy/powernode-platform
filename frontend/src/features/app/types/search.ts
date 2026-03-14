/**
 * Enhanced search and filtering types for marketplace
 */

export type SortOption = 'relevance' | 'popularity' | 'price_low' | 'price_high' | 'newest' | 'oldest' | 'rating' | 'name';
export type ViewMode = 'grid' | 'list' | 'compact';
export type PriceType = 'free' | 'paid' | 'freemium' | 'subscription';

export interface MarketplaceFilters {
  query?: string;
  categories?: string[];
  priceTypes?: PriceType[];
  priceRange?: {
    min: number;
    max: number;
  };
  features?: string[];
  ratings?: number[]; // e.g., [4, 5] for 4+ stars
  tags?: string[];
  sortBy?: SortOption;
  viewMode?: ViewMode;
  page?: number;
  perPage?: number;
  status?: string;
}

export interface SearchFacets {
  categories: CategoryFacet[];
  priceTypes: PriceTypeFacet[];
  features: FeatureFacet[];
  ratings: RatingFacet[];
  tags: TagFacet[];
}

export interface CategoryFacet {
  slug: string;
  name: string;
  count: number;
  icon?: string;
}

export interface PriceTypeFacet {
  type: PriceType;
  label: string;
  count: number;
}

export interface FeatureFacet {
  slug: string;
  name: string;
  count: number;
  category?: string;
}

export interface RatingFacet {
  rating: number;
  count: number;
  label: string; // e.g., "4 stars & up"
}

export interface TagFacet {
  slug: string;
  name: string;
  count: number;
  color?: string;
}

 
export interface SearchResult<T = any> {
  data: T[];
  facets: SearchFacets;
  total: number;
  page: number;
  perPage: number;
  totalPages: number;
  hasMore: boolean;
}

export interface SearchContextType {
  filters: MarketplaceFilters;
  setFilters: (filters: MarketplaceFilters) => void;
   
  updateFilter: (key: keyof MarketplaceFilters, value: any) => void;
  clearFilters: () => void;
  isLoading: boolean;
  results: SearchResult | null;
  error: string | null;
}

// Preset filter combinations for quick access
export interface FilterPreset {
  id: string;
  name: string;
  description: string;
  filters: Partial<MarketplaceFilters>;
  icon?: string;
}

export const DEFAULT_FILTER_PRESETS: FilterPreset[] = [
  {
    id: 'free-apps',
    name: 'Free Apps',
    description: 'Apps with free plans available',
    filters: { priceTypes: ['free', 'freemium'] },
    icon: '🆓'
  },
  {
    id: 'popular',
    name: 'Most Popular',
    description: 'Trending apps with high ratings',
    filters: { sortBy: 'popularity', ratings: [4, 5] },
    icon: '🔥'
  },
  {
    id: 'newest',
    name: 'New Releases',
    description: 'Recently published apps',
    filters: { sortBy: 'newest' },
    icon: '✨'
  },
  {
    id: 'high-rated',
    name: 'Top Rated',
    description: 'Apps with 4+ star ratings',
    filters: { sortBy: 'rating', ratings: [4, 5] },
    icon: '⭐'
  },
  {
    id: 'api-tools',
    name: 'API Tools',
    description: 'Development and integration tools',
    filters: { categories: ['developer-tools', 'integrations'] },
    icon: '🔧'
  }
];

export const SORT_OPTIONS: Array<{ value: SortOption; label: string; description?: string }> = [
  { value: 'relevance', label: 'Relevance', description: 'Best match for your search' },
  { value: 'popularity', label: 'Popularity', description: 'Most installed apps' },
  { value: 'rating', label: 'Highest Rated', description: 'Best customer reviews' },
  { value: 'newest', label: 'Newest', description: 'Recently published' },
  { value: 'name', label: 'Name A-Z', description: 'Alphabetical order' },
  { value: 'price_low', label: 'Price: Low to High', description: 'Cheapest first' },
  { value: 'price_high', label: 'Price: High to Low', description: 'Most expensive first' }
];

export const VIEW_MODE_OPTIONS: Array<{ value: ViewMode; label: string; icon: string; description: string }> = [
  { value: 'grid', label: 'Grid', icon: '⊞', description: 'Card grid layout' },
  { value: 'list', label: 'List', icon: '☰', description: 'Detailed list view' },
  { value: 'compact', label: 'Compact', icon: '≡', description: 'Dense list layout' }
];