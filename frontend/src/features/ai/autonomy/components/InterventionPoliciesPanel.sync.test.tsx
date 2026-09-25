import { render, screen, fireEvent, waitFor, within } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { InterventionPoliciesPanel } from './InterventionPoliciesPanel';

// The unscoped panel shows the same rows twice: grouped by domain on top, one
// card per row below ("All policies"). The two read different endpoints and
// hold their own state, so a save in either must refresh the other — two panes
// that disagree about the account's posture is the defect this panel exists to
// remove. Only apiClient is mocked; react-query, the hook and both panes are real.

const mockGet = jest.fn();
const mockPatch = jest.fn();
const mockPut = jest.fn();

jest.mock('@/shared/services/apiClient', () => ({
  apiClient: {
    get: (...args: unknown[]) => mockGet(...args),
    patch: (...args: unknown[]) => mockPatch(...args),
    put: (...args: unknown[]) => mockPut(...args),
    post: jest.fn(),
    delete: jest.fn(),
  },
}));

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: jest.fn() }),
}));

jest.mock('@/shared/utils/logger', () => ({
  logger: { error: jest.fn(), warn: jest.fn(), info: jest.fn(), debug: jest.fn() },
}));

// The server's state, which both endpoints read and every write changes.
let serverVerb = 'require_approval';
let serverActive = true;

const row = () => ({
  id: 'p1', action_category: 'dev.task_requeue', scope: 'global', policy: serverVerb, priority: 5,
  is_active: serverActive, agent_id: null, agent_name: null, agent_bucket: 'Manual Operations',
  conditions: {}, preferred_channels: [], created_at: '2026-09-25T00:00:00Z', updated_at: '2026-09-25T00:00:00Z',
});

function routeGets(url: string) {
  if (url === '/ai/intervention_policies/grouped') {
    return Promise.resolve({ data: { success: true, data: { chains: [], policies: { by_domain: { other: [row()] } } } } });
  }
  if (url === '/ai/intervention_policies') {
    return Promise.resolve({ data: { success: true, data: { policies: [{ ...row(), agent: null }], total_count: 1 } } });
  }
  return Promise.resolve({ data: { success: true, data: [] } });
}

function renderPanel() {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={queryClient}>
      <InterventionPoliciesPanel />
    </QueryClientProvider>
  );
}

/** The "All policies" pane: the list below the grouped editor. */
function listPane(): HTMLElement {
  return screen.getByRole('heading', { name: 'All policies' }).parentElement as HTMLElement;
}

/** The count on the list pane's summary card for a verb. */
function listCount(verb: string): string | null {
  const label = within(listPane()).getByText(verb, { selector: 'p' });
  return label.nextElementSibling?.textContent ?? null;
}

function gets(url: string): number {
  return mockGet.mock.calls.filter(([u]) => u === url).length;
}

beforeEach(() => {
  serverVerb = 'require_approval';
  serverActive = true;
  mockGet.mockReset();
  mockPatch.mockReset();
  mockPut.mockReset();
  mockGet.mockImplementation(routeGets);
  mockPatch.mockImplementation((_url: string, body: { updates: Array<{ policy: string }> }) => {
    serverVerb = body.updates[0].policy;
    return Promise.resolve({ data: { success: true, data: { changed: 1 } } });
  });
  mockPut.mockImplementation((_url: string, body: { is_active?: boolean }) => {
    if (body.is_active !== undefined) serverActive = body.is_active;
    return Promise.resolve({ data: { success: true, data: row() } });
  });
});

describe('InterventionPoliciesPanel — the grouped editor and the list agree', () => {
  it('shows a grouped-view save in the list without a reload', async () => {
    renderPanel();
    await waitFor(() => expect(listCount('require approval')).toBe('1'));
    await waitFor(() => expect(screen.getByText('Other policies · Manual Operations')).toBeInTheDocument());

    const select = screen.getByText('dev.task_requeue', { selector: 'span.truncate' })
      .closest('div')?.querySelector('select') as HTMLSelectElement;
    fireEvent.change(select, { target: { value: 'block' } });
    fireEvent.click(screen.getByText('Save Permissions'));

    await waitFor(() => expect(listCount('block')).toBe('1'));
    expect(listCount('require approval')).toBe('0');
  });

  it('refetches the grouped view after a change made in the list', async () => {
    renderPanel();
    await waitFor(() => expect(listCount('require approval')).toBe('1'));
    await waitFor(() => expect(gets('/ai/intervention_policies/grouped')).toBe(1));

    // The list's enable/disable toggle on the row's card.
    fireEvent.click(within(listPane()).getByTitle('Disable'));

    await waitFor(() => expect(mockPut).toHaveBeenCalled());
    await waitFor(() => expect(gets('/ai/intervention_policies/grouped')).toBe(2));
  });
});
