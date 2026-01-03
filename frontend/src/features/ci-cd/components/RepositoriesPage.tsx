import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { GitBranch, Search, RefreshCw, ExternalLink, Play } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { PageErrorBoundary } from '@/shared/components/error/ErrorBoundary';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { gitProvidersApi } from '@/features/git-providers/services/gitProvidersApi';
import type { GitRepository, PaginationInfo } from '../types';

const WebhookBadge: React.FC<{ configured: boolean }> = ({ configured }) => (
  <span className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-medium ${
    configured
      ? 'bg-theme-success/10 text-theme-success'
      : 'bg-theme-warning/10 text-theme-warning'
  }`}>
    {configured ? 'Webhook active' : 'No webhook'}
  </span>
);

const RepositoryCard: React.FC<{
  repository: GitRepository;
  onClick: () => void;
}> = ({ repository, onClick }) => (
  <div
    className="bg-theme-surface rounded-lg p-4 border border-theme hover:border-theme-primary transition-colors cursor-pointer"
    onClick={onClick}
  >
    <div className="flex items-start justify-between mb-3">
      <div className="flex items-center gap-3">
        <div className="w-10 h-10 rounded-lg bg-theme-primary/10 flex items-center justify-center">
          <GitBranch className="w-5 h-5 text-theme-primary" />
        </div>
        <div>
          <h3 className="font-medium text-theme-primary">{repository.name}</h3>
          <p className="text-xs text-theme-tertiary">{repository.full_name}</p>
        </div>
      </div>
      <div className="flex items-center gap-2">
        <WebhookBadge configured={repository.webhook_configured} />
        {repository.web_url && (
          <a
            href={repository.web_url}
            target="_blank"
            rel="noopener noreferrer"
            onClick={(e) => e.stopPropagation()}
            className="text-theme-secondary hover:text-theme-primary p-1"
          >
            <ExternalLink className="w-4 h-4" />
          </a>
        )}
      </div>
    </div>

    <div className="flex items-center justify-between text-xs text-theme-tertiary">
      <div className="flex items-center gap-3">
        <span className="capitalize">{repository.provider_type}</span>
        {repository.is_private && (
          <span className="bg-theme-secondary/10 px-2 py-0.5 rounded">Private</span>
        )}
      </div>
      {repository.last_synced_at && (
        <span>Synced: {new Date(repository.last_synced_at).toLocaleDateString()}</span>
      )}
    </div>
  </div>
);

const RepositoriesPageContent: React.FC = () => {
  const navigate = useNavigate();
  const [repositories, setRepositories] = useState<GitRepository[]>([]);
  const [pagination, setPagination] = useState<PaginationInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [page, setPage] = useState(1);

  const fetchRepositories = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const data = await gitProvidersApi.getRepositories({
        page,
        per_page: 20,
        search: searchQuery || undefined,
      });
      setRepositories(data.repositories);
      setPagination(data.pagination);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch repositories');
    } finally {
      setLoading(false);
    }
  }, [page, searchQuery]);

  useEffect(() => {
    fetchRepositories();
  }, [fetchRepositories]);

  const breadcrumbs = [
    { label: 'CI/CD', href: '/app/ci-cd', icon: Play },
    { label: 'Repositories' }
  ];

  const actions = [
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: fetchRepositories,
      variant: 'primary' as const,
      icon: RefreshCw
    }
  ];


  return (
    <PageContainer
      title="Repositories"
      description="View and manage repository pipelines"
      breadcrumbs={breadcrumbs}
      actions={actions}
    >
      <div className="space-y-6">
        {/* Search */}
        <div className="relative max-w-md">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-theme-tertiary" />
          <Input
            type="text"
            placeholder="Search repositories..."
            value={searchQuery}
            onChange={(e) => {
              setSearchQuery(e.target.value);
              setPage(1);
            }}
            className="pl-10"
          />
        </div>

        {/* Error State */}
        {error && (
          <div className="bg-theme-error/10 border border-theme-error rounded-lg p-4">
            <p className="text-theme-error">{error}</p>
            <Button onClick={fetchRepositories} variant="secondary" size="sm" className="mt-2">
              Try Again
            </Button>
          </div>
        )}

        {/* Loading State */}
        {loading && (
          <div className="flex items-center justify-center py-12">
            <LoadingSpinner size="lg" />
            <span className="ml-3 text-theme-secondary">Loading repositories...</span>
          </div>
        )}

        {/* Empty State */}
        {!loading && !error && repositories.length === 0 && (
          <div className="bg-theme-surface rounded-lg p-8 border border-theme text-center">
            <GitBranch className="w-12 h-12 text-theme-secondary mx-auto mb-4" />
            <h3 className="text-lg font-medium text-theme-primary mb-2">No Repositories Found</h3>
            <p className="text-theme-secondary mb-4">
              {searchQuery
                ? 'Try adjusting your search.'
                : 'Connect repositories from your Git providers to start tracking pipelines.'}
            </p>
            {!searchQuery && (
              <Button onClick={() => navigate('/app/system/git-providers')} variant="primary">
                Configure Git Providers
              </Button>
            )}
          </div>
        )}

        {/* Repository Grid */}
        {!loading && !error && repositories.length > 0 && (
          <>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {repositories.map((repo) => (
                <RepositoryCard
                  key={repo.id}
                  repository={repo}
                  onClick={() => navigate(`/app/ci-cd/repositories/${repo.id}`)}
                />
              ))}
            </div>

            {/* Pagination */}
            {pagination && pagination.total_pages > 1 && (
              <div className="flex items-center justify-between pt-4 border-t border-theme">
                <p className="text-sm text-theme-tertiary">
                  Showing {repositories.length} of {pagination.total_count} repositories
                </p>
                <div className="flex items-center gap-2">
                  <Button
                    onClick={() => setPage((p) => Math.max(1, p - 1))}
                    disabled={page === 1}
                    variant="secondary"
                    size="sm"
                  >
                    Previous
                  </Button>
                  <span className="text-sm text-theme-secondary">
                    Page {page} of {pagination.total_pages}
                  </span>
                  <Button
                    onClick={() => setPage((p) => Math.min(pagination.total_pages, p + 1))}
                    disabled={page >= pagination.total_pages}
                    variant="secondary"
                    size="sm"
                  >
                    Next
                  </Button>
                </div>
              </div>
            )}
          </>
        )}
      </div>
    </PageContainer>
  );
};

export const RepositoriesPage: React.FC = () => (
  <PageErrorBoundary>
    <RepositoriesPageContent />
  </PageErrorBoundary>
);

export default RepositoriesPage;
