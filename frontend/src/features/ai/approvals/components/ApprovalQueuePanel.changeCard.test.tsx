import React from 'react';
import { screen, waitFor } from '@testing-library/react';
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

  it('decides from the expanded card and says the card was shown', async () => {
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
      })
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
  describe('presented values', () => {
    const PRESENTED = [
      { value: '11111111-1111-4111-8111-111111111111', label: 'dev-cell-tools', detail: 'owner account: Acme Fleet' },
      { value: '22222222-2222-4222-8222-222222222222', label: '(unknown)', detail: null },
    ];

    it('lists each id with its name and owner beside it, and keeps the raw value', async () => {
      serve({
        ...CARD_ROW,
        change_card: { ...CARD_ROW.change_card, new_value: '["11111111-1111-4111-8111-111111111111"]', presented_new_value: PRESENTED },
      });
      const user = userEvent.setup();
      renderPanel();

      await user.click(await screen.findByText('platform.site_setting.protected_write'));

      expect(await screen.findByText('Exactly what you are approving')).toBeInTheDocument();
      expect(document.querySelector('[data-change-new-value]')).toHaveTextContent('11111111-1111-4111-8111-111111111111');
      const rows = document.querySelectorAll('[data-presented-new-value] [data-presented-row]');
      expect(rows).toHaveLength(2);
      expect(rows[0]).toHaveTextContent('11111111-1111-4111-8111-111111111111');
      expect(rows[0]).toHaveTextContent('dev-cell-tools');
      expect(rows[0]).toHaveTextContent('owner account: Acme Fleet');
      expect(rows[1]).toHaveTextContent('22222222-2222-4222-8222-222222222222');
      expect(rows[1]).toHaveTextContent('(unknown)');
    });

    it('renders a hostile name as text, never as markup', async () => {
      serve({
        ...CARD_ROW,
        change_card: {
          ...CARD_ROW.change_card,
          presented_new_value: [{ value: PRESENTED[0].value, label: '<img src=x onerror=alert(1)>', detail: '<b>boss</b>' }],
        },
      });
      const user = userEvent.setup();
      renderPanel();

      await user.click(await screen.findByText('platform.site_setting.protected_write'));

      const row = await waitFor(() => {
        const found = document.querySelector('[data-presented-new-value] [data-presented-row]');
        expect(found).not.toBeNull();
        return found as Element;
      });
      expect(row).toHaveTextContent('<img src=x onerror=alert(1)>');
      expect(row.querySelector('img')).toBeNull();
      expect(row.querySelector('b')).toBeNull();
      expect(row).toHaveTextContent(PRESENTED[0].value);
    });

    it('shows no presented list when the card carries none, only the raw value', async () => {
      const user = userEvent.setup();
      renderPanel();

      await user.click(await screen.findByText('platform.site_setting.protected_write'));

      expect(await screen.findByText('Exactly what you are approving')).toBeInTheDocument();
      expect(document.querySelector('[data-presented-new-value]')).toBeNull();
      expect(document.querySelector('[data-presented-current-value]')).toBeNull();
    });

    it('lists the current value the same way', async () => {
      serve({ ...CARD_ROW, change_card: { ...CARD_ROW.change_card, presented_current_value: [PRESENTED[0]] } });
      const user = userEvent.setup();
      renderPanel();

      await user.click(await screen.findByText('platform.site_setting.protected_write'));

      await screen.findByText('Exactly what you are approving');
      expect(document.querySelector('[data-presented-current-value] [data-presented-row]')).toHaveTextContent('dev-cell-tools');
    });
  });
});
