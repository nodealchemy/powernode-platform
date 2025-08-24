import React, { useState } from 'react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Card } from '@/shared/components/ui/Card';
import { CategoryFacet } from '../../types/search';
import { ChevronRight, Grid, TrendingUp, Clock } from 'lucide-react';

interface CategoryNavigationProps {
  categories: CategoryFacet[];
  selectedCategories: string[];
  onCategorySelect: (categorySlug: string) => void;
  onCategoryToggle: (categorySlug: string) => void;
  showFeatured?: boolean;
  className?: string;
}

interface CategoryGroup {
  name: string;
  categories: CategoryFacet[];
  icon: string;
  color: string;
}

// Predefined category groups for better organization
const CATEGORY_GROUPS: CategoryGroup[] = [
  {
    name: 'Developer Tools',
    categories: [],
    icon: '🔧',
    color: 'bg-theme-primary'
  },
  {
    name: 'Business Apps',
    categories: [],
    icon: '💼', 
    color: 'bg-theme-success'
  },
  {
    name: 'Marketing',
    categories: [],
    icon: '📈',
    color: 'bg-purple-500'
  },
  {
    name: 'Communication',
    categories: [],
    icon: '💬',
    color: 'bg-orange-500'
  },
  {
    name: 'Analytics',
    categories: [],
    icon: '📊',
    color: 'bg-indigo-500'
  },
  {
    name: 'Security',
    categories: [],
    icon: '🛡️',
    color: 'bg-theme-error'
  }
];

export const CategoryNavigation: React.FC<CategoryNavigationProps> = ({
CategoryNavigation.displayName = 'CategoryNavigation';
  categories,
  selectedCategories,
  onCategorySelect,
  onCategoryToggle,
  showFeatured = true,
  className = ''
}) => {
  const [expandedGroups, setExpandedGroups] = useState<string[]>(['Developer Tools']);

  // Group categories by predefined groups
  const groupedCategories = React.useMemo(() => {
    const groups = CATEGORY_GROUPS.map(group => ({
      ...group,
      categories: categories.filter(cat => 
        group.name.toLowerCase().includes(cat.name.toLowerCase()) ||
        cat.name.toLowerCase().includes(group.name.toLowerCase()) ||
        (group.name === 'Developer Tools' && 
         ['api', 'webhook', 'integration', 'developer', 'tools', 'sdk'].some(keyword => 
           cat.name.toLowerCase().includes(keyword)))
      )
    }));

    // Add ungrouped categories to "Other" group
    const groupedCategoryNames = groups.flatMap(g => g.categories.map(c => c.slug));
    const ungroupedCategories = categories.filter(cat => !groupedCategoryNames.includes(cat.slug));
    
    if (ungroupedCategories.length > 0) {
      groups.push({
        name: 'Other',
        categories: ungroupedCategories,
        icon: '📦',
        color: 'bg-theme-secondary'
      });
    }

    return groups.filter(group => group.categories.length > 0);
  }, [categories]);

  const toggleGroup = (groupName: string) => {
    setExpandedGroups(prev => 
      prev.includes(groupName)
        ? prev.filter(name => name !== groupName)
        : [...prev, groupName]
    );
  };

  const handleCategoryClick = (categorySlug: string, isMultiSelect: boolean = false) => {
    if (isMultiSelect) {
      onCategoryToggle(categorySlug);
    } else {
      onCategorySelect(categorySlug);
    }
  };

  // Featured categories based on app count
  const featuredCategories = categories
    .sort((a, b) => b.count - a.count)
    .slice(0, 6);

  return (
    <div className={`space-y-6 ${className}`}>
      {/* Featured Categories */}
      {showFeatured && featuredCategories.length > 0 && (
        <Card className="p-4">
          <div className="flex items-center space-x-2 mb-4">
            <TrendingUp className="w-5 h-5 text-theme-warning" />
            <h3 className="font-semibold text-theme-primary">Popular Categories</h3>
          </div>
          
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
            {featuredCategories.map((category) => (
              <button
                key={`featured-${category.slug}`}
                onClick={() => handleCategoryClick(category.slug)}
                className={`p-3 text-left rounded-lg border-2 transition-all duration-200 ${
                  selectedCategories.includes(category.slug)
                    ? 'border-theme-interactive-primary bg-theme-interactive-primary/10'
                    : 'border-theme hover:border-theme-interactive-primary/50 bg-theme-surface hover:bg-theme-surface-hover'
                }`}
              >
                <div className="flex items-center justify-between mb-1">
                  <span className="text-base">{category.icon || '📁'}</span>
                  <Badge variant="secondary" className="text-xs">
                    {category.count}
                  </Badge>
                </div>
                <div className="font-medium text-sm text-theme-primary">
                  {category.name}
                </div>
              </button>
            ))}
          </div>
        </Card>
      )}

      {/* All Categories by Group */}
      <Card className="p-4">
        <div className="flex items-center space-x-2 mb-4">
          <Grid className="w-5 h-5 text-theme-interactive-primary" />
          <h3 className="font-semibold text-theme-primary">All Categories</h3>
        </div>

        <div className="space-y-4">
          {groupedCategories.map((group) => {
            const isExpanded = expandedGroups.includes(group.name);
            const hasSelectedInGroup = group.categories.some(cat => selectedCategories.includes(cat.slug));

            return (
              <div key={group.name} className="space-y-2">
                {/* Group Header */}
                <button
                  onClick={() => toggleGroup(group.name)}
                  className={`w-full flex items-center justify-between p-2 rounded-lg transition-colors ${
                    hasSelectedInGroup
                      ? 'bg-theme-interactive-primary/10 border border-theme-interactive-primary/20'
                      : 'bg-theme-surface hover:bg-theme-surface-hover'
                  }`}
                >
                  <div className="flex items-center space-x-3">
                    <span className="text-lg">{group.icon}</span>
                    <span className="font-medium text-theme-primary">{group.name}</span>
                    <Badge variant="secondary" className="text-xs">
                      {group.categories.reduce((sum, cat) => sum + cat.count, 0)}
                    </Badge>
                  </div>
                  <ChevronRight
                    className={`w-4 h-4 text-theme-tertiary transition-transform ${
                      isExpanded ? 'rotate-90' : ''
                    }`}
                  />
                </button>

                {/* Group Categories */}
                {isExpanded && (
                  <div className="pl-4 space-y-1">
                    {group.categories.map((category) => (
                      <button
                        key={category.slug}
                        onClick={(e) => {
                          const isMultiSelect = e.ctrlKey || e.metaKey;
                          handleCategoryClick(category.slug, isMultiSelect);
                        }}
                        className={`w-full flex items-center justify-between p-2 text-left rounded transition-colors ${
                          selectedCategories.includes(category.slug)
                            ? 'bg-theme-success/10 text-theme-success border border-theme-success/20'
                            : 'text-theme-secondary hover:text-theme-primary hover:bg-theme-surface-hover'
                        }`}
                      >
                        <div className="flex items-center space-x-2">
                          <span className="text-sm">{category.icon || '📄'}</span>
                          <span className="text-sm">{category.name}</span>
                        </div>
                        <Badge
                          variant={selectedCategories.includes(category.slug) ? 'success' : 'secondary'}
                          className="text-xs"
                        >
                          {category.count}
                        </Badge>
                      </button>
                    ))}
                  </div>
                )}
              </div>
            );
          })}
        </div>

        {/* Quick Actions */}
        <div className="flex items-center justify-between pt-4 mt-4 border-t border-theme">
          <div className="text-sm text-theme-tertiary">
            {selectedCategories.length > 0 ? (
              <span>{selectedCategories.length} category{selectedCategories.length !== 1 ? 'ies' : 'y'} selected</span>
            ) : (
              <span>Click categories to filter, Ctrl+click for multiple</span>
            )}
          </div>
          
          {selectedCategories.length > 0 && (
            <Button
              variant="outline"
              size="sm"
              onClick={() => selectedCategories.forEach(cat => onCategoryToggle(cat))}
              className="text-xs"
            >
              Clear Selection
            </Button>
          )}
        </div>
      </Card>

      {/* Recently Viewed Categories (placeholder) */}
      <Card className="p-4">
        <div className="flex items-center space-x-2 mb-4">
          <Clock className="w-5 h-5 text-theme-secondary" />
          <h3 className="font-semibold text-theme-primary">Recently Viewed</h3>
        </div>
        
        <div className="text-sm text-theme-secondary text-center py-4">
          <p>Your recently browsed categories will appear here</p>
        </div>
      </Card>
    </div>
  );
};