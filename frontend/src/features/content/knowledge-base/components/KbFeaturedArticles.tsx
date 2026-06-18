import { KbArticle } from '@/shared/services/content/knowledgeBaseApi';
import { Badge } from '@/shared/components/ui/Badge';
import { EntityLink } from '@/shared/components/entity';
import { 
  EyeIcon, 
  ClockIcon, 
  StarIcon as StarIconSolid
} from '@heroicons/react/24/solid';
import { Link } from 'react-router-dom';
import { stripMarkdown } from '@/shared/utils/markdownUtils';

interface KbFeaturedArticlesProps {
  articles: KbArticle[];
}

export function KbFeaturedArticles({ articles }: KbFeaturedArticlesProps) {
  if (articles.length === 0) return null;

  const [primary, ...secondary] = articles;

  return (
    <div className="space-y-6">
      {/* Primary Featured Article */}
      <div className="block bg-gradient-to-br from-theme-primary/5 to-theme-secondary/5 rounded-lg border border-theme-primary/20 p-6 hover:border-theme-primary/30 hover:shadow-lg transition-all">
        <div className="flex items-start gap-4">
          <StarIconSolid className="h-6 w-6 text-theme-warning-fg flex-shrink-0 mt-1" />
          <div className="flex-1">
            <div className="flex items-start justify-between gap-4 mb-3">
              <Link
                to={`/app/content/kb/articles/${primary.id}`}
                className="text-xl font-bold text-theme-primary line-clamp-2 leading-tight hover:text-theme-primary/80 transition-colors"
              >
                {primary.title}
              </Link>
              <Badge variant="primary" size="sm">
                Featured
              </Badge>
            </div>

            {primary.excerpt && (
              <p className="text-theme-secondary line-clamp-3 mb-4 leading-relaxed">
                {stripMarkdown(primary.excerpt)}
              </p>
            )}

            <div className="flex items-center justify-between">
              <div className="flex items-center gap-4 text-sm text-theme-secondary">
                <span className="font-medium">By {primary.author_name}</span>
                
                <div className="flex items-center gap-1">
                  <ClockIcon className="h-4 w-4" />
                  <span>{primary.reading_time} min read</span>
                </div>
                
                <div className="flex items-center gap-1">
                  <EyeIcon className="h-4 w-4" />
                  <span>{primary.views_count.toLocaleString()} views</span>
                </div>
              </div>

              <Badge variant="secondary" size="sm">
                <EntityLink
                  type="kb_category"
                  id={primary.category.id}
                  label={primary.category.name}
                  className="text-inherit"
                />
              </Badge>
            </div>
          </div>
        </div>
      </div>

      {/* Secondary Featured Articles */}
      {secondary.length > 0 && (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {secondary.map(article => (
            <div
              key={article.id}
              className="block bg-theme-surface rounded-lg border border-theme p-4 hover:border-theme-primary/20 hover:shadow-sm transition-all"
            >
              <div className="space-y-3">
                <div className="flex items-start gap-3">
                  <StarIconSolid className="h-4 w-4 text-theme-warning-fg flex-shrink-0 mt-1" />
                  <Link
                    to={`/app/content/kb/articles/${article.id}`}
                    className="font-semibold text-theme-primary line-clamp-2 leading-tight hover:text-theme-primary/80 transition-colors"
                  >
                    {article.title}
                  </Link>
                </div>

                {article.excerpt && (
                  <p className="text-sm text-theme-secondary line-clamp-2">
                    {stripMarkdown(article.excerpt)}
                  </p>
                )}

                <div className="flex items-center justify-between text-sm text-theme-secondary">
                  <div className="flex items-center gap-3">
                    <span>{article.author_name}</span>
                    <div className="flex items-center gap-1">
                      <ClockIcon className="h-3 w-3" />
                      <span>{article.reading_time} min</span>
                    </div>
                  </div>

                  <Badge variant="outline" size="sm">
                    <EntityLink
                      type="kb_category"
                      id={article.category.id}
                      label={article.category.name}
                      className="text-inherit"
                    />
                  </Badge>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}