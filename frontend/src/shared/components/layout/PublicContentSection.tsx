import React from 'react';
import { MarkdownRenderer } from '@/shared/components/ui/MarkdownRenderer';

interface PublicContentSectionProps {
  content: string;
  renderedContent?: string;
  className?: string;
  showMeta?: boolean;
  metaData?: {
    publishedAt?: string;
    readingTime?: number;
    status?: string;
  };
}

export const PublicContentSection: React.FC<PublicContentSectionProps> = ({
  content,
  renderedContent,
  className = "",
  showMeta = false,
  metaData
}) => {

  return (
    <div className="theme-public bg-public-gradient">
      <section className={`py-12 fade-in ${className}`}>
        <div className="max-w-none mx-auto px-4 sm:px-6 lg:px-8">
          {/* Meta Information */}
          {showMeta && metaData && (
            <div className="meta mb-6">
              <div className="flex items-center justify-between text-sm">
                <div className="flex items-center gap-6">
                  {metaData.status && (
                    <div className="flex items-center gap-2">
                      <span className="label">Status:</span>
                      <span className={`px-2 py-1 rounded-full text-xs font-medium ${
                        metaData.status === 'published'
                          ? 'bg-theme-success/20 text-theme-success'
                          : 'bg-theme-warning/20 text-theme-warning'
                      }`}>
                        {metaData.status.charAt(0).toUpperCase() + metaData.status.slice(1)}
                      </span>
                    </div>
                  )}
                  {metaData.publishedAt && (
                    <div className="flex items-center gap-2">
                      <span className="label">Published:</span>
                      <span className="value">{metaData.publishedAt}</span>
                    </div>
                  )}
                  {metaData.readingTime && (
                    <div className="flex items-center gap-2">
                      <span className="label">Reading Time:</span>
                      <span className="value">{metaData.readingTime} min</span>
                    </div>
                  )}
                </div>
              </div>
            </div>
          )}

          {/* Article Content */}
          <article className="surface-lg slide-up">
            <div className="markdown-content">
              <MarkdownRenderer
                content={content}
                renderedContent={renderedContent}
                variant="public"
                className=""
                maxWidth="wide"
                fontSize="lg"
                lineHeight="relaxed"
                enableReadingMode={true}
              />
            </div>
          </article>
        </div>
      </section>
    </div>
  );
};