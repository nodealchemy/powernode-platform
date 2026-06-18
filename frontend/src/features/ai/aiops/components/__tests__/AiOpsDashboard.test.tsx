import { render, screen, fireEvent } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import type { ReactNode } from 'react';
import { AiOpsContent } from '../AiOpsDashboard';
import { OverviewSection } from '../sections/OverviewSection';
import { ProvidersSection } from '../sections/ProvidersSection';
import { AgentsSection } from '../sections/AgentsSection';
import { CostSection } from '../sections/CostSection';
import { ReliabilitySection } from '../sections/ReliabilitySection';
import { TrendsSection } from '../sections/TrendsSection';
import type { AiOpsDashboard as AiOpsDashboardData } from '@/shared/services/ai/AiOpsApiService';
import {
  useAiOpsDashboard,
  useAiOpsRealTime,
  useAiOpsTrends,
  useAiOpsRecentErrors,
} from '../../api/aiopsApi';

// ---- Mocks ------------------------------------------------------------------

jest.mock('recharts', () => {
  const MockChart = ({ children, ...p }: { children?: ReactNode; [key: string]: unknown }) => <div data-testid={(p['data-testid'] as string) || 'chart'}>{children}</div>;
  return {
    ResponsiveContainer: ({ children }: { children?: ReactNode }) => <div data-testid="responsive-container">{children}</div>,
    AreaChart: MockChart, Area: MockChart, LineChart: MockChart, Line: MockChart,
    BarChart: MockChart, Bar: MockChart, PieChart: MockChart, Pie: MockChart, Cell: MockChart,
    XAxis: MockChart, YAxis: MockChart, CartesianGrid: MockChart, Tooltip: MockChart, Legend: MockChart,
  };
});

jest.mock('../../api/aiopsApi', () => ({
  AIOPS_KEYS: { all: ['aiops'] },
  useAiOpsDashboard: jest.fn(),
  useAiOpsRealTime: jest.fn(),
  useAiOpsTrends: jest.fn(),
  useAiOpsRecentErrors: jest.fn(),
}));

jest.mock('@/shared/components/entity', () => ({
  EntityLink: ({ label, id }: { label?: string; id?: string }) => <span>{label ?? id}</span>,
}));

jest.mock('@/shared/hooks/usePageWebSocket', () => ({ usePageWebSocket: jest.fn() }));

const mockAddNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: mockAddNotification, showNotification: jest.fn() }),
}));

// ---- Fixtures ---------------------------------------------------------------

const mockDashboard: AiOpsDashboardData = {
  health: {
    overall_score: 92,
    status: 'healthy',
    uptime_percentage: 99.9,
    last_incident: null,
    components: {
      providers: { score: 95, status: 'healthy', issues: [] },
      agents: { score: 88, status: 'degraded', issues: ['agent-x slow'] },
      infrastructure: { score: 93, status: 'healthy', issues: [] },
    },
  },
  overview: {
    time_range_seconds: 3600,
    executions: { total: 1234, successful: 1200, failed: 34, success_rate: 97.2 },
    performance: { avg_execution_duration_ms: 4200, throughput_per_minute: 20 },
    costs: { total_execution_cost: 12.34, total_tokens: 555000 },
    latency_aggregate: { avg_ms: 100, p95_ms: 300, p99_ms: 500, max_ms: 900, sample_provider_count: 3 },
  },
  providers: [
    {
      provider_id: 'p1', provider_name: 'OpenAI', provider_type: 'openai', is_active: true, health_status: 'healthy',
      metrics: { request_count: 100, success_count: 98, failure_count: 2, success_rate: 98, avg_latency_ms: 120, p95_latency_ms: 300, total_tokens: 50000, total_cost_usd: 5.5 },
      circuit_breaker: { state: 'closed', consecutive_failures: 0 },
      error_breakdown: {},
    },
  ],
  agents: [
    {
      agent_id: 'a1', agent_name: 'Researcher', agent_type: 'worker', status: 'active', provider_name: 'OpenAI',
      metrics: { total_executions: 50, successful: 48, failed: 2, success_rate: 96, avg_duration_ms: 3000, total_tokens: 20000, total_cost: 2.0 },
      last_execution_at: '2026-06-18T00:00:00Z',
    },
  ],
  cost_analysis: {
    time_range_seconds: 3600,
    totals: { agent_cost: 8.0, total_cost: 12.34 },
    by_category: {},
    by_provider: [{ provider_id: 'p1', provider_name: 'OpenAI', cost_usd: 5.5 }],
    hourly_trend: [
      { hour: '2026-06-18T00:00:00Z', cost_usd: 1.2 },
      { hour: '2026-06-18T01:00:00Z', cost_usd: 2.3 },
    ],
    optimization_opportunities: {},
  },
  alerts: [
    { type: 'high_error_rate', severity: 'critical', provider_id: 'p1', provider_name: 'OpenAI', message: 'Error rate exceeded threshold', detected_at: '2026-06-18T01:00:00Z' },
  ],
  circuit_breakers: [
    { provider_id: 'p1', provider_name: 'OpenAI', state: 'open', consecutive_failures: 5, last_failure_at: '2026-06-18T01:00:00Z', last_success_at: '2026-06-18T00:00:00Z' },
  ],
  real_time: {
    timestamp: '2026-06-18T01:00:00Z', current_requests_per_second: 2.5, current_avg_latency_ms: 130,
    current_error_rate: 0.02, active_connections: 4, queue_depth: 1,
  },
  generated_at: '2026-06-18T01:00:00Z',
};

const mockTrends = {
  time_range_seconds: 86400, bucket: 'hour', bucket_count: 2,
  latency: [{ bucket: '2026-06-18T00:00:00Z', avg_ms: 100, p95_ms: 200, p99_ms: 300 }],
  error_rate: [{ bucket: '2026-06-18T00:00:00Z', error_rate: 0.01, request_count: 100 }],
  throughput: [{ bucket: '2026-06-18T00:00:00Z', requests: 100, requests_per_minute: 5 }],
  cost: [{ bucket: '2026-06-18T00:00:00Z', cost_usd: 1.5 }],
};

// ---- Helpers ----------------------------------------------------------------

interface SetupOptions {
  dashboardState?: Partial<{ data: unknown; isLoading: boolean; isError: boolean; refetch: jest.Mock }>;
  trends?: unknown;
  recentErrors?: unknown;
}

const setupHooks = (opts: SetupOptions = {}) => {
  const refetch = opts.dashboardState?.refetch ?? jest.fn();
  (useAiOpsDashboard as jest.Mock).mockReturnValue({
    data: mockDashboard,
    isLoading: false,
    isError: false,
    refetch,
    ...opts.dashboardState,
  });
  (useAiOpsRealTime as jest.Mock).mockReturnValue({ data: mockDashboard.real_time, refetch: jest.fn() });
  (useAiOpsTrends as jest.Mock).mockReturnValue({ data: opts.trends });
  (useAiOpsRecentErrors as jest.Mock).mockReturnValue({ data: opts.recentErrors });
  return { refetch };
};

const renderWithClient = (ui: React.ReactElement) => {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(<QueryClientProvider client={client}>{ui}</QueryClientProvider>);
};

// ---- Tests ------------------------------------------------------------------

describe('OverviewSection', () => {
  it('renders a loading state while the dashboard query is loading', () => {
    setupHooks({ dashboardState: { data: undefined, isLoading: true } });
    renderWithClient(<OverviewSection />);
    expect(screen.getByText(/Loading/i)).toBeInTheDocument();
  });

  it('renders an error state with a working retry button', () => {
    const refetch = jest.fn();
    setupHooks({ dashboardState: { data: undefined, isLoading: false, isError: true, refetch } });
    renderWithClient(<OverviewSection />);
    expect(screen.getByText('Failed to load this section.')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: /retry/i }));
    expect(refetch).toHaveBeenCalledTimes(1);
  });

  it('renders MetricCards, the health panel, and the active-provider-alerts callout', () => {
    setupHooks();
    renderWithClient(<OverviewSection />);
    expect(screen.getByText('Total Executions')).toBeInTheDocument();
    expect(screen.getByText('1,234')).toBeInTheDocument();
    expect(screen.getByText('Success Rate')).toBeInTheDocument();
    expect(screen.getByText('97.2%')).toBeInTheDocument();
    expect(screen.getByText('System Health')).toBeInTheDocument();
    expect(screen.getByText(/agent-x slow/)).toBeInTheDocument();
    // compact provider-alert callout
    expect(screen.getByText('Active Provider Alerts')).toBeInTheDocument();
    expect(screen.getByText('Error rate exceeded threshold')).toBeInTheDocument();
  });

  it('shows an empty callout when there are no provider alerts', () => {
    setupHooks({ dashboardState: { data: { ...mockDashboard, alerts: [] } } });
    renderWithClient(<OverviewSection />);
    expect(screen.getByText(/No active provider alerts/i)).toBeInTheDocument();
  });

  it('fetches the dashboard with the default 1h range', () => {
    setupHooks();
    renderWithClient(<OverviewSection />);
    expect(useAiOpsDashboard).toHaveBeenCalledWith('1h');
  });
});

describe('ProvidersSection', () => {
  it('renders provider rows', () => {
    setupHooks();
    renderWithClient(<ProvidersSection />);
    expect(screen.getByText('OpenAI')).toBeInTheDocument();
    expect(screen.getByText('98.0%')).toBeInTheDocument();
  });

  it('shows an empty state when there are no providers', () => {
    setupHooks({ dashboardState: { data: { ...mockDashboard, providers: [] } } });
    renderWithClient(<ProvidersSection />);
    expect(screen.getByText('No provider activity')).toBeInTheDocument();
  });
});

describe('AgentsSection', () => {
  it('renders agent rows', () => {
    setupHooks();
    renderWithClient(<AgentsSection />);
    expect(screen.getByText('Researcher')).toBeInTheDocument();
  });
});

describe('CostSection', () => {
  it('renders cost KPIs and charts', () => {
    setupHooks();
    renderWithClient(<CostSection />);
    expect(screen.getByText('Total Cost')).toBeInTheDocument();
    expect(screen.getByText('Agent Cost')).toBeInTheDocument();
    expect(screen.getByText('Providers Billed')).toBeInTheDocument();
    expect(screen.getByText('Spend Over Time')).toBeInTheDocument();
  });

  it('shows an empty state when there is no spend', () => {
    const emptyCost = { ...mockDashboard, cost_analysis: { ...mockDashboard.cost_analysis, totals: { agent_cost: 0, total_cost: 0 }, by_provider: [], hourly_trend: [] } };
    setupHooks({ dashboardState: { data: emptyCost } });
    renderWithClient(<CostSection />);
    expect(screen.getByText('No cost data')).toBeInTheDocument();
  });
});

describe('ReliabilitySection', () => {
  it('renders the circuit-breaker table and NO generic alerts list', () => {
    setupHooks();
    renderWithClient(<ReliabilitySection />);
    expect(screen.getByText('Circuit Breakers')).toBeInTheDocument();
    expect(screen.getByText('OpenAI')).toBeInTheDocument();
    // must NOT duplicate the Alerts tab's alert list
    expect(screen.queryByText('Error rate exceeded threshold')).not.toBeInTheDocument();
  });

  it('hides the recent-errors feed when the optional data is absent', () => {
    setupHooks({ recentErrors: undefined });
    renderWithClient(<ReliabilitySection />);
    expect(screen.queryByText('Recent Errors')).not.toBeInTheDocument();
  });

  it('shows the recent-errors feed when the optional data is present', () => {
    setupHooks({ recentErrors: [{ execution_id: 'e1', agent_name: 'Researcher', error: 'boom', failed_at: '2026-06-18T01:00:00Z' }] });
    renderWithClient(<ReliabilitySection />);
    expect(screen.getByText('Recent Errors')).toBeInTheDocument();
    expect(screen.getByText('boom')).toBeInTheDocument();
  });
});

describe('TrendsSection', () => {
  it('falls back to the cost trend when the optional trends payload is absent', () => {
    setupHooks({ trends: undefined });
    renderWithClient(<TrendsSection />);
    expect(screen.getByText(/Detailed latency\/error\/throughput trends are not available yet/i)).toBeInTheDocument();
    expect(screen.queryByText('Error Rate')).not.toBeInTheDocument();
  });

  it('renders trend charts when the optional trends payload is present', () => {
    setupHooks({ trends: mockTrends });
    renderWithClient(<TrendsSection />);
    expect(screen.getByText('Latency')).toBeInTheDocument();
    expect(screen.getByText('Error Rate')).toBeInTheDocument();
    expect(screen.getByText('Throughput')).toBeInTheDocument();
  });
});

describe('AiOpsContent (flat operations body)', () => {
  it('renders the controls bar: time-range select + live ticker', () => {
    setupHooks({ trends: undefined });
    renderWithClient(<AiOpsContent />);
    expect(screen.getByRole('combobox')).toBeInTheDocument();
    // ticker labels are unique to the controls bar
    expect(screen.getByText('Req/sec')).toBeInTheDocument();
    expect(screen.getByText('Queue')).toBeInTheDocument();
    expect(screen.getByText('Connections')).toBeInTheDocument();
  });

  it('renders the four operational sections and not Cost/Reliability', () => {
    setupHooks({ trends: undefined });
    renderWithClient(<AiOpsContent />);
    // Overview + Providers + Agents + Trends present
    expect(screen.getByText('Total Executions')).toBeInTheDocument();
    expect(screen.getAllByText('OpenAI').length).toBeGreaterThan(0);
    expect(screen.getByText('Researcher')).toBeInTheDocument();
    expect(screen.getByText(/Detailed latency\/error\/throughput trends are not available yet/i)).toBeInTheDocument();
    // Cost + Reliability are NOT part of the Operations body
    expect(screen.queryByText('Circuit Breakers')).not.toBeInTheDocument();
    expect(screen.queryByText('Agent Cost')).not.toBeInTheDocument();
    expect(screen.queryByText('Providers Billed')).not.toBeInTheDocument();
  });

  it('drives its sections by refetching with the new range on time-range change', () => {
    setupHooks({ trends: undefined });
    renderWithClient(<AiOpsContent />);
    expect(useAiOpsDashboard).toHaveBeenCalledWith('1h');
    fireEvent.change(screen.getByRole('combobox'), { target: { value: '24h' } });
    expect(useAiOpsDashboard).toHaveBeenCalledWith('24h');
  });

  it('fires a single one-shot error toast when the dashboard query errors', () => {
    setupHooks({ dashboardState: { data: undefined, isError: true }, trends: undefined });
    renderWithClient(<AiOpsContent />);
    expect(mockAddNotification).toHaveBeenCalledTimes(1);
    expect(mockAddNotification).toHaveBeenCalledWith(expect.objectContaining({ type: 'error' }));
  });
});
