import React from 'react';
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { renderWithProviders } from '@/test-utils';
import { ApprovalQueuePanel } from './ApprovalQueuePanel';

// An agent asked for a promotion grant. The card shows the binding first (a
// session- or run-bound grant works only through that target) and the exact
// terms approving it would issue in the approver's name.

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

const GRANT_ROW = {
  id: 'req-s',
  request_id: 'req-s',
  action_category: 'promotion_grant_issue',
  source_type: 'Ai::PromotionGrantRequest',
  status: 'pending',
  description: 'Claude Code #1 asks for a release.promote grant into ops (bound to session sess-1)',
  request_data: { action_category: 'promotion_grant_issue' },
  created_at: '2026-10-23T00:00:00Z',
  current_step_can_approve: true,
  requires_human_session: true,
  change_card: null,
  grant_request: {
    id: 'pgr-1',
    status: 'pending',
    agent: { id: 'agent-1', name: 'Claude Code #1' },
    action_category: 'release.promote',
    environment: { id: 'env-ops', slug: 'ops', name: 'Ops', is_protected: true },
    module_ids: ['mod-a', 'mod-b'],
    max_uses: 2,
    expires_in_hours: 3,
    reason: 'ship the release train',
    granter_driven_only: false,
    binding: { kind: 'mcp_session', id: 'sess-1', description: 'bound to session sess-1', live: true },
    promotion_grant_id: null,
    refusal_reason: null,
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

describe('ApprovalQueuePanel promotion grant request', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (usePolling as jest.Mock).mockImplementation(() => undefined);
    serve(GRANT_ROW);
  });

  it('says what the grant is bound to on the collapsed row', async () => {
    renderPanel();
    expect(await screen.findByText('bound to session sess-1')).toBeInTheDocument();
  });

  it('shows the binding and the exact terms once expanded', async () => {
    const user = userEvent.setup();
    renderPanel();

    await user.click(await screen.findByText('promotion_grant_issue'));

    expect(await screen.findByText('The grant you would issue, in your name')).toBeInTheDocument();
    const card = document.querySelector('[data-grant-request-card]') as HTMLElement;
    expect(card.querySelector('[data-grant-binding]')).toHaveTextContent('bound to session sess-1');
    expect(card.querySelector('[data-grant-modules]')).toHaveTextContent('mod-a, mod-b');
    expect(card).toHaveTextContent('release.promote');
    expect(card).toHaveTextContent('ops');
    expect(card).toHaveTextContent('3 h from your approval');
    expect(card).toHaveTextContent('ship the release train');
  });

  it('says an unbound grant is unbound', async () => {
    serve({
      ...GRANT_ROW,
      grant_request: { ...GRANT_ROW.grant_request, binding: { kind: null, id: null, description: 'unbound', live: false } },
    });
    const user = userEvent.setup();
    renderPanel();

    await user.click(await screen.findByText('promotion_grant_issue'));

    const binding = (await screen.findByText('The grant you would issue, in your name'))
      .parentElement?.querySelector('[data-grant-binding]');
    expect(binding).toHaveTextContent('unbound');
    expect(binding).not.toHaveTextContent('ended');
  });

  it('warns when the bound session has ended', async () => {
    serve({
      ...GRANT_ROW,
      grant_request: { ...GRANT_ROW.grant_request, binding: { ...GRANT_ROW.grant_request.binding, live: false } },
    });
    const user = userEvent.setup();
    renderPanel();

    await user.click(await screen.findByText('promotion_grant_issue'));

    expect(await screen.findByText('(ended: approving issues nothing)')).toBeInTheDocument();
  });
});
