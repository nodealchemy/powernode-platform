import { KbArticle } from '@/shared/services/knowledgeBaseApi';
import { Link } from 'react-router-dom';
import { ClockIcon, EyeIcon } from '@heroicons/react/24/outline';

interface KbRelatedArticlesProps {
  articles: KbArticle[];
  title?: string;
}

export function KbRelatedArticles({ 
  articles, 
  title = "Related Articles" 
}: KbRelatedArticlesProps) {
  if (articles.length === 0) return null;

  return (
    <div className="bg-theme-surface rounded-lg border border-theme p-4">
      <h3 className="font-medium text-theme-primary mb-4">
        {title}
      </h3>
      <div className="space-y-4">
        {articles.map(article => (
          <Link
            key={article.id}
            to={`/app/content/kb/articles/${article.id}`}
            className="block group"
          >
            <div className="space-y-2">
              <h4 className="font-medium text-theme-primary line-clamp-2 leading-tight group-hover:text-theme-primary/80 transition-colors">
                {article.title}
              </h4>
              
              {article.excerpt && (
                <p className="text-sm text-theme-secondary line-clamp-2">
                  {article.excerpt}
                </p>
              )}

              <div className="flex items-center gap-3 text-xs text-theme-secondary">
                <span>{article.author_name}</span>
                
                <div className="flex items-center gap-1">
                  <ClockIcon className="h-3 w-3" />
                  <span>{article.reading_time} min</span>
                </div>
                
                <div className="flex items-center gap-1">
                  <EyeIcon className="h-3 w-3" />
                  <span>{article.views_count}</span>
                </div>
              </div>
            </div>
          </Link>
        ))}
      </div>
    </div>
  );
}