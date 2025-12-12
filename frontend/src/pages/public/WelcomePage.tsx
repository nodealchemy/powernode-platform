import React, { useState, useEffect, useCallback } from 'react';

import { Link } from 'react-router-dom';

import { MarkdownRenderer } from '@/shared/components/ui/MarkdownRenderer';

import { PublicPageContainer } from '@/shared/components/layout/PublicPageContainer';

import { pagesApi, Page } from '@/features/pages/services/pagesApi';

import { getErrorMessage } from '@/shared/utils/errorHandling';


interface WelcomePageProps {
  pageSlug?: string;
}

export const WelcomePage: React.FC<WelcomePageProps> = ({ pageSlug = 'welcome' }) => {
  const [page, setPage] = useState<Page | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loadPage = useCallback(async () => {
    try {
      setIsLoading(true);
      setError(null);
      const response = await pagesApi.getPublicPage(pageSlug);
      setPage(response.data);
    } catch (error: unknown) {
      const errorMessage = getErrorMessage(error);
      setError(errorMessage);
    } finally {
      setIsLoading(false);
    }
  }, [pageSlug]);

  useEffect(() => {

 void loadPage();
  }, [loadPage]);

  if (isLoading) {
    return (
      <PublicPageContainer>
        <div className="flex items-center justify-center py-20">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-info"></div>
        </div>
      </PublicPageContainer>
    );
  }

  if (error) {
    return (
      <PublicPageContainer>
        <div className="text-center py-20">
          <div className="text-4xl mb-6">😕</div>
          <h1 className="text-2xl font-bold text-white mb-4">Oops! Something went wrong</h1>
          <p className="text-white/80 mb-8">{error}</p>
          <div className="flex flex-col sm:flex-row gap-4 justify-center">
            <button onClick={() => loadPage?.()} className="inline-flex items-center justify-center px-6 py-3 border-2 border-white/30 hover:border-white/60 text-white hover:text-white font-semibold rounded-xl transition-all duration-200">
              Try Again
            </button>
            <Link to="/plans" className="inline-flex items-center justify-center px-6 py-3 bg-theme-info-solid hover:bg-theme-interactive-primary-hover text-white font-semibold rounded-xl transition-all duration-200">
              View Plans
            </Link>
          </div>
        </div>
      </PublicPageContainer>
    );
  }

  return (
    <PublicPageContainer 
      title={page?.title || "Welcome to Powernode"}
      description={page?.meta_description || "Streamline your subscription business with automated billing, analytics, and customer lifecycle management."}
    >
      {/* Hero Section */}
      <section className="relative overflow-hidden py-20">
        {/* Background Decorations - Subtle ambient glow */}
        <div className="absolute inset-0 pointer-events-none overflow-hidden">
          <div
            className="absolute -top-32 left-1/4 w-[600px] h-[600px] rounded-full opacity-30"
            style={{ background: 'radial-gradient(circle, rgba(59, 130, 246, 0.15) 0%, rgba(59, 130, 246, 0.05) 40%, transparent 70%)' }}
          />
          <div
            className="absolute -bottom-32 right-1/4 w-[700px] h-[700px] rounded-full opacity-30"
            style={{ background: 'radial-gradient(circle, rgba(139, 92, 246, 0.15) 0%, rgba(139, 92, 246, 0.05) 40%, transparent 70%)' }}
          />
        </div>
        
        <div className="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div>
            {/* Trust Indicators */}
            <div className="flex justify-center flex-wrap gap-4 mb-12">
              <div className="inline-flex items-center space-x-2 bg-white/10 backdrop-blur-sm px-4 py-2 rounded-full border border-white/20">
                <svg className="w-5 h-5 text-theme-success" fill="currentColor" viewBox="0 0 20 20">
                  <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
                </svg>
                <span className="text-sm font-medium text-white">SOC 2 Compliant</span>
              </div>
              <div className="inline-flex items-center space-x-2 bg-white/10 backdrop-blur-sm px-4 py-2 rounded-full border border-white/20">
                <svg className="w-5 h-5 text-theme-info" fill="currentColor" viewBox="0 0 20 20">
                  <path fillRule="evenodd" d="M2.166 4.999A11.954 11.954 0 0010 1.944 11.954 11.954 0 0017.834 5c.11.65.166 1.32.166 2.001 0 5.225-3.34 9.67-8 11.317C5.34 16.67 2 12.225 2 7c0-.682.057-1.35.166-2.001zm11.541 3.708a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
                </svg>
                <span className="text-sm font-medium text-white">PCI Compliant</span>
              </div>
              <div className="inline-flex items-center space-x-2 bg-white/10 backdrop-blur-sm px-4 py-2 rounded-full border border-white/20">
                <svg className="w-5 h-5 text-theme-interactive-primary" fill="currentColor" viewBox="0 0 20 20">
                  <path fillRule="evenodd" d="M6.267 3.455a3.066 3.066 0 001.745-.723 3.066 3.066 0 013.976 0 3.066 3.066 0 001.745.723 3.066 3.066 0 012.812 2.812c.051.643.304 1.254.723 1.745a3.066 3.066 0 010 3.976 3.066 3.066 0 00-.723 1.745 3.066 3.066 0 01-2.812 2.812 3.066 3.066 0 00-1.745.723 3.066 3.066 0 01-3.976 0 3.066 3.066 0 00-1.745-.723 3.066 3.066 0 01-2.812-2.812 3.066 3.066 0 00-.723-1.745 3.066 3.066 0 010-3.976 3.066 3.066 0 00.723-1.745 3.066 3.066 0 012.812-2.812zm7.44 5.252a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
                </svg>
                <span className="text-sm font-medium text-white">99.9% Uptime</span>
              </div>
            </div>

            {/* Hero Content */}
            {page && (
              <div className="max-w-4xl mx-auto">
                <MarkdownRenderer 
                  content={page.content} 
                  variant="public"
                  maxWidth="none"
                  enableReadingMode={false}
                  className="text-white dark:text-white text-left"
                />
              </div>
            )}
          </div>
        </div>
      </section>

      {/* Features Section */}
      <section className="py-20 bg-white/10 backdrop-blur-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-3xl md:text-4xl font-bold text-white mb-6">Why Choose Powernode?</h2>
            <p className="text-xl text-white/80 max-w-2xl mx-auto">Everything you need to manage, grow, and scale your subscription business.</p>
          </div>

          <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-8">
            <div className="bg-white/10 backdrop-blur-sm p-8 rounded-2xl shadow-lg border border-white/20 transform hover:scale-105 transition-all duration-300">
              <div className="w-12 h-12 bg-theme-info/20 rounded-xl flex items-center justify-center mb-6">
                <span className="text-2xl">💳</span>
              </div>
              <h3 className="text-xl font-semibold text-white mb-4">Automated Billing</h3>
              <p className="text-white/70">Handle subscriptions, invoicing, and recurring payments seamlessly with our intelligent billing system.</p>
            </div>

            <div className="bg-white/10 backdrop-blur-sm p-8 rounded-2xl shadow-lg border border-white/20 transform hover:scale-105 transition-all duration-300">
              <div className="w-12 h-12 bg-theme-success/20 rounded-xl flex items-center justify-center mb-6">
                <span className="text-2xl">📊</span>
              </div>
              <h3 className="text-xl font-semibold text-white mb-4">Real-time Analytics</h3>
              <p className="text-white/70">Track revenue, monitor customer lifecycle, and get actionable insights to grow your business.</p>
            </div>

            <div className="bg-white/10 backdrop-blur-sm p-8 rounded-2xl shadow-lg border border-white/20 transform hover:scale-105 transition-all duration-300">
              <div className="w-12 h-12 bg-purple-600/20 rounded-xl flex items-center justify-center mb-6">
                <span className="text-2xl">🔒</span>
              </div>
              <h3 className="text-xl font-semibold text-white mb-4">Enterprise Security</h3>
              <p className="text-white/70">PCI-compliant infrastructure with advanced encryption and security measures to protect your data.</p>
            </div>

            <div className="bg-white/10 backdrop-blur-sm p-8 rounded-2xl shadow-lg border border-white/20 transform hover:scale-105 transition-all duration-300">
              <div className="w-12 h-12 bg-amber-500/20 rounded-xl flex items-center justify-center mb-6">
                <span className="text-2xl">🚀</span>
              </div>
              <h3 className="text-xl font-semibold text-white mb-4">API-First Platform</h3>
              <p className="text-white/70">Integrate seamlessly with your existing tools using our comprehensive REST API and webhooks.</p>
            </div>
          </div>
        </div>
      </section>

      {/* CTA Section */}
      <section className="py-20">
        <div className="max-w-4xl mx-auto text-center px-4 sm:px-6 lg:px-8">
          <h2 className="text-3xl md:text-4xl font-bold text-white mb-6">Ready to Transform Your Subscription Business?</h2>
          <p className="text-xl text-white/80 mb-8">Join thousands of businesses already using Powernode to manage their subscriptions.</p>
          <div className="flex flex-col sm:flex-row gap-4 justify-center">
            <Link to="/plans" className="inline-flex items-center justify-center px-8 py-4 bg-white hover:bg-theme-surface text-slate-800 font-semibold rounded-xl transition-all duration-200 transform hover:scale-105 shadow-lg hover:shadow-xl">
              Start Free Trial
            </Link>
            <Link to="/contact" className="inline-flex items-center justify-center px-8 py-4 border-2 border-white/30 hover:border-white/60 text-white hover:text-white font-semibold rounded-xl transition-all duration-200 transform hover:scale-105">
              Schedule Demo
            </Link>
          </div>
        </div>
      </section>
    </PublicPageContainer>
  );
};

export default WelcomePage;
