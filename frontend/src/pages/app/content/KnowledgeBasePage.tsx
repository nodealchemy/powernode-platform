import { useState, useEffect } from 'react';
import { useSearchParams } from 'react-router-dom';
import { PageContainer, BreadcrumbItem } from '@/shared/components/layout/PageContainer';
import { KbCategoryList } from '@/features/content/knowledge-base/components/KbCategoryList';
import { KbArticleList } from '@/features/content/knowledge-base/components/KbArticleList';
import { KbSearchBar } from '@/features/content/knowledge-base/components/KbSearchBar';
import { KbFeaturedArticles } from '@/features/content/knowledge-base/components/KbFeaturedArticles';
import { knowledgeBaseApi, KbCategory, KbArticle } from '@/shared/services/content/knowledgeBaseApi';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { Button } from '@/shared/components/ui/Button';
import { useNavigate } from 'react-router-dom';
import { usePageWebSocket } from '@/shared/hooks/usePageWebSocket';
import { PlusIcon, BookOpenIcon, TagIcon, ExclamationTriangleIcon } from '@heroicons/react/24/outline';
import { hasPermissions } from '@/shared/utils/permissionUtils';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { logger } from '@/shared/utils/logger';

export default function KnowledgeBasePage() {
  const { user: currentUser } = useSelector((state: RootState) => state.auth);
  const navigate = useNavigate();
  usePageWebSocket({ pageType: 'content' });
  const [searchParams, setSearchParams] = useSearchParams();
  const [categories, setCategories] = useState<KbCategory[]>([]);
  const [articles, setArticles] = useState<KbArticle[]>([]);
  const [featuredArticles, setFeaturedArticles] = useState<KbArticle[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState(searchParams.get('q') || '');
  const [selectedCategory, setSelectedCategory] = useState<string | null>(searchParams.get('category') || null);

  const canManageKb = hasPermissions(currentUser, ['kb.manage']) || hasPermissions(currentUser, ['kb.update']);

  // Generate dynamic breadcrumbs based on current filters
  const getBreadcrumbs = (): BreadcrumbItem[] => {
    const breadcrumbs: BreadcrumbItem[] = [
      {
        label: 'Dashboard',
        href: '/app',
        icon: BookOpenIcon
      },
      {
        label: 'Knowledge Base'
      }
    ];

    // Add category breadcrumb if filtering by category
    if (selectedCategory) {
      const category = categories.find(c => c.id === selectedCategory);
      if (category) {
        breadcrumbs.push({
          label: category.name,
          href: `/app/content/kb?category=${selectedCategory}`
        });
      }
    }

    // Add search breadcrumb if searching
    if (searchQuery) {
      breadcrumbs.push({
        label: `Search: "${searchQuery}"`
      });
    }

    return breadcrumbs;
  };

  // Load categories + featured once on mount. Articles are owned by the
  // search/category effect below (which also runs on mount), so they are
  // fetched exactly once rather than racing a second fetch here.
  useEffect(() => {
    loadInitialData();
  }, []);

  useEffect(() => {
    if (searchQuery || selectedCategory) {
      handleSearch();
    } else {
      loadArticles();
    }
  }, [searchQuery, selectedCategory]);

  const loadInitialData = async () => {
    try {
      setIsLoading(true);
      setError(null);

      const [categoriesResponse, featuredResponse] = await Promise.all([
        knowledgeBaseApi.getCategories(),
        knowledgeBaseApi.getArticles({ featured: true, per_page: 5 })
      ]);

      setCategories(categoriesResponse.data.data);
      setFeaturedArticles(featuredResponse.data.data.articles);
    } catch (_error) {
      logger.error('[KnowledgeBasePage] Failed to load initial data', _error);
      setError('Failed to load the knowledge base. Please try again.');
    } finally {
      setIsLoading(false);
    }
  };

  const loadArticles = async () => {
    try {
      setError(null);
      const response = await knowledgeBaseApi.getArticles({ per_page: 20 });
      setArticles(response.data.data.articles);
    } catch (_error) {
      logger.error('[KnowledgeBasePage] Failed to load articles', _error);
      setError('Failed to load articles. Please try again.');
    }
  };

  const handleSearch = async () => {
    if (!searchQuery && !selectedCategory) {
      loadArticles();
      return;
    }

    try {
      setError(null);
      let response;

      if (searchQuery) {
        response = await knowledgeBaseApi.searchArticles({
          q: searchQuery,
          category_id: selectedCategory || undefined,
          per_page: 20
        });
      } else {
        response = await knowledgeBaseApi.getArticles({
          category_id: selectedCategory || undefined,
          per_page: 20
        });
      }

      setArticles(response.data.data.articles);

      // Update URL params
      const params = new URLSearchParams();
      if (searchQuery) params.set('q', searchQuery);
      if (selectedCategory) params.set('category', selectedCategory);
      setSearchParams(params);
    } catch (_error) {
      logger.error('[KnowledgeBasePage] Search failed', _error);
      setError('Search failed. Please try again.');
    }
  };

  const handleClearSearch = () => {
    setSearchQuery('');
    setSelectedCategory(null);
    setSearchParams({});
  };

  const actions = canManageKb ? [
    {
      id: 'create-article',
      label: 'Create Article',
      onClick: () => navigate('/app/content/kb/articles/new'),
      variant: 'primary' as const,
      icon: PlusIcon
    }
  ] : [];

  const isSearching = searchQuery || selectedCategory;

  if (isLoading) {
    return (
      <PageContainer
        title="Knowledge Base"
        description="Browse articles, guides, and documentation"
        breadcrumbs={[
          { label: 'Dashboard', href: '/app', icon: BookOpenIcon },
          { label: 'Knowledge Base' }
        ]}
      >
        <LoadingSpinner className="h-64" />
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="Knowledge Base"
      description="Browse articles, guides, and documentation"
      breadcrumbs={getBreadcrumbs()}
      actions={actions}
    >
      <div className="space-y-6">
        {/* Error banner — distinguishes a load/search failure from "no articles" */}
        {error && (
          <div className="flex items-center gap-3 rounded-lg border border-theme-error-border bg-theme-error-bg px-4 py-3 text-sm text-theme-error-fg">
            <ExclamationTriangleIcon className="h-5 w-5 flex-shrink-0" />
            <span>{error}</span>
          </div>
        )}

        {/* Search and Filters */}
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <KbSearchBar
            value={searchQuery}
            onChange={setSearchQuery}
            onSearch={handleSearch}
            onClear={handleClearSearch}
            categories={categories}
            selectedCategory={selectedCategory}
            onCategoryChange={setSelectedCategory}
          />
        </div>

        {isSearching ? (
          /* Search Results */
          <div className="space-y-6">
            <div className="flex items-center justify-between">
              <div>
                <h2 className="text-lg font-semibold text-theme-primary">
                  Search Results
                </h2>
                {searchQuery && (
                  <p className="text-sm text-theme-secondary mt-1">
                    Results for: "{searchQuery}"
                  </p>
                )}
                {selectedCategory && (
                  <p className="text-sm text-theme-secondary mt-1">
                    Category: {categories.find(c => c.id === selectedCategory)?.name}
                  </p>
                )}
              </div>
              <Button
                variant="ghost"
                size="sm"
                onClick={handleClearSearch}
              >
                Clear Filters
              </Button>
            </div>

            <KbArticleList articles={articles} showCategory={!selectedCategory} />

            {articles.length === 0 && (
              <div className="text-center py-12">
                <TagIcon className="h-12 w-12 text-theme-tertiary mx-auto mb-4" />
                <h3 className="text-lg font-medium text-theme-primary mb-2">
                  No articles found
                </h3>
                <p className="text-theme-secondary">
                  Try adjusting your search terms or browse categories below.
                </p>
              </div>
            )}
          </div>
        ) : (
          /* Default View */
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            {/* Main Content */}
            <div className="lg:col-span-2 space-y-6">
              {/* Featured Articles */}
              {featuredArticles.length > 0 && (
                <div>
                  <h2 className="text-lg font-semibold text-theme-primary mb-4">
                    Featured Articles
                  </h2>
                  <KbFeaturedArticles articles={featuredArticles} />
                </div>
              )}

              {/* Recent Articles */}
              <div>
                <h2 className="text-lg font-semibold text-theme-primary mb-4">
                  Recent Articles
                </h2>
                <KbArticleList articles={articles} showCategory />
              </div>
            </div>

            {/* Sidebar */}
            <div className="space-y-6">
              {/* Categories */}
              <div>
                <h2 className="text-lg font-semibold text-theme-primary mb-4">
                  Categories
                </h2>
                <KbCategoryList 
                  categories={categories} 
                  onCategorySelect={(categoryId) => {
                    setSelectedCategory(categoryId);
                    setSearchQuery('');
                  }}
                />
              </div>

              {/* Quick Links */}
              {canManageKb && (
                <div className="bg-theme-surface rounded-lg border border-theme p-4">
                  <h3 className="font-medium text-theme-primary mb-3">Quick Actions</h3>
                  <div className="space-y-2">
                    <Button
                      onClick={() => navigate('/app/content/kb/manage')}
                      variant="ghost"
                      size="sm"
                      className="w-full justify-start"
                    >
                      Manage Knowledge Base
                    </Button>
                    <Button
                      onClick={() => navigate('/app/content/kb/admin/analytics')}
                      variant="ghost"
                      size="sm"
                      className="w-full justify-start"
                    >
                      View Analytics
                    </Button>
                  </div>
                </div>
              )}
            </div>
          </div>
        )}
      </div>
    </PageContainer>
  );
}