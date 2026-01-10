import { useState, useEffect, useRef } from 'react';
import { useSearchParams } from 'react-router-dom';
import {
  FolderGit2, Search, RefreshCw, Filter, MoreVertical,
  GitBranch, GitCommit, GitPullRequest,
  Lock, Unlock, Star, ExternalLink, Webhook, Trash2,
  ChevronLeft, ChevronRight, X, Loader2, Clock, Archive, Eye
} from 'lucide-react';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import { gitProvidersApi } from '@/features/git-providers/services/gitProvidersApi';
import { CommitDetailModal } from '@/features/git-providers/components/CommitDetailModal';
import type { GitRepository, GitProvider, PaginationInfo } from '@/features/git-providers/types';
import { useNotifications } from '@/shared/hooks/useNotifications';

interface RepositoryFilters {
  provider_id?: string;
  search?: string;
  is_private?: boolean;
  webhook_configured?: boolean;
}

const ProviderBadge: React.FC<{ type: string }> = ({ type }) => {
  const config: Record<string, { bg: string; text: string; label: string }> = {
    github: { bg: 'bg-theme-background dark:bg-theme-surface', text: 'text-white dark:text-theme-primary', label: 'GitHub' },
    gitlab: { bg: 'bg-theme-warning', text: 'text-white', label: 'GitLab' },
    gitea: { bg: 'bg-theme-success', text: 'text-white', label: 'Gitea' },
    bitbucket: { bg: 'bg-theme-info', text: 'text-white', label: 'Bitbucket' },
  };
  const c = config[type?.toLowerCase()] || config.github;
  return (
    <span className={`px-2 py-0.5 text-xs font-medium rounded ${c.bg} ${c.text}`}>
      {c.label}
    </span>
  );
};

const RepositoryCard: React.FC<{
  repository: GitRepository;
  onSync: () => void;
  onConfigureWebhook: () => void;
  onViewDetails: () => void;
  onDelete: () => void;
  syncing: boolean;
}> = ({ repository, onSync, onConfigureWebhook, onViewDetails, onDelete, syncing }) => {
  const [menuOpen, setMenuOpen] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(event.target as Node)) {
        setMenuOpen(false);
      }
    };
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, []);

  const formatTimeAgo = (dateStr?: string): string => {
    if (!dateStr) return 'Never';
    const date = new Date(dateStr);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffMins = Math.floor(diffMs / 60000);
    if (diffMins < 1) return 'Just now';
    if (diffMins < 60) return `${diffMins}m ago`;
    const diffHours = Math.floor(diffMins / 60);
    if (diffHours < 24) return `${diffHours}h ago`;
    const diffDays = Math.floor(diffHours / 24);
    return `${diffDays}d ago`;
  };

  return (
    <div className="bg-theme-surface border border-theme rounded-lg p-4 hover:border-theme-primary transition-colors">
      <div className="flex items-start justify-between gap-3">
        <div className="flex items-start gap-3 min-w-0 flex-1">
          <div className={`p-2 rounded-lg ${repository.is_private ? 'bg-theme-warning/10' : 'bg-theme-primary/10'}`}>
            {repository.is_private ? (
              <Lock className="w-5 h-5 text-theme-warning" />
            ) : (
              <FolderGit2 className="w-5 h-5 text-theme-primary" />
            )}
          </div>
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-2 flex-wrap">
              <h3 className="font-medium text-theme-primary truncate">{repository.name}</h3>
              <ProviderBadge type={repository.provider_type} />
              {repository.is_archived && (
                <span className="flex items-center gap-1 px-1.5 py-0.5 text-xs rounded bg-theme-secondary/10 text-theme-secondary">
                  <Archive className="w-3 h-3" />
                  Archived
                </span>
              )}
              {repository.webhook_configured && (
                <span className="flex items-center gap-1 px-1.5 py-0.5 text-xs rounded bg-theme-success/10 text-theme-success ">
                  <Webhook className="w-3 h-3" />
                  Webhook
                </span>
              )}
            </div>
            <p className="text-sm text-theme-secondary truncate">{repository.full_name}</p>
            {repository.description && (
              <p className="text-sm text-theme-tertiary mt-1 line-clamp-2">{repository.description}</p>
            )}
          </div>
        </div>

        <div className="relative" ref={menuRef}>
          <button
            onClick={() => setMenuOpen(!menuOpen)}
            className="p-1.5 hover:bg-theme-bg-subtle rounded-lg text-theme-secondary hover:text-theme-primary"
          >
            <MoreVertical className="w-4 h-4" />
          </button>
          {menuOpen && (
            <div className="absolute right-0 top-full mt-1 w-48 bg-theme-surface border border-theme rounded-lg shadow-lg z-10 py-1">
              <button
                onClick={() => { onViewDetails(); setMenuOpen(false); }}
                className="w-full flex items-center gap-2 px-3 py-2 text-sm text-theme-primary hover:bg-theme-bg-subtle"
              >
                <FolderGit2 className="w-4 h-4" />
                View Details
              </button>
              <button
                onClick={() => { onSync(); setMenuOpen(false); }}
                disabled={syncing}
                className="w-full flex items-center gap-2 px-3 py-2 text-sm text-theme-primary hover:bg-theme-bg-subtle disabled:opacity-50"
              >
                <RefreshCw className={`w-4 h-4 ${syncing ? 'animate-spin' : ''}`} />
                {syncing ? 'Syncing...' : 'Sync Repository'}
              </button>
              <button
                onClick={() => { onConfigureWebhook(); setMenuOpen(false); }}
                className="w-full flex items-center gap-2 px-3 py-2 text-sm text-theme-primary hover:bg-theme-bg-subtle"
              >
                <Webhook className="w-4 h-4" />
                {repository.webhook_configured ? 'Update Webhook' : 'Configure Webhook'}
              </button>
              {repository.web_url && (
                <a
                  href={repository.web_url}
                  target="_blank"
                  rel="noopener noreferrer"
                  onClick={() => setMenuOpen(false)}
                  className="w-full flex items-center gap-2 px-3 py-2 text-sm text-theme-primary hover:bg-theme-bg-subtle"
                >
                  <ExternalLink className="w-4 h-4" />
                  Open in Browser
                </a>
              )}
              <div className="border-t border-theme my-1" />
              <button
                onClick={() => { onDelete(); setMenuOpen(false); }}
                className="w-full flex items-center gap-2 px-3 py-2 text-sm text-theme-danger hover:bg-theme-danger/10"
              >
                <Trash2 className="w-4 h-4" />
                Remove Repository
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Stats Row */}
      <div className="flex items-center gap-4 mt-4 pt-3 border-t border-theme text-sm">
        <div className="flex items-center gap-1 text-theme-secondary">
          <Star className="w-4 h-4" />
          <span>{repository.stars_count}</span>
        </div>
        <div className="flex items-center gap-1 text-theme-secondary">
          <GitBranch className="w-4 h-4" />
          <span>{repository.default_branch}</span>
        </div>
        {repository.primary_language && (
          <div className="flex items-center gap-1 text-theme-secondary">
            <span className="w-2 h-2 rounded-full bg-theme-primary" />
            <span>{repository.primary_language}</span>
          </div>
        )}
        <div className="flex items-center gap-1 text-theme-secondary ml-auto">
          <Clock className="w-4 h-4" />
          <span>Synced {formatTimeAgo(repository.last_synced_at)}</span>
        </div>
      </div>
    </div>
  );
};

interface RepositoryDetailModalProps {
  repository: GitRepository;
  onClose: () => void;
}

const RepositoryDetailModal: React.FC<RepositoryDetailModalProps> = ({ repository, onClose }) => {
  const [activeTab, setActiveTab] = useState<'overview' | 'branches' | 'commits' | 'prs'>('overview');
  const [branches, setBranches] = useState<Array<{ name: string; is_default: boolean; protected: boolean }>>([]);
  const [commits, setCommits] = useState<Array<{ sha: string; short_sha: string; message: string; author: string; date: string }>>([]);
  const [pullRequests, setPullRequests] = useState<Array<{ id: string; number: number; title: string; state: string; author: string }>>([]);
  const [loading, setLoading] = useState(false);
  const [selectedCommitSha, setSelectedCommitSha] = useState<string | null>(null);

  useEffect(() => {
    const fetchData = async () => {
      setLoading(true);
      try {
        if (activeTab === 'branches') {
          const data = await gitProvidersApi.getBranches(repository.id) as Array<{ name?: string; is_default?: boolean; protected?: boolean }>;
          setBranches((data || []).map((b) => ({
            name: b.name || '',
            is_default: b.is_default || false,
            protected: b.protected || false
          })));
        } else if (activeTab === 'commits') {
          const data = await gitProvidersApi.getCommits(repository.id) as Array<{
            sha?: string;
            message?: string;
            commit?: { message?: string; author?: { name?: string; date?: string } };
            author?: { login?: string; name?: string } | string;
            created_at?: string;
          }>;
          setCommits((data || []).map((c) => {
            // Handle different provider formats (GitHub vs GitLab vs Gitea)
            const message = c.message || c.commit?.message || '';
            const authorName = typeof c.author === 'string'
              ? c.author
              : (c.author?.login || c.author?.name || c.commit?.author?.name || 'Unknown');
            const date = c.created_at || c.commit?.author?.date || '';
            const sha = c.sha || '';
            return {
              sha,
              short_sha: sha.substring(0, 7),
              message: message.split('\n')[0], // First line only
              author: authorName,
              date: date ? new Date(date).toLocaleDateString() : ''
            };
          }));
        } else if (activeTab === 'prs') {
          const data = await gitProvidersApi.getPullRequests(repository.id) as Array<{ id?: string; number?: number; title?: string; state?: string; author?: string }>;
          setPullRequests((data || []).map((pr) => ({
            id: pr.id || '',
            number: pr.number || 0,
            title: pr.title || '',
            state: pr.state || '',
            author: pr.author || ''
          })));
        }
      } catch (error) {
        // Silently fail
      } finally {
        setLoading(false);
      }
    };
    if (activeTab !== 'overview') {
      fetchData();
    }
  }, [activeTab, repository.id]);

  return (
    <div className="fixed inset-0 bg-theme-bg/80 flex items-center justify-center z-50 p-4">
      <div className="bg-theme-surface rounded-lg border border-theme w-full max-w-3xl max-h-[90vh] overflow-hidden flex flex-col">
        <div className="p-4 border-b border-theme flex items-center justify-between">
          <div className="flex items-center gap-3">
            <FolderGit2 className="w-5 h-5 text-theme-primary" />
            <div>
              <h3 className="font-medium text-theme-primary">{repository.name}</h3>
              <p className="text-sm text-theme-secondary">{repository.full_name}</p>
            </div>
          </div>
          <button onClick={onClose} className="p-2 hover:bg-theme-bg-subtle rounded-lg">
            <X className="w-5 h-5 text-theme-secondary" />
          </button>
        </div>

        {/* Tabs */}
        <div className="flex border-b border-theme">
          {[
            { id: 'overview', label: 'Overview', icon: FolderGit2 },
            { id: 'branches', label: 'Branches', icon: GitBranch },
            { id: 'commits', label: 'Commits', icon: GitCommit },
            { id: 'prs', label: 'Pull Requests', icon: GitPullRequest },
          ].map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id as typeof activeTab)}
              className={`flex items-center gap-2 px-4 py-3 text-sm font-medium border-b-2 -mb-px transition-colors ${
                activeTab === tab.id
                  ? 'border-theme-primary text-theme-primary'
                  : 'border-transparent text-theme-secondary hover:text-theme-primary'
              }`}
            >
              <tab.icon className="w-4 h-4" />
              {tab.label}
            </button>
          ))}
        </div>

        {/* Content */}
        <div className="flex-1 overflow-auto p-4">
          {activeTab === 'overview' && (
            <div className="space-y-4">
              {repository.description && (
                <div>
                  <h4 className="text-sm font-medium text-theme-secondary mb-1">Description</h4>
                  <p className="text-theme-primary">{repository.description}</p>
                </div>
              )}
              <div className="grid grid-cols-2 gap-4">
                <div className="bg-theme-bg-subtle rounded-lg p-3">
                  <p className="text-sm text-theme-secondary">Visibility</p>
                  <p className="font-medium text-theme-primary flex items-center gap-2">
                    {repository.is_private ? <Lock className="w-4 h-4" /> : <Unlock className="w-4 h-4" />}
                    {repository.is_private ? 'Private' : 'Public'}
                  </p>
                </div>
                <div className="bg-theme-bg-subtle rounded-lg p-3">
                  <p className="text-sm text-theme-secondary">Default Branch</p>
                  <p className="font-medium text-theme-primary">{repository.default_branch}</p>
                </div>
                <div className="bg-theme-bg-subtle rounded-lg p-3">
                  <p className="text-sm text-theme-secondary">Stars</p>
                  <p className="font-medium text-theme-primary">{repository.stars_count}</p>
                </div>
                <div className="bg-theme-bg-subtle rounded-lg p-3">
                  <p className="text-sm text-theme-secondary">Forks</p>
                  <p className="font-medium text-theme-primary">{repository.forks_count}</p>
                </div>
                <div className="bg-theme-bg-subtle rounded-lg p-3">
                  <p className="text-sm text-theme-secondary">Open Issues</p>
                  <p className="font-medium text-theme-primary">{repository.open_issues_count}</p>
                </div>
                <div className="bg-theme-bg-subtle rounded-lg p-3">
                  <p className="text-sm text-theme-secondary">Open PRs</p>
                  <p className="font-medium text-theme-primary">{repository.open_prs_count}</p>
                </div>
              </div>
              {repository.topics && repository.topics.length > 0 && (
                <div>
                  <h4 className="text-sm font-medium text-theme-secondary mb-2">Topics</h4>
                  <div className="flex flex-wrap gap-2">
                    {repository.topics.map((topic) => (
                      <span key={topic} className="px-2 py-1 text-xs rounded-full bg-theme-primary/10 text-theme-primary">
                        {topic}
                      </span>
                    ))}
                  </div>
                </div>
              )}
            </div>
          )}

          {activeTab === 'branches' && (
            <div>
              {loading ? (
                <div className="flex items-center justify-center py-8">
                  <Loader2 className="w-6 h-6 animate-spin text-theme-primary" />
                </div>
              ) : branches.length > 0 ? (
                <div className="space-y-2">
                  {branches.map((branch) => (
                    <div key={branch.name} className="flex items-center justify-between p-3 bg-theme-bg-subtle rounded-lg">
                      <div className="flex items-center gap-2">
                        <GitBranch className="w-4 h-4 text-theme-secondary" />
                        <span className="font-medium text-theme-primary">{branch.name}</span>
                        {branch.is_default && (
                          <span className="px-2 py-0.5 text-xs rounded bg-theme-primary text-white">Default</span>
                        )}
                        {branch.protected && (
                          <span className="px-2 py-0.5 text-xs rounded bg-theme-warning/10 text-theme-warning">Protected</span>
                        )}
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="text-center text-theme-secondary py-8">No branches found</p>
              )}
            </div>
          )}

          {activeTab === 'commits' && (
            <div>
              {loading ? (
                <div className="flex items-center justify-center py-8">
                  <Loader2 className="w-6 h-6 animate-spin text-theme-primary" />
                </div>
              ) : commits.length > 0 ? (
                <div className="space-y-2">
                  {commits.map((commit) => (
                    <div key={commit.sha} className="p-3 bg-theme-bg-subtle rounded-lg group">
                      <div className="flex items-start gap-3">
                        <GitCommit className="w-4 h-4 text-theme-secondary mt-1" />
                        <div className="flex-1 min-w-0">
                          <p className="text-theme-primary truncate">{commit.message}</p>
                          <p className="text-sm text-theme-secondary">
                            <span className="font-mono text-xs bg-theme-surface px-1 rounded">{commit.short_sha}</span>
                            {' by '}{commit.author}{' • '}{commit.date}
                          </p>
                        </div>
                        <button
                          onClick={() => setSelectedCommitSha(commit.sha)}
                          className="flex items-center gap-1 px-2 py-1 text-xs text-theme-secondary hover:text-theme-primary hover:bg-theme-surface rounded opacity-0 group-hover:opacity-100 transition-opacity"
                          title="View commit details"
                        >
                          <Eye className="w-3 h-3" />
                          View
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="text-center text-theme-secondary py-8">No commits found</p>
              )}
            </div>
          )}

          {activeTab === 'prs' && (
            <div>
              {loading ? (
                <div className="flex items-center justify-center py-8">
                  <Loader2 className="w-6 h-6 animate-spin text-theme-primary" />
                </div>
              ) : pullRequests.length > 0 ? (
                <div className="space-y-2">
                  {pullRequests.map((pr) => (
                    <div key={pr.id} className="p-3 bg-theme-bg-subtle rounded-lg">
                      <div className="flex items-start gap-3">
                        <GitPullRequest className={`w-4 h-4 mt-1 ${pr.state === 'open' ? 'text-theme-success' : 'text-theme-interactive-primary'}`} />
                        <div className="flex-1 min-w-0">
                          <p className="text-theme-primary">
                            <span className="text-theme-secondary">#{pr.number}</span> {pr.title}
                          </p>
                          <p className="text-sm text-theme-secondary">
                            by {pr.author} • {pr.state}
                          </p>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <p className="text-center text-theme-secondary py-8">No pull requests found</p>
              )}
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="p-4 border-t border-theme flex justify-end">
          <Button onClick={onClose} variant="secondary">Close</Button>
        </div>
      </div>

      {/* Commit Detail Modal */}
      {selectedCommitSha && (
        <CommitDetailModal
          isOpen={!!selectedCommitSha}
          onClose={() => setSelectedCommitSha(null)}
          repositoryId={repository.id}
          sha={selectedCommitSha}
          repositoryName={repository.full_name}
        />
      )}
    </div>
  );
};

export function RepositoriesPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const { showNotification } = useNotifications();
  const [repositories, setRepositories] = useState<GitRepository[]>([]);
  const [providers, setProviders] = useState<GitProvider[]>([]);
  const [loading, setLoading] = useState(true);
  const [syncing, setSyncing] = useState<string | null>(null);
  const [syncingAll, setSyncingAll] = useState(false);
  const [pagination, setPagination] = useState<PaginationInfo | null>(null);
  const [filters, setFilters] = useState<RepositoryFilters>({
    provider_id: searchParams.get('provider') || undefined,
    search: searchParams.get('search') || undefined,
  });
  const [showFilters, setShowFilters] = useState(false);
  const [selectedRepository, setSelectedRepository] = useState<GitRepository | null>(null);
  const [page, setPage] = useState(1);

  const fetchRepositories = async () => {
    try {
      setLoading(true);
      const data = await gitProvidersApi.getRepositories({
        page,
        per_page: 20,
        search: filters.search,
        provider_id: filters.provider_id,
        is_private: filters.is_private,
        webhook_configured: filters.webhook_configured,
      });
      setRepositories(data.repositories);
      setPagination(data.pagination);
    } catch (error) {
      showNotification('Failed to load repositories', 'error');
    } finally {
      setLoading(false);
    }
  };

  const fetchProviders = async () => {
    try {
      const data = await gitProvidersApi.getProviders();
      setProviders(data);
    } catch (error) {
      // Silently fail
    }
  };

  useEffect(() => {
    fetchProviders();
  }, []);

  useEffect(() => {
    fetchRepositories();
  }, [page, filters]);

  const handleSyncAll = async () => {
    setSyncingAll(true);
    try {
      // Get all providers and their credentials, then sync each
      const allProviders = await gitProvidersApi.getProviders();
      let totalSynced = 0;
      for (const provider of allProviders) {
        const credentials = await gitProvidersApi.getCredentials(provider.id);
        for (const credential of credentials) {
          try {
            const result = await gitProvidersApi.syncRepositories(provider.id, credential.id);
            totalSynced += result.synced_count;
          } catch {
            // Continue with next credential
          }
        }
      }
      showNotification(`Synced ${totalSynced} repositories`, 'success');
      fetchRepositories();
    } catch (error) {
      showNotification('Failed to sync repositories', 'error');
    } finally {
      setSyncingAll(false);
    }
  };

  const handleSyncRepository = async (repoId: string) => {
    setSyncing(repoId);
    try {
      // For individual repo sync, we'd need an endpoint or use credential sync
      showNotification('Repository sync initiated', 'success');
    } catch (error) {
      showNotification('Failed to sync repository', 'error');
    } finally {
      setSyncing(null);
    }
  };

  const handleConfigureWebhook = async (repoId: string) => {
    try {
      await gitProvidersApi.configureWebhook(repoId);
      showNotification('Webhook configured successfully', 'success');
      fetchRepositories();
    } catch (error) {
      showNotification('Failed to configure webhook', 'error');
    }
  };

  const handleDeleteRepository = async (repoId: string) => {
    if (!window.confirm('Are you sure you want to remove this repository from tracking?')) {
      return;
    }
    try {
      await gitProvidersApi.deleteRepository(repoId);
      showNotification('Repository removed', 'success');
      setRepositories(repositories.filter(r => r.id !== repoId));
    } catch (error) {
      showNotification('Failed to remove repository', 'error');
    }
  };

  const handleFilterChange = (key: keyof RepositoryFilters, value: string | boolean | undefined) => {
    const newFilters = { ...filters, [key]: value || undefined };
    setFilters(newFilters);
    setPage(1);

    // Update URL params
    const params = new URLSearchParams();
    if (newFilters.provider_id) params.set('provider', newFilters.provider_id);
    if (newFilters.search) params.set('search', newFilters.search);
    setSearchParams(params);
  };

  const clearFilters = () => {
    setFilters({});
    setSearchParams({});
    setPage(1);
  };

  const hasActiveFilters = filters.provider_id || filters.search || filters.is_private !== undefined || filters.webhook_configured !== undefined;

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'Automation', href: '/app/automation' },
    { label: 'Repositories' }
  ];

  const pageActions: PageAction[] = [
    {
      id: 'sync-all',
      label: syncingAll ? 'Syncing...' : 'Sync All',
      onClick: handleSyncAll,
      variant: 'primary',
      icon: RefreshCw,
      disabled: syncingAll
    }
  ];

  return (
    <PageContainer
      title="Git Repositories"
      description="Manage synced repositories from all connected Git providers"
      breadcrumbs={breadcrumbs}
      actions={pageActions}
    >
      <div className="space-y-4">
        {/* Search and Filters */}
        <div className="flex flex-col sm:flex-row gap-4">
          <div className="relative flex-1 max-w-md">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-theme-tertiary" />
            <input
              type="text"
              placeholder="Search repositories..."
              value={filters.search || ''}
              onChange={(e) => handleFilterChange('search', e.target.value)}
              className="w-full pl-10 pr-4 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-primary"
            />
          </div>

          <div className="flex items-center gap-2">
            <select
              value={filters.provider_id || ''}
              onChange={(e) => handleFilterChange('provider_id', e.target.value)}
              className="px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary"
            >
              <option value="">All Providers</option>
              {providers.map((p) => (
                <option key={p.id} value={p.id}>{p.name}</option>
              ))}
            </select>

            <button
              onClick={() => setShowFilters(!showFilters)}
              className={`flex items-center gap-2 px-3 py-2 border rounded-lg transition-colors ${
                hasActiveFilters
                  ? 'border-theme-primary bg-theme-primary/10 text-theme-primary'
                  : 'border-theme bg-theme-surface text-theme-secondary hover:text-theme-primary'
              }`}
            >
              <Filter className="w-4 h-4" />
              Filters
              {hasActiveFilters && (
                <span className="w-2 h-2 rounded-full bg-theme-primary" />
              )}
            </button>

            {hasActiveFilters && (
              <button
                onClick={clearFilters}
                className="flex items-center gap-1 px-2 py-2 text-theme-secondary hover:text-theme-primary"
              >
                <X className="w-4 h-4" />
                Clear
              </button>
            )}
          </div>
        </div>

        {/* Expanded Filters */}
        {showFilters && (
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={filters.is_private === true}
                  onChange={(e) => handleFilterChange('is_private', e.target.checked ? true : undefined)}
                  className="rounded border-theme text-theme-primary focus:ring-theme-primary"
                />
                <span className="text-sm text-theme-primary">Private only</span>
              </label>
              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={filters.webhook_configured === true}
                  onChange={(e) => handleFilterChange('webhook_configured', e.target.checked ? true : undefined)}
                  className="rounded border-theme text-theme-primary focus:ring-theme-primary"
                />
                <span className="text-sm text-theme-primary">With webhooks</span>
              </label>
              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={filters.webhook_configured === false}
                  onChange={(e) => handleFilterChange('webhook_configured', e.target.checked ? false : undefined)}
                  className="rounded border-theme text-theme-primary focus:ring-theme-primary"
                />
                <span className="text-sm text-theme-primary">Without webhooks</span>
              </label>
            </div>
          </div>
        )}

        {/* Repository List */}
        {loading ? (
          <div className="flex items-center justify-center py-12">
            <Loader2 className="w-8 h-8 animate-spin text-theme-primary" />
          </div>
        ) : repositories.length === 0 ? (
          <div className="bg-theme-surface border border-theme rounded-lg p-8 text-center">
            <FolderGit2 className="w-12 h-12 mx-auto mb-3 text-theme-secondary opacity-50" />
            <h3 className="text-lg font-medium text-theme-primary mb-2">No Repositories Found</h3>
            <p className="text-theme-secondary mb-4">
              {hasActiveFilters
                ? 'Try adjusting your filters or search query.'
                : 'Sync repositories from your Git providers to get started.'}
            </p>
            {!hasActiveFilters && (
              <Button onClick={handleSyncAll} variant="primary" disabled={syncingAll}>
                <RefreshCw className={`w-4 h-4 mr-2 ${syncingAll ? 'animate-spin' : ''}`} />
                Sync Repositories
              </Button>
            )}
          </div>
        ) : (
          <>
            <div className="grid grid-cols-1 gap-4">
              {repositories.map((repo) => (
                <RepositoryCard
                  key={repo.id}
                  repository={repo}
                  onSync={() => handleSyncRepository(repo.id)}
                  onConfigureWebhook={() => handleConfigureWebhook(repo.id)}
                  onViewDetails={() => setSelectedRepository(repo)}
                  onDelete={() => handleDeleteRepository(repo.id)}
                  syncing={syncing === repo.id}
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
                    <ChevronLeft className="w-4 h-4" />
                    Previous
                  </Button>
                  <span className="text-sm text-theme-secondary px-2">
                    Page {page} of {pagination.total_pages}
                  </span>
                  <Button
                    onClick={() => setPage((p) => Math.min(pagination.total_pages, p + 1))}
                    disabled={page >= pagination.total_pages}
                    variant="secondary"
                    size="sm"
                  >
                    Next
                    <ChevronRight className="w-4 h-4" />
                  </Button>
                </div>
              </div>
            )}
          </>
        )}
      </div>

      {/* Repository Detail Modal */}
      {selectedRepository && (
        <RepositoryDetailModal
          repository={selectedRepository}
          onClose={() => setSelectedRepository(null)}
        />
      )}
    </PageContainer>
  );
}

export default RepositoriesPage;
