import { KbArticle } from '@/shared/services/knowledgeBaseApi';
import { Badge } from '@/shared/components/ui/Badge';
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
      <Link
        to={`/app/content/kb/articles/${primary.id}`}
        className="block bg-gradient-to-br from-theme-primary/5 to-theme-secondary/5 rounded-lg border border-theme-primary/20 p-6 hover:border-theme-primary/30 hover:shadow-lg transition-all"
      >
        <div className="flex items-start gap-4">
          <StarIconSolid className="h-6 w-6 text-yellow-500 flex-shrink-0 mt-1" />
          <div className="flex-1">
            <div className="flex items-start justify-between gap-4 mb-3">
              <h2 className="text-xl font-bold text-theme-primary line-clamp-2 leading-tight">
                {primary.title}
              </h2>
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
                {primary.category.name}
              </Badge>
            </div>
          </div>
        </div>
      </Link>

      {/* Secondary Featured Articles */}
      {secondary.length > 0 && (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {secondary.map(article => (
            <Link
              key={article.id}
              to={`/app/content/kb/articles/${article.id}`}
              className="block bg-theme-surface rounded-lg border border-theme p-4 hover:border-theme-primary/20 hover:shadow-sm transition-all"
            >
              <div className="space-y-3">
                <div className="flex items-start gap-3">
                  <StarIconSolid className="h-4 w-4 text-yellow-500 flex-shrink-0 mt-1" />
                  <h3 className="font-semibold text-theme-primary line-clamp-2 leading-tight">
                    {article.title}
                  </h3>
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
                    {article.category.name}
                  </Badge>
                </div>
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}