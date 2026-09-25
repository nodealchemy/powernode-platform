const mockGet = jest.fn();
const mockPost = jest.fn();
const mockPut = jest.fn();
const mockPatch = jest.fn();
const mockDelete = jest.fn();

jest.mock('@/shared/services/api', () => ({
  __esModule: true,
  api: {
    get: (...args: unknown[]) => mockGet(...args),
    post: (...args: unknown[]) => mockPost(...args),
    put: (...args: unknown[]) => mockPut(...args),
    patch: (...args: unknown[]) => mockPatch(...args),
    delete: (...args: unknown[]) => mockDelete(...args),
  },
}));

import { agentsApi } from '../AgentsApiService';

beforeEach(() => {
  mockGet.mockReset();
  mockPost.mockReset();
  mockPut.mockReset();
  mockPatch.mockReset();
  mockDelete.mockReset();
});

// fc-37 item 7: distinct from getActiveConversations (which filters the
// INDEX action by ?status=active), this hits its own agent- and
// user-scoped collection route, GET /ai/agents/:agent_id/conversations/active,
// returning an array of at most one conversation.
describe('AgentsApiService.getActiveConversation', () => {
  it('gets /ai/agents/:agentId/conversations/active and returns the first (only) conversation', async () => {
    mockGet.mockResolvedValueOnce({ data: { data: [{ id: 'conv-1' }] } });
    const result = await agentsApi.getActiveConversation('agent-1');
    expect(mockGet).toHaveBeenCalledWith('/ai/agents/agent-1/conversations/active', undefined);
    expect(result).toEqual({ id: 'conv-1' });
  });

  it('returns null when the agent has no active conversation for this user', async () => {
    mockGet.mockResolvedValueOnce({ data: { data: [] } });
    const result = await agentsApi.getActiveConversation('agent-1');
    expect(result).toBeNull();
  });
});
