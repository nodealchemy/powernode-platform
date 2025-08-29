import React, { useState, useRef, useEffect, useMemo } from 'react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Card } from '@/shared/components/ui/Card';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { MarketplaceFilters, SearchFacets, FilterPreset, DEFAULT_FILTER_PRESETS, SORT_OPTIONS, VIEW_MODE_OPTIONS } from '../../types/search';
import { Search, Filter, X, ChevronDown, BarChart3, Star, DollarSign, Tag, Sliders } from 'lucide-react';

interface MarketplaceSearchProps {
  filters: MarketplaceFilters;
  facets?: SearchFacets;
  onFiltersChange: (filters: MarketplaceFilters) => void;
  onSearch: (query: string) => void;
  isLoading?: boolean;
  resultCount?: number;
  className?: string;
}

export const MarketplaceSearch: React.FC<MarketplaceSearchProps> = ({
  filters,
  facets,
  onFiltersChange,
  onSearch,
  isLoading = false,
  resultCount = 0,
  className = ''
}) => {
  const [searchQuery, setSearchQuery] = useState(filters.query || '');
  const [showAdvancedFilters, setShowAdvancedFilters] = useState(false);
  const [showSortDropdown, setShowSortDropdown] = useState(false);
  const searchInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    setSearchQuery(filters.query || '');
  }, [filters.query]);

  const handleSearchSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onSearch(searchQuery);
    onFiltersChange({ ...filters, query: searchQuery, page: 1 });
  };

  const handleFilterChange = (key: keyof MarketplaceFilters, value: any) => {
    const newFilters = { ...filters, [key]: value, page: 1 };
    onFiltersChange(newFilters);
  };

  const handleArrayFilterToggle = (key: keyof MarketplaceFilters, value: string) => {
    const currentArray = (Object.prototype.hasOwnProperty.call(filters, key) ? filters[key as keyof typeof filters] as string[] : []) || [];
    const newArray = currentArray.includes(value)
      ? currentArray.filter(item => item !== value)
      : [...currentArray, value];
    handleFilterChange(key, newArray);
  };

  const handlePresetFilter = (preset: FilterPreset) => {
    const newFilters = { ...filters, ...preset.filters, page: 1 };
    onFiltersChange(newFilters);
  };

  const clearAllFilters = () => {
    onFiltersChange({ 
      query: searchQuery,
      sortBy: 'relevance',
      viewMode: filters.viewMode || 'grid',
      page: 1,
      perPage: filters.perPage || 20
    });
  };

  // Fixed: Memoized active filter count to prevent expensive array checks on every render
  const activeFilterCount = useMemo(() => {
    let count = 0;
    if (filters.categories?.length) count += filters.categories.length;
    if (filters.priceTypes?.length) count += filters.priceTypes.length;
    if (filters.features?.length) count += filters.features.length;
    if (filters.ratings?.length) count += filters.ratings.length;
    if (filters.tags?.length) count += filters.tags.length;
    if (filters.priceRange) count += 1;
    return count;
  }, [filters.categories, filters.priceTypes, filters.features, filters.ratings, filters.tags, filters.priceRange]);
  const selectedSort = SORT_OPTIONS.find(option => option.value === filters.sortBy) || SORT_OPTIONS[0];
  // Removed unused selectedViewMode variable

  return (
    <div className={`space-y-4 ${className}`}>
      {/* Search Bar and Quick Actions */}
      <div className="flex flex-col sm:flex-row gap-4 items-start sm:items-center">
        {/* Search Input */}
        <form onSubmit={handleSearchSubmit} className="flex-1 w-full sm:w-auto">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-theme-tertiary w-5 h-5" />
            <input
              ref={searchInputRef}
              type="text"
              placeholder="Search apps, integrations, and tools..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full pl-10 pr-4 py-2.5 border border-theme rounded-lg bg-theme-surface text-theme-primary placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
            />
            {isLoading && (
              <div className="absolute right-3 top-1/2 transform -translate-y-1/2">
                <LoadingSpinner size="sm" />
              </div>
            )}
          </div>
        </form>

        {/* View Mode Toggle */}
        <div className="hidden sm:flex items-center bg-theme-surface border border-theme rounded-lg p-1">
          {VIEW_MODE_OPTIONS.map((mode) => (
            <button
              key={mode.value}
              onClick={() => handleFilterChange('viewMode', mode.value)}
              className={`px-3 py-1.5 text-sm font-medium rounded transition-colors ${
                filters.viewMode === mode.value
                  ? 'bg-theme-interactive-primary text-white'
                  : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover'
              }`}
              title={mode.description}
            >
              <span className="text-base">{mode.icon}</span>
            </button>
          ))}
        </div>

        {/* Sort Dropdown */}
        <div className="relative">
          <button
            onClick={() => setShowSortDropdown(!showSortDropdown)}
            className="flex items-center space-x-2 px-4 py-2.5 border border-theme rounded-lg bg-theme-surface text-theme-primary hover:bg-theme-surface-hover transition-colors"
          >
            <BarChart3 className="w-4 h-4" />
            <span className="text-sm font-medium">{selectedSort.label}</span>
            <ChevronDown className="w-4 h-4" />
          </button>

          {showSortDropdown && (
            <Card className="absolute right-0 top-full mt-2 w-56 z-20 p-2">
              <div className="space-y-1">
                {SORT_OPTIONS.map((option) => (
                  <button
                    key={option.value}
                    onClick={() => {
                      handleFilterChange('sortBy', option.value);
                      setShowSortDropdown(false);
                    }}
                    className={`w-full text-left px-3 py-2 text-sm rounded transition-colors ${
                      filters.sortBy === option.value
                        ? 'bg-theme-interactive-primary text-white'
                        : 'text-theme-primary hover:bg-theme-surface-hover'
                    }`}
                  >
                    <div className="font-medium">{option.label}</div>
                    {option.description && (
                      <div className="text-xs text-theme-secondary">{option.description}</div>
                    )}
                  </button>
                ))}
              </div>
            </Card>
          )}
        </div>

        {/* Advanced Filters Toggle */}
        <Button
          variant="outline"
          size="sm"
          onClick={() => setShowAdvancedFilters(!showAdvancedFilters)}
          className="relative"
        >
          <Filter className="w-4 h-4" />
          <span className="ml-2 hidden sm:inline">Filters</span>
          {activeFilterCount > 0 && (
            <Badge
              variant="primary"
              className="absolute -top-2 -right-2 w-5 h-5 text-xs rounded-full flex items-center justify-center p-0"
            >
              {activeFilterCount}
            </Badge>
          )}
        </Button>
      </div>

      {/* Filter Presets */}
      <div className="flex flex-wrap gap-2">
        {DEFAULT_FILTER_PRESETS.map((preset) => (
          <button
            key={preset.id}
            onClick={() => handlePresetFilter(preset)}
            className="flex items-center space-x-2 px-3 py-1.5 text-sm bg-theme-surface hover:bg-theme-surface-hover border border-theme rounded-lg transition-colors"
          >
            <span>{preset.icon}</span>
            <span className="font-medium text-theme-primary">{preset.name}</span>
          </button>
        ))}
      </div>

      {/* Active Filters Display */}
      {activeFilterCount > 0 && (
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-sm font-medium text-theme-secondary">Active filters:</span>
          
          {/* Category filters */}
          {filters.categories?.map((category) => (
            <button
              key={`category-${category}`}
              onClick={() => handleArrayFilterToggle('categories', category)}
              className="inline-flex"
            >
              <Badge
                variant="secondary"
                className="flex items-center space-x-1 cursor-pointer hover:bg-theme-error/10"
              >
                <Tag className="w-3 h-3" />
                <span>{category}</span>
                <X className="w-3 h-3" />
              </Badge>
            </button>
          ))}

          {/* Price type filters */}
          {filters.priceTypes?.map((priceType) => (
            <button
              key={`price-${priceType}`}
              onClick={() => handleArrayFilterToggle('priceTypes', priceType)}
              className="inline-flex"
            >
              <Badge
                variant="secondary"
                className="flex items-center space-x-1 cursor-pointer hover:bg-theme-error/10"
              >
                <DollarSign className="w-3 h-3" />
                <span>{priceType}</span>
                <X className="w-3 h-3" />
              </Badge>
            </button>
          ))}

          {/* Rating filters */}
          {filters.ratings?.map((rating) => (
            <button
              key={`rating-${rating}`}
              onClick={() => handleArrayFilterToggle('ratings', rating.toString())}
              className="inline-flex"
            >
              <Badge
                variant="secondary"
                className="flex items-center space-x-1 cursor-pointer hover:bg-theme-error/10"
              >
                <Star className="w-3 h-3" />
                <span>{rating}+ stars</span>
                <X className="w-3 h-3" />
              </Badge>
            </button>
          ))}

          {/* Clear all button */}
          <Button
            variant="outline"
            size="sm"
            onClick={clearAllFilters}
            className="text-theme-error border-theme-error hover:bg-theme-error/10"
          >
            <X className="w-4 h-4" />
            <span className="ml-1">Clear all</span>
          </Button>
        </div>
      )}

      {/* Results Summary */}
      <div className="flex items-center justify-between text-sm text-theme-secondary">
        <span>
          {isLoading ? (
            'Searching...'
          ) : (
            `${resultCount.toLocaleString()} ${resultCount === 1 ? 'app' : 'apps'} found`
          )}
          {filters.query && (
            <span> for "{filters.query}"</span>
          )}
        </span>
        
        {resultCount > 0 && (
          <span className="hidden sm:inline">
            Sorted by {selectedSort.label.toLowerCase()}
          </span>
        )}
      </div>

      {/* Advanced Filters Panel */}
      {showAdvancedFilters && facets && (
        <Card className="p-6">
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
            {/* Categories */}
            {facets.categories.length > 0 && (
              <div>
                <h4 className="font-semibold text-theme-primary mb-3 flex items-center">
                  <Tag className="w-4 h-4 mr-2" />
                  Categories
                </h4>
                <div className="space-y-2">
                  {facets.categories.map((category) => (
                    <label key={category.slug} className="flex items-center space-x-2 cursor-pointer">
                      <input
                        type="checkbox"
                        checked={filters.categories?.includes(category.slug) || false}
                        onChange={() => handleArrayFilterToggle('categories', category.slug)}
                        className="rounded border-theme-border text-theme-interactive-primary focus:ring-theme-interactive-primary"
                      />
                      <span className="text-sm text-theme-primary">{category.name}</span>
                      <Badge variant="secondary" className="text-xs">
                        {category.count}
                      </Badge>
                    </label>
                  ))}
                </div>
              </div>
            )}

            {/* Price Types */}
            {facets.priceTypes.length > 0 && (
              <div>
                <h4 className="font-semibold text-theme-primary mb-3 flex items-center">
                  <DollarSign className="w-4 h-4 mr-2" />
                  Pricing
                </h4>
                <div className="space-y-2">
                  {facets.priceTypes.map((priceType) => (
                    <label key={priceType.type} className="flex items-center space-x-2 cursor-pointer">
                      <input
                        type="checkbox"
                        checked={filters.priceTypes?.includes(priceType.type) || false}
                        onChange={() => handleArrayFilterToggle('priceTypes', priceType.type)}
                        className="rounded border-theme-border text-theme-interactive-primary focus:ring-theme-interactive-primary"
                      />
                      <span className="text-sm text-theme-primary">{priceType.label}</span>
                      <Badge variant="secondary" className="text-xs">
                        {priceType.count}
                      </Badge>
                    </label>
                  ))}
                </div>
              </div>
            )}

            {/* Ratings */}
            {facets.ratings.length > 0 && (
              <div>
                <h4 className="font-semibold text-theme-primary mb-3 flex items-center">
                  <Star className="w-4 h-4 mr-2" />
                  Rating
                </h4>
                <div className="space-y-2">
                  {facets.ratings.map((rating) => (
                    <label key={rating.rating} className="flex items-center space-x-2 cursor-pointer">
                      <input
                        type="checkbox"
                        checked={filters.ratings?.includes(rating.rating) || false}
                        onChange={() => handleArrayFilterToggle('ratings', rating.rating.toString())}
                        className="rounded border-theme-border text-theme-interactive-primary focus:ring-theme-interactive-primary"
                      />
                      <span className="text-sm text-theme-primary">{rating.label}</span>
                      <Badge variant="secondary" className="text-xs">
                        {rating.count}
                      </Badge>
                    </label>
                  ))}
                </div>
              </div>
            )}

            {/* Features */}
            {facets.features.length > 0 && (
              <div>
                <h4 className="font-semibold text-theme-primary mb-3 flex items-center">
                  <Sliders className="w-4 h-4 mr-2" />
                  Features
                </h4>
                <div className="space-y-2 max-h-48 overflow-y-auto">
                  {facets.features.map((feature) => (
                    <label key={feature.slug} className="flex items-center space-x-2 cursor-pointer">
                      <input
                        type="checkbox"
                        checked={filters.features?.includes(feature.slug) || false}
                        onChange={() => handleArrayFilterToggle('features', feature.slug)}
                        className="rounded border-theme-border text-theme-interactive-primary focus:ring-theme-interactive-primary"
                      />
                      <span className="text-sm text-theme-primary">{feature.name}</span>
                      <Badge variant="secondary" className="text-xs">
                        {feature.count}
                      </Badge>
                    </label>
                  ))}
                </div>
              </div>
            )}
          </div>
        </Card>
      )}
    </div>
  );
};