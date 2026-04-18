import React, { useState, useEffect } from 'react';
import { pagesApi, BacklinkItem, UnlinkedMentionItem, RelatedPageItem } from '../services/pagesApi';
import { logger } from '@/shared/utils/logger';

interface BacklinksPanelProps {
  pageId: string;
  pageTitle: string;
}

export const BacklinksPanel: React.FC<BacklinksPanelProps> = ({ pageId, pageTitle }) => {
  const [backlinks, setBacklinks] = useState<BacklinkItem[]>([]);
  const [unlinkedMentions, setUnlinkedMentions] = useState<UnlinkedMentionItem[]>([]);
  const [relatedPages, setRelatedPages] = useState<RelatedPageItem[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!pageId) return;

    const fetchData = async () => {
      setLoading(true);
      try {
        const [backlinksRes, mentionsRes, relatedRes] = await Promise.allSettled([
          pagesApi.getBacklinks(pageId),
          pagesApi.getUnlinkedMentions(pageId),
          pagesApi.getRelatedPages(pageId),
        ]);

        if (backlinksRes.status === 'fulfilled') {
          setBacklinks(backlinksRes.value.data.backlinks || []);
        }
        if (mentionsRes.status === 'fulfilled') {
          setUnlinkedMentions(mentionsRes.value.data.unlinked_mentions || []);
        }
        if (relatedRes.status === 'fulfilled') {
          setRelatedPages(relatedRes.value.data.related_pages || []);
        }
      } catch (err) {
        logger.warn('[BacklinksPanel] Failed to fetch link data');
      } finally {
        setLoading(false);
      }
    };

    fetchData();
  }, [pageId]);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <div className="animate-spin rounded-full h-8 w-8 border-2 border-theme-link border-t-transparent" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Backlinks */}
      <div className="card-theme p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-2">
          Backlinks ({backlinks.length})
        </h3>
        <p className="text-sm text-theme-secondary mb-4">
          Pages that link to &ldquo;{pageTitle}&rdquo; using [[wikilinks]].
        </p>
        {backlinks.length > 0 ? (
          <ul className="space-y-3">
            {backlinks.map((bl) => (
              <li key={bl.id} className="p-3 rounded-lg bg-theme-background-secondary border border-theme hover:border-theme-focus transition-colors">
                <a
                  href={`/app/content/pages/${bl.slug}`}
                  className="text-theme-link hover:text-theme-link-hover font-medium"
                >
                  {bl.title}
                </a>
                <span className="ml-2 text-xs px-2 py-0.5 rounded-full bg-theme-surface text-theme-secondary">
                  {bl.type}
                </span>
                <p className="text-sm text-theme-tertiary mt-1 line-clamp-2">{bl.excerpt}</p>
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-sm text-theme-tertiary italic">
            No pages link to this page yet. Use [[{pageTitle}]] in other pages to create links.
          </p>
        )}
      </div>

      {/* Unlinked Mentions */}
      <div className="card-theme p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-2">
          Unlinked Mentions ({unlinkedMentions.length})
        </h3>
        <p className="text-sm text-theme-secondary mb-4">
          Pages that mention &ldquo;{pageTitle}&rdquo; as plain text but don&apos;t use a [[wikilink]].
        </p>
        {unlinkedMentions.length > 0 ? (
          <ul className="space-y-3">
            {unlinkedMentions.map((mention) => (
              <li key={mention.id} className="p-3 rounded-lg bg-theme-background-secondary border border-theme">
                <div className="flex items-center justify-between">
                  <a
                    href={`/app/content/pages/${mention.slug}`}
                    className="text-theme-link hover:text-theme-link-hover font-medium"
                  >
                    {mention.title}
                  </a>
                  <button
                    onClick={() => navigator.clipboard.writeText(`[[${pageTitle}]]`)}
                    className="text-xs px-2 py-1 rounded bg-theme-surface text-theme-secondary hover:text-theme-primary transition-colors"
                    title="Copy wikilink to clipboard"
                  >
                    Copy [[link]]
                  </button>
                </div>
                <p className="text-sm text-theme-tertiary mt-1 line-clamp-2">{mention.excerpt}</p>
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-sm text-theme-tertiary italic">No unlinked mentions found.</p>
        )}
      </div>

      {/* Related Pages (Semantic) */}
      <div className="card-theme p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-2">
          Related Pages ({relatedPages.length})
        </h3>
        <p className="text-sm text-theme-secondary mb-4">
          Semantically similar pages based on content embeddings.
        </p>
        {relatedPages.length > 0 ? (
          <ul className="space-y-3">
            {relatedPages.map((rp) => (
              <li key={rp.id} className="p-3 rounded-lg bg-theme-background-secondary border border-theme hover:border-theme-focus transition-colors">
                <div className="flex items-center justify-between">
                  <a
                    href={`/app/content/pages/${rp.slug}`}
                    className="text-theme-link hover:text-theme-link-hover font-medium"
                  >
                    {rp.title}
                  </a>
                  <div className="flex items-center space-x-2">
                    <div className="w-16 h-1.5 rounded-full bg-theme-surface overflow-hidden">
                      <div
                        className="h-full rounded-full bg-theme-success-solid"
                        style={{ width: `${Math.round(rp.similarity * 100)}%` }}
                      />
                    </div>
                    <span className="text-xs text-theme-tertiary">
                      {Math.round(rp.similarity * 100)}%
                    </span>
                  </div>
                </div>
                <p className="text-sm text-theme-tertiary mt-1 line-clamp-2">{rp.excerpt}</p>
              </li>
            ))}
          </ul>
        ) : (
          <p className="text-sm text-theme-tertiary italic">
            No related pages found. Semantic linking requires content embeddings to be generated.
          </p>
        )}
      </div>
    </div>
  );
};
