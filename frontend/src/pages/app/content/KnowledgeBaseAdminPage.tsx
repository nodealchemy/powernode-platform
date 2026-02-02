import { useState, useEffect } from 'react';
import { PageContainer, BreadcrumbItem } from '@/shared/components/layout/PageContainer';
import { knowledgeBaseAdminApi, KbArticle, KbCategory } from '@/shared/services/content/knowledgeBaseApi';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { useDispatch } from 'react-redux';
import { addNotification } from '@/shared/services/slices/uiSlice';
import { AppDispatch } from '@/shared/services';
import { 
  PlusIcon, 
 
  ChartBarIcon, 
  DocumentTextIcon,
  FolderIcon,
  ChatBubbleLeftRightIcon,
  BookOpenIcon,
  MagnifyingGlassIcon,
  FunnelIcon,
  TrashIcon,
  ArchiveBoxIcon,
  CheckIcon,
  XMarkIcon
} from '@heroicons/react/24/outline';
import { Navigate } from 'react-router-dom';

export default function KnowledgeBaseAdminPage() {
  const dispatch = useDispatch<AppDispatch>();
  const { user: currentUser } = useSelector((state: RootState) => state.auth);
  const [articles, setArticles] = useState<KbArticle[]>([]);
  const [categories, setCategories] = useState<KbCategory[]>([]);
  const [stats, setStats] = useState({
    total: 0,
    published: 0,
    draft: 0,
    review: 0,
    archived: 0
  });
  const [isLoading, setIsLoading] = useState(true);
  const [selectedArticles, setSelectedArticles] = useState<string[]>([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [categoryFilter, setCategoryFilter] = useState('');
  const [showFilters, setShowFilters] = useState(false);
  const [currentPage, setCurrentPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);

  // Check permissions
  const canManageKb = currentUser?.permissions?.includes('kb.manage');
  const canEditKb = currentUser?.permissions?.includes('kb.update') || canManageKb;

  // Static breadcrumbs for admin page
  const breadcrumbs: BreadcrumbItem[] = [
    {
      label: 'Dashboard',
      href: '/app',
      icon: BookOpenIcon
    },
    {
      label: 'Knowledge Base',
      href: '/app/content/kb'
    },
    {
      label: 'Admin'
    }
  ];

  useEffect(() => {
    if (canEditKb) {
      loadAdminData();
    }
  }, [canEditKb, currentPage, searchQuery, statusFilter, categoryFilter]);

  const loadAdminData = async () => {
    try {
      setIsLoading(true);
      
      const params = {
        per_page: 20,
        page: currentPage,
        search: searchQuery || undefined,
        status: statusFilter || undefined,
        category_id: categoryFilter || undefined
      };

      const [articlesResponse, categoriesResponse] = await Promise.all([
        knowledgeBaseAdminApi.getArticles(params),
        knowledgeBaseAdminApi.getCategories({ per_page: 100 })
      ]);

      setArticles(articlesResponse.data.data.articles || []);
      setStats(articlesResponse.data.data.stats || { total: 0, published: 0, draft: 0, review: 0, archived: 0 });
      setCategories(categoriesResponse.data.data || []);
      setTotalPages(articlesResponse.data.data.pagination?.total_pages || 1);
    } catch {
      dispatch(addNotification({ type: 'error', message: 'Failed to load data' }));
    } finally {
      setIsLoading(false);
    }
  };

  // Bulk operations
  const toggleArticleSelection = (articleId: string) => {
    setSelectedArticles(prev => 
      prev.includes(articleId) 
        ? prev.filter(id => id !== articleId)
        : [...prev, articleId]
    );
  };

  const selectAllArticles = () => {
    setSelectedArticles(
      selectedArticles.length === articles.length 
        ? [] 
        : articles.map(article => article.id)
    );
  };

  const bulkUpdateStatus = async (status: string) => {
    if (selectedArticles.length === 0) return;

    try {
      await knowledgeBaseAdminApi.bulkUpdateArticles(selectedArticles, { status });
      dispatch(addNotification({ type: 'success', message: `${selectedArticles.length} articles updated` }));
      setSelectedArticles([]);
      loadAdminData();
    } catch {
      dispatch(addNotification({ type: 'error', message: 'Failed to update articles' }));
    }
  };

  const bulkDeleteArticles = async () => {
    if (selectedArticles.length === 0) return;
    
    if (!confirm(`Delete ${selectedArticles.length} articles? This cannot be undone.`)) {
      return;
    }

    try {
      await knowledgeBaseAdminApi.bulkDeleteArticles(selectedArticles);
      dispatch(addNotification({ type: 'success', message: `${selectedArticles.length} articles deleted` }));
      setSelectedArticles([]);
      loadAdminData();
    } catch {
      dispatch(addNotification({ type: 'error', message: 'Failed to delete articles' }));
    }
  };

  if (!canEditKb) {
    return <Navigate to="/app/content/kb" replace />;
  }

  const actions = [
    {
      id: 'create-article',
      label: 'Create Article',
      onClick: () => { window.location.href = '/app/content/kb/admin/articles/new'; },
      variant: 'primary' as const,
      icon: PlusIcon
    },
    {
      id: 'manage-categories',
      label: 'Manage Categories', 
      onClick: () => { window.location.href = '/app/content/kb/admin/categories'; },
      variant: 'secondary' as const,
      icon: FolderIcon
    }
  ];

  // Add bulk actions when articles are selected
  if (selectedArticles.length > 0 && canManageKb) {
    actions.unshift(
      {
        id: 'bulk-publish',
        label: `Publish (${selectedArticles.length})`,
        onClick: () => { bulkUpdateStatus('published'); },
        variant: 'secondary' as const,
        icon: CheckIcon
      },
      {
        id: 'bulk-archive',
        label: `Archive (${selectedArticles.length})`,
        onClick: () => { bulkUpdateStatus('archived'); },
        variant: 'secondary' as const,
        icon: ArchiveBoxIcon
      },
      {
        id: 'bulk-delete',
        label: `Delete (${selectedArticles.length})`,
        onClick: bulkDeleteArticles,
        variant: 'secondary' as const,
        icon: TrashIcon
      }
    );
  }

  if (canManageKb) {
    actions.push({
      id: 'analytics',
      label: 'Analytics',
      onClick: () => window.location.href = '/app/content/kb/admin/analytics',
      variant: 'secondary' as const,
      icon: ChartBarIcon
    });
  }

  if (isLoading) {
    return (
      <PageContainer
        title="Knowledge Base Admin"
        description="Manage articles, categories, and content"
        breadcrumbs={breadcrumbs}
        actions={actions}
      >
        <div className="flex items-center justify-center h-64">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-primary"></div>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title="Knowledge Base Admin"
      description="Manage articles, categories, and content"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="space-y-6">
        {/* Search and Filters */}
        <div className="bg-theme-surface rounded-lg border border-theme p-4">
          <div className="flex flex-col sm:flex-row gap-4 items-start sm:items-center justify-between">
            {/* Search */}
            <div className="flex-1 max-w-md">
              <div className="relative">
                <MagnifyingGlassIcon className="absolute left-3 top-1/2 transform -translate-y-1/2 h-4 w-4 text-theme-secondary" />
                <Input
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  placeholder="Search articles..."
                  className="pl-10"
                />
              </div>
            </div>

            {/* Filter Toggle */}
            <Button
              onClick={() => setShowFilters(!showFilters)}
              variant="ghost"
              size="sm"
              className="flex items-center gap-2"
            >
              <FunnelIcon className="h-4 w-4" />
              Filters
              {(statusFilter || categoryFilter) && (
                <Badge variant="primary" size="sm">
                  {[statusFilter, categoryFilter].filter(Boolean).length}
                </Badge>
              )}
            </Button>
          </div>

          {/* Filter Panel */}
          {showFilters && (
            <div className="mt-4 pt-4 border-t border-theme">
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-1">
                    Status
                  </label>
                  <Select
                    value={statusFilter}
                    onChange={(value) => setStatusFilter(value)}
                  >
                    <option value="">All Statuses</option>
                    <option value="draft">Draft</option>
                    <option value="review">In Review</option>
                    <option value="published">Published</option>
                    <option value="archived">Archived</option>
                  </Select>
                </div>

                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-1">
                    Category
                  </label>
                  <Select
                    value={categoryFilter}
                    onChange={(value) => setCategoryFilter(value)}
                  >
                    <option value="">All Categories</option>
                    {categories.map(category => (
                      <option key={category.id} value={category.id}>
                        {category.name}
                      </option>
                    ))}
                  </Select>
                </div>

                <div className="flex items-end">
                  <Button
                    onClick={() => {
                      setStatusFilter('');
                      setCategoryFilter('');
                      setSearchQuery('');
                    }}
                    variant="ghost"
                    size="sm"
                  >
                    Clear Filters
                  </Button>
                </div>
              </div>
            </div>
          )}
        </div>

        {/* Stats Overview */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4">
          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="flex items-center">
              <DocumentTextIcon className="h-8 w-8 text-theme-secondary" />
              <div className="ml-3">
                <p className="text-sm font-medium text-theme-secondary">Total Articles</p>
                <p className="text-2xl font-bold text-theme-primary">{stats.total}</p>
              </div>
            </div>
          </div>

          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="flex items-center">
              <div className="h-8 w-8 bg-theme-success rounded-lg flex items-center justify-center">
                <span className="text-white text-sm font-bold">P</span>
              </div>
              <div className="ml-3">
                <p className="text-sm font-medium text-theme-secondary">Published</p>
                <p className="text-2xl font-bold text-theme-primary">{stats.published}</p>
              </div>
            </div>
          </div>

          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="flex items-center">
              <div className="h-8 w-8 bg-theme-warning rounded-lg flex items-center justify-center">
                <span className="text-white text-sm font-bold">D</span>
              </div>
              <div className="ml-3">
                <p className="text-sm font-medium text-theme-secondary">Draft</p>
                <p className="text-2xl font-bold text-theme-primary">{stats.draft}</p>
              </div>
            </div>
          </div>

          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="flex items-center">
              <div className="h-8 w-8 bg-theme-info rounded-lg flex items-center justify-center">
                <span className="text-white text-sm font-bold">R</span>
              </div>
              <div className="ml-3">
                <p className="text-sm font-medium text-theme-secondary">In Review</p>
                <p className="text-2xl font-bold text-theme-primary">{stats.review}</p>
              </div>
            </div>
          </div>

          <div className="bg-theme-surface rounded-lg border border-theme p-4">
            <div className="flex items-center">
              <div className="h-8 w-8 bg-theme-surface0 rounded-lg flex items-center justify-center">
                <span className="text-white text-sm font-bold">A</span>
              </div>
              <div className="ml-3">
                <p className="text-sm font-medium text-theme-secondary">Archived</p>
                <p className="text-2xl font-bold text-theme-primary">{stats.archived}</p>
              </div>
            </div>
          </div>
        </div>

        {/* Quick Actions */}
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <h2 className="text-lg font-semibold text-theme-primary mb-4">Quick Actions</h2>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
            <Button
              onClick={() => window.location.href = '/app/content/kb/admin/articles/new'}
              variant="outline"
              className="h-auto p-4 flex-col items-start"
            >
              <PlusIcon className="h-6 w-6 mb-2" />
              <span className="font-medium">Create Article</span>
              <span className="text-sm text-theme-secondary mt-1">Write a new knowledge base article</span>
            </Button>

            <Button
              onClick={() => window.location.href = '/app/content/kb/admin/categories'}
              variant="outline"
              className="h-auto p-4 flex-col items-start"
            >
              <FolderIcon className="h-6 w-6 mb-2" />
              <span className="font-medium">Manage Categories</span>
              <span className="text-sm text-theme-secondary mt-1">Organize articles into categories</span>
            </Button>

            {canManageKb && (
              <Button
                onClick={() => window.location.href = '/app/content/kb/admin/comments'}
                variant="outline"
                className="h-auto p-4 flex-col items-start"
              >
                <ChatBubbleLeftRightIcon className="h-6 w-6 mb-2" />
                <span className="font-medium">Moderate Comments</span>
                <span className="text-sm text-theme-secondary mt-1">Review and approve comments</span>
              </Button>
            )}

            {canManageKb && (
              <Button
                onClick={() => window.location.href = '/app/content/kb/admin/analytics'}
                variant="outline"
                className="h-auto p-4 flex-col items-start"
              >
                <ChartBarIcon className="h-6 w-6 mb-2" />
                <span className="font-medium">View Analytics</span>
                <span className="text-sm text-theme-secondary mt-1">Track content performance</span>
              </Button>
            )}
          </div>
        </div>

        {/* Articles List */}
        <div>
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center gap-4">
              <h2 className="text-lg font-semibold text-theme-primary">Articles</h2>
              {selectedArticles.length > 0 && (
                <div className="flex items-center gap-2">
                  <Badge variant="primary">{selectedArticles.length} selected</Badge>
                  <Button
                    onClick={() => setSelectedArticles([])}
                    variant="ghost"
                    size="sm"
                  >
                    <XMarkIcon className="h-4 w-4" />
                  </Button>
                </div>
              )}
            </div>
            
            {articles.length > 0 && (
              <div className="flex items-center gap-2">
                <Button
                  onClick={selectAllArticles}
                  variant="ghost"
                  size="sm"
                >
                  {selectedArticles.length === articles.length ? 'Deselect All' : 'Select All'}
                </Button>
              </div>
            )}
          </div>
          
          {articles.length > 0 ? (
            <div className="space-y-4">
              {articles.map(article => (
                <div 
                  key={article.id}
                  className={`bg-theme-surface rounded-lg border p-4 transition-colors ${
                    selectedArticles.includes(article.id) 
                      ? 'border-theme-primary bg-theme-primary/5' 
                      : 'border-theme hover:border-theme-secondary'
                  }`}
                >
                  <div className="flex items-start gap-4">
                    {/* Selection Checkbox */}
                    <div className="pt-1">
                      <input
                        type="checkbox"
                        checked={selectedArticles.includes(article.id)}
                        onChange={() => toggleArticleSelection(article.id)}
                        className="h-4 w-4 text-theme-primary focus:ring-theme-primary border-theme rounded"
                      />
                    </div>

                    <div className="flex-1">
                      <div className="flex items-center gap-3 mb-2">
                        <h3 className="font-medium text-theme-primary line-clamp-1">
                          {article.title}
                        </h3>
                        <Badge 
                          variant={
                            article.status === 'published' ? 'success' : 
                            article.status === 'draft' ? 'warning' : 
                            article.status === 'review' ? 'primary' : 'secondary'
                          }
                          size="sm"
                        >
                          {article.status}
                        </Badge>
                        {article.is_featured && (
                          <Badge variant="primary" size="sm">Featured</Badge>
                        )}
                      </div>
                      
                      <div className="flex items-center gap-4 text-sm text-theme-secondary">
                        <span>By {article.author_name}</span>
                        <span>{article.category.name}</span>
                        <span>{article.views_count} views</span>
                        {article.comments_count !== undefined && (
                          <span>{article.comments_count} comments</span>
                        )}
                      </div>
                    </div>

                    <div className="flex items-center gap-2">
                      <Button
                        onClick={() => window.location.href = `/app/content/kb/articles/${article.id}`}
                        variant="ghost"
                        size="sm"
                      >
                        View
                      </Button>
                      <Button
                        onClick={() => window.location.href = `/app/content/kb/admin/articles/${article.id}/edit`}
                        variant="ghost"
                        size="sm"
                      >
                        Edit
                      </Button>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <div className="text-center py-12 bg-theme-surface rounded-lg border border-theme">
              <DocumentTextIcon className="h-12 w-12 text-theme-tertiary mx-auto mb-4" />
              <h3 className="text-lg font-medium text-theme-primary mb-2">
                No articles yet
              </h3>
              <p className="text-theme-secondary mb-4">
                Get started by creating your first knowledge base article.
              </p>
              <Button
                onClick={() => window.location.href = '/app/content/kb/admin/articles/new'}
                variant="primary"
              >
                <PlusIcon className="h-4 w-4 mr-1" />
                Create First Article
              </Button>
            </div>
          )}

          {/* Pagination */}
          {totalPages > 1 && (
            <div className="flex items-center justify-between mt-6 pt-6 border-t border-theme">
              <div className="text-sm text-theme-secondary">
                Page {currentPage} of {totalPages}
              </div>
              <div className="flex items-center gap-2">
                <Button
                  onClick={() => setCurrentPage(Math.max(1, currentPage - 1))}
                  disabled={currentPage === 1}
                  variant="ghost"
                  size="sm"
                >
                  Previous
                </Button>
                <Button
                  onClick={() => setCurrentPage(Math.min(totalPages, currentPage + 1))}
                  disabled={currentPage === totalPages}
                  variant="ghost"
                  size="sm"
                >
                  Next
                </Button>
              </div>
            </div>
          )}
        </div>
      </div>
    </PageContainer>
  );
}