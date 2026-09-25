import React from 'react';
import { render, waitFor } from '@testing-library/react';
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
    mockGetAgents.mockResolvedValue({ items: [], pagination: {} });
    mockGetActiveSessions.mockResolvedValue([]);
  });

  it('fetches agents via agentsApi.getAgents with status active and include_types', async () => {
    render(<SessionSearch onCreateWorkspace={jest.fn()} onClose={jest.fn()} />);

    await waitFor(() => {
      expect(mockGetAgents).toHaveBeenCalledWith({
        status: 'active',
        include_types: 'assistant,monitor,code_assistant,content_generator,image_generator,mcp_client',
      });
    });
  });
});
