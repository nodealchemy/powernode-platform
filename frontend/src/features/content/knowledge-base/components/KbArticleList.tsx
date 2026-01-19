import { KbArticle } from '@/shared/services/content/knowledgeBaseApi';
import { Badge } from '@/shared/components/ui/Badge';
import { 
  EyeIcon, 
  ClockIcon, 
  CalendarIcon,
  // StarIcon,
  TagIcon
} from '@heroicons/react/24/outline';
import { StarIcon as StarIconSolid } from '@heroicons/react/24/solid';
import { formatDistanceToNow } from 'date-fns';
import { Link } from 'react-router-dom';
import { stripMarkdown } from '@/shared/utils/markdownUtils';

interface KbArticleListProps {
  articles: KbArticle[];
  showCategory?: boolean;
  layout?: 'list' | 'grid';
}

export function KbArticleList({ 
  articles, 
  showCategory = false,
  layout = 'list'
}: KbArticleListProps) {
  if (articles.length === 0) {
    return (
      <div className="text-center py-12">
        <TagIcon className="h-12 w-12 text-theme-tertiary mx-auto mb-4" />
        <h3 className="text-lg font-medium text-theme-primary mb-2">
          No articles found
        </h3>
        <p className="text-theme-secondary">
          Check back later for new content.
        </p>
      </div>
    );
  }

  if (layout === 'grid') {
    return (
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {articles.map(article => (
          <ArticleCard 
            key={article.id} 
            article={article} 
            showCategory={showCategory} 
          />
        ))}
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {articles.map(article => (
        <ArticleListItem 
          key={article.id} 
          article={article} 
          showCategory={showCategory} 
        />
      ))}
    </div>
  );
}

function ArticleCard({ article, showCategory }: { article: KbArticle; showCategory: boolean }) {
  return (
    <Link
      to={`/app/content/kb/articles/${article.id}`}
      className="block bg-theme-surface rounded-lg border border-theme p-6 hover:border-theme-primary/20 hover:shadow-sm transition-all"
    >
      <div className="space-y-4">
        {/* Header */}
        <div className="flex items-start justify-between gap-4">
          <h3 className="text-lg font-semibold text-theme-primary line-clamp-2 leading-tight">
            {article.title}
          </h3>
          {article.is_featured && (
            <StarIconSolid className="h-5 w-5 text-theme-warning flex-shrink-0" />
          )}
        </div>

        {/* Excerpt */}
        {article.excerpt && (
          <p className="text-theme-secondary line-clamp-3 leading-relaxed">
            {stripMarkdown(article.excerpt)}
          </p>
        )}

        {/* Category */}
        {showCategory && (
          <Badge variant="secondary" size="sm">
            {article.category.name}
          </Badge>
        )}

        {/* Tags */}
        {article.tags.length > 0 && (
          <div className="flex flex-wrap gap-1">
            {article.tags.slice(0, 3).map((tag, index) => (
              <Badge key={index} variant="outline" size="sm">
                {tag}
              </Badge>
            ))}
            {article.tags.length > 3 && (
              <Badge variant="outline" size="sm">
                +{article.tags.length - 3}
              </Badge>
            )}
          </div>
        )}

        {/* Meta */}
        <div className="flex items-center gap-4 text-sm text-theme-secondary">
          <span>{article.author_name}</span>
          
          <div className="flex items-center gap-1">
            <ClockIcon className="h-4 w-4" />
            <span>{article.reading_time} min</span>
          </div>
          
          <div className="flex items-center gap-1">
            <EyeIcon className="h-4 w-4" />
            <span>{article.views_count}</span>
          </div>

          {article.published_at && (
            <div className="flex items-center gap-1 ml-auto">
              <CalendarIcon className="h-4 w-4" />
              <span>
                {formatDistanceToNow(new Date(article.published_at), { addSuffix: true })}
              </span>
            </div>
          )}
        </div>
      </div>
    </Link>
  );
}

function ArticleListItem({ article, showCategory }: { article: KbArticle; showCategory: boolean }) {
  return (
    <Link
      to={`/app/content/kb/articles/${article.id}`}
      className="block bg-theme-surface rounded-lg border border-theme p-6 hover:border-theme-primary/20 hover:shadow-sm transition-all"
    >
      <div className="flex items-start gap-4">
        {/* Content */}
        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-4 mb-3">
            <h3 className="text-lg font-semibold text-theme-primary line-clamp-1">
              {article.title}
            </h3>
            {article.is_featured && (
              <StarIconSolid className="h-5 w-5 text-theme-warning flex-shrink-0" />
            )}
          </div>

          {article.excerpt && (
            <p className="text-theme-secondary line-clamp-2 mb-4">
              {stripMarkdown(article.excerpt)}
            </p>
          )}

          {/* Tags and Category */}
          <div className="flex flex-wrap items-center gap-2 mb-4">
            {showCategory && (
              <Badge variant="secondary" size="sm">
                {article.category.name}
              </Badge>
            )}
            {article.tags.slice(0, 2).map((tag, index) => (
              <Badge key={index} variant="outline" size="sm">
                {tag}
              </Badge>
            ))}
            {article.tags.length > 2 && (
              <span className="text-sm text-theme-tertiary">
                +{article.tags.length - 2} more
              </span>
            )}
          </div>

          {/* Meta */}
          <div className="flex flex-wrap items-center gap-4 text-sm text-theme-secondary">
            <span className="font-medium">By {article.author_name}</span>
            
            <div className="flex items-center gap-1">
              <ClockIcon className="h-4 w-4" />
              <span>{article.reading_time} min read</span>
            </div>
            
            <div className="flex items-center gap-1">
              <EyeIcon className="h-4 w-4" />
              <span>{article.views_count.toLocaleString()} views</span>
            </div>

            {article.published_at && (
              <div className="flex items-center gap-1">
                <CalendarIcon className="h-4 w-4" />
                <span>
                  {formatDistanceToNow(new Date(article.published_at), { addSuffix: true })}
                </span>
              </div>
            )}
          </div>
        </div>
      </div>
    </Link>
  );
}