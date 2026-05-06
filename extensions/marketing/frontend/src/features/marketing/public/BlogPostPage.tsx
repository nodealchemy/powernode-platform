import React from 'react';
import { useParams, Link } from 'react-router-dom';
import ReactMarkdown from 'react-markdown';
import { ArrowLeft, Calendar, Clock } from 'lucide-react';
import { PublicPageContainer } from '@/shared/components/layout/PublicPageContainer';
import { blogApi, BlogPostDetail } from '../services/blogApi';

const mainNav = [
  { label: 'Features', path: '/features' },
  { label: 'Pricing', path: '/pricing' },
  { label: 'Blog', path: '/blog' },
  { label: 'Docs', path: '/docs' },
];

export const BlogPostPage: React.FC = () => {
  const { slug } = useParams<{ slug: string }>();
  const [post, setPost] = React.useState<BlogPostDetail | null>(null);
  const [loading, setLoading] = React.useState(true);
  const [error, setError] = React.useState<string | null>(null);

  React.useEffect(() => {
    if (!slug) return;
    let cancelled = false;
    setLoading(true);
    setError(null);
    blogApi.getPost(slug)
      .then(data => { if (!cancelled) setPost(data.post); })
      .catch(err => {
        if (!cancelled) {
          const status = err?.response?.status;
          setError(status === 404 ? 'Post not found' : (err?.message || 'Failed to load post'));
        }
      })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [slug]);

  return (
    <PublicPageContainer
      title={post?.title || 'Blog'}
      description={post?.excerpt || undefined}
      mainNav={mainNav}
    >
      <article className="max-w-3xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        <Link
          to="/blog"
          className="inline-flex items-center gap-2 text-sm font-semibold text-theme-secondary hover:text-theme-primary mb-8"
        >
          <ArrowLeft className="w-4 h-4" />
          Back to blog
        </Link>

        {loading && (
          <p className="text-theme-secondary">Loading post…</p>
        )}

        {error && (
          <div>
            <h1 className="text-3xl font-bold text-theme-primary mb-3">{error}</h1>
            <p className="text-theme-secondary">
              Try the <Link to="/blog" className="text-theme-info hover:underline">blog index</Link> for
              the latest posts.
            </p>
          </div>
        )}

        {!loading && !error && post && (
          <>
            <header className="mb-8 pb-8 border-b border-theme">
              <h1 className="text-3xl md:text-4xl lg:text-5xl font-extrabold text-theme-primary mb-4">
                {post.title}
              </h1>
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
              </div>
            </header>

            <div className="prose prose-lg max-w-none text-theme-secondary
                            prose-headings:text-theme-primary
                            prose-strong:text-theme-primary
                            prose-a:text-theme-info hover:prose-a:underline
                            prose-code:text-theme-primary prose-code:bg-theme-surface prose-code:px-1 prose-code:py-0.5 prose-code:rounded
                            prose-pre:bg-theme-surface prose-pre:text-theme-primary
                            prose-blockquote:border-l-theme-info prose-blockquote:text-theme-secondary">
              <ReactMarkdown>{post.content}</ReactMarkdown>
            </div>
          </>
        )}
      </article>
    </PublicPageContainer>
  );
};
