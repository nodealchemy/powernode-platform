import React from 'react';
import { render, waitFor } from '@testing-library/react';
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
    mockGetAgents.mockResolvedValue({ items: [], pagination: {} });
  });

  it('fetches agents via agentsApi.getAgents with status active', async () => {
    render(<ConversationCreator />);

    await waitFor(() => {
      expect(mockGetAgents).toHaveBeenCalledWith({ status: 'active' });
    });
  });
});
