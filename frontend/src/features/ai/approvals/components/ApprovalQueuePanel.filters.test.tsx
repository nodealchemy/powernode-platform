import React from 'react';
import { screen, waitFor, within } from '@testing-library/react';
import { renderWithProviders } from '@/test-utils';
import userEvent from '@testing-library/user-event';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ApprovalQueuePanel } from './ApprovalQueuePanel';

// IMP-2184bd06b98e — the queue was one flat list, oldest first, with no way to
// narrow it: with ~26 mixed items an operator could not find the human-session
// request they had just parked, because it was last. The operator can now
// narrow by category and severity, show only what needs a person, and flip to
// newest first. All four live in the URL (a link to a view is a view), and a
// deep-linked request is never filtered out from under the link that named it.

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

const row = (
  id: string,
  category: string,
  severity: string | undefined,
  createdAt: string,
  extra: Record<string, unknown> = {}
) => ({
  id,
  request_id: id,
  action_type: category,
  action_category: category,
  status: 'pending',
  description: `request ${id}`,
  request_data: { action_category: category, payload: severity ? { signal_severity: severity } : {} },
  created_at: createdAt,
  current_step_can_approve: true,
  ...extra,
});

// Oldest first, which is the order the server sends.
const ROWS = [
  row('r1', 'system.module_assign', 'medium', '2026-09-20T00:00:00Z'),
  row('r2', 'system.instance_replace', 'critical', '2026-09-21T00:00:00Z'),
  row('r3', 'system.module_assign', 'high', '2026-09-22T00:00:00Z'),
  row('r4', 'dev.campaign_propose', 'low', '2026-09-23T00:00:00Z'),
  row('r5', 'release.promote', undefined, '2026-09-24T00:00:00Z'),
  row('r6', 'platform.site_setting.protected_write', 'high', '2026-09-25T00:00:00Z', {
    requires_human_session: true,
  }),
];

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

const shownIds = (container: HTMLElement): string[] =>
  Array.from(container.querySelectorAll('[data-approval-card]')).map(
    (el) => el.getAttribute('data-approval-card') as string
  );

describe('ApprovalQueuePanel filters and order', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    window.history.pushState({}, '', '/app/ai/control/approvals/queue');
    mockGet.mockResolvedValue({ data: { data: ROWS } });
  });

  it('shows everything, oldest first, until the operator narrows it', async () => {
    const { container } = renderPanel();
    await screen.findByLabelText('Category');

    expect(shownIds(container)).toEqual(['r1', 'r2', 'r3', 'r4', 'r5', 'r6']);
  });

  it('narrows by category, and says how many each category holds', async () => {
    const user = userEvent.setup();
    const { container } = renderPanel();
    const category = await screen.findByLabelText('Category');

    expect(within(category).getByRole('option', { name: 'system.module_assign (2)' })).toBeInTheDocument();
    await user.selectOptions(category, 'system.module_assign');

    expect(shownIds(container)).toEqual(['r1', 'r3']);
  });

  it('narrows by severity, with the requests that carry none under their own heading', async () => {
    const user = userEvent.setup();
    const { container } = renderPanel();
    const severity = await screen.findByLabelText('Severity');

    await user.selectOptions(severity, 'high');
    expect(shownIds(container)).toEqual(['r3', 'r6']);

    await user.selectOptions(severity, 'none');
    expect(shownIds(container)).toEqual(['r5']);
  });

  it('shows only what needs a person when asked', async () => {
    const user = userEvent.setup();
    const { container } = renderPanel();

    await user.click(await screen.findByLabelText(/Only what needs a person/));

    expect(shownIds(container)).toEqual(['r6']);
  });

  it('flips to newest first without losing the filters', async () => {
    const user = userEvent.setup();
    const { container } = renderPanel();
    await user.selectOptions(await screen.findByLabelText('Category'), 'system.module_assign');

    await user.selectOptions(screen.getByLabelText('Order'), 'newest');

    expect(shownIds(container)).toEqual(['r3', 'r1']);
  });

  it('keeps the view in the URL, so a link to it is the view', async () => {
    const user = userEvent.setup();
    renderPanel();
    await user.selectOptions(await screen.findByLabelText('Category'), 'system.module_assign');
    await user.selectOptions(screen.getByLabelText('Order'), 'newest');

    const params = new URLSearchParams(window.location.search);
    expect(params.get('category')).toBe('system.module_assign');
    expect(params.get('order')).toBe('newest');
  });

  it('applies the filters a link carries when it mounts', async () => {
    window.history.pushState({}, '', '/app/ai/control/approvals/queue?severity=high&order=newest');
    const { container } = renderPanel();
    await screen.findByLabelText('Severity');

    expect(shownIds(container)).toEqual(['r6', 'r3']);
    expect(screen.getByLabelText('Severity')).toHaveValue('high');
  });

  it('keeps the request a deep link names visible even when the filters would hide it', async () => {
    window.history.pushState({}, '', '/app/ai/control/approvals/queue?request=r4&category=system.module_assign');
    const { container } = renderPanel();
    await screen.findByLabelText('Category');

    expect(shownIds(container)).toEqual(['r1', 'r3', 'r4']);
  });

  it('says so when nothing matches, and one click puts everything back', async () => {
    const user = userEvent.setup();
    const { container } = renderPanel();
    await user.selectOptions(await screen.findByLabelText('Category'), 'release.promote');
    await user.selectOptions(screen.getByLabelText('Severity'), 'critical');

    expect(shownIds(container)).toEqual([]);
    expect(screen.getByText('No approvals match these filters')).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: 'Clear filters' }));

    expect(shownIds(container)).toHaveLength(6);
    expect(window.location.search).not.toContain('category=');
  });

  it('reports how many of the queue the view shows', async () => {
    const user = userEvent.setup();
    renderPanel();
    await user.selectOptions(await screen.findByLabelText('Category'), 'system.module_assign');

    expect(screen.getByText('Showing 2 of 6')).toBeInTheDocument();
  });

  it('removes a stale filter from the URL, so it cannot come back into force when a request of that kind arrives', async () => {
    window.history.pushState({}, '', '/app/ai/control/approvals/queue?category=gone.category&needs_person=1&request=r2');
    renderPanel();
    await screen.findByLabelText('Category');

    await waitFor(() => expect(window.location.search).not.toContain('category='));
    const params = new URLSearchParams(window.location.search);
    expect(params.get('needs_person')).toBe('1');
    expect(params.get('request')).toBe('r2');
  });

  it('keeps the deep link in the URL while a filter changes', async () => {
    window.history.pushState({}, '', '/app/ai/control/approvals/queue?request=r2');
    const user = userEvent.setup();
    renderPanel();
    await user.selectOptions(await screen.findByLabelText('Severity'), 'high');

    const params = new URLSearchParams(window.location.search);
    expect(params.get('request')).toBe('r2');
    expect(params.get('severity')).toBe('high');
  });

  it('shows no count line when only the order changed', async () => {
    const user = userEvent.setup();
    renderPanel();
    await user.selectOptions(await screen.findByLabelText('Order'), 'newest');

    expect(screen.queryByText(/^Showing /)).not.toBeInTheDocument();
  });

  it('drops a filter value that matches nothing in the queue instead of hiding everything', async () => {
    window.history.pushState({}, '', '/app/ai/control/approvals/queue?category=gone.category');
    const { container } = renderPanel();
    await screen.findByLabelText('Category');

    expect(shownIds(container)).toHaveLength(6);
  });
});
