import { render, screen, fireEvent, waitFor, within } from '@testing-library/react';
import { MemoryRouter, Routes, Route, useLocation } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { BudgetsPanel } from './BudgetsPanel';

// ONE Budgets page. It replaces two surfaces over the same rows (Ai::AgentBudget):
// Autonomy's allocation panel (create / edit / delete / transactions, over
// GET /ai/autonomy/budgets) and FinOps' utilization panel (the same active
// agent budgets through /ai/finops/budget_utilization, with entity filters
// that could only ever match agents). One client, one list, filters the data
// supports, and allocate_child exposed for the first time.
//
// Only apiClient and the permission hook are mocked: react-query, routing and
// the panel are real, so the list, the URL filters and the allocate request are
// the real ones.

const mockGet = jest.fn();
const mockPost = jest.fn();
const mockPut = jest.fn();
const mockDelete = jest.fn();

jest.mock('@/shared/services/apiClient', () => ({
  apiClient: {
    get: (...args: unknown[]) => mockGet(...args),
    post: (...args: unknown[]) => mockPost(...args),
    put: (...args: unknown[]) => mockPut(...args),
    delete: (...args: unknown[]) => mockDelete(...args),
  },
}));

jest.mock('@/shared/services/ai/AgentsApiService', () => ({
  agentsApi: {
    getAgents: () =>
      Promise.resolve({ items: [{ id: 'a-new', name: 'New Agent' }, { id: 'a-hot', name: 'Hot Agent' }] }),
  },
}));

let mockPermissions: string[] = [];
jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({ hasPermission: (p: string) => mockPermissions.includes(p) }),
}));

jest.mock('@/shared/components/entity', () => ({
  EntityLink: ({ label }: { label: string }) => <span>{label}</span>,
}));

const budget = (overrides: Record<string, unknown>) => ({
  id: 'b', agent_id: 'a', agent_name: 'Agent', total_budget_cents: 10_000, spent_cents: 0, reserved_cents: 0,
  remaining_cents: 10_000, currency: 'USD', period_type: 'monthly', utilization_percentage: 0, exceeded: false,
  period_start: '2026-09-01T00:00:00Z', period_end: '2099-12-31T00:00:00Z', created_at: '2026-09-01T00:00:00Z',
  ...overrides,
});

// A parent with one child carved out of it, an exceeded weekly budget, and an
// expired one. Server order is created_at desc, so the child arrives FIRST —
// the list must still put it under its parent.
const BUDGETS = [
  budget({ id: 'child', agent_id: 'a-child', agent_name: 'Child Agent', total_budget_cents: 2_500,
           remaining_cents: 2_500, parent_budget_id: 'parent' }),
  budget({ id: 'parent', agent_id: 'a-parent', agent_name: 'Parent Agent', reserved_cents: 2_500,
           remaining_cents: 7_500 }),
  budget({ id: 'hot', agent_id: 'a-hot', agent_name: 'Hot Agent', period_type: 'weekly', spent_cents: 10_000,
           remaining_cents: 0, utilization_percentage: 100, exceeded: true }),
  budget({ id: 'old', agent_id: 'a-old', agent_name: 'Old Agent', period_end: '2020-01-31T00:00:00Z' }),
];

function routeGets(url: string) {
  if (url === '/ai/autonomy/budgets') return Promise.resolve({ data: { success: true, data: BUDGETS } });
  if (url === '/ai/autonomy/stats') {
    return Promise.resolve({
      data: { success: true, data: { budgets: { total_budget_cents: 10_000, total_spent_cents: 9_000 } } },
    });
  }
  return Promise.resolve({ data: { success: true, data: [] } });
}

let currentSearch = '';
const LocationProbe = () => {
  currentSearch = useLocation().search;
  return null;
};

function renderPanel(path = '/app/ai/control/budgets') {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter initialEntries={[path]}>
        <Routes>
          <Route path="/app/ai/control/budgets" element={<><BudgetsPanel /><LocationProbe /></>} />
        </Routes>
      </MemoryRouter>
    </QueryClientProvider>
  );
}

/** Agent names in list order. */
function listedAgents(): string[] {
  return screen.queryAllByTestId('budget-row').map((row) => within(row).getByTestId('budget-agent').textContent || '');
}

function row(agentName: string): HTMLElement {
  const found = screen.getAllByTestId('budget-row').find((r) => within(r).queryByText(agentName));
  if (!found) throw new Error(`no row for ${agentName}`);
  return found;
}

beforeEach(() => {
  mockGet.mockReset();
  mockPost.mockReset();
  mockPut.mockReset();
  mockDelete.mockReset();
  mockGet.mockImplementation(routeGets);
  mockPermissions = ['ai.agents.read', 'ai.autonomy.manage'];
  currentSearch = '';
});

describe('BudgetsPanel — the merged list', () => {
  it('reads every agent budget from the one autonomy budgets endpoint', async () => {
    renderPanel();

    await waitFor(() => expect(listedAgents()).toHaveLength(4));
    expect(mockGet).toHaveBeenCalledWith('/ai/autonomy/budgets');
    expect(mockGet.mock.calls.map(([u]) => u)).not.toContain('/ai/finops/budget_utilization');
  });

  it('nests a child budget directly under the parent it was allocated from', async () => {
    renderPanel();

    await waitFor(() => expect(listedAgents()).toHaveLength(4));
    const order = listedAgents();
    expect(order.indexOf('Child Agent')).toBe(order.indexOf('Parent Agent') + 1);
    expect(within(row('Child Agent')).getByText(/allocated from Parent Agent/i)).toBeInTheDocument();
  });

  it('shows the budget regime', async () => {
    renderPanel();

    await waitFor(() => expect(screen.getByText('Critical')).toBeInTheDocument());
  });
});

describe('BudgetsPanel — filters the data supports, in the URL', () => {
  it('filters by status: exceeded, active and expired', async () => {
    renderPanel('/app/ai/control/budgets?status=exceeded');
    await waitFor(() => expect(listedAgents()).toEqual(['Hot Agent']));

    fireEvent.change(screen.getByLabelText('Status'), { target: { value: 'expired' } });
    expect(listedAgents()).toEqual(['Old Agent']);
    expect(currentSearch).toContain('status=expired');

    fireEvent.change(screen.getByLabelText('Status'), { target: { value: 'active' } });
    expect(listedAgents()).not.toContain('Old Agent');
    expect(listedAgents()).toHaveLength(3);
  });

  it('filters by period type', async () => {
    renderPanel();
    await waitFor(() => expect(listedAgents()).toHaveLength(4));

    fireEvent.change(screen.getByLabelText('Period'), { target: { value: 'weekly' } });

    expect(listedAgents()).toEqual(['Hot Agent']);
    expect(currentSearch).toContain('period=weekly');
  });

  it('filters by agent, from a deep link', async () => {
    renderPanel('/app/ai/control/budgets?agent=a-old');

    await waitFor(() => expect(listedAgents()).toEqual(['Old Agent']));
    expect((screen.getByLabelText('Agent') as HTMLSelectElement).value).toBe('a-old');
  });

  // A child whose parent is filtered out still shows, flat, rather than vanishing.
  it('keeps a matching child when its parent is filtered out', async () => {
    renderPanel('/app/ai/control/budgets?agent=a-child');

    await waitFor(() => expect(listedAgents()).toEqual(['Child Agent']));
  });

  // Every budget is an AGENT budget, so the filters are exactly agent, period
  // and status — no account or team filter, no free-text search.
  it('offers exactly the agent, period and status filters', async () => {
    renderPanel();
    await waitFor(() => expect(listedAgents()).toHaveLength(4));

    const filters = screen.getByRole('group', { name: 'Budget filters' });
    const controls = within(filters).getAllByRole('combobox').map((c) => c.getAttribute('aria-label'));
    expect(controls).toEqual(['Agent', 'Period', 'Status']);
    expect(within(filters).queryAllByRole('textbox')).toHaveLength(0);
    expect(within(filters).queryAllByRole('button')).toHaveLength(0);
    expect(within(filters).queryAllByRole('checkbox')).toHaveLength(0);

    const optionText = (label: string) =>
      within(within(filters).getByLabelText(label)).getAllByRole('option').map((o) => o.textContent);
    expect(optionText('Agent')).toEqual(['All agents', 'Child Agent', 'Hot Agent', 'Old Agent', 'Parent Agent']);
    expect(optionText('Period')).toEqual(['All periods', 'monthly', 'weekly']);
    expect(optionText('Status')).toEqual(['All', 'Active', 'Exceeded', 'Expired']);
  });
});

describe('BudgetsPanel — row detail', () => {
  it('shows the remaining balance on every row, reserved or not', async () => {
    renderPanel();
    await waitFor(() => expect(listedAgents()).toHaveLength(4));

    expect(within(row('Old Agent')).getByText(/Remaining: \$100\.00/)).toBeInTheDocument();
    expect(within(row('Hot Agent')).getByText(/Remaining: \$0\.00/)).toBeInTheDocument();
    expect(within(row('Parent Agent')).getByText(/Remaining: \$75\.00/)).toBeInTheDocument();
  });

  it('indents each generation one level deeper than its parent', async () => {
    const tree = [
      budget({ id: 'grand', agent_id: 'a-grand', agent_name: 'Grand Agent', parent_budget_id: 'child' }),
      budget({ id: 'child', agent_id: 'a-child', agent_name: 'Child Agent', parent_budget_id: 'root' }),
      budget({ id: 'root', agent_id: 'a-root', agent_name: 'Root Agent' }),
    ];
    mockGet.mockImplementation((url: string) =>
      url === '/ai/autonomy/budgets' ? Promise.resolve({ data: { success: true, data: tree } }) : routeGets(url));
    renderPanel();

    await waitFor(() => expect(listedAgents()).toEqual(['Root Agent', 'Child Agent', 'Grand Agent']));
    expect(screen.getAllByTestId('budget-row').map((r) => r.getAttribute('data-depth'))).toEqual(['0', '1', '2']);
    expect(row('Grand Agent').style.marginLeft).not.toBe(row('Child Agent').style.marginLeft);
  });
});

describe('BudgetsPanel — allocate to a child agent', () => {
  async function openAllocate(agentName: string) {
    renderPanel();
    await waitFor(() => expect(listedAgents()).toHaveLength(4));
    fireEvent.click(within(row(agentName)).getByRole('button', { name: /allocate/i }));
    await waitFor(() => expect(within(screen.getByLabelText('Child agent')).getByText('New Agent')).toBeInTheDocument());
  }

  it('posts the chosen agent and the amount in cents to allocate_child', async () => {
    mockPost.mockResolvedValue({ data: { success: true, data: budget({ id: 'new-child' }) } });
    await openAllocate('Parent Agent');

    fireEvent.change(screen.getByLabelText('Child agent'), { target: { value: 'a-new' } });
    fireEvent.change(screen.getByLabelText('Amount (USD)'), { target: { value: '12.50' } });
    fireEvent.click(screen.getByRole('button', { name: 'Allocate budget' }));

    await waitFor(() => expect(mockPost).toHaveBeenCalledWith(
      '/ai/autonomy/budgets/parent/allocate_child', { agent_id: 'a-new', amount_cents: 1250 }
    ));
    await waitFor(() => expect(mockGet.mock.calls.filter(([u]) => u === '/ai/autonomy/budgets').length).toBe(2));
  });

  it('refuses an amount above the parent\'s remaining balance without calling the server', async () => {
    await openAllocate('Parent Agent');

    fireEvent.change(screen.getByLabelText('Child agent'), { target: { value: 'a-new' } });
    fireEvent.change(screen.getByLabelText('Amount (USD)'), { target: { value: '80' } });
    fireEvent.click(screen.getByRole('button', { name: 'Allocate budget' }));

    expect(await screen.findByText(/more than the \$75\.00 remaining/i)).toBeInTheDocument();
    expect(mockPost).not.toHaveBeenCalled();
  });

  it('shows the server\'s refusal in the form', async () => {
    mockPost.mockRejectedValue({ response: { data: { error: 'Insufficient budget remaining' } } });
    await openAllocate('Parent Agent');

    fireEvent.change(screen.getByLabelText('Child agent'), { target: { value: 'a-new' } });
    fireEvent.change(screen.getByLabelText('Amount (USD)'), { target: { value: '5' } });
    fireEvent.click(screen.getByRole('button', { name: 'Allocate budget' }));

    expect(await screen.findByText('Insufficient budget remaining')).toBeInTheDocument();
  });
});

describe('BudgetsPanel — delete asks in the app, not the browser', () => {
  let nativeConfirm: jest.SpyInstance;
  beforeEach(() => {
    nativeConfirm = jest.spyOn(window, 'confirm').mockImplementation(() => true);
  });
  afterEach(() => nativeConfirm.mockRestore());

  it('deletes only after the confirmation dialog is accepted', async () => {
    mockDelete.mockResolvedValue({ data: { success: true, data: { deleted: true } } });
    renderPanel();
    await waitFor(() => expect(listedAgents()).toHaveLength(4));

    fireEvent.click(within(row('Old Agent')).getByTitle('Delete budget'));
    expect(await screen.findByText(/delete the budget for Old Agent/i)).toBeInTheDocument();
    expect(mockDelete).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole('button', { name: 'Delete' }));
    await waitFor(() => expect(mockDelete).toHaveBeenCalledWith('/ai/autonomy/budgets/old'));
    expect(nativeConfirm).not.toHaveBeenCalled();
  });

  it('deletes nothing when the dialog is cancelled', async () => {
    renderPanel();
    await waitFor(() => expect(listedAgents()).toHaveLength(4));

    fireEvent.click(within(row('Old Agent')).getByTitle('Delete budget'));
    fireEvent.click(await screen.findByRole('button', { name: 'Cancel' }));

    await waitFor(() => expect(screen.queryByText(/delete the budget for Old Agent/i)).not.toBeInTheDocument());
    expect(mockDelete).not.toHaveBeenCalled();
    expect(nativeConfirm).not.toHaveBeenCalled();
  });
});

describe('BudgetsPanel — allocating from a non-USD budget', () => {
  it('labels the amount in the parent budget\'s currency', async () => {
    mockGet.mockImplementation((url: string) =>
      url === '/ai/autonomy/budgets'
        ? Promise.resolve({ data: { success: true, data: [budget({ id: 'eur', agent_name: 'Euro Agent', currency: 'EUR' })] } })
        : routeGets(url));
    renderPanel();
    await waitFor(() => expect(listedAgents()).toEqual(['Euro Agent']));

    fireEvent.click(within(row('Euro Agent')).getByRole('button', { name: /allocate/i }));

    expect(screen.getByLabelText('Amount (EUR)')).toBeInTheDocument();
    expect(screen.queryByLabelText('Amount (USD)')).not.toBeInTheDocument();
  });
});

describe('BudgetsPanel — gated on what the endpoints check', () => {
  it('shows the list but no write controls without ai.autonomy.manage', async () => {
    mockPermissions = ['ai.agents.read'];
    renderPanel();

    await waitFor(() => expect(listedAgents()).toHaveLength(4));
    expect(screen.queryByRole('button', { name: /create budget/i })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /allocate/i })).not.toBeInTheDocument();
    expect(screen.queryByTitle('Edit budget')).not.toBeInTheDocument();
    expect(screen.queryByTitle('Delete budget')).not.toBeInTheDocument();
  });

  it('shows the write controls with ai.autonomy.manage', async () => {
    renderPanel();

    await waitFor(() => expect(listedAgents()).toHaveLength(4));
    expect(screen.getByRole('button', { name: /create budget/i })).toBeInTheDocument();
    expect(within(row('Parent Agent')).getByTitle('Edit budget')).toBeInTheDocument();
  });
});
