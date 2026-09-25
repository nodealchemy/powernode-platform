import React from 'react';
import { render, screen, waitFor, fireEvent, within } from '@testing-library/react';
import { MemoryRouter, Routes, Route } from 'react-router-dom';

let mockAllowed: string[] = [];
const mockAddNotification = jest.fn();
const mockGetAlerts = jest.fn();
const mockAcknowledgeAlert = jest.fn();
const mockResolveAlert = jest.fn();
const mockGetDashboard = jest.fn();
const mockGetHealth = jest.fn();
const mockGetConversations = jest.fn();
// The page's own resources mapping (M1 tail) — captured so a `|| 5` or a
// fabricated storage split regresses visibly, same discipline as before the merge.
const mockResourceProps: Array<{ resourceData: Record<string, unknown> | null }> = [];
const mockConversationProps: Array<{ conversations: Array<Record<string, unknown>> }> = [];

jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));
jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({ hasPermission: (p: string) => mockAllowed.includes(p) }),
}));
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: mockAddNotification }),
}));
jest.mock('@/shared/services/ai/MonitoringApiService', () => ({
  monitoringApi: {
    getDashboard: (...args: unknown[]) => mockGetDashboard(...args),
    getHealth: (...args: unknown[]) => mockGetHealth(...args),
    getAlerts: (...args: unknown[]) => mockGetAlerts(...args),
    acknowledgeAlert: (...args: unknown[]) => mockAcknowledgeAlert(...args),
    resolveAlert: (...args: unknown[]) => mockResolveAlert(...args),
  },
}));
jest.mock('@/shared/services/ai/ConversationsApiService', () => ({
  conversationsApi: { getConversations: (...args: unknown[]) => mockGetConversations(...args) },
}));
jest.mock('@/shared/components/error/AiErrorBoundary', () => ({
  AiErrorBoundary: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));
jest.mock('@/features/ai/monitoring/components/SystemHealthDashboard', () => ({
  SystemHealthDashboard: () => <div data-testid="health-leaf" />,
}));
jest.mock('@/features/ai/monitoring/components/ResourceUtilizationChart', () => ({
  ResourceUtilizationChart: (props: { resourceData: Record<string, unknown> | null }) => {
    mockResourceProps.push(props);
    return <div data-testid="resources-leaf" />;
  },
}));
jest.mock('@/features/ai/monitoring/components/ConversationAnalytics', () => ({
  ConversationAnalytics: (props: { conversations: Array<Record<string, unknown>> }) => {
    mockConversationProps.push(props);
    return <div data-testid="conversations-leaf" />;
  },
}));
jest.mock('@/features/ai/monitoring/components/AlertManagementCenter', () => ({
  AlertManagementCenter: (props: {
    alerts: Array<Record<string, unknown>>;
    canManageAlerts: boolean;
    onAcknowledgeAlert: (id: string, note?: string) => void;
    onResolveAlert: (id: string, note?: string) => void;
  }) => (
    <div data-testid="alerts-leaf">
      {props.alerts.map((a) => (
        <div key={a.id as string}>
          <span>{a.message as string}</span>
          <span>{a.acknowledged ? 'Acknowledged' : 'Pending'}</span>
          {props.canManageAlerts && !a.acknowledged && (
            <button onClick={() => props.onAcknowledgeAlert(a.id as string)}>Acknowledge</button>
          )}
          {props.canManageAlerts && !a.resolved && (
            <button onClick={() => props.onResolveAlert(a.id as string)}>Resolve</button>
          )}
        </div>
      ))}
    </div>
  ),
}));
jest.mock('@/features/ai/monitoring/components/CircuitBreakersTab', () => ({
  CircuitBreakersTab: () => <div data-testid="circuit-breakers-leaf" />,
}));
jest.mock('@/features/ai/self-healing/SelfHealingDashboard', () => ({ SelfHealingContent: () => <div /> }));
jest.mock('@/features/ai/evaluation/pages/EvaluationDashboardPage', () => ({ EvaluationContent: () => <div data-testid="evaluation-leaf" /> }));
jest.mock('@/features/ai/aiops/components/AiOpsDashboard', () => ({ AiOpsContent: () => <div data-testid="systems-leaf" /> }));
jest.mock('../ExecutionTracesPage', () => ({ ExecutionTracesContent: () => <div data-testid="traces-leaf" /> }));

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

const ALL_PERMISSIONS = [
  'ai.monitoring.read',
  'ai.monitoring.manage',
  'ai.aiops.read',
  'ai.aiops.manage',
  'ai.conversations.read',
  'ai_monitoring.read',
  'ai.analytics.read',
];

describe('ObservabilityPage', () => {
  beforeEach(() => {
    mockAllowed = [];
    mockAddNotification.mockClear();
    mockGetDashboard.mockReset().mockResolvedValue({});
    mockGetHealth.mockReset().mockResolvedValue({});
    mockGetAlerts.mockReset().mockResolvedValue([]);
    mockAcknowledgeAlert.mockReset();
    mockResolveAlert.mockReset();
    mockGetConversations.mockReset().mockResolvedValue({
      items: [],
      pagination: { current_page: 1, per_page: 50, total_pages: 0, total_count: 0 },
    });
    mockResourceProps.length = 0;
    mockConversationProps.length = 0;
  });

  it('renders all seven merged tabs when every underlying permission is held', () => {
    mockAllowed = ALL_PERMISSIONS;
    renderAt('/app/ai/observability/health');

    expect(screen.getByRole('link', { name: 'System Health' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Systems' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Circuit Breakers' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Alerts' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Conversations' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Execution Traces' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Evaluation' })).toBeInTheDocument();
  });

  it('no longer exposes a separate Operations/AIOps hub — Systems IS the AIOps body', () => {
    mockAllowed = ['ai.aiops.read'];
    renderAt('/app/ai/observability/systems');
    expect(screen.getByTestId('systems-leaf')).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'AIOps' })).not.toBeInTheDocument();
  });

  it('shows Access Denied when the user holds none of the tab permissions', () => {
    mockAllowed = [];
    renderAt('/app/ai/observability/health');
    expect(screen.getByText(/Access Denied/i)).toBeInTheDocument();
  });

  // Mutant proof for the permission-matching fix: a version that gated every
  // tab on the single old blanket `ai.analytics.read` would make ALL of these
  // pass together. Holding each tab's permission in isolation and checking
  // the OTHERS stay gated proves the tabs are wired to distinct permissions.
  describe('each tab is gated on its own backend permission, not a blanket one', () => {
    it('ai.monitoring.read alone unlocks Health, Circuit Breakers and Alerts, not Systems/Conversations', () => {
      mockAllowed = ['ai.monitoring.read'];
      renderAt('/app/ai/observability/health');
      expect(screen.getByRole('link', { name: 'System Health' })).toBeInTheDocument();
      expect(screen.getByRole('link', { name: 'Circuit Breakers' })).toBeInTheDocument();
      expect(screen.getByRole('link', { name: 'Alerts' })).toBeInTheDocument();
      expect(screen.queryByRole('link', { name: 'Systems' })).not.toBeInTheDocument();
      expect(screen.queryByRole('link', { name: 'Conversations' })).not.toBeInTheDocument();
    });

    it('ai.aiops.read alone unlocks only Systems', () => {
      mockAllowed = ['ai.aiops.read'];
      renderAt('/app/ai/observability/systems');
      expect(screen.getByRole('link', { name: 'Systems' })).toBeInTheDocument();
      expect(screen.queryByRole('link', { name: 'System Health' })).not.toBeInTheDocument();
      expect(screen.queryByRole('link', { name: 'Alerts' })).not.toBeInTheDocument();
    });

    it('ai.conversations.read alone unlocks only Conversations (fixes the old ai.analytics.read mismatch)', () => {
      mockAllowed = ['ai.conversations.read'];
      renderAt('/app/ai/observability/conversations');
      expect(screen.getByRole('link', { name: 'Conversations' })).toBeInTheDocument();
      expect(screen.queryByRole('link', { name: 'System Health' })).not.toBeInTheDocument();
    });

    it('ai_monitoring.read alone unlocks only Execution Traces', () => {
      mockAllowed = ['ai_monitoring.read'];
      renderAt('/app/ai/observability/traces');
      expect(screen.getByRole('link', { name: 'Execution Traces' })).toBeInTheDocument();
      expect(screen.getByTestId('traces-leaf')).toBeInTheDocument();
      expect(screen.queryByRole('link', { name: 'System Health' })).not.toBeInTheDocument();
    });

    it('ai.analytics.read alone unlocks only Evaluation', () => {
      mockAllowed = ['ai.analytics.read'];
      renderAt('/app/ai/observability/evaluation');
      expect(screen.getByRole('link', { name: 'Evaluation' })).toBeInTheDocument();
      expect(screen.getByTestId('evaluation-leaf')).toBeInTheDocument();
      expect(screen.queryByRole('link', { name: 'Conversations' })).not.toBeInTheDocument();
    });
  });

  describe('Health tab resource figures (M1 tail — carried through the merge)', () => {
    const resources = (connection_count: number | null) => ({
      cpu: { usage_percent: 5, idle_percent: 95, load_average: '0.1' },
      memory: { total_mb: 100, used_mb: 40, free_mb: 60, usage_percent: 40 },
      database: { status: 'ok', connection_count },
      redis: { status: 'ok', used_memory: '1', connected_clients: 2 },
    });
    const lastDatabase = () =>
      (mockResourceProps[mockResourceProps.length - 1]?.resourceData as { database: Record<string, unknown> } | null)
        ?.database;

    beforeEach(() => {
      mockAllowed = ['ai.monitoring.read'];
    });

    it('the database pool carries the size the server sent and nothing it did not', async () => {
      mockGetDashboard.mockResolvedValue({ resources: resources(10) });
      renderAt('/app/ai/observability/health');
      await waitFor(() => expect(lastDatabase()).toBeTruthy());
      expect(lastDatabase()?.connection_pool).toEqual({ size: 10, used: null, available: null });
      expect(lastDatabase()?.storage_usage).toBeNull();
    });

    it('no pool size from the server is a null size — not a made-up 5', async () => {
      mockGetDashboard.mockResolvedValue({ resources: resources(null) });
      renderAt('/app/ai/observability/health');
      await waitFor(() => expect(lastDatabase()).toBeTruthy());
      expect(lastDatabase()?.connection_pool).toEqual({ size: null, used: null, available: null });
    });
  });

  describe('Conversations tab figures (M1 tail — carried through the merge)', () => {
    beforeEach(() => {
      mockAllowed = ['ai.conversations.read'];
    });

    it('a conversation arrives with no health score and no success rate — never 100', async () => {
      mockGetConversations.mockResolvedValue({
        items: [{
          id: 'c1', title: 'Chat', status: 'active', message_count: 3, total_tokens: 10, total_cost: 0,
          last_activity_at: '2026-09-11T00:00:00Z', created_at: '2026-09-11T00:00:00Z',
        }],
        pagination: { current_page: 1, per_page: 50, total_pages: 1, total_count: 1 },
      });

      renderAt('/app/ai/observability/conversations');
      const last = () => mockConversationProps[mockConversationProps.length - 1]?.conversations ?? [];
      await waitFor(() => expect(last()).toHaveLength(1));
      expect(last()[0].health_score).toBeNull();
      expect((last()[0].performance as Record<string, unknown>).success_rate).toBeNull();
    });
  });

  describe('Alerts tab (moved from the former Operations hub, fc-04 working acknowledge)', () => {
    const ALERT_ID = '019f0000-0000-7000-8000-000000000001';
    const apiAlert = (overrides: Record<string, unknown> = {}) => ({
      id: ALERT_ID,
      alert_type: 'high_latency',
      severity: 'critical',
      message: 'Alert triggered: High latency',
      timestamp: '2026-09-24T10:00:00Z',
      acknowledged: false,
      resolved: false,
      ...overrides,
    });

    beforeEach(() => {
      mockAllowed = ['ai.monitoring.read', 'ai.aiops.manage'];
      mockGetAlerts.mockResolvedValue([apiAlert()]);
    });

    it('acknowledges through the API and updates the row', async () => {
      mockAcknowledgeAlert.mockResolvedValue(apiAlert({ acknowledged: true, acknowledged_at: '2026-09-24T10:05:00Z' }));
      renderAt('/app/ai/observability/alerts');

      const leaf = screen.getByTestId('alerts-leaf');
      await within(leaf).findByText('Alert triggered: High latency');
      fireEvent.click(within(leaf).getByRole('button', { name: 'Acknowledge' }));

      await waitFor(() => expect(mockAcknowledgeAlert).toHaveBeenCalledWith(ALERT_ID, undefined));
      expect(await within(leaf).findByText('Acknowledged')).toBeInTheDocument();
    });

    it('gates the acknowledge/resolve actions on ai.aiops.manage alone, as the server does', async () => {
      mockAllowed = ['ai.monitoring.read'];
      renderAt('/app/ai/observability/alerts');
      const leaf = screen.getByTestId('alerts-leaf');
      await within(leaf).findByText('Alert triggered: High latency');
      expect(within(leaf).queryByRole('button', { name: 'Acknowledge' })).not.toBeInTheDocument();
    });

    it('reports a failed acknowledge and leaves the row unchanged', async () => {
      mockAcknowledgeAlert.mockRejectedValue(new Error('Alert not found'));
      renderAt('/app/ai/observability/alerts');
      const leaf = screen.getByTestId('alerts-leaf');
      await within(leaf).findByText('Alert triggered: High latency');

      fireEvent.click(within(leaf).getByRole('button', { name: 'Acknowledge' }));
      await waitFor(() =>
        expect(mockAddNotification).toHaveBeenCalledWith(
          expect.objectContaining({ type: 'error', message: 'Alert not found' }),
        ),
      );
      expect(within(leaf).getByRole('button', { name: 'Acknowledge' })).toBeInTheDocument();
    });
  });

  it('renders the Circuit Breakers tab body', async () => {
    mockAllowed = ['ai.monitoring.read'];
    renderAt('/app/ai/observability/circuit-breakers');
    expect(await screen.findByTestId('circuit-breakers-leaf')).toBeInTheDocument();
  });
});
