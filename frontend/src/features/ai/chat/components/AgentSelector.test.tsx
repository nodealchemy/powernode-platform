import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { AgentSelector } from './AgentSelector';

// fc-37: the agents fetch moved from a raw apiClient.get('/ai/agents', ...)
// call to the canonical agentsApi.getAgents, same params. The agent_teams
// fetch stays on apiClient — out of fc-37's /ai/agents scope, distinct
// endpoint — so apiClient is still mocked, just not asserted on here.
const mockGetAgents = jest.fn();
jest.mock('@/shared/services/ai', () => ({
  agentsApi: { getAgents: (...args: unknown[]) => mockGetAgents(...args) },
}));

const mockApiClientGet = jest.fn();
jest.mock('@/shared/services/apiClient', () => ({
  apiClient: { get: (...args: unknown[]) => mockApiClientGet(...args) },
}));

describe('AgentSelector (fc-37 migration)', () => {
  beforeEach(() => {
    mockGetAgents.mockReset();
    mockApiClientGet.mockReset();
    mockApiClientGet.mockResolvedValue({ data: { data: { items: [] } } });
  });

  it('fetches agents via agentsApi.getAgents with status active and include_types', async () => {
    mockGetAgents.mockResolvedValue({ items: [], pagination: {} });
    render(<AgentSelector onSelect={jest.fn()} />);

    await waitFor(() => {
      expect(mockGetAgents).toHaveBeenCalledWith({
        status: 'active',
        include_types: 'assistant,monitor,code_assistant,content_generator,image_generator,mcp_client',
      });
    });
  });

  // Guards against a mutant that reverts the read from the canonical
  // response.items to the old raw-axios response.data?.data?.items shape:
  // with the mock below (no nested .data), that mutant reads undefined,
  // renders zero agents, and this assertion goes red.
  it('renders an agent returned by agentsApi.getAgents (consumed via .items)', async () => {
    mockGetAgents.mockResolvedValue({
      items: [{ id: 'agent-1', name: 'Research Assistant', agent_type: 'assistant', status: 'active' }],
      pagination: {},
    });

    render(<AgentSelector onSelect={jest.fn()} />);

    const trigger = await screen.findByRole('button', { name: /select an agent/i });
    fireEvent.click(trigger);

    expect(await screen.findByText('Research Assistant')).toBeInTheDocument();
  });
});
