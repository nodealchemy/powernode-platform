import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { PageContainer, BreadcrumbItem, PageAction } from '@/shared/components/layout/PageContainer';
import { KbArticleContent } from '@/features/knowledge-base/components/KbArticleContent';
import { KbArticleComments } from '@/features/knowledge-base/components/KbArticleComments';
import { KbRelatedArticles } from '@/features/knowledge-base/components/KbRelatedArticles';
import { knowledgeBaseApi, KbArticle } from '@/shared/services/knowledgeBaseApi';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { Badge } from '@/shared/components/ui/Badge';
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

  useEffect(() => {
    if (id) {
      loadArticle();
    }
  }, [id]);

  const loadArticle = async () => {
    if (!id) return;

    try {
      setIsLoading(true);
      setError(null);

      const response = await knowledgeBaseApi.getArticle(id);
      setArticle(response.data.data.article);
      setRelatedArticles(response.data.data.related_articles);
    } catch (error: any) {
      if (error.response?.status === 404) {
        setError('Article not found');
      } else if (error.response?.status === 403) {
        setError('You do not have permission to view this article');
      } else {
        setError('Failed to load article');
      }
      console.error('Failed to load article:', error);
    } finally {
      setIsLoading(false);
    }
  };

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

    if (article?.can_edit) {
      actions.push({
        id: 'edit',
        label: 'Edit Article',
        onClick: () => navigate(`/app/content/kb/admin/articles/${article.id}/edit`),
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
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <div className="flex flex-wrap items-center gap-4 text-sm text-theme-secondary">
            <div className="flex items-center gap-1">
              <UserIcon className="h-4 w-4" />
              <span>By {article.author_name}</span>
            </div>
            
            {article.published_at && (
              <div className="flex items-center gap-1">
                <CalendarIcon className="h-4 w-4" />
                <span>
                  Published {formatDistanceToNow(new Date(article.published_at), { addSuffix: true })}
                </span>
              </div>
            )}

            <div className="flex items-center gap-1">
              <ClockIcon className="h-4 w-4" />
              <span>{article.reading_time} min read</span>
            </div>

            <div className="flex items-center gap-1">
              <EyeIcon className="h-4 w-4" />
              <span>{article.views_count.toLocaleString()} views</span>
            </div>

            {article.is_featured && (
              <Badge variant="primary" size="sm">
                Featured
              </Badge>
            )}
          </div>

          {/* Tags */}
          {article.tags.length > 0 && (
            <div className="flex flex-wrap gap-2 mt-4">
              {article.tags.map((tag, index) => (
                <button
                  key={index}
                  onClick={() => navigate(`/app/content/kb?tags=${tag}`)}
                  className="cursor-pointer hover:bg-theme-primary hover:text-white transition-colors"
                >
                  <Badge 
                    variant="secondary" 
                    size="sm"
                  >
                    {tag}
                  </Badge>
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Main Content Grid */}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
          {/* Article Content */}
          <div className="lg:col-span-2 space-y-8">
            <KbArticleContent article={article} />

            {/* Comments Section */}
            <div className="border-t border-theme pt-8">
              <KbArticleComments articleId={article.id} />
            </div>
          </div>

          {/* Sidebar */}
          <div className="space-y-6">
            {/* Related Articles */}
            {relatedArticles.length > 0 && (
              <KbRelatedArticles articles={relatedArticles} />
            )}

            {/* Article Info */}
            <div className="bg-theme-surface rounded-lg border border-theme p-4">
              <h3 className="font-medium text-theme-primary mb-3">Article Info</h3>
              <dl className="space-y-2 text-sm">
                <div>
                  <dt className="text-theme-secondary">Category</dt>
                  <dd className="text-theme-primary font-medium">
                    <button
                      onClick={() => navigate(`/app/content/kb?category=${article.category.id}`)}
                      className="hover:underline"
                    >
                      {article.category.name}
                    </button>
                  </dd>
                </div>
                <div>
                  <dt className="text-theme-secondary">Author</dt>
                  <dd className="text-theme-primary">{article.author_name}</dd>
                </div>
                <div>
                  <dt className="text-theme-secondary">Views</dt>
                  <dd className="text-theme-primary">{article.views_count.toLocaleString()}</dd>
                </div>
                <div>
                  <dt className="text-theme-secondary">Reading Time</dt>
                  <dd className="text-theme-primary">{article.reading_time} minutes</dd>
                </div>
                {article.published_at && (
                  <div>
                    <dt className="text-theme-secondary">Published</dt>
                    <dd className="text-theme-primary">
                      {new Date(article.published_at).toLocaleDateString()}
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