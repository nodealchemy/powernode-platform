import { render, screen, waitFor } from '@testing-library/react';
import { SessionSearch } from './SessionSearch';

// fc-37: the agents fetch moved from a raw apiClient.get('/ai/agents', ...)
// call to the canonical agentsApi.getAgents, same params.
const mockGetAgents = jest.fn();
jest.mock('@/shared/services/ai', () => ({
  agentsApi: { getAgents: (...args: unknown[]) => mockGetAgents(...args) },
}));

const mockGetActiveSessions = jest.fn();
jest.mock('@/shared/services/ai/WorkspacesApiService', () => ({
  workspacesApi: { getActiveSessions: (...args: unknown[]) => mockGetActiveSessions(...args) },
}));

describe('SessionSearch (fc-37 migration)', () => {
  beforeEach(() => {
    mockGetAgents.mockReset();
    mockGetActiveSessions.mockReset();
    mockGetActiveSessions.mockResolvedValue([]);
  });

  it('fetches agents via agentsApi.getAgents with status active and include_types', async () => {
    mockGetAgents.mockResolvedValue({ items: [], pagination: {} });
    render(<SessionSearch onCreateWorkspace={jest.fn()} onClose={jest.fn()} />);

    await waitFor(() => {
      expect(mockGetAgents).toHaveBeenCalledWith({
        status: 'active',
        include_types: 'assistant,monitor,code_assistant,content_generator,image_generator,mcp_client',
      });
    });
  });

  // Guards against a mutant that reverts the read from the canonical
  // response.items to the old raw-axios response.data?.data?.items shape:
  // with the mock below (no nested .data), that mutant renders zero
  // agents, and this assertion goes red.
  it('renders an agent returned by agentsApi.getAgents (consumed via .items)', async () => {
    mockGetAgents.mockResolvedValue({
      items: [{ id: 'agent-1', name: 'Research Assistant', agent_type: 'assistant', status: 'active', is_concierge: false }],
      pagination: {},
    });

    render(<SessionSearch onCreateWorkspace={jest.fn()} onClose={jest.fn()} />);

    expect(await screen.findByText('Research Assistant')).toBeInTheDocument();
  });
});
