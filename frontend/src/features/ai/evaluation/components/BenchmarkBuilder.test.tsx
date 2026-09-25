import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { BenchmarkBuilder } from './BenchmarkBuilder';

// fc-37: the agents fetch moved from a raw apiClient.get('/ai/agents', ...)
// call to the canonical agentsApi.getAgents, same params.
const mockGetAgents = jest.fn();
jest.mock('@/shared/services/ai', () => ({
  agentsApi: { getAgents: (...args: unknown[]) => mockGetAgents(...args) },
}));

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: jest.fn() }),
}));

// jest.config's resetMocks:true wipes a jest.fn().mockResolvedValue(...) set
// inline in a mock factory before the first test runs, so wire this one
// through a named mock and set its resolved value in beforeEach instead.
const mockFetchBenchmarks = jest.fn();
jest.mock('../api/evaluationApi', () => ({
  fetchBenchmarks: (...args: unknown[]) => mockFetchBenchmarks(...args),
  createBenchmark: jest.fn(),
  runBenchmark: jest.fn(),
}));

describe('BenchmarkBuilder (fc-37 migration)', () => {
  beforeEach(() => {
    mockGetAgents.mockReset();
    mockFetchBenchmarks.mockReset();
    mockFetchBenchmarks.mockResolvedValue([]);
  });

  it('fetches agents via agentsApi.getAgents with status active and limit 100', async () => {
    mockGetAgents.mockResolvedValue({ items: [], pagination: {} });
    render(<BenchmarkBuilder />);

    await waitFor(() => {
      expect(mockGetAgents).toHaveBeenCalledWith({ status: 'active', limit: 100 });
    });
  });

  // Guards against a mutant that reverts the read from the canonical
  // response.items to the old raw-axios response.data?.data?.items shape:
  // with the mock below (no nested .data), that mutant renders zero
  // agent options, and this assertion goes red.
  it('renders an agent returned by agentsApi.getAgents as a select option (consumed via .items)', async () => {
    mockGetAgents.mockResolvedValue({
      items: [{ id: 'agent-1', name: 'Research Assistant' }],
      pagination: {},
    });

    render(<BenchmarkBuilder />);

    fireEvent.click(await screen.findByText('New Benchmark'));

    expect(await screen.findByRole('option', { name: 'Research Assistant' })).toBeInTheDocument();
  });
});
