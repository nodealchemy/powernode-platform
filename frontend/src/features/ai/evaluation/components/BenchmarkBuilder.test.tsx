import React from 'react';
import { render, waitFor } from '@testing-library/react';
import { BenchmarkBuilder } from './BenchmarkBuilder';

// fc-37: the agents fetch moved from a raw apiClient.get('/ai/agents', ...)
// call to the canonical agentsApi.getAgents, same params. This asserts the
// migrated caller hits the canonical method with the same params.
const mockGetAgents = jest.fn();
jest.mock('@/shared/services/ai', () => ({
  agentsApi: { getAgents: (...args: unknown[]) => mockGetAgents(...args) },
}));

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: jest.fn() }),
}));

jest.mock('../api/evaluationApi', () => ({
  fetchBenchmarks: jest.fn().mockResolvedValue([]),
  createBenchmark: jest.fn(),
  runBenchmark: jest.fn(),
}));

describe('BenchmarkBuilder (fc-37 migration)', () => {
  beforeEach(() => {
    mockGetAgents.mockReset();
    mockGetAgents.mockResolvedValue({ items: [{ id: 'agent-1', name: 'Agent One' }], pagination: {} });
  });

  it('fetches agents via agentsApi.getAgents with status active and limit 100', async () => {
    render(<BenchmarkBuilder />);

    await waitFor(() => {
      expect(mockGetAgents).toHaveBeenCalledWith({ status: 'active', limit: 100 });
    });
  });
});
