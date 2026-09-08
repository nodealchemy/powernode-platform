import React from 'react';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ApprovalQueuePanel } from './ApprovalQueuePanel';

// IMP-246994888a1f — approving a parked operation that minted secret material
// is the ONE moment the plaintext exists on this surface: the server empties
// its one-shot slot with the read that produced the approve response, and
// everything else about the row is redacted. A client that drops the payload
// destroys the secret. These examples pin the whole one-shot contract: shown
// once, copyable, never persisted, never logged, and never carried anywhere
// else.

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

const PENDING_ROW = {
  id: 'req-1',
  request_id: 'req-1',
  action_type: 'system.disk_image_webhook_rotate_secret',
  status: 'pending',
  description: 'Rotate secret for disk image webhook',
  request_data: { webhook_id: 'wh-1' },
  created_at: '2026-09-08T00:00:00Z',
};

const SECRET = 'whsec_zz_test_only_not_a_real_secret';
const URL_FIELD = 'https://example.invalid/hooks/wh-1';

const approveResponse = (revealed?: Record<string, unknown>) => ({
  data: {
    data: {
      ...PENDING_ROW,
      status: 'approved',
      completed_at: '2026-09-08T00:01:00Z',
      ...(revealed ? { revealed_result: revealed } : {}),
    },
  },
});

const renderPanel = () => {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });
  return {
    queryClient,
    ...render(
      <QueryClientProvider client={queryClient}>
        <ApprovalQueuePanel />
      </QueryClientProvider>
    ),
  };
};

const approveFirstRow = async (user: ReturnType<typeof userEvent.setup>) => {
  const approveButtons = await screen.findAllByRole('button', { name: /approve/i });
  await user.click(approveButtons[0]);
};

describe('ApprovalQueuePanel one-shot revealed_result', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockGet.mockResolvedValue({ data: { data: [PENDING_ROW] } });
  });

  it('reveals the approve response revealed_result exactly once, with a copy affordance', async () => {
    const user = userEvent.setup();
    mockPost.mockResolvedValue(
      approveResponse({ secret_plaintext: SECRET, webhook_url: URL_FIELD })
    );

    renderPanel();
    await approveFirstRow(user);

    const reveal = await screen.findByTestId('one-shot-reveal');
    expect(within(reveal).getByText(SECRET)).toBeInTheDocument();
    expect(within(reveal).getByText(URL_FIELD)).toBeInTheDocument();

    // userEvent.setup() installs the clipboard stub this reads back.
    await user.click(within(reveal).getByTestId('one-shot-copy-secret_plaintext'));
    await waitFor(async () => {
      expect(await navigator.clipboard.readText()).toBe(SECRET);
    });
  });

  it('keeps the reveal open once the approved row leaves the pending queue', async () => {
    const user = userEvent.setup();
    mockPost.mockResolvedValue(approveResponse({ secret_plaintext: SECRET }));
    // The approve invalidates the queue and the row is no longer pending, so
    // the card that owned the mutation unmounts. The reveal must outlive it.
    mockGet
      .mockResolvedValueOnce({ data: { data: [PENDING_ROW] } })
      .mockResolvedValue({ data: { data: [] } });

    renderPanel();
    await approveFirstRow(user);
    await screen.findByTestId('one-shot-reveal');

    await waitFor(() => expect(screen.getByText(/no pending approvals/i)).toBeInTheDocument());

    expect(screen.getByTestId('one-shot-reveal')).toBeInTheDocument();
    expect(screen.getByText(SECRET)).toBeInTheDocument();
  });

  it('cannot be dismissed until the operator acknowledges, and the value is gone afterwards', async () => {
    const user = userEvent.setup();
    mockPost.mockResolvedValue(approveResponse({ secret_plaintext: SECRET }));

    renderPanel();
    await approveFirstRow(user);
    const reveal = await screen.findByTestId('one-shot-reveal');

    // Done lives in the modal footer, outside the reveal body.
    const done = screen.getByRole('button', { name: /done/i });
    expect(done).toBeDisabled();

    // Escape must not be an exit: it would discard an unrecoverable secret.
    await user.keyboard('{Escape}');
    expect(screen.getByTestId('one-shot-reveal')).toBeInTheDocument();

    await user.click(within(reveal).getByRole('checkbox'));
    expect(done).toBeEnabled();
    await user.click(done);

    await waitFor(() => expect(screen.queryByTestId('one-shot-reveal')).not.toBeInTheDocument());
    expect(screen.queryByText(SECRET)).not.toBeInTheDocument();
  });

  it('never writes the revealed value to browser storage, a cache, or a log', async () => {
    const user = userEvent.setup();
    const setLocal = jest.spyOn(Storage.prototype, 'setItem');
    const spies = (['log', 'info', 'warn', 'error', 'debug'] as const).map((level) =>
      jest.spyOn(console, level).mockImplementation(() => {})
    );
    mockPost.mockResolvedValue(approveResponse({ secret_plaintext: SECRET }));

    const { queryClient } = renderPanel();
    await approveFirstRow(user);
    await screen.findByTestId('one-shot-reveal');

    // react-query would otherwise hold the plaintext in the approve mutation's
    // state (and in the queue cache, if the response were written there) long
    // after the reveal is closed.
    // The presence guard matters: an empty mutation cache would make the
    // absence assertion below pass without proving anything.
    expect(queryClient.getMutationCache().getAll()).toHaveLength(1);
    const cached = JSON.stringify([
      queryClient.getQueryCache().getAll().map((q) => q.state.data),
      queryClient.getMutationCache().getAll().map((m) => m.state),
    ]);
    expect(cached).not.toContain(SECRET);

    const stored = setLocal.mock.calls.map((call) => String(call[1])).join('|');
    expect(stored).not.toContain(SECRET);
    spies.forEach((spy) => {
      const logged = spy.mock.calls.map((call) => JSON.stringify(call)).join('|');
      expect(logged).not.toContain(SECRET);
    });

    setLocal.mockRestore();
    spies.forEach((spy) => spy.mockRestore());
  });

  it('sends the revealed value nowhere: approve is the only request made', async () => {
    const user = userEvent.setup();
    mockPost.mockResolvedValue(approveResponse({ secret_plaintext: SECRET }));

    renderPanel();
    await approveFirstRow(user);
    await screen.findByTestId('one-shot-reveal');

    expect(mockPost).toHaveBeenCalledTimes(1);
    expect(mockPost).toHaveBeenCalledWith('/ai/autonomy/approvals/req-1/approve', { comments: undefined });
  });

  it('shows no reveal when the one-shot slot came back empty', async () => {
    const user = userEvent.setup();
    mockPost.mockResolvedValue(approveResponse({}));

    renderPanel();
    await approveFirstRow(user);

    // The invalidation refetch can only happen after the approve settled, so
    // this is an oracle for "the response was processed", where a bare
    // toHaveBeenCalled() on the POST is satisfied inside mutate() itself.
    await waitFor(() => expect(mockGet).toHaveBeenCalledTimes(2));
    expect(screen.queryByTestId('one-shot-reveal')).not.toBeInTheDocument();
  });

  it('shows no reveal when the one-shot slot is not an object of fields', async () => {
    const user = userEvent.setup();
    mockPost.mockResolvedValue(approveResponse(SECRET as unknown as Record<string, unknown>));

    renderPanel();
    await approveFirstRow(user);

    await waitFor(() => expect(mockGet).toHaveBeenCalledTimes(2));
    expect(screen.queryByTestId('one-shot-reveal')).not.toBeInTheDocument();
    expect(screen.queryByText(SECRET)).not.toBeInTheDocument();
  });

  it('shows no reveal when every field in the slot is empty', async () => {
    const user = userEvent.setup();
    mockPost.mockResolvedValue(approveResponse({ secret_plaintext: '', webhook_url: null }));

    renderPanel();
    await approveFirstRow(user);

    // A dialog with no fields still has to be acknowledged to escape, so an
    // empty slot must not open one.
    await waitFor(() => expect(mockGet).toHaveBeenCalledTimes(2));
    expect(screen.queryByTestId('one-shot-reveal')).not.toBeInTheDocument();
  });

  it('shows no reveal when the approve response carries no one-shot slot', async () => {
    const user = userEvent.setup();
    mockPost.mockResolvedValue(approveResponse());

    renderPanel();
    await approveFirstRow(user);

    await waitFor(() => expect(mockGet).toHaveBeenCalledTimes(2));
    expect(screen.queryByTestId('one-shot-reveal')).not.toBeInTheDocument();
  });

  it('queues a second reveal instead of overwriting an unacknowledged one', async () => {
    const user = userEvent.setup();
    const SECOND = 'whsec_zz_second_row_not_a_real_secret';
    mockGet.mockResolvedValue({
      data: { data: [PENDING_ROW, { ...PENDING_ROW, id: 'req-2', request_id: 'req-2' }] },
    });
    mockPost.mockImplementation((url: string) =>
      Promise.resolve(
        approveResponse({ secret_plaintext: url.includes('req-2') ? SECOND : SECRET })
      )
    );

    renderPanel();
    const approveButtons = await screen.findAllByRole('button', { name: /approve/i });
    await user.click(approveButtons[0]);
    await user.click(approveButtons[1]);

    // Both approvals minted material. Overwriting one slot with the other
    // would destroy a secret the operator has not saved.
    const first = await screen.findByTestId('one-shot-reveal');
    expect(within(first).getByText(SECRET)).toBeInTheDocument();

    await user.click(within(first).getByRole('checkbox'));
    await user.click(screen.getByRole('button', { name: /done/i }));

    await waitFor(() => expect(screen.getByText(SECOND)).toBeInTheDocument());
    expect(screen.getByTestId('one-shot-reveal')).toBeInTheDocument();
  });

  it('keeps keyboard focus inside the reveal, which has no other exit', async () => {
    const user = userEvent.setup();
    mockPost.mockResolvedValue(approveResponse({ secret_plaintext: SECRET }));

    renderPanel();
    await approveFirstRow(user);
    const reveal = await screen.findByTestId('one-shot-reveal');
    const dialog = reveal.closest('[role="dialog"]') as HTMLElement;

    // Tabbing out would put Enter on another row's Approve, whose reveal would
    // then be queued behind an unsaved one — and the operator cannot see it.
    for (let i = 0; i < 10; i += 1) {
      await user.tab();
      expect(dialog.contains(document.activeElement)).toBe(true);
    }
  });

  it('says the copy failed instead of showing a success tick', async () => {
    const user = userEvent.setup();
    mockPost.mockResolvedValue(approveResponse({ secret_plaintext: SECRET }));

    renderPanel();
    await approveFirstRow(user);
    const reveal = await screen.findByTestId('one-shot-reveal');

    jest.spyOn(navigator.clipboard, 'writeText').mockRejectedValue(new Error('denied'));
    await user.click(within(reveal).getByTestId('one-shot-copy-secret_plaintext'));

    // A silent no-op would tell the operator they had saved an unrecoverable
    // value they had not.
    await screen.findByTestId('one-shot-copy-failed-secret_plaintext');
    expect(screen.getByText(SECRET)).toBeInTheDocument();
  });
});
