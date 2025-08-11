import React, { useState, useEffect } from 'react';
import { Link } from 'react-router-dom';
import ReactMarkdown from 'react-markdown';
import { pagesApi, Page } from '../services/pagesApi';

interface WelcomePageProps {
  pageSlug?: string; // Allow custom page slug, defaults to 'welcome'
}

export const WelcomePage: React.FC<WelcomePageProps> = ({ pageSlug = 'welcome' }) => {
  const [page, setPage] = useState<Page | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    loadPage();
  }, [pageSlug]);

  const loadPage = async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await pagesApi.getPublicPage(pageSlug);
      setPage(response.data);
      
      // Update page title and meta tags
      if (response.data.title) {
        document.title = `${response.data.title} | Powernode`;
      }
      
      // Update meta description
      if (response.data.meta_description) {
        const metaDescription = document.querySelector('meta[name="description"]');
        if (metaDescription) {
          metaDescription.setAttribute('content', response.data.meta_description);
        }
      }

      // Update meta keywords
      if (response.data.meta_keywords) {
        let metaKeywords = document.querySelector('meta[name="keywords"]');
        if (!metaKeywords) {
          metaKeywords = document.createElement('meta');
          metaKeywords.setAttribute('name', 'keywords');
          document.head.appendChild(metaKeywords);
        }
        metaKeywords.setAttribute('content', response.data.meta_keywords);
      }
    } catch (error: any) {
      console.error('Failed to load page:', error);
      setError(error.response?.status === 404 ? 'Page not found' : 'Failed to load page');
    } finally {
      setLoading(false);
    }
  };

  // Loading state
  if (loading) {
    return (
      <div className="min-h-screen bg-theme-background-secondary flex items-center justify-center">
        <div className="text-center">
          <div className="animate-spin h-12 w-12 border-4 border-theme-interactive-primary border-t-transparent rounded-full mx-auto mb-4"></div>
          <p className="text-theme-secondary">Loading...</p>
        </div>
      </div>
    );
  }

  // Error state
  if (error) {
    return (
      <div className="min-h-screen bg-theme-background-secondary">
        {/* Header */}
        <header className="bg-theme-surface shadow-sm">
          <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
            <div className="flex items-center justify-between">
              <div className="flex items-center space-x-4">
                <div className="w-10 h-10 bg-theme-interactive-primary rounded-xl flex items-center justify-center">
                  <span className="text-white font-bold text-lg">P</span>
                </div>
                <div>
                  <h1 className="text-2xl font-bold text-theme-primary">Powernode</h1>
                </div>
              </div>
              <div className="flex items-center space-x-4">
                <Link
                  to="/login"
                  className="btn-theme btn-theme-secondary"
                >
                  Sign In
                </Link>
                <Link
                  to="/plans"
                  className="btn-theme btn-theme-primary"
                >
                  Get Started
                </Link>
              </div>
            </div>
          </div>
        </header>

        {/* Error Content */}
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-16 text-center">
          <div className="text-6xl mb-6">😕</div>
          <h2 className="text-3xl font-bold text-theme-primary mb-4">
            {error === 'Page not found' ? 'Page Not Found' : 'Something went wrong'}
          </h2>
          <p className="text-xl text-theme-secondary mb-8">
            {error === 'Page not found' 
              ? "The page you're looking for doesn't exist or hasn't been published yet."
              : "We're having trouble loading this page. Please try again later."
            }
          </p>
          <div className="space-x-4">
            <button
              onClick={loadPage}
              className="btn-theme btn-theme-secondary"
            >
              Try Again
            </button>
            <Link
              to="/plans"
              className="btn-theme btn-theme-primary"
            >
              View Plans
            </Link>
          </div>
        </div>
      </div>
    );
  }

  // Success state with page content
  return (
    <div className="min-h-screen bg-theme-background-secondary">
      {/* Header */}
      <header className="bg-theme-surface shadow-sm sticky top-0 z-50">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center space-x-4">
              <div className="w-10 h-10 bg-theme-interactive-primary rounded-xl flex items-center justify-center">
                <span className="text-white font-bold text-lg">P</span>
              </div>
              <div>
                <h1 className="text-2xl font-bold text-theme-primary">Powernode</h1>
              </div>
            </div>
            <div className="flex items-center space-x-4">
              <Link
                to="/login"
                className="text-theme-link hover:text-theme-link-hover font-medium"
              >
                Sign In
              </Link>
              <Link
                to="/plans"
                className="btn-theme btn-theme-primary"
              >
                Get Started
              </Link>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        {page && (
          <article className="prose prose-lg max-w-none">
            {/* Custom markdown rendering with theme classes */}
            <div className="markdown-content">
              <ReactMarkdown
                components={{
                  h1: ({ children }) => (
                    <h1 className="text-4xl font-bold text-theme-primary mb-6 leading-tight">
                      {children}
                    </h1>
                  ),
                  h2: ({ children }) => (
                    <h2 className="text-3xl font-bold text-theme-primary mb-4 mt-8 leading-tight">
                      {children}
                    </h2>
                  ),
                  h3: ({ children }) => (
                    <h3 className="text-2xl font-semibold text-theme-primary mb-3 mt-6 leading-tight">
                      {children}
                    </h3>
                  ),
                  h4: ({ children }) => (
                    <h4 className="text-xl font-semibold text-theme-primary mb-2 mt-4 leading-tight">
                      {children}
                    </h4>
                  ),
                  p: ({ children }) => (
                    <p className="text-theme-secondary mb-4 leading-relaxed text-lg">
                      {children}
                    </p>
                  ),
                  ul: ({ children }) => (
                    <ul className="list-disc list-inside mb-4 space-y-2 text-theme-secondary">
                      {children}
                    </ul>
                  ),
                  ol: ({ children }) => (
                    <ol className="list-decimal list-inside mb-4 space-y-2 text-theme-secondary">
                      {children}
                    </ol>
                  ),
                  li: ({ children }) => (
                    <li className="text-lg leading-relaxed">{children}</li>
                  ),
                  blockquote: ({ children }) => (
                    <blockquote className="border-l-4 border-theme-interactive-primary pl-6 my-6 italic text-theme-primary bg-theme-surface p-4 rounded-r-lg">
                      {children}
                    </blockquote>
                  ),
                  code: ({ children, className }) => {
                    const isInline = !className;
                    if (isInline) {
                      return (
                        <code className="bg-theme-surface px-2 py-1 rounded text-sm font-mono text-theme-primary">
                          {children}
                        </code>
                      );
                    }
                    return (
                      <code className={className} style={{ all: 'inherit' }}>
                        {children}
                      </code>
                    );
                  },
                  pre: ({ children }) => (
                    <pre className="bg-theme-surface p-4 rounded-lg overflow-x-auto mb-6 border border-theme">
                      {children}
                    </pre>
                  ),
                  a: ({ href, children }) => (
                    <a
                      href={href}
                      className="text-theme-link hover:text-theme-link-hover underline"
                      target={href?.startsWith('http') ? '_blank' : undefined}
                      rel={href?.startsWith('http') ? 'noopener noreferrer' : undefined}
                    >
                      {children}
                    </a>
                  ),
                  strong: ({ children }) => (
                    <strong className="font-semibold text-theme-primary">{children}</strong>
                  ),
                  em: ({ children }) => (
                    <em className="italic text-theme-primary">{children}</em>
                  )
                }}
              >
                {page.content}
              </ReactMarkdown>
            </div>
          </article>
        )}
      </main>

      {/* Call to Action Section */}
      <section className="bg-theme-surface py-16">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
          <h2 className="text-3xl font-bold text-theme-primary mb-4">
            Ready to get started?
          </h2>
          <p className="text-xl text-theme-secondary mb-8">
            Choose the perfect plan for your needs and start building today.
          </p>
          <div className="flex flex-col sm:flex-row gap-4 justify-center">
            <Link
              to="/plans"
              className="btn-theme btn-theme-primary text-lg px-8 py-3"
            >
              View Plans & Pricing
            </Link>
            <Link
              to="/login"
              className="btn-theme btn-theme-secondary text-lg px-8 py-3"
            >
              Sign In
            </Link>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="bg-theme-background-secondary py-12 border-t border-theme">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center">
            <div className="flex items-center justify-center space-x-4 mb-4">
              <div className="w-8 h-8 bg-theme-interactive-primary rounded-lg flex items-center justify-center">
                <span className="text-white font-bold">P</span>
              </div>
              <span className="text-xl font-bold text-theme-primary">Powernode</span>
            </div>
            <p className="text-theme-secondary">
              © 2025 Powernode. All rights reserved.
            </p>
          </div>
        </div>
      </footer>
    </div>
  );
};