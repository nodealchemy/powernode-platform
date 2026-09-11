import { renderHook, waitFor, act } from '@testing-library/react';
import { useDashboardStats } from '@/shared/hooks/useDashboardStats';

// M1 review F1 + F4. The hook's default is what a FAILED fetch leaves on
// screen, so it is the first thing that can lie: it read "healthy at 100"
// before M1. And a failed read must stay distinguishable from a server that
// answered "not_measured" — the first is "the dashboard cannot reach the
// platform", the second is "the platform cannot see the fleet". Different
// incidents; `monitoringError` is what tells them apart.

const mockGetDashboard = jest.fn();
const mockGetRepositories = jest.fn();

jest.mock('@/shared/services/ai/MonitoringApiService', () => ({
  monitoringApi: { getDashboard: (...args: unknown[]) => mockGetDashboard(...args) },
}));
jest.mock('@/features/devops/git/services/git/repositoriesApi', () => ({
  repositoriesApi: { getRepositories: (...args: unknown[]) => mockGetRepositories(...args) },
}));
jest.mock('@/shared/utils/logger', () => ({
  logger: { warn: jest.fn(), error: jest.fn(), info: jest.fn(), debug: jest.fn() },
}));

const answered = (status: string, uptime: number | null) => ({
  system_health: { status, uptime_percentage: uptime },
  overview: { active_agents: 2, total_executions_today: 12, total_cost_today: 1.5, avg_response_time: 230, success_rate: 91.5 },
  providers: [],
  agents: { total: 3, active: 2, paused: 1, errored: 0 },
  alerts: [],
});

describe('useDashboardStats', () => {
  beforeEach(() => {
    mockGetRepositories.mockResolvedValue({ pagination: { total_count: 4 } });
  });

  it('starts NOT MEASURED with no score before anything answers — never healthy at 100', () => {
    mockGetDashboard.mockReturnValue(new Promise(() => {}));
    mockGetRepositories.mockReturnValue(new Promise(() => {}));

    const { result } = renderHook(() => useDashboardStats());

    expect(result.current.loading).toBe(true);
    expect(result.current.stats.systemHealth).toEqual({ status: 'not_measured', score: null });
    expect(result.current.monitoringError).toBeNull();
  });

  it('a REJECTED monitoring fetch leaves not_measured with no score AND reports monitoringError with the reason', async () => {
    mockGetDashboard.mockRejectedValue(new Error('Network Error'));

    const { result } = renderHook(() => useDashboardStats());
    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(result.current.stats.systemHealth).toEqual({ status: 'not_measured', score: null });
    expect(result.current.monitoringError).toBe('Network Error');
    // Only one of the two fetches failed, so the combined error stays clear —
    // which is exactly why the monitoring failure needs its own flag.
    expect(result.current.error).toBeNull();
    expect(result.current.stats.repositories).toBe(4);
  });

  it('a server that ANSWERED not_measured is not a failure: monitoringError stays null', async () => {
    mockGetDashboard.mockResolvedValue(answered('not_measured', null));

    const { result } = renderHook(() => useDashboardStats());
    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(result.current.stats.systemHealth).toEqual({ status: 'not_measured', score: null });
    expect(result.current.monitoringError).toBeNull();
  });

  it('passes an answered verdict and score through unchanged', async () => {
    mockGetDashboard.mockResolvedValue(answered('degraded', 70));

    const { result } = renderHook(() => useDashboardStats());
    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(result.current.stats.systemHealth).toEqual({ status: 'degraded', score: 70 });
    expect(result.current.stats.overview.successRate).toBe(91.5);
    expect(result.current.monitoringError).toBeNull();
  });

  it('a refresh that succeeds clears a previous monitoringError', async () => {
    mockGetDashboard.mockRejectedValueOnce(new Error('Network Error'));
    mockGetDashboard.mockResolvedValue(answered('ok', 100));

    const { result } = renderHook(() => useDashboardStats());
    await waitFor(() => expect(result.current.monitoringError).toBe('Network Error'));

    await act(async () => { await result.current.refresh(); });

    expect(result.current.monitoringError).toBeNull();
    expect(result.current.stats.systemHealth).toEqual({ status: 'ok', score: 100 });
  });

  it('both fetches failing also sets the combined error', async () => {
    mockGetDashboard.mockRejectedValue(new Error('Network Error'));
    mockGetRepositories.mockRejectedValue(new Error('Network Error'));

    const { result } = renderHook(() => useDashboardStats());
    await waitFor(() => expect(result.current.loading).toBe(false));

    expect(result.current.error).toBe('Failed to load dashboard data');
    expect(result.current.monitoringError).toBe('Network Error');
  });
});
