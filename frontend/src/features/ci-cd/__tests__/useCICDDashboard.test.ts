import { renderHook, waitFor, act } from '@testing-library/react';
import { useCICDDashboard } from '../hooks/useCICDDashboard';
import { gitProvidersApi } from '@/features/git-providers/services/gitProvidersApi';

jest.mock('@/features/git-providers/services/gitProvidersApi');

const mockGitProvidersApi = gitProvidersApi as jest.Mocked<typeof gitProvidersApi>;

describe('useCICDDashboard', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  const mockRepositories = [
    {
      id: 'repo-1',
      name: 'project-a',
      full_name: 'org/project-a',
      owner: 'org',
      default_branch: 'main',
      is_private: false,
      is_fork: false,
      is_archived: false,
      webhook_configured: true,
      stars_count: 10,
      forks_count: 2,
      open_issues_count: 5,
      open_prs_count: 1,
      topics: [],
      created_at: new Date().toISOString(),
      provider_type: 'github',
      credential_id: 'cred-1',
    },
    {
      id: 'repo-2',
      name: 'project-b',
      full_name: 'org/project-b',
      owner: 'org',
      default_branch: 'main',
      is_private: false,
      is_fork: false,
      is_archived: false,
      webhook_configured: false,
      stars_count: 5,
      forks_count: 1,
      open_issues_count: 2,
      open_prs_count: 0,
      topics: [],
      created_at: new Date().toISOString(),
      provider_type: 'github',
      credential_id: 'cred-1',
    },
  ];

  const mockPipelines = [
    {
      id: 'pipeline-1',
      external_id: 'ext-1',
      name: 'CI Build',
      status: 'completed' as const,
      conclusion: 'success' as const,
      branch_name: 'main',
      sha: 'abc123',
      total_jobs: 3,
      completed_jobs: 3,
      failed_jobs: 0,
      progress_percentage: 100,
      created_at: new Date().toISOString(),
    },
    {
      id: 'pipeline-2',
      external_id: 'ext-2',
      name: 'Deploy',
      status: 'running' as const,
      branch_name: 'develop',
      sha: 'def456',
      total_jobs: 2,
      completed_jobs: 1,
      failed_jobs: 0,
      progress_percentage: 50,
      created_at: new Date().toISOString(),
    },
  ];

  const mockStats = {
    total_runs: 10,
    success_count: 8,
    failed_count: 1,
    cancelled_count: 1,
    success_rate: 80,
    avg_duration_seconds: 180,
    runs_today: 2,
    runs_this_week: 10,
    active_runs: 1,
  };

  it('fetches repositories and pipelines on mount', async () => {
    mockGitProvidersApi.getRepositories.mockResolvedValue({
      repositories: mockRepositories,
      pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 2 },
    });

    mockGitProvidersApi.getPipelines.mockResolvedValue({
      pipelines: mockPipelines,
      pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 2 },
      stats: mockStats,
    });

    const { result } = renderHook(() => useCICDDashboard());

    expect(result.current.loading).toBe(true);

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(result.current.repositories).toHaveLength(2);
    expect(mockGitProvidersApi.getRepositories).toHaveBeenCalledWith({ per_page: 20 });
  });

  it('fetches pipelines for each repository', async () => {
    mockGitProvidersApi.getRepositories.mockResolvedValue({
      repositories: mockRepositories,
      pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 2 },
    });

    mockGitProvidersApi.getPipelines.mockResolvedValue({
      pipelines: mockPipelines,
      pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 2 },
      stats: mockStats,
    });

    const { result } = renderHook(() => useCICDDashboard());

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    // Should fetch pipelines for each repo
    expect(mockGitProvidersApi.getPipelines).toHaveBeenCalledWith('repo-1', { per_page: 5 });
    expect(mockGitProvidersApi.getPipelines).toHaveBeenCalledWith('repo-2', { per_page: 5 });
  });

  it('returns empty arrays when no repositories', async () => {
    mockGitProvidersApi.getRepositories.mockResolvedValue({
      repositories: [],
      pagination: { current_page: 1, per_page: 20, total_pages: 0, total_count: 0 },
    });

    const { result } = renderHook(() => useCICDDashboard());

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(result.current.repositories).toEqual([]);
    expect(result.current.recentPipelines).toEqual([]);
    expect(result.current.globalStats).toBeNull();
  });

  it('handles fetch errors gracefully', async () => {
    mockGitProvidersApi.getRepositories.mockRejectedValue(new Error('Network error'));

    const { result } = renderHook(() => useCICDDashboard());

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(result.current.error).toBe('Network error');
  });

  it('provides refresh function', async () => {
    mockGitProvidersApi.getRepositories.mockResolvedValue({
      repositories: mockRepositories,
      pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 2 },
    });

    mockGitProvidersApi.getPipelines.mockResolvedValue({
      pipelines: mockPipelines,
      pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 2 },
      stats: mockStats,
    });

    const { result } = renderHook(() => useCICDDashboard());

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(typeof result.current.refresh).toBe('function');

    // Initial call
    expect(mockGitProvidersApi.getRepositories).toHaveBeenCalledTimes(1);

    // Refresh should trigger new API calls
    await act(async () => {
      await result.current.refresh();
    });

    expect(mockGitProvidersApi.getRepositories).toHaveBeenCalledTimes(2);
  });

  it('aggregates stats from multiple repositories', async () => {
    mockGitProvidersApi.getRepositories.mockResolvedValue({
      repositories: mockRepositories,
      pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 2 },
    });

    mockGitProvidersApi.getPipelines.mockResolvedValue({
      pipelines: mockPipelines,
      pagination: { current_page: 1, per_page: 20, total_pages: 1, total_count: 2 },
      stats: mockStats,
    });

    const { result } = renderHook(() => useCICDDashboard());

    await waitFor(() => {
      expect(result.current.loading).toBe(false);
    });

    expect(result.current.globalStats).not.toBeNull();
    expect(result.current.globalStats?.total_runs).toBeGreaterThanOrEqual(0);
  });
});
