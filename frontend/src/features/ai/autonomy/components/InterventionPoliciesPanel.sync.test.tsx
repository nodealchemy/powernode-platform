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

function routeGets(url: string, ..._rest: unknown[]) {
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

describe('InterventionPoliciesPanel — "All policies" is the whole set', () => {
  // More rows than the index's old default page of 50. The list must show every
  // one, and must not ask the server for a page.
  it('lists every row the account has, past fifty', async () => {
    const many = Array.from({ length: 60 }, (_, i) => ({ ...row(), id: `p${i}`, agent: null }));
    mockGet.mockImplementation((url: string, ...rest: unknown[]) =>
      url === '/ai/intervention_policies'
        ? Promise.resolve({ data: { success: true, data: { policies: many, total_count: 60 } } })
        : routeGets(url, ...rest)
    );
    renderPanel();

    await waitFor(() => expect(listCount('require approval')).toBe('60'));
    expect(within(listPane()).getAllByText('dev.task_requeue')).toHaveLength(60);
    const listCalls = mockGet.mock.calls.filter(([u]) => u === '/ai/intervention_policies');
    expect(listCalls.every((call) => call.length === 1)).toBe(true);
  });
});

describe('InterventionPoliciesPanel — a list write never drops unsaved grouped edits', () => {
  function groupedSelect(): HTMLSelectElement {
    return screen.getByText('dev.task_requeue', { selector: 'span.truncate' })
      .closest('div')?.querySelector('select') as HTMLSelectElement;
  }

  async function stageGroupedEditThenWriteInList() {
    renderPanel();
    await waitFor(() => expect(listCount('require approval')).toBe('1'));
    await waitFor(() => expect(gets('/ai/intervention_policies/grouped')).toBe(1));

    fireEvent.change(groupedSelect(), { target: { value: 'block' } });
    fireEvent.click(within(listPane()).getByTitle('Disable'));
    await waitFor(() => expect(mockPut).toHaveBeenCalled());
  }

  it('keeps the staged edit and says a refresh is waiting, instead of refetching', async () => {
    await stageGroupedEditThenWriteInList();

    await waitFor(() => expect(screen.getByTestId('policy-refresh-deferred')).toBeInTheDocument());
    expect(gets('/ai/intervention_policies/grouped')).toBe(1);
    expect(groupedSelect().value).toBe('block');
  });

  it('saves the staged edit, then applies the waiting refresh', async () => {
    await stageGroupedEditThenWriteInList();
    await waitFor(() => expect(screen.getByTestId('policy-refresh-deferred')).toBeInTheDocument());

    fireEvent.click(screen.getByText('Save Permissions'));

    await waitFor(() => expect(mockPatch).toHaveBeenCalledTimes(1));
    expect(mockPatch.mock.calls[0][1]).toEqual({
      updates: [{ action_category: 'dev.task_requeue', policy: 'block', scope: 'global', agent_id: null }],
    });
    await waitFor(() => expect(gets('/ai/intervention_policies/grouped')).toBe(2));
    expect(screen.queryByTestId('policy-refresh-deferred')).not.toBeInTheDocument();
  });

  it('discards the staged edit only when the operator chooses to', async () => {
    await stageGroupedEditThenWriteInList();
    await waitFor(() => expect(screen.getByTestId('policy-refresh-deferred')).toBeInTheDocument());

    fireEvent.click(screen.getByRole('button', { name: /discard my edits and refresh/i }));

    await waitFor(() => expect(gets('/ai/intervention_policies/grouped')).toBe(2));
    await waitFor(() => expect(groupedSelect().value).toBe('require_approval'));
    expect(mockPatch).not.toHaveBeenCalled();
    expect(screen.queryByTestId('policy-refresh-deferred')).not.toBeInTheDocument();
  });
});

