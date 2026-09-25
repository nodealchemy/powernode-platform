import React from 'react';
import { renderHook, waitFor } from '@testing-library/react';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { useViolations } from './auditApi';

// GovernanceController#violations nests each violation's policy as
// { policy: { id, name } }; the client flattens it to policy_id/policy_name.

const mockGet = jest.fn();
jest.mock('@/shared/services/apiClient', () => ({
  apiClient: { get: (...args: unknown[]) => mockGet(...args), put: jest.fn(), post: jest.fn(), delete: jest.fn() },
}));

it('flattens the nested policy into policy_id and policy_name', async () => {
  mockGet.mockResolvedValue({ data: { success: true, data: {
    violations: [{ id: 'v-1', violation_id: 'V-1', severity: 'high', status: 'open', description: 'x',
                   source_type: 'Ai::Execution', remediation_steps: [], detected_at: '2026-09-01T00:00:00Z',
                   policy: { id: 'pol-9', name: 'No PII' } }],
    pagination: { current_page: 1, total_pages: 1, total_count: 1, per_page: 20 },
  } } });
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const wrapper = ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={client}>{children}</QueryClientProvider>
  );

  const { result } = renderHook(() => useViolations(), { wrapper });

  await waitFor(() => expect(result.current.isSuccess).toBe(true));
  expect(result.current.data?.data[0]).toMatchObject({ id: 'v-1', policy_id: 'pol-9', policy_name: 'No PII' });
  expect(result.current.data?.data[0]).not.toHaveProperty('policy');
});
