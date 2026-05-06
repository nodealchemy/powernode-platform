import React from 'react';
import { Link } from 'react-router-dom';
import { Calendar, Clock, ArrowRight } from 'lucide-react';
import { PublicPageContainer } from '@/shared/components/layout/PublicPageContainer';
import { blogApi, BlogPostSummary } from '../services/blogApi';

const mainNav = [
  { label: 'Features', path: '/features' },
  { label: 'Pricing', path: '/pricing' },
  { label: 'Blog', path: '/blog' },
  { label: 'Docs', path: '/docs' },
];

export const BlogIndexPage: React.FC = () => {
  const [posts, setPosts] = React.useState<BlogPostSummary[]>([]);
  const [loading, setLoading] = React.useState(true);
  const [error, setError] = React.useState<string | null>(null);

  React.useEffect(() => {
    let cancelled = false;
    blogApi.listPosts()
      .then(data => { if (!cancelled) setPosts(data.posts); })
      .catch(err => { if (!cancelled) setError(err?.message || 'Failed to load posts'); })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, []);

  return (
    <PublicPageContainer
      title="Blog"
      description="Updates, deep-dives, and post-mortems from the Powernode team. Filed under: AI agent ops, knowledge graphs, swarm coordination, and the operational realities of running production agent fleets."
      mainNav={mainNav}
    >
      <section className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        {loading && (
          <div className="text-center py-16">
            <p className="text-theme-secondary">Loading posts…</p>
          </div>
        )}

        {error && (
          <div className="text-center py-16">
            <p className="text-theme-danger">{error}</p>
          </div>
        )}

        {!loading && !error && posts.length === 0 && (
          <div className="text-center py-16">
            <h2 className="text-2xl font-bold text-theme-primary mb-3">First post coming soon</h2>
            <p className="text-theme-secondary max-w-xl mx-auto">
              The blog launches alongside the OSS announcement. In the meantime, follow the project on
              GitHub for commits and release notes.
            </p>
          </div>
        )}

        {!loading && !error && posts.length > 0 && (
          <div className="space-y-8">
            {posts.map(post => (
              <article
                key={post.slug}
                className="border-b border-theme pb-8 last:border-b-0"
                data-testid={`blog-post-${post.slug}`}
              >
                <Link
                  to={`/blog/${post.slug}`}
                  className="group block"
                >
                  <h2 className="text-2xl md:text-3xl font-bold text-theme-primary group-hover:text-theme-info transition-colors mb-3">
                    {post.title}
                  </h2>
                  {post.excerpt && (
                    <p className="text-theme-secondary text-base md:text-lg leading-relaxed mb-4">
                      {post.excerpt}
                    </p>
                  )}
                  <div className="flex items-center gap-6 text-sm text-theme-tertiary">
                    {post.published_at && (
                      <span className="inline-flex items-center gap-1.5">
                        <Calendar className="w-4 h-4" />
                        {new Date(post.published_at).toLocaleDateString(undefined, { year: 'numeric', month: 'long', day: 'numeric' })}
                      </span>
                    )}
                    {post.estimated_read_time != null && (
                      <span className="inline-flex items-center gap-1.5">
                        <Clock className="w-4 h-4" />
                        {post.estimated_read_time} min read
                      </span>
                    )}
                    <span className="inline-flex items-center gap-1 text-theme-info group-hover:translate-x-0.5 transition-transform">
                      Read post <ArrowRight className="w-4 h-4" />
                    </span>
                  </div>
                </Link>
              </article>
            ))}
          </div>
        )}
      </section>
    </PublicPageContainer>
  );
};
