import React from 'react';
import { act, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { renderWithProviders } from '@/test-utils';
import { ApprovalQueuePanel } from './ApprovalQueuePanel';

// Act-on-behalf: an instance (a machine) asked for a protected change. The card
// shows the exact tool, key, NEW value and CURRENT value from the server's
// change_card, so the person knows what they are confirming.

const mockGet = jest.fn();
const mockPost = jest.fn();

jest.mock('@/shared/services/apiClient', () => ({
  __esModule: true,
  apiClient: {
    get: (...args: unknown[]) => mockGet(...args),
    post: (...args: unknown[]) => mockPost(...args),
  },
}));

jest.mock('@/shared/components/entity', () => ({
  EntityLink: ({ label }: { label: React.ReactNode }) => <span>{label}</span>,
}));

jest.mock('@/shared/hooks/useWebSocket', () => {
  const socket = { isConnected: false, error: null, subscribe: () => () => undefined };
  return { useWebSocket: () => socket };
});
jest.mock('@/shared/hooks/usePolling', () => ({ usePolling: jest.fn() }));
import { usePolling } from '@/shared/hooks/usePolling';
// Mocked so a refused decision's notice can be asserted.
const mockShowNotification = jest.fn();
jest.mock('@/shared/hooks/useNotification', () => ({
  useNotification: () => ({ showNotification: mockShowNotification }),
}));

const CARD_ROW = {
  id: 'req-s',
  request_id: 'req-s',
  action_category: 'platform.site_setting.protected_write',
  source_type: 'Ai::DeferredOperation',
  status: 'pending',
  description: 'site_setting_set_protected via Ai::Tools::SiteSettingTool',
  request_data: { action_category: 'platform.site_setting.protected_write' },
  created_at: '2026-09-29T00:00:00Z',
  current_step_can_approve: true,
  requires_human_session: true,
  change_card: {
    tool: 'site_setting',
    action: 'site_setting_set_protected',
    key: 'ai_approvals_human_session_categories',
    new_value: '["campaign.*"]',
    current_value: '["campaign.*","spend.*"]',
    current_value_set: true,
    // Rendered by the server; the client echoes it on approve and never computes one.
    digest: 'v1:' + 'ab'.repeat(32),
  },
};

const renderPanel = () => {
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
          user: { id: 'u-1', permissions: ['ai.agents.read', 'ai.autonomy.approve'] },
          isAuthenticated: true,
          isLoading: false,
        },
      },
    }
  );
};

const serve = (row: Record<string, unknown>) =>
  mockGet.mockImplementation((url: string) =>
    Promise.resolve(
      String(url).endsWith('/req-s')
        ? { data: { data: { ...row, step_statuses: [], decisions: [] } } }
        : { data: { data: [row] } }
    )
  );

describe('ApprovalQueuePanel change card', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    serve(CARD_ROW);
  });

  it('shows the tool, setting, new value and current value once expanded', async () => {
    const user = userEvent.setup();
    renderPanel();

    await user.click(await screen.findByText('platform.site_setting.protected_write'));

    expect(await screen.findByText('Exactly what you are approving')).toBeInTheDocument();
    expect(screen.getByText('site_setting_set_protected')).toBeInTheDocument();
    expect(screen.getByText('ai_approvals_human_session_categories')).toBeInTheDocument();
    expect(document.querySelector('[data-change-new-value]')).toHaveTextContent('["campaign.*"]');
    expect(document.querySelector('[data-change-current-value]')).toHaveTextContent('["campaign.*","spend.*"]');
  });

  it('says a value the card does not carry is not shown, rather than blank', async () => {
    const { current_value: _hidden, current_value_set: _set, ...withheld } = CARD_ROW.change_card;
    serve({ ...CARD_ROW, change_card: withheld });
    const user = userEvent.setup();
    renderPanel();

    await user.click(await screen.findByText('platform.site_setting.protected_write'));

    expect(await screen.findByText(/Not shown to you/)).toBeInTheDocument();
  });

  it('says an unset setting is unset', async () => {
    serve({ ...CARD_ROW, change_card: { ...CARD_ROW.change_card, current_value: null, current_value_set: false } });
    const user = userEvent.setup();
    renderPanel();

    await user.click(await screen.findByText('platform.site_setting.protected_write'));

    expect(await screen.findByText('Not set')).toBeInTheDocument();
  });

  it('shows no card for a row that has none', async () => {
    serve({ ...CARD_ROW, change_card: null });
    const user = userEvent.setup();
    renderPanel();

    await user.click(await screen.findByText('platform.site_setting.protected_write'));

    expect(await screen.findByText('Approval chain')).toBeInTheDocument();
    expect(document.querySelector('[data-change-card]')).toBeNull();
  });

  it('offers no Approve or Reject on the collapsed row of a request with a change card', async () => {
    renderPanel();

    await screen.findByText('platform.site_setting.protected_write');

    expect(screen.queryByRole('button', { name: /^Approve$/ })).toBeNull();
    expect(screen.queryByRole('button', { name: /^Reject$/ })).toBeNull();
  });

  it('decides from the expanded card, says the card was shown and echoes its digest', async () => {
    mockPost.mockResolvedValue({ data: { data: { id: 'req-s', status: 'approved' } } });
    const user = userEvent.setup();
    renderPanel();

    await user.click(await screen.findByText('platform.site_setting.protected_write'));
    await screen.findByText('Exactly what you are approving');
    await user.click(screen.getByRole('button', { name: /^Approve$/ }));

    await waitFor(() =>
      expect(mockPost).toHaveBeenCalledWith('/ai/autonomy/approvals/req-s/approve', {
        comments: undefined,
        change_card_shown: true,
        change_card_digest: 'v1:' + 'ab'.repeat(32),
      })
    );
  });

  it('sends no digest for a card the server rendered without one, rather than inventing it', async () => {
    mockPost.mockResolvedValue({ data: { data: { id: 'req-s', status: 'approved' } } });
    const { digest: _none, current_value: _hidden, current_value_set: _set, ...withheld } = CARD_ROW.change_card;
    serve({ ...CARD_ROW, change_card: withheld });
    const user = userEvent.setup();
    renderPanel();

    await user.click(await screen.findByText('platform.site_setting.protected_write'));
    await screen.findByText('Exactly what you are approving');
    await user.click(screen.getByRole('button', { name: /^Approve$/ }));

    await waitFor(() =>
      expect(mockPost).toHaveBeenCalledWith('/ai/autonomy/approvals/req-s/approve', {
        comments: undefined,
        change_card_shown: true,
      })
    );
  });

  it('says the request changed since it was viewed when the server refuses a stale digest', async () => {
    mockPost.mockRejectedValue({
      response: { status: 422, data: { error: 'The request changed since you viewed it; review the card again.', code: 'change_card_stale' } },
    });
    const user = userEvent.setup();
    renderPanel();

    await user.click(await screen.findByText('platform.site_setting.protected_write'));
    await screen.findByText('Exactly what you are approving');
    await user.click(screen.getByRole('button', { name: /^Approve$/ }));

    await waitFor(() =>
      expect(mockShowNotification).toHaveBeenCalledWith(
        expect.stringMatching(/changed since you viewed it/),
        'error'
      )
    );
  });

  it('keeps the quick buttons on a row with no card, and sends no card flag', async () => {
    mockPost.mockResolvedValue({ data: { data: { id: 'req-s', status: 'approved' } } });
    serve({ ...CARD_ROW, change_card: null });
    const user = userEvent.setup();
    renderPanel();

    await user.click(await screen.findByRole('button', { name: /^Approve$/ }));

    await waitFor(() =>
      expect(mockPost).toHaveBeenCalledWith('/ai/autonomy/approvals/req-s/approve', { comments: undefined })
    );
  });
  // Fix round (critic B F1/F4): "the card shown" is the card the person
  // REVIEWED. It is pinned when opened; a refetch that brings a different card
  // is not swapped in silently — a notice says so and Approve is held until
  // the person reviews the updated change, after which the NEW digest is sent.
  describe('the pinned card', () => {
    const DIGEST_A = 'v1:' + 'ab'.repeat(32);
    const DIGEST_B = 'v1:' + 'cd'.repeat(32);
    const CHANGED_ROW = {
      ...CARD_ROW,
      change_card: { ...CARD_ROW.change_card, current_value: '["campaign.*","spend.*","deploy.*"]', digest: DIGEST_B },
    };

    // The queue's poll callback, as the panel registered it: calling it is a refetch.
    const refetchQueue = async () => {
      const calls = (usePolling as jest.Mock).mock.calls;
      const refresh = calls[calls.length - 1][0] as () => void;
      await act(async () => {
        refresh();
      });
    };

    const openCard = async () => {
      const user = userEvent.setup();
      renderPanel();
      await user.click(await screen.findByText('platform.site_setting.protected_write'));
      await screen.findByText('Exactly what you are approving');
      return user;
    };

    it('sends the pinned digest when a refetch brings the same card', async () => {
      mockPost.mockResolvedValue({ data: { data: { id: 'req-s', status: 'approved' } } });
      const user = await openCard();

      await refetchQueue();
      await user.click(screen.getByRole('button', { name: /^Approve$/ }));

      await waitFor(() =>
        expect(mockPost).toHaveBeenCalledWith('/ai/autonomy/approvals/req-s/approve', {
          comments: undefined,
          change_card_shown: true,
          change_card_digest: DIGEST_A,
        })
      );
    });

    it('keeps showing the reviewed card, says it changed, and holds Approve until the update is reviewed; then sends the new digest', async () => {
      mockPost.mockResolvedValue({ data: { data: { id: 'req-s', status: 'approved' } } });
      const user = await openCard();

      serve(CHANGED_ROW);
      await refetchQueue();

      expect(await screen.findByText(/changed since you opened it/)).toBeInTheDocument();
      // The values on screen are still the ones the person reviewed.
      expect(document.querySelector('[data-change-current-value]')).toHaveTextContent('["campaign.*","spend.*"]');
      expect(screen.getByRole('button', { name: /^Approve$/ })).toBeDisabled();

      await user.click(screen.getByRole('button', { name: /Review the updated change/ }));

      expect(screen.queryByText(/changed since you opened it/)).toBeNull();
      expect(document.querySelector('[data-change-current-value]')).toHaveTextContent('deploy.*');
      expect(screen.getByRole('button', { name: /^Approve$/ })).toBeEnabled();
      await user.click(screen.getByRole('button', { name: /^Approve$/ }));

      await waitFor(() =>
        expect(mockPost).toHaveBeenCalledWith('/ai/autonomy/approvals/req-s/approve', {
          comments: undefined,
          change_card_shown: true,
          change_card_digest: DIGEST_B,
        })
      );
      expect(mockPost).toHaveBeenCalledTimes(1);
    });

    it('refetches the queue on a stale refusal, so the changed card is shown at once', async () => {
      mockPost.mockRejectedValue({
        response: { status: 422, data: { error: 'The request changed since you viewed it.', code: 'change_card_stale' } },
      });
      const user = await openCard();
      const readsBefore = mockGet.mock.calls.length;

      serve(CHANGED_ROW);
      await user.click(screen.getByRole('button', { name: /^Approve$/ }));

      expect(await screen.findByText(/changed since you opened it/)).toBeInTheDocument();
      expect(mockGet.mock.calls.length).toBeGreaterThan(readsBefore);
      expect(screen.getByRole('button', { name: /^Approve$/ })).toBeDisabled();
    });
  });

  describe('presented values', () => {
    const ID_A = '11111111-1111-4111-8111-111111111111';
    const ID_B = '22222222-2222-4222-8222-222222222222';
    const PRESENTED = {
      items: [
        { raw: ID_A, fields: { name: 'dev-cell-tools', owner: 'Acme Fleet' }, flags: [] },
        { raw: ID_B, fields: {}, flags: ['unknown'] },
      ],
      omitted: 0,
    };

    const open = async (card: Record<string, unknown>) => {
      serve({ ...CARD_ROW, change_card: { ...CARD_ROW.change_card, ...card } });
      const user = userEvent.setup();
      renderPanel();
      await user.click(await screen.findByText('platform.site_setting.protected_write'));
      await screen.findByText('Exactly what you are approving');
    };

    it('lists each id first and complete, with its fields in their own labelled elements, and keeps the raw value', async () => {
      await open({ new_value: `["${ID_A}"]`, presented_new_value: PRESENTED });

      expect(document.querySelector('[data-change-new-value]')).toHaveTextContent(ID_A);
      const rows = document.querySelectorAll('[data-presented-new-value] [data-presented-row]');
      expect(rows).toHaveLength(2);
      expect(rows[0].querySelector('[data-presented-raw]')).toHaveTextContent(ID_A);
      expect(rows[0].firstElementChild).toBe(rows[0].querySelector('[data-presented-raw]'));
      expect(rows[0].querySelector('[data-presented-field="name"]')).toHaveTextContent('dev-cell-tools');
      expect(rows[0].querySelector('[data-presented-field="owner"]')).toHaveTextContent('Acme Fleet');
      expect(rows[0]).toHaveTextContent('Owner account:');
      expect(rows[0].querySelector('[data-presented-flag]')).toBeNull();
    });

    it('shows server-computed flags as fixed text, never from a field', async () => {
      await open({
        presented_new_value: {
          items: [
            { raw: ID_A, fields: { name: '(unknown)' }, flags: ['other_account'] },
            { raw: ID_B, fields: {}, flags: ['unknown'] },
          ],
          omitted: 0,
        },
      });

      const rows = document.querySelectorAll('[data-presented-new-value] [data-presented-row]');
      expect(rows[0].querySelector('[data-presented-flag="other_account"]')).toHaveTextContent('Another account');
      expect(rows[0].querySelector('[data-presented-flag="unknown"]')).toBeNull();
      expect(rows[1].querySelector('[data-presented-flag="unknown"]')).toHaveTextContent(/Not found/);
    });

    it('renders a hostile name as text in its own field: no markup, no extra row, no extra badge', async () => {
      const hostile = '<img src=x onerror=alert(1)> "quoted" (Owner account: Mine) 33333333-3333-4333-8333-333333333333';
      await open({ presented_new_value: { items: [{ raw: ID_A, fields: { name: hostile }, flags: [] }], omitted: 0 } });

      const rows = document.querySelectorAll('[data-presented-new-value] [data-presented-row]');
      expect(rows).toHaveLength(1);
      const field = rows[0].querySelector('[data-presented-field="name"]') as Element;
      expect(field).toHaveTextContent(hostile);
      expect(rows[0].querySelector('img')).toBeNull();
      expect(rows[0].querySelectorAll('[data-presented-field]')).toHaveLength(1);
      expect(rows[0].querySelector('[data-presented-flag]')).toBeNull();
      expect(rows[0].querySelector('[data-presented-raw]')).toHaveTextContent(ID_A);
    });

    it('says how many entries are shown raw only', async () => {
      await open({ presented_new_value: { items: PRESENTED.items, omitted: 7 } });

      expect(document.querySelector('[data-presented-omitted]')).toHaveTextContent('+7 more (raw value only)');
    });

    it('shows no presented list when the card carries none, only the raw value', async () => {
      await open({});

      expect(document.querySelector('[data-presented-new-value]')).toBeNull();
      expect(document.querySelector('[data-presented-current-value]')).toBeNull();
    });

    it('lists the current value the same way', async () => {
      await open({ presented_current_value: { items: [PRESENTED.items[0]], omitted: 0 } });

      expect(document.querySelector('[data-presented-current-value] [data-presented-field="name"]')).toHaveTextContent('dev-cell-tools');
    });
  });
});
