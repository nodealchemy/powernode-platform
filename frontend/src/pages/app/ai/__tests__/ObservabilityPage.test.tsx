import React from 'react';
import { render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Routes, Route } from 'react-router-dom';

let mockAllowed: string[] = [];
// Captures what the page hands the agent panel (M1 re-review k1): the agent
// mapping is the page's own code, and a bare `() => <div />` mock let a
// restored `|| 100` there pass every example.
const mockAgentPanelProps: Array<{ agents: Array<Record<string, unknown>> }> = [];

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
jest.mock('@/features/ai/monitoring/components/ProviderMonitoringGrid', () => ({ ProviderMonitoringGrid: () => <div /> }));
jest.mock('@/features/ai/monitoring/components/AgentPerformancePanel', () => ({
  AgentPerformancePanel: (props: { agents: Array<Record<string, unknown>> }) => {
    mockAgentPanelProps.push(props);
    return <div />;
  },
}));
jest.mock('@/features/ai/monitoring/components/ConversationAnalytics', () => ({ ConversationAnalytics: () => <div /> }));
jest.mock('@/features/ai/monitoring/components/ResourceUtilizationChart', () => ({ ResourceUtilizationChart: () => <div /> }));
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
});
