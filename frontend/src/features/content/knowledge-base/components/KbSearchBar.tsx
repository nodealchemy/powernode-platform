import { useState, useEffect } from 'react';
import { Button } from '@/shared/components/ui/Button';
import { KbCategory } from '@/shared/services/content/knowledgeBaseApi';
import { 
  MagnifyingGlassIcon, 
  XMarkIcon,
  FunnelIcon 
} from '@heroicons/react/24/outline';

interface KbSearchBarProps {
  value: string;
  onChange: (value: string) => void;
  onSearch: () => void;
  onClear: () => void;
  categories: KbCategory[];
  selectedCategory: string | null;
  onCategoryChange: (categoryId: string | null) => void;
  placeholder?: string;
}

export function KbSearchBar({
  value,
  onChange,
  onSearch,
  onClear,
  categories,
  selectedCategory,
  onCategoryChange,
  placeholder = "Search articles, guides, and documentation..."
}: KbSearchBarProps) {
  const [showFilters, setShowFilters] = useState(false);

  // Auto-search when typing (debounced)
  useEffect(() => {
    const timer = setTimeout(() => {
      if (value.trim()) {
        onSearch();
      }
    }, 300);

    return () => clearTimeout(timer);
  }, [value, onSearch]);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onSearch();
  };

  const handleClear = () => {
    onChange('');
    onCategoryChange(null);
    onClear();
    setShowFilters(false);
  };

  const hasActiveFilters = value.trim() || selectedCategory;

  return (
    <div className="space-y-4">
      {/* Search Input */}
      <form onSubmit={handleSubmit} className="flex gap-3">
        <div className="flex-1 relative">
          <MagnifyingGlassIcon className="absolute left-3 top-1/2 transform -translate-y-1/2 h-5 w-5 text-theme-tertiary" />
          <input
            type="text"
            value={value}
            onChange={(e) => onChange(e.target.value)}
            placeholder={placeholder}
            className="w-full pl-10 pr-4 py-3 border border-theme rounded-lg bg-theme-surface text-theme-primary placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary focus:border-transparent"
          />
        </div>
        
        <Button
          type="button"
          variant="secondary"
          onClick={() => setShowFilters(!showFilters)}
          className={selectedCategory ? 'ring-2 ring-theme-primary' : ''}
        >
          <FunnelIcon className="h-4 w-4 mr-1" />
          Filters
        </Button>

        {hasActiveFilters && (
          <Button
            type="button"
            variant="ghost"
            onClick={handleClear}
          >
            <XMarkIcon className="h-4 w-4 mr-1" />
            Clear
          </Button>
        )}
      </form>

      {/* Filters Panel */}
      {showFilters && (
        <div className="border border-theme rounded-lg p-4 bg-theme-surface">
          <div className="space-y-4">
            {/* Category Filter */}
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Category
              </label>
              <select
                value={selectedCategory || ''}
                onChange={(e) => onCategoryChange(e.target.value || null)}
                className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary focus:border-transparent"
              >
                <option value="">All Categories</option>
                {categories.map(category => (
                  <CategoryOption key={category.id} category={category} level={0} />
                ))}
              </select>
            </div>

            {/* Filter Actions */}
            <div className="flex items-center justify-between pt-2 border-t border-theme">
              <div className="text-sm text-theme-secondary">
                {hasActiveFilters && (
                  <span>
                    {value && `Search: "${value}"`}
                    {value && selectedCategory && ' • '}
                    {selectedCategory && `Category: ${categories.find(c => c.id === selectedCategory)?.name}`}
                  </span>
                )}
              </div>
              <div className="flex gap-2">
                <Button
                  size="sm"
                  variant="ghost"
                  onClick={() => setShowFilters(false)}
                >
                  Close
                </Button>
                {hasActiveFilters && (
                  <Button
                    size="sm"
                    variant="secondary"
                    onClick={handleClear}
                  >
                    Clear All
                  </Button>
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Quick Filters */}
      {!showFilters && hasActiveFilters && (
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-sm text-theme-secondary">Active filters:</span>
          
          {value && (
            <div className="flex items-center gap-1 bg-theme-primary/10 text-theme-primary px-3 py-1 rounded-full text-sm">
              <span>Search: "{value}"</span>
              <button
                onClick={() => onChange('')}
                className="hover:bg-theme-primary/20 rounded-full p-0.5"
              >
                <XMarkIcon className="h-3 w-3" />
              </button>
            </div>
          )}

          {selectedCategory && (
            <div className="flex items-center gap-1 bg-theme-primary/10 text-theme-primary px-3 py-1 rounded-full text-sm">
              <span>{categories.find(c => c.id === selectedCategory)?.name}</span>
              <button
                onClick={() => onCategoryChange(null)}
                className="hover:bg-theme-primary/20 rounded-full p-0.5"
              >
                <XMarkIcon className="h-3 w-3" />
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function CategoryOption({ 
  category, 
  level 
}: { 
  category: KbCategory; 
  level: number;
}) {
  const indent = '—'.repeat(level);
  
  return (
    <>
      <option value={category.id}>
        {indent} {category.name} ({category.article_count})
      </option>
      {category.children?.map(child => (
        <CategoryOption key={child.id} category={child} level={level + 1} />
      ))}
    </>
  );
}