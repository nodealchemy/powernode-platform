import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render } from '@/test-utils';
import GovernancePage from './GovernancePage';

// fc-05: "Create Policy" used to be a dead PageContainer action
// (`onClick: () => {}`). The backend has always had a working create
// endpoint (governanceApi.createPolicy -> POST /ai/governance/policies), so
// the operator's stub-removal rule calls for wiring it, not removing it.

const mockCreatePolicy = jest.fn();

jest.mock('@/shared/services/ai/GovernanceApiService', () => ({
  governanceApi: {
    getPolicies: () => Promise.resolve({ items: [] }),
    getViolations: () => Promise.resolve({ items: [] }),
    getApprovalChains: () => Promise.resolve({ items: [] }),
    getPendingApprovals: () => Promise.resolve({ approval_requests: [] }),
    getSummary: () => Promise.resolve({ summary: null }),
    getGovernanceReports: () => Promise.resolve({ items: [] }),
    getCollusionIndicators: () => Promise.resolve({ items: [] }),
    createPolicy: (...args: unknown[]) => mockCreatePolicy(...args),
  },
}));

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

describe('GovernancePage "Create Policy" action', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('opens a create-policy form instead of doing nothing', async () => {
    const user = userEvent.setup();
    renderPage();

    await user.click(await screen.findByRole('button', { name: /create policy/i }));

    expect(await screen.findByRole('heading', { name: /create compliance policy/i })).toBeInTheDocument();
  });

  it('submits the form to the real create-policy endpoint', async () => {
    const user = userEvent.setup();
    mockCreatePolicy.mockResolvedValue({ policy: { id: 'pol-1' } });
    renderPage();

    await user.click(await screen.findByRole('button', { name: /create policy/i }));
    const dialog = await screen.findByRole('dialog');
    await user.type(within(dialog).getByLabelText(/^name$/i), 'No External API Keys');
    await user.click(within(dialog).getByRole('button', { name: /^create policy$/i }));

    await waitFor(() =>
      expect(mockCreatePolicy).toHaveBeenCalledWith(
        expect.objectContaining({ name: 'No External API Keys' })
      )
    );
  });

  // fc-05 review (L13): error path — the server's error message must surface,
  // not a generic fallback that swallows what actually went wrong.
  it('surfaces the server error message when creation fails', async () => {
    const user = userEvent.setup();
    mockCreatePolicy.mockRejectedValue({
      response: { data: { error: 'Policy name already exists' } },
    });
    renderPage();

    await user.click(await screen.findByRole('button', { name: /create policy/i }));
    const dialog = await screen.findByRole('dialog');
    await user.type(within(dialog).getByLabelText(/^name$/i), 'Duplicate');
    await user.click(within(dialog).getByRole('button', { name: /^create policy$/i }));

    await waitFor(() =>
      expect(mockAddNotification).toHaveBeenCalledWith(
        expect.objectContaining({ type: 'error', message: 'Policy name already exists' })
      )
    );
    // The dialog stays open on failure — nothing to recover otherwise.
    expect(screen.getByRole('dialog')).toBeInTheDocument();
  });

  // fc-05 review (M9): permission-gated, using permissions only.
  it('hides the action without ai.governance.manage', async () => {
    renderPage([]);

    await screen.findByText('Governance & Compliance');
    expect(screen.queryByRole('button', { name: /create policy/i })).not.toBeInTheDocument();
  });
});
