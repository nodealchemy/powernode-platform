import { useState, useEffect } from 'react';
import { PageContainer, BreadcrumbItem } from '@/shared/components/layout/PageContainer';
import { knowledgeBaseAdminApi, KbArticle, KbCategory } from '@/shared/services/knowledgeBaseApi';
import { KbArticleList } from '@/features/knowledge-base/components/KbArticleList';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { 
  PlusIcon, 
  CogIcon, 
  ChartBarIcon, 
  DocumentTextIcon,
  FolderIcon,
  ChatBubbleLeftRightIcon,
  BookOpenIcon
} from '@heroicons/react/24/outline';
import { Navigate } from 'react-router-dom';

export default function KnowledgeBaseAdminPage() {
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

  // Check permissions
  const canManageKb = currentUser?.permissions?.includes('kb.manage');
  const canWriteKb = currentUser?.permissions?.includes('kb.write') || canManageKb;

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
    if (canWriteKb) {
      loadAdminData();
    }
  }, [canWriteKb]);

  const loadAdminData = async () => {
    try {
      setIsLoading(true);
      
      const [articlesResponse, categoriesResponse] = await Promise.all([
        knowledgeBaseAdminApi.getArticles({ per_page: 20 }),
        knowledgeBaseAdminApi.getCategories({ per_page: 50 })
      ]);

      setArticles(articlesResponse.data.data.articles);
      setStats(articlesResponse.data.data.stats);
      setCategories(categoriesResponse.data.data.categories);
    } catch (error) {
      console.error('Failed to load admin data:', error);
    } finally {
      setIsLoading(false);
    }
  };

  if (!canWriteKb) {
    return <Navigate to="/app/content/kb" replace />;
  }

  const actions = [
    {
      id: 'create-article',
      label: 'Create Article',
      onClick: () => window.location.href = '/app/content/kb/admin/articles/new',
      variant: 'primary' as const,
      icon: PlusIcon
    },
    {
      id: 'manage-categories',
      label: 'Manage Categories', 
      onClick: () => window.location.href = '/app/content/kb/admin/categories',
      variant: 'secondary' as const,
      icon: FolderIcon
    }
  ];

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
              <div className="h-8 w-8 bg-green-500 rounded-lg flex items-center justify-center">
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
              <div className="h-8 w-8 bg-yellow-500 rounded-lg flex items-center justify-center">
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
              <div className="h-8 w-8 bg-blue-500 rounded-lg flex items-center justify-center">
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
              <div className="h-8 w-8 bg-gray-500 rounded-lg flex items-center justify-center">
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

        {/* Recent Articles */}
        <div>
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-semibold text-theme-primary">Recent Articles</h2>
            <Button
              onClick={() => window.location.href = '/app/content/kb/admin/articles'}
              variant="ghost"
              size="sm"
            >
              View All Articles
            </Button>
          </div>
          
          {articles.length > 0 ? (
            <div className="space-y-4">
              {articles.slice(0, 5).map(article => (
                <div 
                  key={article.id}
                  className="bg-theme-surface rounded-lg border border-theme p-4"
                >
                  <div className="flex items-start justify-between">
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
        </div>
      </div>
    </PageContainer>
  );
}