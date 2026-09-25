import React from 'react';
import { renderHook, waitFor, act } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useAutonomyStats } from '@/features/ai/autonomy/api/autonomyApi';
import { useAgentBudgets, useAllocateChildBudget, useCreateBudget, useDeleteBudget, useUpdateBudget } from './budgetsApi';

// A budget write changes the account's budget totals, which the budget regime
// (Budgets page, Autonomy, dashboard) reads from /ai/autonomy/stats. Every
// write must therefore refetch the stats as well as the budget list. The
// query layer is real; only apiClient is mocked, and the refetch is observed
// as a second GET — not as a call on a spied queryClient.

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

jest.mock('@/shared/services/ai/AgentsApiService', () => ({ agentsApi: { getAgents: jest.fn() } }));

const ok = (data: unknown) => Promise.resolve({ data: { success: true, data } });
const getsOf = (url: string) => mockGet.mock.calls.filter(([u]) => u === url).length;

function setup() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={client}>{children}</QueryClientProvider>
  );
  return renderHook(
    () => ({
      stats: useAutonomyStats(),
      budgets: useAgentBudgets(),
      create: useCreateBudget(),
      update: useUpdateBudget(),
      remove: useDeleteBudget(),
      allocate: useAllocateChildBudget(),
    }),
    { wrapper }
  );
}

beforeEach(() => {
  mockGet.mockImplementation((url: string) => ok(url === '/ai/autonomy/budgets' ? [] : {}));
  mockPost.mockImplementation(() => ok({}));
  mockPut.mockImplementation(() => ok({}));
  mockDelete.mockImplementation(() => ok({ deleted: true }));
});

describe('budget writes refetch the autonomy stats', () => {
  const writes: Array<[string, (r: ReturnType<typeof setup>['result']['current']) => Promise<unknown>]> = [
    ['create', (r) => r.create.mutateAsync({ agent_id: 'a', total_budget_cents: 100 })],
    ['update', (r) => r.update.mutateAsync({ id: 'b', total_budget_cents: 200 })],
    ['delete', (r) => r.remove.mutateAsync('b')],
    ['allocate_child', (r) => r.allocate.mutateAsync({ budgetId: 'b', agentId: 'c', amountCents: 50 })],
  ];

  it.each(writes)('%s refetches /ai/autonomy/stats and the budget list', async (_name, write) => {
    const { result } = setup();
    await waitFor(() => expect(result.current.stats.isSuccess && result.current.budgets.isSuccess).toBe(true));
    expect(getsOf('/ai/autonomy/stats')).toBe(1);
    expect(getsOf('/ai/autonomy/budgets')).toBe(1);

    await act(async () => { await write(result.current); });

    await waitFor(() => expect(getsOf('/ai/autonomy/stats')).toBe(2));
    await waitFor(() => expect(getsOf('/ai/autonomy/budgets')).toBe(2));
  });
});
