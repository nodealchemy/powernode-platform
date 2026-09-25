import { render, screen, waitFor } from '@testing-library/react';
import { ConversationCreator } from './ConversationCreator';

// fc-37: the agents fetch moved from a raw apiClient.get('/ai/agents', ...)
// call to the canonical agentsApi.getAgents, same params.
const mockGetAgents = jest.fn();
jest.mock('@/shared/services/ai', () => ({
  agentsApi: { getAgents: (...args: unknown[]) => mockGetAgents(...args) },
}));

jest.mock('../context/ChatWindowContext', () => ({
  useChatWindow: () => ({
    state: { tabs: [], activeTabId: null },
    openConversation: jest.fn(),
    openConcierge: jest.fn(),
    switchTab: jest.fn(),
    setMode: jest.fn(),
  }),
}));

describe('ConversationCreator (fc-37 migration)', () => {
  beforeEach(() => {
    mockGetAgents.mockReset();
  });

  it('fetches agents via agentsApi.getAgents with status active', async () => {
    mockGetAgents.mockResolvedValue({ items: [], pagination: {} });
    render(<ConversationCreator />);

    await waitFor(() => {
      expect(mockGetAgents).toHaveBeenCalledWith({ status: 'active' });
    });
  });

  // Guards against a mutant that reverts the read from the canonical
  // response.items to the old raw-axios response.data?.data?.items (or
  // ?.data) shape: with the mock below (no nested .data), that mutant
  // renders zero agents, and this assertion goes red.
  it('renders an agent returned by agentsApi.getAgents (consumed via .items)', async () => {
    mockGetAgents.mockResolvedValue({
      items: [{ id: 'agent-1', name: 'Research Assistant', agent_type: 'assistant', status: 'active' }],
      pagination: {},
    });

    render(<ConversationCreator />);

    expect(await screen.findByText('Research Assistant')).toBeInTheDocument();
  });
});
