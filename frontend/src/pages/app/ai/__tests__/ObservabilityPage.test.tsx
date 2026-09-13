import React from 'react';
import { render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Routes, Route } from 'react-router-dom';

let mockAllowed: string[] = [];
// Captures what the page hands the agent panel (M1 re-review k1): the agent
// mapping is the page's own code, and a bare `() => <div />` mock let a
// restored `|| 100` there pass every example.
const mockAgentPanelProps: Array<{ agents: Array<Record<string, unknown>> }> = [];
// The same capture for the provider grid, the conversation list and the
// resource chart (M1 tail): each of those mappings is the page's own code too.
const mockProviderGridProps: Array<{ providers: Array<Record<string, unknown>> }> = [];
const mockConversationProps: Array<{ conversations: Array<Record<string, unknown>> }> = [];
const mockResourceProps: Array<{ resourceData: Record<string, unknown> | null }> = [];

jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));
jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({ hasPermission: (p: string) => mockAllowed.includes(p) }),
}));
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: jest.fn() }),
}));
jest.mock('@/shared/services/ai/MonitoringApiService', () => ({
  monitoringApi: {
    getDashboard: jest.fn().mockResolvedValue({}),
    getHealth: jest.fn().mockResolvedValue({}),
    getAlerts: jest.fn().mockResolvedValue([]),
  },
}));
jest.mock('@/shared/services/ai/ConversationsApiService', () => ({
  conversationsApi: {
    getConversations: jest.fn().mockResolvedValue({
      items: [],
      pagination: { current_page: 1, per_page: 50, total_pages: 0, total_count: 0 },
    }),
  },
}));
jest.mock('@/shared/components/error/AiErrorBoundary', () => ({
  AiErrorBoundary: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));
// Keep MONITORING_TABS real; stub the data transforms.
jest.mock('@/features/ai/monitoring/utils', () => {
  const actual = jest.requireActual('@/features/ai/monitoring/utils');
  return { ...actual, transformDashboardData: () => ({}), transformAlerts: () => [] };
});
// Stub the dashboard child components so the page renders without data shapes.
jest.mock('@/features/ai/monitoring/components/MonitoringOverviewCards', () => ({ MonitoringOverviewCards: () => <div /> }));
jest.mock('@/features/ai/monitoring/components/MonitoringStatusBar', () => ({ MonitoringStatusBar: () => <div /> }));
jest.mock('@/features/ai/monitoring/components/SystemHealthDashboard', () => ({ SystemHealthDashboard: () => <div data-testid="health-leaf" /> }));
jest.mock('@/features/ai/monitoring/components/ProviderMonitoringGrid', () => ({
  ProviderMonitoringGrid: (props: { providers: Array<Record<string, unknown>> }) => {
    mockProviderGridProps.push(props);
    return <div />;
  },
}));
jest.mock('@/features/ai/monitoring/components/AgentPerformancePanel', () => ({
  AgentPerformancePanel: (props: { agents: Array<Record<string, unknown>> }) => {
    mockAgentPanelProps.push(props);
    return <div />;
  },
}));
jest.mock('@/features/ai/monitoring/components/ConversationAnalytics', () => ({
  ConversationAnalytics: (props: { conversations: Array<Record<string, unknown>> }) => {
    mockConversationProps.push(props);
    return <div />;
  },
}));
jest.mock('@/features/ai/monitoring/components/ResourceUtilizationChart', () => ({
  ResourceUtilizationChart: (props: { resourceData: Record<string, unknown> | null }) => {
    mockResourceProps.push(props);
    return <div />;
  },
}));
jest.mock('@/features/ai/self-healing/SelfHealingDashboard', () => ({ SelfHealingContent: () => <div /> }));
jest.mock('@/features/ai/evaluation/pages/EvaluationDashboardPage', () => ({ EvaluationContent: () => <div /> }));

import { ObservabilityPage } from '../ObservabilityPage';

function renderAt(path: string) {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <Routes>
        <Route path="/app/ai/observability/*" element={<ObservabilityPage />} />
      </Routes>
    </MemoryRouter>,
  );
}

describe('ObservabilityPage', () => {
  afterEach(() => {
    mockAllowed = [];
  });

  it('renders the monitoring-only tab set when analytics is permitted', () => {
    mockAllowed = ['ai.analytics.read'];
    renderAt('/app/ai/observability/health');

    expect(screen.getByRole('link', { name: 'System Health' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Systems' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Conversations' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Evaluation' })).toBeInTheDocument();
  });

  it('no longer surfaces the moved Credits/Operations/Alerts tabs', () => {
    mockAllowed = ['ai.analytics.read'];
    renderAt('/app/ai/observability/health');

    expect(screen.queryByRole('link', { name: /Credits/i })).not.toBeInTheDocument();
    expect(screen.queryByRole('link', { name: /Operations/i })).not.toBeInTheDocument();
    expect(screen.queryByRole('link', { name: /Alerts/i })).not.toBeInTheDocument();
  });

  it('shows Access Denied when the user lacks analytics permission', () => {
    mockAllowed = [];
    renderAt('/app/ai/observability/health');
    expect(screen.getByText(/Access Denied/i)).toBeInTheDocument();
  });

  // M1 re-review k1: the page passes an agent's rate through, never `|| 100`.
  describe('agent rates handed to the Systems tab', () => {
    const { monitoringApi } = jest.requireMock('@/shared/services/ai/MonitoringApiService');
    const { conversationsApi } = jest.requireMock('@/shared/services/ai/ConversationsApiService');

    beforeEach(() => {
      mockAgentPanelProps.length = 0;
      mockAllowed = ['ai.analytics.read'];
      monitoringApi.getHealth.mockResolvedValue({});
      monitoringApi.getAlerts.mockResolvedValue([]);
      conversationsApi.getConversations.mockResolvedValue({
        items: [],
        pagination: { current_page: 1, per_page: 50, total_pages: 0, total_count: 0 },
      });
    });

    const lastAgents = () => mockAgentPanelProps[mockAgentPanelProps.length - 1]?.agents ?? [];

    it('an agent with no measured rate arrives with a null health and success rate — never 100', async () => {
      monitoringApi.getDashboard.mockResolvedValue({
        agentsList: [{ id: 'a1', name: 'Never ran', status: 'active', executions: 0, success_rate: null }],
      });

      renderAt('/app/ai/observability/systems');
      await waitFor(() => expect(lastAgents()).toHaveLength(1));

      const [agent] = lastAgents();
      expect(agent.health_score).toBeNull();
      expect((agent.performance as Record<string, unknown>).success_rate).toBeNull();
      expect((agent.performance as Record<string, unknown>).error_rate).toBeNull();
    });

    it('an agent at a real 0% arrives as 0 with a 100% error rate', async () => {
      monitoringApi.getDashboard.mockResolvedValue({
        agentsList: [{ id: 'a1', name: 'Always failed', status: 'active', executions: 4, success_rate: 0 }],
      });

      renderAt('/app/ai/observability/systems');
      await waitFor(() => expect(lastAgents()).toHaveLength(1));

      const [agent] = lastAgents();
      expect(agent.health_score).toBe(0);
      expect((agent.performance as Record<string, unknown>).error_rate).toBe(100);
    });
  });

  // M1 tail: what the page hands the provider grid, the conversation list and
  // the resource chart. A figure the server does not send arrives as null —
  // never the 100, the 5 or the 1000/100/900 the page used to make up.
  describe('figures handed to the Systems, Conversations and Health tabs', () => {
    const { monitoringApi } = jest.requireMock('@/shared/services/ai/MonitoringApiService');
    const { conversationsApi } = jest.requireMock('@/shared/services/ai/ConversationsApiService');
    const page = (items: unknown[]) => ({
      items,
      pagination: { current_page: 1, per_page: 50, total_pages: items.length ? 1 : 0, total_count: items.length },
    });

    beforeEach(() => {
      mockProviderGridProps.length = 0;
      mockConversationProps.length = 0;
      mockResourceProps.length = 0;
      mockAllowed = ['ai.analytics.read'];
      monitoringApi.getHealth.mockResolvedValue({});
      monitoringApi.getAlerts.mockResolvedValue([]);
      conversationsApi.getConversations.mockResolvedValue(page([]));
    });

    const last = <T,>(calls: T[]): T | undefined => calls[calls.length - 1];
    const lastProviders = () => last(mockProviderGridProps)?.providers ?? [];
    const lastConversations = () => last(mockConversationProps)?.conversations ?? [];
    const perf = (row: Record<string, unknown>) => row.performance as Record<string, unknown>;
    const resources = (connection_count: number | null) => ({
      cpu: { usage_percent: 5, idle_percent: 95, load_average: '0.1' },
      memory: { total_mb: 100, used_mb: 40, free_mb: 60, usage_percent: 40 },
      database: { status: 'ok', connection_count },
      redis: { status: 'ok', used_memory: '1', connected_clients: 2 },
    });
    const lastDatabase = () =>
      (last(mockResourceProps)?.resourceData as { database: Record<string, unknown> } | null)?.database;

    it('a provider with no measured error rate arrives with null rates — not 100% success and 0% errors', async () => {
      monitoringApi.getDashboard.mockResolvedValue({ providers: [{ id: 'p1', name: 'Idle', status: 'healthy', latency_ms: 0 }] });

      renderAt('/app/ai/observability/systems');
      await waitFor(() => expect(lastProviders()).toHaveLength(1));

      expect(perf(lastProviders()[0]).success_rate).toBeNull();
      expect(perf(lastProviders()[0]).error_rate).toBeNull();
    });

    it('a provider at a real 0% error rate arrives as 0 errors and 100% success', async () => {
      monitoringApi.getDashboard.mockResolvedValue({ providers: [{ id: 'p1', name: 'Clean', status: 'healthy', latency_ms: 5, error_rate: 0 }] });

      renderAt('/app/ai/observability/systems');
      await waitFor(() => expect(lastProviders()).toHaveLength(1));

      expect(perf(lastProviders()[0]).error_rate).toBe(0);
      expect(perf(lastProviders()[0]).success_rate).toBe(100);
    });

    it('a provider failing every call arrives as 0% success', async () => {
      monitoringApi.getDashboard.mockResolvedValue({ providers: [{ id: 'p1', name: 'Broken', status: 'unhealthy', latency_ms: 5, error_rate: 100 }] });

      renderAt('/app/ai/observability/systems');
      await waitFor(() => expect(lastProviders()).toHaveLength(1));

      expect(perf(lastProviders()[0]).success_rate).toBe(0);
      expect(perf(lastProviders()[0]).error_rate).toBe(100);
    });

    it('the database pool carries the size the server sent and nothing it did not', async () => {
      monitoringApi.getDashboard.mockResolvedValue({ resources: resources(10) });

      renderAt('/app/ai/observability/health');
      await waitFor(() => expect(lastDatabase()).toBeTruthy());

      expect(lastDatabase()?.connection_pool).toEqual({ size: 10, used: null, available: null });
      expect(lastDatabase()?.storage_usage).toBeNull();
    });

    it('no pool size from the server is a null size — not a made-up 5', async () => {
      monitoringApi.getDashboard.mockResolvedValue({ resources: resources(null) });

      renderAt('/app/ai/observability/health');
      await waitFor(() => expect(lastDatabase()).toBeTruthy());

      expect(lastDatabase()?.connection_pool).toEqual({ size: null, used: null, available: null });
    });

    it('a conversation arrives with no health score and no success rate — never 100', async () => {
      monitoringApi.getDashboard.mockResolvedValue({});
      conversationsApi.getConversations.mockResolvedValue(page([{
        id: 'c1', title: 'Chat', status: 'active', message_count: 3, total_tokens: 10, total_cost: 0,
        last_activity_at: '2026-09-11T00:00:00Z', created_at: '2026-09-11T00:00:00Z',
      }]));

      renderAt('/app/ai/observability/conversations');
      await waitFor(() => expect(lastConversations()).toHaveLength(1));

      expect(lastConversations()[0].health_score).toBeNull();
      expect(perf(lastConversations()[0]).success_rate).toBeNull();
    });
  });
});
