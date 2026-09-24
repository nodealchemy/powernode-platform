import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render } from '@/test-utils';
import GovernancePage from './GovernancePage';

// fc-05 review (M7): a draft compliance policy had no way to become active
// from the UI at all — the backend has always had PUT
// /ai/governance/policies/:id/activate (governanceApi.activatePolicy). Adds
// an "Activate" action to each draft policy row.

const mockActivatePolicy = jest.fn();

jest.mock('@/shared/services/ai/GovernanceApiService', () => {
  const draftPolicy = {
    id: 'pol-1',
    name: 'PII Access Restriction',
    policy_type: 'data_access',
    category: null,
    description: 'Restrict access to PII fields',
    status: 'draft',
    enforcement_level: 'block',
    conditions: {},
    actions: {},
    is_system: false,
    is_required: false,
    priority: 0,
    violation_count: 0,
    last_triggered_at: null,
    created_at: new Date().toISOString(),
  };
  return {
    governanceApi: {
      getPolicies: () => Promise.resolve({ items: [draftPolicy] }),
      getViolations: () => Promise.resolve({ items: [] }),
      getApprovalChains: () => Promise.resolve({ items: [] }),
      getPendingApprovals: () => Promise.resolve({ approval_requests: [] }),
      getSummary: () => Promise.resolve({ summary: null }),
      getGovernanceReports: () => Promise.resolve({ items: [] }),
      getCollusionIndicators: () => Promise.resolve({ items: [] }),
      activatePolicy: (...args: unknown[]) => mockActivatePolicy(...args),
    },
  };
});

jest.mock('@/shared/services/ai/IntelligenceApiService', () => ({
  intelligenceApi: {
    getCoordinationSummary: () => Promise.resolve({ summary: null }),
    getSignals: () => Promise.resolve({ items: [] }),
    getPressureFields: () => Promise.resolve({ items: [] }),
    getTeamEvents: () => Promise.resolve({ items: [] }),
  },
}));

jest.mock('@/shared/hooks/usePageWebSocket', () => ({ usePageWebSocket: () => {} }));
const mockAddNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: mockAddNotification }),
}));
jest.mock('@/features/ai/security/pages/SecurityDashboardPage', () => ({ SecurityContent: () => null }));
jest.mock('@/features/ai/audit/components/AuditLogList', () => ({ AuditLogList: () => null }));

const renderPage = (permissions: string[] = ['ai.governance.manage']) => {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return render(
    <QueryClientProvider client={queryClient}>
      <GovernancePage />
    </QueryClientProvider>,
    { preloadedState: { auth: { user: { permissions }, isLoading: false, isAuthenticated: true } } }
  );
};

describe('GovernancePage "Activate" policy action', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('calls the real activate-policy endpoint for a draft policy', async () => {
    const user = userEvent.setup();
    mockActivatePolicy.mockResolvedValue({ policy: { id: 'pol-1', status: 'active' } });
    renderPage();

    await user.click(await screen.findByRole('button', { name: /^activate$/i }));

    await waitFor(() => expect(mockActivatePolicy).toHaveBeenCalledWith('pol-1'));
    await waitFor(() =>
      expect(mockAddNotification).toHaveBeenCalledWith(
        expect.objectContaining({ type: 'success', message: 'Policy activated' })
      )
    );
  });

  // fc-05 review (L13): error path.
  it('surfaces the server error message when activation fails', async () => {
    const user = userEvent.setup();
    mockActivatePolicy.mockRejectedValue({
      response: { data: { error: 'Policy already active' } },
    });
    renderPage();

    await user.click(await screen.findByRole('button', { name: /^activate$/i }));

    await waitFor(() =>
      expect(mockAddNotification).toHaveBeenCalledWith(
        expect.objectContaining({ type: 'error', message: 'Policy already active' })
      )
    );
  });

  // fc-05 review (M9): permission-gated, using permissions only.
  it('hides the action without ai.governance.manage', async () => {
    renderPage([]);

    await screen.findByText('PII Access Restriction');
    expect(screen.queryByRole('button', { name: /^activate$/i })).not.toBeInTheDocument();
  });
});
