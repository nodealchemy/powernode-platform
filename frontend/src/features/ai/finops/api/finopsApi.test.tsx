import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import React from 'react';
import { useBudgetUtilization } from './finopsApi';

// finopsApi imports the *named* apiClient export; mock that.
const mockGet = jest.fn();
jest.mock('@/shared/services/apiClient', () => ({
  apiClient: {
    get: (...args: unknown[]) => mockGet(...args),
  },
}));

// Backend (finops#budget_utilization, wrapped by render_success) returns an
// OBJECT under response.data.data with the budget rows nested in `agent_budgets`.
const backendResponse = {
  data: {
    data: {
      agent_budgets: [
        {
          agent_id: 'a1',
          agent_name: 'Agent One',
          total_budget_cents: 10000,
          spent_cents: 5000,
          utilization: 50,
          period_type: 'monthly',
          exceeded: false,
        },
      ],
    },
  },
};

const wrapper = ({ children }: { children: React.ReactNode }) => {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  return <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>;
};

describe('useBudgetUtilization adapter', () => {
  beforeEach(() => {
    mockGet.mockReset();
  });

  it('maps the backend agent_budgets object into a BudgetUtilization[] (not the raw object)', async () => {
    mockGet.mockResolvedValue(backendResponse);

    const { result } = renderHook(() => useBudgetUtilization(), { wrapper });

    await waitFor(() => expect(result.current.isSuccess).toBe(true));

    expect(Array.isArray(result.current.data)).toBe(true);
    expect(result.current.data).toEqual([
      {
        id: 'a1',
        name: 'Agent One',
        entity_type: 'agent',
        budget_limit: 100, // 10000 cents → dollars
        current_spend: 50, // 5000 cents → dollars
        utilization_pct: 50,
        period: 'monthly',
        alert_threshold: 80,
        is_over_budget: false,
      },
    ]);
    // projected_spend is intentionally absent (backend computes no projections).
    expect(result.current.data?.[0]).not.toHaveProperty('projected_spend');
  });

  it('filters to [] when a non-agent entity_type is requested (backend has no such budgets)', async () => {
    mockGet.mockResolvedValue(backendResponse);

    const { result } = renderHook(
      () => useBudgetUtilization({ entity_type: 'team' }),
      { wrapper },
    );

    await waitFor(() => expect(result.current.isSuccess).toBe(true));

    expect(result.current.data).toEqual([]);
  });
});
