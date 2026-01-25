import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { PageContainer, BreadcrumbItem, PageAction } from '@/shared/components/layout/PageContainer';
import { KbArticleContent } from '@/features/content/knowledge-base/components/KbArticleContent';
import { KbArticleComments } from '@/features/content/knowledge-base/components/KbArticleComments';
import { KbRelatedArticles } from '@/features/content/knowledge-base/components/KbRelatedArticles';
import { knowledgeBaseApi, knowledgeBaseAdminApi, KbArticle } from '@/shared/services/content/knowledgeBaseApi';
import { Badge } from '@/shared/components/ui/Badge';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { hasPermissions } from '@/shared/utils/permissionUtils';
import { 
  ArrowLeftIcon, 
  PencilIcon, 
  EyeIcon, 
  ClockIcon, 
  CalendarIcon,
  UserIcon,
  BookOpenIcon
} from '@heroicons/react/24/outline';
import { formatDistanceToNow } from 'date-fns';

export default function KnowledgeBaseArticlePage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { user: currentUser } = useSelector((state: RootState) => state.auth);
  
  const [article, setArticle] = useState<KbArticle | null>(null);
  const [relatedArticles, setRelatedArticles] = useState<KbArticle[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Check if user can edit KB (allows viewing draft articles)
  const canEditKb = hasPermissions(currentUser, ['kb.update']) || hasPermissions(currentUser, ['kb.manage']);

  const loadArticle = async () => {
    if (!id) return;

    try {
      setIsLoading(true);
      setError(null);

      // Use admin API for users with edit permissions (allows viewing drafts)
      // Fall back to public API for regular users
      const api = canEditKb ? knowledgeBaseAdminApi : knowledgeBaseApi;
      const response = await api.getArticle(id);
      setArticle(response.data.data.article);
      setRelatedArticles(response.data.data.related_articles || []);
    } catch (error: unknown) {
      if (error && typeof error === 'object' && 'response' in error && error.response && typeof error.response === 'object' && 'status' in error.response) {
        const status = (error.response as { status: number }).status;
        if (status === 404) {
          setError('Article not found');
        } else if (status === 403) {
          setError('You do not have permission to view this article');
        } else {
          setError('Failed to load article');
        }
      } else {
        setError('Failed to load article');
      }
    } finally {
      setIsLoading(false);
    }
  };

  // Load article when id or permissions change
  useEffect(() => {
    if (id) {
      loadArticle();
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id, canEditKb]);

  // Generate breadcrumbs based on article data
  const getBreadcrumbs = (): BreadcrumbItem[] => {
    const breadcrumbs: BreadcrumbItem[] = [
      {
        label: 'Dashboard',
        href: '/app',
        icon: BookOpenIcon
      },
      {
        label: 'Knowledge Base',
        href: '/app/content/kb'
      }
    ];

    if (article?.category) {
      breadcrumbs.push({
        label: article.category.name,
        href: `/app/content/kb?category=${article.category.id}`
      });
    }

    if (article) {
      breadcrumbs.push({
        label: article.title
      });
    }

    return breadcrumbs;
  };

  // Generate actions based on article data
  const getActions = (): PageAction[] => {
    const actions: PageAction[] = [
      {
        id: 'back',
        label: 'Back to KB',
        onClick: () => navigate('/app/content/kb'),
        variant: 'outline',
        icon: ArrowLeftIcon
      }
    ];

    // Check if user can edit KB articles
    const canEditKb = hasPermissions(currentUser, ['kb.update']) || hasPermissions(currentUser, ['kb.manage']);
    if (canEditKb && article) {
      actions.push({
        id: 'edit',
        label: 'Edit Article',
        onClick: () => navigate(`/app/content/kb/articles/${article.id}/edit`),
        variant: 'secondary',
        icon: PencilIcon
      });
    }

    return actions;
  };

  if (isLoading) {
    return (
      <PageContainer
        title="Loading..."
        description="Loading article content"
        breadcrumbs={[
          { label: 'Dashboard', href: '/app', icon: BookOpenIcon },
          { label: 'Knowledge Base', href: '/app/content/kb' }
        ]}
      >
        <div className="flex items-center justify-center h-64">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-primary"></div>
        </div>
      </PageContainer>
    );
  }

  if (error) {
    return (
      <PageContainer
        title="Error"
        description="Unable to load article"
        breadcrumbs={[
          { label: 'Dashboard', href: '/app', icon: BookOpenIcon },
          { label: 'Knowledge Base', href: '/app/content/kb' }
        ]}
        actions={[
          {
            id: 'back',
            label: 'Back to KB',
            onClick: () => navigate('/app/content/kb'),
            variant: 'primary',
            icon: ArrowLeftIcon
          }
        ]}
      >
        <div className="text-center py-12">
          <div className="text-theme-danger mb-4">
            <BookOpenIcon className="h-12 w-12 mx-auto" />
          </div>
          <h3 className="text-lg font-medium text-theme-primary mb-2">
            {error}
          </h3>
        </div>
      </PageContainer>
    );
  }

  if (!article) {
    return null;
  }

  return (
    <PageContainer
      title={article.title}
      description={article.excerpt || `${article.reading_time} min read • ${article.views_count.toLocaleString()} views`}
      breadcrumbs={getBreadcrumbs()}
      actions={getActions()}
    >
      <div className="space-y-8">
        {/* Article Meta */}
        <div className="bg-theme-surface rounded-xl border border-theme p-8 shadow-sm">
          <div className="flex flex-wrap items-center gap-6 text-sm">
            <div className="flex items-center gap-2 text-theme-secondary">
              <div className="w-8 h-8 bg-theme-primary rounded-full flex items-center justify-center">
                <UserIcon className="h-4 w-4 text-white" />
              </div>
              <div>
                <span className="text-xs text-theme-tertiary block">Author</span>
                <span className="font-medium text-theme-primary">{article.author_name}</span>
              </div>
            </div>
            
            {article.published_at && (
              <div className="flex items-center gap-2 text-theme-secondary">
                <div className="w-8 h-8 bg-theme-success rounded-full flex items-center justify-center">
                  <CalendarIcon className="h-4 w-4 text-white" />
                </div>
                <div>
                  <span className="text-xs text-theme-tertiary block">Published</span>
                  <span className="font-medium text-theme-primary">
                    {formatDistanceToNow(new Date(article.published_at), { addSuffix: true })}
                  </span>
                </div>
              </div>
            )}

            <div className="flex items-center gap-2 text-theme-secondary">
              <div className="w-8 h-8 bg-theme-info rounded-full flex items-center justify-center">
                <ClockIcon className="h-4 w-4 text-white" />
              </div>
              <div>
                <span className="text-xs text-theme-tertiary block">Reading Time</span>
                <span className="font-medium text-theme-primary">{article.reading_time} min read</span>
              </div>
            </div>

            <div className="flex items-center gap-2 text-theme-secondary">
              <div className="w-8 h-8 bg-theme-warning rounded-full flex items-center justify-center">
                <EyeIcon className="h-4 w-4 text-white" />
              </div>
              <div>
                <span className="text-xs text-theme-tertiary block">Views</span>
                <span className="font-medium text-theme-primary">{article.views_count.toLocaleString()} views</span>
              </div>
            </div>

            {article.is_featured && (
              <div className="ml-auto">
                <Badge variant="primary" size="lg" className="font-semibold px-4 py-2">
                  ⭐ Featured Article
                </Badge>
              </div>
            )}
          </div>

          {/* Tags */}
          {article.tags.length > 0 && (
            <div className="mt-6 pt-6 border-t border-theme-light">
              <div className="flex items-center gap-3 mb-3">
                <svg className="w-4 h-4 text-theme-secondary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M7 7h.01M7 3h5c.512 0 1.024.195 1.414.586l7 7a2 2 0 010 2.828l-7 7a2 2 0 01-2.828 0l-7-7A1.994 1.994 0 013 12V7a4 4 0 014-4z" />
                </svg>
                <span className="text-sm font-medium text-theme-secondary">Article Tags</span>
              </div>
              <div className="flex flex-wrap gap-3">
                {article.tags.map((tag, index) => (
                  <button
                    key={index}
                    onClick={() => navigate(`/app/content/kb?tags=${tag}`)}
                    className="group"
                  >
                    <Badge 
                      variant="secondary" 
                      size="lg"
                      className="font-medium px-3 py-1 group-hover:bg-theme-primary group-hover:text-white transition-all group-hover:scale-105"
                    >
                      {tag}
                    </Badge>
                  </button>
                ))}
              </div>
            </div>
          )}
        </div>

        {/* Main Content Grid */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-12">
          {/* Article Content */}
          <div className="lg:col-span-2 space-y-12">
            <div className="bg-theme-surface rounded-xl border border-theme p-8 lg:p-12 shadow-sm">
              <KbArticleContent article={article} />
            </div>

            {/* Comments Section */}
            <div className="bg-theme-surface rounded-xl border border-theme p-8 shadow-sm">
              <div className="flex items-center gap-3 mb-6">
                <svg className="w-5 h-5 text-theme-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
                </svg>
                <h3 className="text-xl font-semibold text-theme-primary">Discussion</h3>
              </div>
              <KbArticleComments articleId={article.id} />
            </div>
          </div>

          {/* Sidebar */}
          <div className="space-y-8">
            {/* Related Articles */}
            {relatedArticles.length > 0 && (
              <div className="bg-theme-surface rounded-xl border border-theme p-6 shadow-sm">
                <KbRelatedArticles articles={relatedArticles} />
              </div>
            )}

            {/* Article Info */}
            <div className="bg-theme-surface rounded-xl border border-theme p-6 shadow-sm sticky top-6">
              <h3 className="font-semibold text-theme-primary mb-6 flex items-center gap-2">
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
                Article Details
              </h3>
              <dl className="space-y-4 text-sm">
                <div>
                  <dt className="text-theme-tertiary font-medium mb-1">Category</dt>
                  <dd>
                    <button
                      onClick={() => navigate(`/app/content/kb?category=${article.category.id}`)}
                      className="text-theme-primary font-semibold hover:text-theme-link hover:underline transition-colors"
                    >
                      {article.category.name}
                    </button>
                  </dd>
                </div>
                <div>
                  <dt className="text-theme-tertiary font-medium mb-1">Author</dt>
                  <dd className="text-theme-primary font-medium">{article.author_name}</dd>
                </div>
                <div>
                  <dt className="text-theme-tertiary font-medium mb-1">Views</dt>
                  <dd className="text-theme-primary font-medium">{article.views_count.toLocaleString()}</dd>
                </div>
                <div>
                  <dt className="text-theme-tertiary font-medium mb-1">Reading Time</dt>
                  <dd className="text-theme-primary font-medium">{article.reading_time} minutes</dd>
                </div>
                {article.published_at && (
                  <div>
                    <dt className="text-theme-tertiary font-medium mb-1">Published</dt>
                    <dd className="text-theme-primary font-medium">
                      {new Date(article.published_at).toLocaleDateString('en-US', {
                        year: 'numeric',
                        month: 'long',
                        day: 'numeric'
                      })}
                    </dd>
                  </div>
                )}
              </dl>
            </div>
          </div>
        </div>
      </div>
    </PageContainer>
  );
}