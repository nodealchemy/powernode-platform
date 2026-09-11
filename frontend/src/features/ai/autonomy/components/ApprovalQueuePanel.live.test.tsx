import React from 'react';
import { screen, waitFor, act, fireEvent } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { renderWithProviders } from '@/test-utils';
import { ApprovalQueuePanel } from './ApprovalQueuePanel';
import { useWebSocket } from '@/shared/hooks/useWebSocket';

// C3b part 2, mounted end to end: the REAL panel, the REAL live-queue hook and
// the REAL usePageWebSocket. Only the socket underneath and the HTTP client are
// faked, so what is proved here is the producer and the consumer together —
// the proof C3b part 1 lacked while nothing imported its pieces.

const mockGet = jest.fn();
const mockPost = jest.fn();
jest.mock('@/shared/services/apiClient', () => ({
  __esModule: true,
  apiClient: {
    get: (...args: unknown[]) => mockGet(...args),
    post: (...args: unknown[]) => mockPost(...args),
  },
  default: {
    get: (...args: unknown[]) => mockGet(...args),
    post: (...args: unknown[]) => mockPost(...args),
  },
}));
jest.mock('@/shared/components/entity', () => ({
  EntityLink: ({ label }: { label: React.ReactNode }) => <span>{label}</span>,
}));
jest.mock('@/shared/hooks/useWebSocket');
jest.mock('@/shared/hooks/usePolling', () => ({ usePolling: jest.fn() }));

const mockedWebSocket = useWebSocket as jest.MockedFunction<typeof useWebSocket>;

interface CapturedSubscription {
  channel: string;
  onMessage: (data: unknown) => void;
}
let subscriptions: CapturedSubscription[];

const LIST = '/ai/autonomy/approvals';
let listRows: Record<string, unknown>[];
let details: Record<string, Record<string, unknown>>;

const row = (id: string, overrides: Record<string, unknown> = {}) => ({
  id,
  request_id: id,
  action_type: `action ${id}`,
  status: 'pending',
  request_data: {},
  created_at: '2026-09-10T00:00:00Z',
  current_step: 0,
  total_steps: 1,
  ...overrides,
});

/** A two-step chain at its second step, which needs two approvals. */
const twoStepDetail = (id: string, secondStepApprovals = 1, overrides: Record<string, unknown> = {}) => ({
  id,
  status: 'pending',
  current_step: 1,
  total_steps: 2,
  step_statuses: [
    { step_number: 0, step_name: 'SRE review', approvers: ['*'], status: 'approved', required_approvals: 1, current_approvals: 1 },
    {
      step_number: 1,
      step_name: 'Security sign-off',
      approvers: [{ type: 'permission', value: 'ai.autonomy.approve' }],
      status: 'pending',
      required_approvals: 2,
      current_approvals: secondStepApprovals,
    },
  ],
  decisions: [],
  current_step_can_approve: true,
  ...overrides,
});

const approvalPush = (id: string) => ({
  type: 'new_notification',
  notification: {
    id: `n-${id}`,
    notification_type: 'autonomy_approval_required',
    metadata: { approval_request_id: id },
  },
});

const detailReads = (id: string) => mockGet.mock.calls.filter((call) => call[0] === `${LIST}/${id}`).length;
const listReads = () => mockGet.mock.calls.filter((call) => call[0] === LIST).length;

const renderPanel = (permissions: string[] = ['ai.agents.read', 'ai.autonomy.approve']) => {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return renderWithProviders(
    <QueryClientProvider client={queryClient}>
      <ApprovalQueuePanel />
    </QueryClientProvider>,
    {
      preloadedState: {
        auth: {
          // `account` is what usePageWebSocket subscribes with.
          user: { id: 'u-1', permissions, account: { id: 'acct-1' } } as never,
          isAuthenticated: true,
          isLoading: false,
        },
      },
    }
  );
};

/** Deliver a message on the latest NotificationChannel subscription, as ActionCable would. */
const deliver = (data: unknown) => {
  const latest = subscriptions.filter((sub) => sub.channel === 'NotificationChannel').pop();
  if (!latest) throw new Error('no NotificationChannel subscription was made');
  act(() => latest.onMessage(data));
};

describe('ApprovalQueuePanel — mounted, live (C3b part 2)', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    subscriptions = [];
    listRows = [row('req-1')];
    details = {};
    mockedWebSocket.mockReturnValue({
      isConnected: true,
      error: null,
      subscribe: jest.fn((sub: CapturedSubscription) => {
        subscriptions.push(sub);
        return jest.fn();
      }),
    } as unknown as ReturnType<typeof useWebSocket>);
    mockGet.mockImplementation((url: string) =>
      Promise.resolve({ data: { data: url === LIST ? listRows : details[url.slice(LIST.length + 1)] } })
    );
  });

  it('a new approval appears without reload when its push arrives', async () => {
    renderPanel();
    expect(await screen.findByText('action req-1')).toBeInTheDocument();

    listRows = [row('req-1'), row('req-2')];
    deliver(approvalPush('req-2'));

    expect(await screen.findByText('action req-2')).toBeInTheDocument();
  });

  it('an expanded multi-step card shows every step of its chain', async () => {
    listRows = [row('req-1', { current_step: 1, total_steps: 2 })];
    details['req-1'] = twoStepDetail('req-1');
    renderPanel();

    expect(await screen.findByText('Step 2 of 2')).toBeInTheDocument();
    fireEvent.click(screen.getByTitle('Expand'));

    expect(await screen.findByText('Step 1: SRE review')).toBeInTheDocument();
    expect(screen.getByText('Step 2: Security sign-off')).toBeInTheDocument();
    expect(screen.getByText('1 of 2 approvals')).toBeInTheDocument();
  });

  it('says a failed chain read failed — never shows it as an empty chain', async () => {
    mockGet.mockImplementation((url: string) =>
      url === LIST ? Promise.resolve({ data: { data: listRows } }) : Promise.reject(new Error('502 Bad Gateway'))
    );
    renderPanel();
    await screen.findByText('action req-1');

    fireEvent.click(screen.getByTitle('Expand'));

    expect(await screen.findByText(/Could not load the approval chain: 502 Bad Gateway/)).toBeInTheDocument();
  });

  it('shows no Approve or Reject without ai.autonomy.approve, collapsed or expanded', async () => {
    details['req-1'] = twoStepDetail('req-1');
    renderPanel(['ai.agents.read']);
    await screen.findByText('action req-1');

    expect(screen.queryByRole('button', { name: /approve/i })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /reject/i })).not.toBeInTheDocument();

    fireEvent.click(screen.getByTitle('Expand'));
    await screen.findByText('Step 1: SRE review');
    expect(screen.queryByRole('button', { name: /approve/i })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /reject/i })).not.toBeInTheDocument();
  });

  it('reads nothing and subscribes to nothing without ai.agents.read, and says why', async () => {
    renderPanel([]);

    expect(screen.getByText(/Viewing the approval queue needs/)).toBeInTheDocument();
    await act(async () => {
      await Promise.resolve();
    });
    expect(mockGet).not.toHaveBeenCalled();
    expect(subscriptions).toHaveLength(0);
  });

  it('hides the buttons once the chain says this viewer cannot decide the current step', async () => {
    details['req-1'] = twoStepDetail('req-1', 1, { current_step_can_approve: false });
    renderPanel();
    await screen.findByText('action req-1');
    // Collapsed, nothing has said otherwise yet: the permission alone decides.
    expect(screen.getAllByRole('button', { name: /approve/i })).toHaveLength(1);

    fireEvent.click(screen.getByTitle('Expand'));

    expect(await screen.findByText(/not an approver on the current step/)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /approve/i })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /reject/i })).not.toBeInTheDocument();
  });

  it("re-reads an expanded chain on a push naming ITS request, and not on another request's (C3b1 F1)", async () => {
    listRows = [row('req-1', { current_step: 1, total_steps: 2 }), row('req-2')];
    details['req-1'] = twoStepDetail('req-1');
    renderPanel();
    await screen.findByText('action req-1');
    fireEvent.click(screen.getAllByTitle('Expand')[0]);
    await screen.findByText('1 of 2 approvals');
    const readsAfterExpand = detailReads('req-1');

    // A push about ANOTHER request refetches the list, not this chain.
    const listBefore = listReads();
    deliver(approvalPush('req-2'));
    await waitFor(() => expect(listReads()).toBeGreaterThan(listBefore));
    expect(detailReads('req-1')).toBe(readsAfterExpand);

    // A push about THIS request re-reads its chain.
    details['req-1'] = twoStepDetail('req-1', 2);
    deliver(approvalPush('req-1'));
    await waitFor(() => expect(detailReads('req-1')).toBe(readsAfterExpand + 1));
    expect(await screen.findByText('2 of 2 approvals')).toBeInTheDocument();
  });

  it("re-reads an expanded chain after the viewer's own decision inside a multi-approval step", async () => {
    listRows = [row('req-1', { current_step: 1, total_steps: 2 })];
    details['req-1'] = twoStepDetail('req-1');
    // An approval that does not finish the step: the row stays pending at the
    // same step, so nothing on the list changes.
    mockPost.mockResolvedValue({ data: { data: twoStepDetail('req-1', 2) } });
    renderPanel();
    await screen.findByText('action req-1');
    fireEvent.click(screen.getByTitle('Expand'));
    await screen.findByText('1 of 2 approvals');
    const before = detailReads('req-1');

    details['req-1'] = twoStepDetail('req-1', 2);
    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: /approve/i }));
    });

    await waitFor(() => expect(detailReads('req-1')).toBeGreaterThan(before));
    expect(await screen.findByText('2 of 2 approvals')).toBeInTheDocument();
  });
});
