import { render, screen, waitFor } from '@testing-library/react';
import { WorkspaceMembersPanel } from './WorkspaceMembersPanel';

// fc-37: the agents fetch moved from a raw apiClient.get('/ai/agents', ...)
// call to the canonical agentsApi.getAgents, same params.
const mockGetAgents = jest.fn();
const mockGetWorkspace = jest.fn();
jest.mock('@/shared/services/ai', () => ({
  agentsApi: { getAgents: (...args: unknown[]) => mockGetAgents(...args) },
  workspacesApi: { getWorkspace: (...args: unknown[]) => mockGetWorkspace(...args) },
}));

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: jest.fn() }),
}));

describe('WorkspaceMembersPanel (fc-37 migration)', () => {
  beforeEach(() => {
    mockGetAgents.mockReset();
    mockGetWorkspace.mockReset();
    mockGetWorkspace.mockResolvedValue({ members: [] });
  });

  it('fetches agents via agentsApi.getAgents with status active', async () => {
    mockGetAgents.mockResolvedValue({ items: [], pagination: {} });
    render(<WorkspaceMembersPanel conversationId="conv-1" onClose={jest.fn()} />);

    await waitFor(() => {
      expect(mockGetAgents).toHaveBeenCalledWith({ status: 'active' });
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

    render(<WorkspaceMembersPanel conversationId="conv-1" onClose={jest.fn()} />);

    expect(await screen.findByText('Research Assistant')).toBeInTheDocument();
  });
});
