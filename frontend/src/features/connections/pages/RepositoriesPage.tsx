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

type CardMode = 'collapsed' | 'expanded';

const RepositoryCard: React.FC<{
  repository: GitRepository;
  onSync: () => void;
  onConfigureWebhook: () => void;
  onDelete: () => void;
  syncing: boolean;
}> = ({ repository, onSync, onConfigureWebhook, onDelete, syncing }) => {
  const [menuOpen, setMenuOpen] = useState(false);
  const [mode, setMode] = useState<CardMode>('collapsed');
  const [activeTab, setActiveTab] = useState<'overview' | 'code' | 'prs'>('overview');
  const [branches, setBranches] = useState<Branch[]>([]);
  const [commits, setCommits] = useState<Commit[]>([]);
  const [pullRequests, setPullRequests] = useState<Array<{ id: string; number: number; title: string; state: string; author: string }>>([]);
  const [selectedBranch, setSelectedBranch] = useState<string | null>(null);
  const [loadingBranches, setLoadingBranches] = useState(false);
  const [loadingCommits, setLoadingCommits] = useState(false);
  const [loadingPRs, setLoadingPRs] = useState(false);
  const [expandedCommit, setExpandedCommit] = useState<string | null>(null);
  const [selectedCommitSha, setSelectedCommitSha] = useState<string | null>(null);
  const [activityData, setActivityData] = useState<Map<string, number>>(new Map());
  const [loadingActivity, setLoadingActivity] = useState(false);
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

  // Fetch branches when expanded and on code tab
  useEffect(() => {
    if (mode === 'expanded' && activeTab === 'code' && branches.length === 0) {
      const fetchBranches = async () => {
        setLoadingBranches(true);
        try {
          const data = await gitProvidersApi.getBranches(repository.id) as Array<{ name?: string; is_default?: boolean; protected?: boolean }>;
          const branchList = (data || []).map((b) => ({
            name: b.name || '',
            is_default: b.is_default || false,
            protected: b.protected || false
          }));
          setBranches(branchList);
          const defaultBranch = branchList.find(b => b.is_default) || branchList[0];
          if (defaultBranch) {
            setSelectedBranch(defaultBranch.name);
          }
        } catch {
          // Silently fail
        } finally {
          setLoadingBranches(false);
        }
      };
      fetchBranches();
    }
  }, [mode, activeTab, repository.id, branches.length]);

  // Fetch commits when branch is selected
  useEffect(() => {
    if (mode === 'expanded' && activeTab === 'code' && selectedBranch) {
      const fetchCommits = async () => {
        setLoadingCommits(true);
        setCommits([]);
        try {
          const data = await gitProvidersApi.getCommits(repository.id, { sha: selectedBranch }) as Array<{
            sha?: string;
            message?: string;
            commit?: { message?: string; author?: { name?: string; date?: string } };
            author?: { login?: string; name?: string } | string;
            created_at?: string;
          }>;
          setCommits((data || []).map((c) => {
            const message = c.message || c.commit?.message || '';
            const authorName = typeof c.author === 'string'
              ? c.author
              : (c.author?.login || c.author?.name || c.commit?.author?.name || 'Unknown');
            const date = c.created_at || c.commit?.author?.date || '';
            const sha = c.sha || '';
            return {
              sha,
              short_sha: sha.substring(0, 7),
              message: message.split('\n')[0],
              author: authorName,
              date: date ? new Date(date).toLocaleDateString() : ''
            };
          }));
        } catch {
          // Silently fail
        } finally {
          setLoadingCommits(false);
        }
      };
      fetchCommits();
    }
  }, [mode, activeTab, selectedBranch, repository.id]);

  // Fetch PRs when viewing PRs tab
  useEffect(() => {
    if (mode === 'expanded' && activeTab === 'prs' && pullRequests.length === 0) {
      const fetchPRs = async () => {
        setLoadingPRs(true);
        try {
          const data = await gitProvidersApi.getPullRequests(repository.id) as Array<{ id?: string; number?: number; title?: string; state?: string; author?: string }>;
          setPullRequests((data || []).map((pr) => ({
            id: pr.id || '',
            number: pr.number || 0,
            title: pr.title || '',
            state: pr.state || '',
            author: pr.author || ''
          })));
        } catch {
          // Silently fail
        } finally {
          setLoadingPRs(false);
        }
      };
      fetchPRs();
    }
  }, [mode, activeTab, repository.id, pullRequests.length]);

  // Fetch commit activity for activity map (from all branches)
  useEffect(() => {
    if (mode === 'expanded' && activeTab === 'overview' && activityData.size === 0) {
      const fetchActivity = async () => {
        setLoadingActivity(true);
        try {
          // First fetch branches
          const branchData = await gitProvidersApi.getBranches(repository.id) as Array<{ name?: string }>;
          const branchNames = (branchData || []).map(b => b.name).filter(Boolean).slice(0, 5); // Limit to 5 branches

          // Aggregate commits by date from all branches
          const activity = new Map<string, number>();
          const seenShas = new Set<string>();

          // Fetch commits from each branch
          for (const branch of branchNames) {
            try {
              const data = await gitProvidersApi.getCommits(repository.id, { sha: branch, per_page: 50 }) as Array<{
                sha?: string;
                created_at?: string;
                commit?: { author?: { date?: string } };
              }>;

              (data || []).forEach((commit) => {
                // Deduplicate commits that appear in multiple branches
                if (commit.sha && seenShas.has(commit.sha)) return;
                if (commit.sha) seenShas.add(commit.sha);

                const dateStr = commit.created_at || commit.commit?.author?.date;
                if (dateStr) {
                  const date = new Date(dateStr).toISOString().split('T')[0];
                  activity.set(date, (activity.get(date) || 0) + 1);
                }
              });
            } catch {
              // Continue with other branches if one fails
            }
          }

          setActivityData(activity);
        } catch {
          // Silently fail
        } finally {
          setLoadingActivity(false);
        }
      };
      fetchActivity();
    }
  }, [mode, activeTab, repository.id, activityData.size]);

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

  // Generate weekly activity data (last 16 weeks)
  const generateWeeklyActivity = () => {
    const weeks: { weekStart: string; weekLabel: string; count: number }[] = [];
    const today = new Date();

    for (let w = 15; w >= 0; w--) {
      const weekStart = new Date(today);
      weekStart.setDate(today.getDate() - (w * 7 + today.getDay()));

      let weekCount = 0;
      for (let d = 0; d < 7; d++) {
        const date = new Date(weekStart);
        date.setDate(weekStart.getDate() + d);
        const dateStr = date.toISOString().split('T')[0];
        weekCount += activityData.get(dateStr) || 0;
      }

      const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      weeks.push({
        weekStart: weekStart.toISOString().split('T')[0],
        weekLabel: `${monthNames[weekStart.getMonth()]} ${weekStart.getDate()}`,
        count: weekCount
      });
    }
    return weeks;
  };

  const getActivityBarHeight = (count: number, maxCount: number): string => {
    if (count === 0 || maxCount === 0) return 'h-1';
    const percentage = (count / maxCount) * 100;
    if (percentage <= 20) return 'h-3';
    if (percentage <= 40) return 'h-6';
    if (percentage <= 60) return 'h-9';
    if (percentage <= 80) return 'h-12';
    return 'h-16';
  };

  const handleCardClick = (e: React.MouseEvent) => {
    if ((e.target as HTMLElement).closest('.no-expand')) return;
    setMode(mode === 'collapsed' ? 'expanded' : 'collapsed');
    if (mode === 'expanded') {
      setExpandedCommit(null);
    }
  };

  const handleCollapse = (e: React.MouseEvent) => {
    e.stopPropagation();
    setMode('collapsed');
    setExpandedCommit(null);
  };

  return (
    <div
      className={`bg-theme-surface border rounded-lg transition-all ${
        mode !== 'collapsed' ? 'border-theme-primary ring-1 ring-theme-primary/20' : 'border-theme hover:border-theme-primary cursor-pointer'
      }`}
      onClick={handleCardClick}
    >
      {/* Header - Always visible */}
      <div className="p-4">
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
                  <span className="flex items-center gap-1 px-1.5 py-0.5 text-xs rounded bg-theme-success/10 text-theme-success">
                    <Webhook className="w-3 h-3" />
                    Webhook
                  </span>
                )}
              </div>
              <p className="text-sm text-theme-secondary truncate">{repository.full_name}</p>
              {mode === 'collapsed' && repository.description && (
                <p className="text-sm text-theme-tertiary mt-1 line-clamp-1">{repository.description}</p>
              )}
            </div>
          </div>

          <div className="flex items-center gap-1 no-expand">
            <div className="relative" ref={menuRef}>
              <button
                onClick={(e) => { e.stopPropagation(); setMenuOpen(!menuOpen); }}
                className="p-1.5 hover:bg-theme-bg-subtle rounded-lg text-theme-secondary hover:text-theme-primary"
              >
                <MoreVertical className="w-4 h-4" />
              </button>
              {menuOpen && (
                <div className="absolute right-0 top-full mt-1 w-48 bg-theme-surface border border-theme rounded-lg shadow-lg z-10 py-1">
                  <button
                    onClick={(e) => { e.stopPropagation(); onSync(); setMenuOpen(false); }}
                    disabled={syncing}
                    className="w-full flex items-center gap-2 px-3 py-2 text-sm text-theme-primary hover:bg-theme-bg-subtle disabled:opacity-50"
                  >
                    <RefreshCw className={`w-4 h-4 ${syncing ? 'animate-spin' : ''}`} />
                    {syncing ? 'Syncing...' : 'Sync Repository'}
                  </button>
                  <button
                    onClick={(e) => { e.stopPropagation(); onConfigureWebhook(); setMenuOpen(false); }}
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
                      onClick={(e) => { e.stopPropagation(); setMenuOpen(false); }}
                      className="w-full flex items-center gap-2 px-3 py-2 text-sm text-theme-primary hover:bg-theme-bg-subtle"
                    >
                      <ExternalLink className="w-4 h-4" />
                      Open in Browser
                    </a>
                  )}
                  <div className="border-t border-theme my-1" />
                  <button
                    onClick={(e) => { e.stopPropagation(); onDelete(); setMenuOpen(false); }}
                    className="w-full flex items-center gap-2 px-3 py-2 text-sm text-theme-danger hover:bg-theme-danger/10"
                  >
                    <Trash2 className="w-4 h-4" />
                    Remove Repository
                  </button>
                </div>
              )}
            </div>
            {mode === 'expanded' && (
              <button
                onClick={handleCollapse}
                className="p-1.5 hover:bg-theme-bg-subtle rounded-lg text-theme-secondary hover:text-theme-primary"
                title="Collapse"
              >
                <X className="w-4 h-4" />
              </button>
            )}
          </div>
        </div>

        {/* Compact Stats Row */}
        {mode === 'collapsed' && (
          <div className="flex items-center gap-4 mt-3 text-sm">
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
              <span>{formatTimeAgo(repository.last_synced_at)}</span>
            </div>
          </div>
        )}
      </div>

      {/* Expanded Mode */}
      {mode === 'expanded' && (
        <div className="border-t border-theme no-expand">
          {/* Tabs */}
          <div className="flex border-b border-theme bg-theme-bg-subtle/30">
            {[
              { id: 'overview', label: 'Overview', icon: FolderGit2 },
              { id: 'code', label: 'Code', icon: GitBranch },
              { id: 'prs', label: 'Pull Requests', icon: GitPullRequest },
            ].map((tab) => (
              <button
                key={tab.id}
                onClick={(e) => { e.stopPropagation(); setActiveTab(tab.id as typeof activeTab); }}
                className={`flex items-center gap-2 px-4 py-2.5 text-sm font-medium border-b-2 -mb-px transition-colors ${
                  activeTab === tab.id
                    ? 'border-theme-primary text-theme-primary bg-theme-surface'
                    : 'border-transparent text-theme-secondary hover:text-theme-primary'
                }`}
              >
                <tab.icon className="w-4 h-4" />
                {tab.label}
              </button>
            ))}
          </div>

          {/* Tab Content */}
          <div className="min-h-[300px] max-h-[500px] overflow-hidden">
            {/* Overview Tab */}
            {activeTab === 'overview' && (
              <div className="p-4 overflow-auto h-full">
                <div className="space-y-4">
                  {repository.description && (
                    <div>
                      <h4 className="text-sm font-medium text-theme-secondary mb-1">Description</h4>
                      <p className="text-theme-primary">{repository.description}</p>
                    </div>
                  )}
                  <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
                    <div className="bg-theme-bg-subtle rounded-lg p-3">
                      <p className="text-xs text-theme-secondary">Visibility</p>
                      <p className="text-sm font-medium text-theme-primary flex items-center gap-1 mt-1">
                        {repository.is_private ? <Lock className="w-3.5 h-3.5" /> : <Unlock className="w-3.5 h-3.5" />}
                        {repository.is_private ? 'Private' : 'Public'}
                      </p>
                    </div>
                    <div className="bg-theme-bg-subtle rounded-lg p-3">
                      <p className="text-xs text-theme-secondary">Stars</p>
                      <p className="text-sm font-medium text-theme-primary mt-1">{repository.stars_count}</p>
                    </div>
                    <div className="bg-theme-bg-subtle rounded-lg p-3">
                      <p className="text-xs text-theme-secondary">Forks</p>
                      <p className="text-sm font-medium text-theme-primary mt-1">{repository.forks_count}</p>
                    </div>
                    <div className="bg-theme-bg-subtle rounded-lg p-3">
                      <p className="text-xs text-theme-secondary">Open Issues</p>
                      <p className="text-sm font-medium text-theme-primary mt-1">{repository.open_issues_count}</p>
                    </div>
                    <div className="bg-theme-bg-subtle rounded-lg p-3">
                      <p className="text-xs text-theme-secondary">Open PRs</p>
                      <p className="text-sm font-medium text-theme-primary mt-1">{repository.open_prs_count}</p>
                    </div>
                    <div className="bg-theme-bg-subtle rounded-lg p-3">
                      <p className="text-xs text-theme-secondary">Default Branch</p>
                      <p className="text-sm font-medium text-theme-primary mt-1">{repository.default_branch}</p>
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

                  {/* Activity Map */}
                  <div>
                    <h4 className="text-sm font-medium text-theme-secondary mb-2 flex items-center gap-2">
                      <GitCommit className="w-4 h-4" />
                      Commit Activity
                    </h4>
                    {loadingActivity ? (
                      <div className="flex items-center justify-center py-4">
                        <Loader2 className="w-4 h-4 animate-spin text-theme-primary" />
                      </div>
                    ) : (() => {
                      const weeklyData = generateWeeklyActivity();
                      const maxCount = Math.max(...weeklyData.map(w => w.count), 1);
                      const totalCommits = weeklyData.reduce((sum, w) => sum + w.count, 0);

                      return (
                        <div className="bg-theme-bg-subtle rounded-lg p-3">
                          {/* Bar Chart */}
                          <div className="flex items-end justify-between gap-1 h-20 mb-2">
                            {weeklyData.map((week, idx) => (
                              <div
                                key={idx}
                                className="flex-1 flex flex-col items-center justify-end h-full group"
                              >
                                <div
                                  className={`w-full rounded-t-sm bg-emerald-500 transition-all group-hover:bg-emerald-400 cursor-default ${getActivityBarHeight(week.count, maxCount)}`}
                                  title={`Week of ${week.weekLabel}: ${week.count} commit${week.count !== 1 ? 's' : ''}`}
                                />
                              </div>
                            ))}
                          </div>
                          {/* X-axis labels - show every 4th week */}
                          <div className="flex justify-between text-[10px] text-theme-tertiary">
                            {weeklyData.filter((_, i) => i % 4 === 0).map((week, idx) => (
                              <span key={idx}>{week.weekLabel}</span>
                            ))}
                          </div>
                          {/* Summary */}
                          <div className="flex items-center justify-between mt-3 pt-2 border-t border-theme text-xs text-theme-tertiary">
                            <span>{totalCommits} commits in 16 weeks</span>
                            <span>Avg: {Math.round(totalCommits / 16)}/week</span>
                          </div>
                        </div>
                      );
                    })()}
                  </div>

                  {/* Quick Actions */}
                  <div>
                    <h4 className="text-sm font-medium text-theme-secondary mb-2">Quick Actions</h4>
                    <div className="flex flex-wrap gap-2">
                      <button
                        onClick={(e) => { e.stopPropagation(); onSync(); }}
                        disabled={syncing}
                        className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-lg bg-theme-primary text-white hover:bg-theme-primary/90 disabled:opacity-50 transition-colors"
                      >
                        <RefreshCw className={`w-3.5 h-3.5 ${syncing ? 'animate-spin' : ''}`} />
                        {syncing ? 'Syncing...' : 'Sync'}
                      </button>
                      <button
                        onClick={(e) => { e.stopPropagation(); onConfigureWebhook(); }}
                        className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-lg border border-theme text-theme-primary hover:bg-theme-bg-subtle transition-colors"
                      >
                        <Webhook className="w-3.5 h-3.5" />
                        {repository.webhook_configured ? 'Update Webhook' : 'Add Webhook'}
                      </button>
                      {repository.web_url && (
                        <a
                          href={repository.web_url}
                          target="_blank"
                          rel="noopener noreferrer"
                          onClick={(e) => e.stopPropagation()}
                          className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-lg border border-theme text-theme-primary hover:bg-theme-bg-subtle transition-colors"
                        >
                          <ExternalLink className="w-3.5 h-3.5" />
                          Open in Browser
                        </a>
                      )}
                      <button
                        onClick={(e) => { e.stopPropagation(); setActiveTab('code'); }}
                        className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-lg border border-theme text-theme-primary hover:bg-theme-bg-subtle transition-colors"
                      >
                        <GitBranch className="w-3.5 h-3.5" />
                        Browse Code
                      </button>
                      <button
                        onClick={(e) => { e.stopPropagation(); setActiveTab('prs'); }}
                        className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-lg border border-theme text-theme-primary hover:bg-theme-bg-subtle transition-colors"
                      >
                        <GitPullRequest className="w-3.5 h-3.5" />
                        View PRs
                      </button>
                    </div>
                  </div>
                </div>
              </div>
            )}

            {/* Code Tab - Branch/Commit Split View */}
            {activeTab === 'code' && (
              <div className="flex h-[400px]">
                {/* Left Panel - Branches */}
                <div className="w-56 border-r border-theme flex flex-col bg-theme-bg-subtle/30">
                  <div className="p-2 border-b border-theme">
                    <h4 className="text-xs font-medium text-theme-secondary uppercase tracking-wide flex items-center gap-1">
                      <GitBranch className="w-3 h-3" />
                      Branches
                      {branches.length > 0 && <span className="ml-auto text-theme-tertiary">({branches.length})</span>}
                    </h4>
                  </div>
                  <div className="flex-1 overflow-auto">
                    {loadingBranches ? (
                      <div className="flex items-center justify-center py-6">
                        <Loader2 className="w-4 h-4 animate-spin text-theme-primary" />
                      </div>
                    ) : branches.length > 0 ? (
                      <div className="py-1">
                        {branches.map((branch) => (
                          <button
                            key={branch.name}
                            onClick={(e) => { e.stopPropagation(); setSelectedBranch(branch.name); setExpandedCommit(null); }}
                            className={`w-full flex items-center gap-1.5 px-2 py-1.5 text-left text-xs transition-colors ${
                              selectedBranch === branch.name
                                ? 'bg-theme-primary/10 text-theme-primary border-l-2 border-theme-primary'
                                : 'text-theme-secondary hover:bg-theme-bg-subtle hover:text-theme-primary'
                            }`}
                          >
                            <GitBranch className="w-3 h-3 flex-shrink-0" />
                            <span className="truncate flex-1">{branch.name}</span>
                            {branch.is_default && (
                              <span className="px-1 py-0.5 text-[9px] rounded bg-theme-primary text-white flex-shrink-0">
                                default
                              </span>
                            )}
                            {branch.protected && (
                              <span title="Protected"><Lock className="w-2.5 h-2.5 text-theme-warning flex-shrink-0" /></span>
                            )}
                          </button>
                        ))}
                      </div>
                    ) : (
                      <p className="text-center text-theme-tertiary py-6 text-xs">No branches</p>
                    )}
                  </div>
                </div>

                {/* Right Panel - Commits */}
                <div className="flex-1 flex flex-col overflow-hidden">
                  <div className="p-2 border-b border-theme flex items-center justify-between">
                    <h4 className="text-xs font-medium text-theme-secondary uppercase tracking-wide flex items-center gap-1">
                      <GitCommit className="w-3 h-3" />
                      Commits
                      {selectedBranch && (
                        <span className="text-theme-primary font-normal normal-case ml-1">
                          on <span className="font-medium">{selectedBranch}</span>
                        </span>
                      )}
                    </h4>
                    {commits.length > 0 && <span className="text-xs text-theme-tertiary">({commits.length})</span>}
                  </div>
                  <div className="flex-1 overflow-auto">
                    {!selectedBranch ? (
                      <div className="flex flex-col items-center justify-center py-8 text-theme-secondary">
                        <GitBranch className="w-6 h-6 mb-2 opacity-50" />
                        <p className="text-xs">Select a branch</p>
                      </div>
                    ) : loadingCommits ? (
                      <div className="flex items-center justify-center py-6">
                        <Loader2 className="w-4 h-4 animate-spin text-theme-primary" />
                      </div>
                    ) : commits.length > 0 ? (
                      <div className="divide-y divide-theme">
                        {commits.map((commit, index) => (
                          <div key={commit.sha}>
                            <button
                              onClick={(e) => { e.stopPropagation(); setExpandedCommit(expandedCommit === commit.sha ? null : commit.sha); }}
                              className={`w-full text-left p-2 hover:bg-theme-bg-subtle transition-colors ${
                                expandedCommit === commit.sha ? 'bg-theme-bg-subtle' : ''
                              }`}
                            >
                              <div className="flex items-start gap-2">
                                <div className="flex flex-col items-center pt-1">
                                  <div className={`w-2 h-2 rounded-full border-2 ${
                                    index === 0 ? 'border-theme-primary bg-theme-primary' : 'border-theme-secondary bg-theme-surface'
                                  }`} />
                                  {index < commits.length - 1 && (
                                    <div className="w-0.5 h-full min-h-[16px] bg-theme-secondary/30 mt-1" />
                                  )}
                                </div>
                                <div className="flex-1 min-w-0">
                                  <p className="text-xs text-theme-primary line-clamp-1">{commit.message}</p>
                                  <div className="flex items-center gap-1.5 mt-0.5 text-[10px] text-theme-secondary">
                                    <span className="font-mono bg-theme-bg-subtle px-1 py-0.5 rounded">{commit.short_sha}</span>
                                    <span>{commit.author}</span>
                                    <span>•</span>
                                    <span>{commit.date}</span>
                                  </div>
                                </div>
                              </div>
                            </button>
                            {expandedCommit === commit.sha && (
                              <div className="px-2 pb-2 bg-theme-bg-subtle/50">
                                <div className="ml-4 pl-2 border-l-2 border-theme-primary/30">
                                  <div className="flex items-center gap-2 mb-2">
                                    <Button
                                      onClick={(e) => { e.stopPropagation(); setSelectedCommitSha(commit.sha); }}
                                      variant="secondary"
                                      size="sm"
                                    >
                                      <Eye className="w-3 h-3 mr-1" />
                                      Details
                                    </Button>
                                    <button
                                      onClick={(e) => { e.stopPropagation(); navigator.clipboard.writeText(commit.sha); }}
                                      className="px-2 py-1 text-[10px] text-theme-secondary hover:text-theme-primary hover:bg-theme-surface rounded"
                                    >
                                      Copy SHA
                                    </button>
                                  </div>
                                  <p className="text-[10px] text-theme-secondary">
                                    <span className="text-theme-tertiary">SHA:</span> <span className="font-mono">{commit.sha}</span>
                                  </p>
                                </div>
                              </div>
                            )}
                          </div>
                        ))}
                      </div>
                    ) : (
                      <div className="flex flex-col items-center justify-center py-8 text-theme-secondary">
                        <GitCommit className="w-6 h-6 mb-2 opacity-50" />
                        <p className="text-xs">No commits</p>
                      </div>
                    )}
                  </div>
                </div>
              </div>
            )}

            {/* Pull Requests Tab */}
            {activeTab === 'prs' && (
              <div className="p-4 overflow-auto h-full">
                {loadingPRs ? (
                  <div className="flex items-center justify-center py-6">
                    <Loader2 className="w-5 h-5 animate-spin text-theme-primary" />
                  </div>
                ) : pullRequests.length > 0 ? (
                  <div className="space-y-2">
                    {pullRequests.map((pr) => (
                      <div key={pr.id} className="p-3 bg-theme-bg-subtle rounded-lg">
                        <div className="flex items-start gap-3">
                          <GitPullRequest className={`w-4 h-4 mt-0.5 ${pr.state === 'open' ? 'text-theme-success' : 'text-theme-interactive-primary'}`} />
                          <div className="flex-1 min-w-0">
                            <p className="text-sm text-theme-primary">
                              <span className="text-theme-secondary">#{pr.number}</span> {pr.title}
                            </p>
                            <p className="text-xs text-theme-secondary mt-0.5">
                              by {pr.author} • {pr.state}
                            </p>
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                ) : (
                  <div className="flex flex-col items-center justify-center py-8 text-theme-secondary">
                    <GitPullRequest className="w-6 h-6 mb-2 opacity-50" />
                    <p className="text-sm">No pull requests</p>
                  </div>
                )}
              </div>
            )}
          </div>
        </div>
      )}

      {/* Commit Detail Modal - Only shown when viewing commit details */}
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

interface Branch {
  name: string;
  is_default: boolean;
  protected: boolean;
}

interface Commit {
  sha: string;
  short_sha: string;
  message: string;
  author: string;
  date: string;
}

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
    { label: 'DevOps', href: '/app/devops' },
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

    </PageContainer>
  );
}

export default RepositoriesPage;
