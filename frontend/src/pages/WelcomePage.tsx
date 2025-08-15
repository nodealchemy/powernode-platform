import React, { useState, useEffect, useCallback } from 'react';
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

  const loadPage = useCallback(async () => {
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
  }, [pageSlug]);

  useEffect(() => {
    loadPage();
  }, [loadPage]);

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
    <div className="min-h-screen bg-gradient-to-br from-theme-background via-theme-background-secondary to-theme-surface">
      {/* Header */}
      <header className="bg-theme-surface/80 backdrop-blur-md shadow-lg sticky top-0 z-50 border-b border-theme">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center space-x-4">
              <div className="w-12 h-12 bg-gradient-to-br from-theme-interactive-primary to-theme-interactive-secondary rounded-xl flex items-center justify-center shadow-lg hover:shadow-xl transition-all duration-300 hover:scale-105">
                <span className="text-white font-bold text-xl">P</span>
              </div>
              <div>
                <h1 className="text-2xl font-bold bg-gradient-to-r from-theme-primary to-theme-interactive-primary bg-clip-text text-transparent">
                  Powernode
                </h1>
                <p className="text-xs text-theme-tertiary">Subscription Platform</p>
              </div>
            </div>
            <div className="flex items-center space-x-4">
              <Link
                to="/login"
                className="text-theme-link hover:text-theme-link-hover font-medium transition-colors duration-200 px-3 py-2 rounded-lg hover:bg-theme-surface-hover"
              >
                Sign In
              </Link>
              <Link
                to="/plans"
                className="btn-theme btn-theme-primary shadow-lg hover:shadow-xl transition-all duration-300 hover:scale-105"
              >
                Get Started
              </Link>
            </div>
          </div>
        </div>
      </header>

      {/* Hero Section */}
      <section className="relative overflow-hidden py-20 sm:py-32">
        {/* Background Pattern */}
        <div className="absolute inset-0 bg-grid-slate-100 [mask-image:linear-gradient(0deg,white,rgba(255,255,255,0.6))] opacity-10"></div>
        
        <div className="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center">
            <div className="inline-flex items-center px-4 py-2 bg-theme-interactive-primary/10 border border-theme-interactive-primary/20 rounded-full mb-8">
              <span className="text-sm font-medium text-theme-interactive-primary">
                ✨ New: Advanced Analytics Dashboard Available
              </span>
            </div>
            
            {page && (
              <div className="space-y-6">
                <h1 className="text-5xl sm:text-6xl lg:text-7xl font-bold tracking-tight">
                  <span className="block bg-gradient-to-r from-theme-primary via-theme-interactive-primary to-theme-primary bg-clip-text text-transparent animate-pulse">
                    Welcome to
                  </span>
                  <span className="block bg-gradient-to-r from-theme-interactive-primary to-theme-interactive-secondary bg-clip-text text-transparent">
                    Powernode
                  </span>
                </h1>
                
                <p className="max-w-3xl mx-auto text-xl sm:text-2xl text-theme-secondary leading-relaxed">
                  The complete subscription lifecycle management platform that scales with your business
                </p>
                
                <div className="flex flex-col sm:flex-row gap-4 justify-center items-center pt-8">
                  <Link
                    to="/plans"
                    className="inline-flex items-center px-8 py-4 bg-theme-interactive-primary text-white rounded-xl font-semibold shadow-lg hover:shadow-xl hover:bg-theme-interactive-primary/90 transition-all duration-200"
                  >
                    Start Free Trial
                  </Link>
                  
                  <Link
                    to="#features"
                    className="inline-flex items-center px-8 py-4 bg-theme-surface border border-theme rounded-xl font-semibold text-theme-primary hover:bg-theme-surface-hover transition-all duration-200 shadow-lg"
                  >
                    Learn More
                    <svg className="ml-2 w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
                    </svg>
                  </Link>
                </div>
              </div>
            )}
          </div>
        </div>
      </section>

      {/* Features Section */}
      <section id="features" className="py-20 bg-theme-surface/50">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-4xl font-bold text-theme-primary mb-4">
              Why Choose Powernode?
            </h2>
            <p className="text-xl text-theme-secondary max-w-3xl mx-auto">
              Everything you need to manage subscriptions, payments, and customer relationships in one powerful platform
            </p>
          </div>
          
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
            {[
              {
                icon: "💰",
                title: "Revenue Management",
                description: "Track recurring revenue, manage subscriptions, and optimize pricing strategies with advanced analytics."
              },
              {
                icon: "⚡",
                title: "Lightning Fast",
                description: "Built for performance with modern tech stack. Sub-second load times and real-time updates."
              },
              {
                icon: "🔒",
                title: "Enterprise Security",
                description: "Bank-level security with SOC 2 compliance, end-to-end encryption, and advanced access controls."
              },
              {
                icon: "🚀",
                title: "Scalable Platform",
                description: "From startup to enterprise. Our platform grows with your business needs seamlessly."
              },
              {
                icon: "📊",
                title: "Advanced Analytics",
                description: "Deep insights into customer behavior, churn prediction, and revenue optimization metrics."
              },
              {
                icon: "🤖",
                title: "Smart Automation",
                description: "Automate billing, notifications, and customer lifecycle management with intelligent workflows."
              }
            ].map((feature, index) => (
              <div
                key={index}
                className="group relative bg-theme-surface rounded-2xl p-8 shadow-lg hover:shadow-2xl transition-all duration-300 hover:scale-105 border border-theme"
              >
                <div className="text-4xl mb-4">{feature.icon}</div>
                <h3 className="text-xl font-semibold text-theme-primary mb-3">
                  {feature.title}
                </h3>
                <p className="text-theme-secondary leading-relaxed">
                  {feature.description}
                </p>
                <div className="absolute inset-0 bg-gradient-to-br from-theme-interactive-primary/5 to-transparent rounded-2xl opacity-0 group-hover:opacity-100 transition-opacity duration-300"></div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Content Section */}
      {page && (
        <section className="py-20">
          <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8">
            <article className="prose prose-lg max-w-none">
              <div className="markdown-content bg-theme-surface/60 backdrop-blur-sm rounded-3xl p-8 lg:p-12 shadow-xl border border-theme">
                <ReactMarkdown
                  components={{
                    h1: ({ children }) => (
                      <h1 className="text-4xl font-bold bg-gradient-to-r from-theme-primary to-theme-interactive-primary bg-clip-text text-transparent mb-6 leading-tight">
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
                      <ul className="list-none mb-4 space-y-3 text-theme-secondary">
                        {children}
                      </ul>
                    ),
                    ol: ({ children }) => (
                      <ol className="list-decimal list-inside mb-4 space-y-2 text-theme-secondary">
                        {children}
                      </ol>
                    ),
                    li: ({ children }) => (
                      <li className="text-lg leading-relaxed flex items-start">
                        <span className="text-theme-interactive-primary mr-3 mt-1">•</span>
                        <span>{children}</span>
                      </li>
                    ),
                    blockquote: ({ children }) => (
                      <blockquote className="border-l-4 border-theme-interactive-primary pl-6 my-6 italic text-theme-primary bg-gradient-to-r from-theme-interactive-primary/10 to-transparent p-6 rounded-r-xl">
                        {children}
                      </blockquote>
                    ),
                    code: ({ children, className }) => {
                      const isInline = !className;
                      if (isInline) {
                        return (
                          <code className="bg-theme-interactive-primary/10 px-2 py-1 rounded text-sm font-mono text-theme-interactive-primary">
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
                      <pre className="bg-theme-background p-6 rounded-xl overflow-x-auto mb-6 border border-theme shadow-lg">
                        {children}
                      </pre>
                    ),
                    a: ({ href, children }) => (
                      <a
                        href={href}
                        className="text-theme-interactive-primary hover:text-theme-interactive-secondary underline decoration-2 underline-offset-2 transition-colors duration-200"
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
          </div>
        </section>
      )}

      {/* Call to Action Section */}
      <section className="relative py-20 overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-r from-theme-interactive-primary via-theme-interactive-secondary to-theme-interactive-primary opacity-10"></div>
        <div className="relative max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
          <div className="bg-theme-surface/80 backdrop-blur-md rounded-3xl p-12 shadow-2xl border border-theme">
            <h2 className="text-4xl font-bold bg-gradient-to-r from-theme-primary to-theme-interactive-primary bg-clip-text text-transparent mb-6">
              Ready to Transform Your Business?
            </h2>
            <p className="text-xl text-theme-secondary mb-8 max-w-2xl mx-auto leading-relaxed">
              Join thousands of businesses that trust Powernode to manage their subscription lifecycle and accelerate growth.
            </p>
            
            <div className="flex flex-col sm:flex-row gap-6 justify-center items-center">
              <Link
                to="/plans"
                className="inline-flex items-center px-8 py-4 bg-theme-interactive-primary text-white rounded-xl font-semibold shadow-lg hover:shadow-xl hover:bg-theme-interactive-primary/90 transition-all duration-200"
              >
                View Plans & Pricing
                <svg className="ml-2 w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M17 8l4 4m0 0l-4 4m4-4H3" />
                </svg>
              </Link>
              
              <Link
                to="/login"
                className="inline-flex items-center px-8 py-4 bg-theme-surface border border-theme rounded-xl font-semibold text-theme-primary hover:bg-theme-surface-hover transition-all duration-200 shadow-lg"
              >
                Sign In to Dashboard
              </Link>
            </div>
            
            <div className="mt-8 flex items-center justify-center space-x-6 text-sm text-theme-tertiary">
              <div className="flex items-center">
                <span className="text-theme-success mr-2">✓</span>
                14-day free trial
              </div>
              <div className="flex items-center">
                <span className="text-theme-success mr-2">✓</span>
                No credit card required
              </div>
              <div className="flex items-center">
                <span className="text-theme-success mr-2">✓</span>
                Cancel anytime
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="bg-theme-background py-16 border-t border-theme">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center">
            <div className="flex items-center justify-center space-x-4 mb-6">
              <div className="w-10 h-10 bg-gradient-to-br from-theme-interactive-primary to-theme-interactive-secondary rounded-xl flex items-center justify-center shadow-lg">
                <span className="text-white font-bold text-lg">P</span>
              </div>
              <span className="text-2xl font-bold bg-gradient-to-r from-theme-primary to-theme-interactive-primary bg-clip-text text-transparent">
                Powernode
              </span>
            </div>
            
            <div className="flex items-center justify-center space-x-8 mb-6 text-sm text-theme-secondary">
              <span>🔒 SOC 2 Compliant</span>
              <span>⚡ 99.9% Uptime</span>
              <span>🌍 Global CDN</span>
              <span>📞 24/7 Support</span>
            </div>
            
            <p className="text-theme-tertiary">
              © 2025 Powernode. All rights reserved. Built with ❤️ for growing businesses.
            </p>
          </div>
        </div>
      </footer>
    </div>
  );
};