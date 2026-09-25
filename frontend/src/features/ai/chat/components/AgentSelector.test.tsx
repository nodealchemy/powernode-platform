import React from 'react';
import { render, waitFor } from '@testing-library/react';
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
    mockGetAgents.mockResolvedValue({ items: [], pagination: {} });
    mockApiClientGet.mockResolvedValue({ data: { data: { items: [] } } });
  });

  it('fetches agents via agentsApi.getAgents with status active and include_types', async () => {
    render(<AgentSelector onSelect={jest.fn()} />);

    await waitFor(() => {
      expect(mockGetAgents).toHaveBeenCalledWith({
        status: 'active',
        include_types: 'assistant,monitor,code_assistant,content_generator,image_generator,mcp_client',
      });
    });
  });
});
