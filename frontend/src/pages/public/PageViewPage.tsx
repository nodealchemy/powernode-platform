import React, { useState, useEffect } from 'react';

import { useParams } from 'react-router-dom';

import { pagesApi, Page } from '@/features/pages/services/pagesApi';

import { PublicPageContainer } from '@/shared/components/layout/PublicPageContainer';

import { PublicContentSection } from '@/shared/components/layout/PublicContentSection';
import { getErrorMessage } from '@/shared/utils/errorHandling';


export const PageViewPage: React.FC = () => {
  const { slug } = useParams<{ slug: string }>();
  const [page, setPage] = useState<Page | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {

    if (slug) {
 void loadPage();
    }
  }, [slug]);

  const loadPage = async () => {
    if (!slug) return;

    try {
      setIsLoading(true);
      setError(null);
      const response = await pagesApi.getPublicPage(slug);
      setPage(response.data);
    } catch (error: unknown) {
      const errorMessage = getErrorMessage(error);
      setError(errorMessage);
    } finally {
      setIsLoading(false);
    }
  };

  // Format published date
  const formatPublishedDate = (publishedAt?: string): string => {
    if (!publishedAt) return 'Not published';
    return new Date(publishedAt).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'long',
      day: 'numeric'
    });
  };

  if (isLoading) {
    return (
      <PublicPageContainer>
        <div className="min-h-screen flex items-center justify-center">
          <div className="text-center">
            <div className="animate-spin h-12 w-12 border-4 border-blue-600 border-t-transparent rounded-full mx-auto mb-4"></div>
            <p className="text-slate-600 dark:text-slate-400">Loading page...</p>
          </div>
        </div>
      </PublicPageContainer>
    );
  }

  if (error || !page) {
    return (
      <PublicPageContainer 
        title="Page Not Found" 
        description={error === 'Page not found' 
          ? "The page you're looking for doesn't exist or hasn't been published yet."
          : "We're having trouble loading this page. Please try again later."
        }
        showBackButton
        backButtonLabel="Back to Home"
        backButtonHref="/"
      >
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-16 text-center">
          <div className="text-6xl mb-6">😕</div>
          <p className="text-xl text-slate-600 dark:text-slate-300 mb-8">
            {error === 'Page not found' 
              ? "The page you're looking for doesn't exist or hasn't been published yet."
              : "We're having trouble loading this page. Please try again later."
            }
          </p>
          <button
            onClick={() => loadPage?.()}
            className="inline-flex items-center space-x-2 px-6 py-3 bg-theme-info-solid hover:bg-theme-interactive-primary-hover text-white font-semibold rounded-xl transition-all duration-200 transform hover:scale-105 shadow-lg hover:shadow-xl"
          >
            <span>Try Again</span>
          </button>
        </div>
      </PublicPageContainer>
    );
  }

  return (
    <PublicPageContainer 
      title={page.title}
      description={page.meta_description || undefined}
      showBackButton
      backButtonLabel="Back to Home"
      backButtonHref="/"
    >
      <PublicContentSection
        content={page.content}
        renderedContent={page.rendered_content}
        showMeta
        metaData={{
          status: page.status,
          publishedAt: formatPublishedDate(page.published_at),
          readingTime: page.estimated_read_time
        }}
      />
    </PublicPageContainer>
  );
};
