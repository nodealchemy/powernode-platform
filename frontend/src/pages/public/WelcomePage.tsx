import React, { useState, useEffect, useCallback } from 'react';

import { Link } from 'react-router-dom';

import { MarkdownRenderer } from '@/shared/components/ui/MarkdownRenderer';

import { PublicPageContainer } from '@/shared/components/layout/PublicPageContainer';

import { pagesApi, Page } from '@/features/content/pages/services/pagesApi';

import { getErrorMessage } from '@/shared/utils/errorHandling';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';


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
    } catch (err) {
      const errorMessage = getErrorMessage(err);
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
        <LoadingSpinner className="py-20" />
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
            style={{ background: 'radial-gradient(circle, var(--color-info, rgba(59, 130, 246, 0.15)) 0%, transparent 70%)' }}
          />
          <div
            className="absolute -bottom-32 right-1/4 w-[700px] h-[700px] rounded-full opacity-30"
            style={{ background: 'radial-gradient(circle, var(--color-interactive-primary, rgba(139, 92, 246, 0.15)) 0%, transparent 70%)' }}
          />
        </div>
        
        <div className="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div>
            {/* Trust Indicators */}
            <div className="flex justify-center flex-wrap gap-4 mb-12">
              <div className="inline-flex items-center space-x-2 bg-white/10 backdrop-blur-sm px-4 py-2 rounded-full border border-white/20">
                <span className="text-lg">🤖</span>
                <span className="text-sm font-medium text-white">AI-Powered</span>
              </div>
              <div className="inline-flex items-center space-x-2 bg-white/10 backdrop-blur-sm px-4 py-2 rounded-full border border-white/20">
                <span className="text-lg">🔒</span>
                <span className="text-sm font-medium text-white">Enterprise Security</span>
              </div>
              <div className="inline-flex items-center space-x-2 bg-white/10 backdrop-blur-sm px-4 py-2 rounded-full border border-white/20">
                <span className="text-lg">⚡</span>
                <span className="text-sm font-medium text-white">Real-time</span>
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
            <h2 className="text-3xl md:text-4xl font-bold text-white mb-6">AI-Powered Platform</h2>
            <p className="text-xl text-white/80 max-w-2xl mx-auto">Intelligent automation and insights to transform your business.</p>
          </div>

          <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-8">
            <div className="bg-white/10 backdrop-blur-sm p-8 rounded-2xl shadow-lg border border-white/20 transform hover:scale-105 transition-all duration-300">
              <div className="w-12 h-12 bg-gradient-to-br from-theme-interactive-primary/30 to-theme-interactive-secondary/30 rounded-xl flex items-center justify-center mb-6">
                <span className="text-2xl">🤖</span>
              </div>
              <h3 className="text-xl font-semibold text-white mb-4">AI Agents</h3>
              <p className="text-white/70">Deploy intelligent agents that automate workflows, analyze data, and make smart decisions in real-time.</p>
            </div>

            <div className="bg-white/10 backdrop-blur-sm p-8 rounded-2xl shadow-lg border border-white/20 transform hover:scale-105 transition-all duration-300">
              <div className="w-12 h-12 bg-gradient-to-br from-theme-info/30 to-theme-interactive-primary/30 rounded-xl flex items-center justify-center mb-6">
                <span className="text-2xl">🧠</span>
              </div>
              <h3 className="text-xl font-semibold text-white mb-4">Predictive Analytics</h3>
              <p className="text-white/70">AI-driven insights that forecast trends, identify opportunities, and optimize your operations.</p>
            </div>

            <div className="bg-white/10 backdrop-blur-sm p-8 rounded-2xl shadow-lg border border-white/20 transform hover:scale-105 transition-all duration-300">
              <div className="w-12 h-12 bg-gradient-to-br from-theme-success/30 to-theme-success/30 rounded-xl flex items-center justify-center mb-6">
                <span className="text-2xl">⚡</span>
              </div>
              <h3 className="text-xl font-semibold text-white mb-4">Smart Automation</h3>
              <p className="text-white/70">Automate billing, notifications, and customer workflows with intelligent orchestration.</p>
            </div>
          </div>
        </div>
      </section>

      {/* CTA Section */}
      <section className="py-20">
        <div className="max-w-4xl mx-auto text-center px-4 sm:px-6 lg:px-8">
          <h2 className="text-3xl md:text-4xl font-bold text-white mb-6">Get Started Today</h2>
          <p className="text-xl text-white/80 mb-8">Experience the power of AI-driven automation.</p>
          <div className="flex flex-col sm:flex-row gap-4 justify-center">
            <Link to="/register" className="inline-flex items-center justify-center px-8 py-4 bg-theme-surface hover:bg-theme-surface-hover text-theme-primary font-semibold rounded-xl transition-all duration-200 transform hover:scale-105 shadow-lg hover:shadow-xl">
              Create Account
            </Link>
            <Link to="/login" className="inline-flex items-center justify-center px-8 py-4 border-2 border-white/30 hover:border-white/60 text-white hover:text-white font-semibold rounded-xl transition-all duration-200 transform hover:scale-105">
              Sign In
            </Link>
          </div>
        </div>
      </section>
    </PublicPageContainer>
  );
};

export default WelcomePage;
