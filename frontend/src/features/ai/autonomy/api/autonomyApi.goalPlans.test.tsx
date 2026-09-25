import React from 'react';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { apiClient } from '@/shared/services/apiClient';
import { useGoalPlans, useGoalPlan } from './autonomyApi';

jest.mock('@/shared/services/apiClient', () => ({
  apiClient: { get: jest.fn(), post: jest.fn(), put: jest.fn(), delete: jest.fn(), patch: jest.fn() },
}));

const mockGet = apiClient.get as jest.Mock;

const wrapper = ({ children }: { children: React.ReactNode }) => {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return <QueryClientProvider client={client}>{children}</QueryClientProvider>;
};

// fc-39: the /ai/goals family has one client. The goal-plan reads moved here
// from IntelligenceApiService; fixtures are the real { success, data } envelope.
describe('autonomyApi goal plans', () => {
  beforeEach(() => mockGet.mockReset());

  it('useGoalPlans lists a goal\'s plans, unwrapped', async () => {
    mockGet.mockResolvedValue({ data: { success: true, data: { plans: [{ id: 'p1', version: 1 }] } } });

    const { result } = renderHook(() => useGoalPlans('g1'), { wrapper });

    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(mockGet).toHaveBeenCalledWith('/ai/goals/g1/plans');
    expect(result.current.data).toEqual([{ id: 'p1', version: 1 }]);
  });

  it('useGoalPlan reads one plan with its steps, unwrapped', async () => {
    mockGet.mockResolvedValue({ data: { success: true, data: { plan: { id: 'p1', steps: [{ id: 's1' }] } } } });

    const { result } = renderHook(() => useGoalPlan('g1', 'p1'), { wrapper });

    await waitFor(() => expect(result.current.isSuccess).toBe(true));
    expect(mockGet).toHaveBeenCalledWith('/ai/goals/g1/plans/p1');
    expect(result.current.data).toEqual({ id: 'p1', steps: [{ id: 's1' }] });
  });

  it('does not fetch without a goal id', () => {
    renderHook(() => useGoalPlans(''), { wrapper });
    expect(mockGet).not.toHaveBeenCalled();
  });
});
