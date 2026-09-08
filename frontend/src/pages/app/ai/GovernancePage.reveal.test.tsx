import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render } from '@/test-utils';
import GovernancePage from './GovernancePage';

// IMP-246994888a1f — governance is the OTHER human surface that resolves an
// approval (the decide endpoint merges the same one-shot slot as the autonomy
// approve action, and the read empties it server-side). A decision here that
// dropped the payload would destroy the minted material just as surely.

const mockDecideApproval = jest.fn();
const PENDING = {
  id: 'req-1',
  request_id: 'REQ-0001',
  description: 'Rotate secret for disk image webhook',
  status: 'pending',
};
const SECRET = 'whsec_zz_test_only_not_a_real_secret';

jest.mock('@/shared/services/ai/GovernanceApiService', () => ({
  governanceApi: {
    getPolicies: () => Promise.resolve({ items: [] }),
    getViolations: () => Promise.resolve({ items: [] }),
    getApprovalChains: () => Promise.resolve({ items: [] }),
    getPendingApprovals: () =>
      Promise.resolve({
        approval_requests: [
          { id: 'req-1', request_id: 'REQ-0001', description: 'Rotate secret for disk image webhook', status: 'pending' },
        ],
      }),
    getSummary: () => Promise.resolve({ summary: null }),
    getGovernanceReports: () => Promise.resolve({ items: [] }),
    getCollusionIndicators: () => Promise.resolve({ items: [] }),
    decideApproval: (...args: unknown[]) => mockDecideApproval(...args),
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
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: () => {} }),
}));
jest.mock('@/features/ai/security/pages/SecurityDashboardPage', () => ({ SecurityContent: () => null }));
jest.mock('@/features/ai/audit/components/AuditLogList', () => ({ AuditLogList: () => null }));

const renderPage = () => {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return {
    queryClient,
    ...render(
      <QueryClientProvider client={queryClient}>
        <GovernancePage />
      </QueryClientProvider>
    ),
  };
};

const openApprovalsAndApprove = async (user: ReturnType<typeof userEvent.setup>) => {
  await user.click(await screen.findByRole('tab', { name: /approvals/i }));
  await user.click(await screen.findByRole('button', { name: /^approve$/i }));
};

describe('GovernancePage one-shot revealed_result', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('reveals the decide response revealed_result once, and keeps it out of the mutation cache', async () => {
    const user = userEvent.setup();
    mockDecideApproval.mockResolvedValue({
      approval_request: { ...PENDING, status: 'approved', revealed_result: { secret_plaintext: SECRET } },
    });

    const { queryClient } = renderPage();
    await openApprovalsAndApprove(user);

    const reveal = await screen.findByTestId('one-shot-reveal');
    expect(within(reveal).getByText(SECRET)).toBeInTheDocument();

    // react-query keeps a settled mutation (response body and all) for gcTime
    // after the reveal closes, which is why the slot is stripped in mutationFn.
    await waitFor(() => expect(queryClient.getMutationCache().getAll()).toHaveLength(1));
    const cached = JSON.stringify([
      queryClient.getQueryCache().getAll().map((q) => q.state.data),
      queryClient.getMutationCache().getAll().map((m) => m.state),
    ]);
    expect(cached).not.toContain(SECRET);
  });

  it('shows no reveal when the decision minted nothing', async () => {
    const user = userEvent.setup();
    mockDecideApproval.mockResolvedValue({ approval_request: { ...PENDING, status: 'approved' } });

    renderPage();
    await openApprovalsAndApprove(user);

    await waitFor(() => expect(mockDecideApproval).toHaveBeenCalledTimes(1));
    await waitFor(() => expect(screen.queryByTestId('one-shot-reveal')).not.toBeInTheDocument());
  });
});
