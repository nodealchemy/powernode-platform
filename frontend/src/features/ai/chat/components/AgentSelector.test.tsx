import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { AgentSelector } from './AgentSelector';

// fc-37: the agents fetch moved from a raw apiClient.get('/ai/agents', ...)
// call to the canonical agentsApi.getAgents, same params. fc-39 moved the
// agent_teams fetch onto agentTeamsApi, the /ai/agent_teams client.
const mockGetAgents = jest.fn();
jest.mock('@/shared/services/ai', () => ({
  agentsApi: { getAgents: (...args: unknown[]) => mockGetAgents(...args) },
}));

const mockGetTeams = jest.fn();
jest.mock('@/features/ai/agent-teams/services/agentTeamsApi', () => ({
  agentTeamsApi: { getTeams: (...args: unknown[]) => mockGetTeams(...args) },
}));

describe('AgentSelector (fc-37 migration)', () => {
  beforeEach(() => {
    mockGetAgents.mockReset();
    mockGetTeams.mockReset();
    mockGetTeams.mockResolvedValue([]);
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

  it('lists active teams from agentTeamsApi.getTeams on the Teams tab', async () => {
    mockGetAgents.mockResolvedValue({ items: [], pagination: {} });
    mockGetTeams.mockResolvedValue([
      { id: 'team-1', name: 'Release Crew', team_type: 'hierarchical', status: 'active', member_count: 3 },
    ]);

    render(<AgentSelector onSelect={jest.fn()} onSelectTeam={jest.fn()} />);
    fireEvent.click(await screen.findByRole('button', { name: /select an agent/i }));
    fireEvent.click(await screen.findByRole('button', { name: /^teams$/i }));

    expect(await screen.findByText('Release Crew')).toBeInTheDocument();
    expect(mockGetTeams).toHaveBeenCalledWith({ status: 'active' });
  });
});
