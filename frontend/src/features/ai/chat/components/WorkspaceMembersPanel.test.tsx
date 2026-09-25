import React from 'react';
import { render, waitFor } from '@testing-library/react';
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
    mockGetAgents.mockResolvedValue({ items: [], pagination: {} });
    mockGetWorkspace.mockResolvedValue({ members: [] });
  });

  it('fetches agents via agentsApi.getAgents with status active', async () => {
    render(<WorkspaceMembersPanel conversationId="conv-1" onClose={jest.fn()} />);

    await waitFor(() => {
      expect(mockGetAgents).toHaveBeenCalledWith({ status: 'active' });
    });
  });
});
