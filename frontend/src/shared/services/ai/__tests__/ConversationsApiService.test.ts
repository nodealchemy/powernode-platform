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

import { conversationsApi } from '../ConversationsApiService';

beforeEach(() => {
  mockGet.mockReset();
  mockPost.mockReset();
  mockPut.mockReset();
  mockPatch.mockReset();
  mockDelete.mockReset();
});

// fc-37: createConciergeConversation/createProvisioningConversation/
// confirmConciergeAction moved here from chatApi.ts (a duplicate
// /ai/conversations client), same request shape and same '/ai/conversations'
// base path (already correctly prefixed by BaseApiService, unlike the
// AgentsApiService duplicates fc-37 also deleted).
describe('ConversationsApiService concierge/provisioning methods', () => {
  it('createConciergeConversation posts to /ai/conversations/concierge with no body', async () => {
    mockPost.mockResolvedValueOnce({ data: { conversation: { id: 'conv-1' } } });
    const result = await conversationsApi.createConciergeConversation();
    expect(mockPost).toHaveBeenCalledWith('/ai/conversations/concierge', undefined, undefined);
    expect(result).toEqual({ id: 'conv-1' });
  });

  // The server 404s (conversations_controller.rb#create_concierge) rather
  // than resolving 200 with a null conversation when no concierge agent is
  // configured — this rejects rather than resolving to null.
  it('createConciergeConversation rejects when no concierge agent is configured', async () => {
    const notFound = { response: { status: 404, data: { error: 'No concierge agent configured' } } };
    mockPost.mockRejectedValueOnce(notFound);
    await expect(conversationsApi.createConciergeConversation()).rejects.toEqual(notFound);
  });

  it('createProvisioningConversation posts to /ai/conversations/provisioning with no body when no id is given', async () => {
    mockPost.mockResolvedValueOnce({ data: { conversation: { id: 'conv-2' } } });
    const result = await conversationsApi.createProvisioningConversation();
    expect(mockPost).toHaveBeenCalledWith('/ai/conversations/provisioning', undefined, undefined);
    expect(result).toEqual({ id: 'conv-2' });
  });

  it('createProvisioningConversation forwards a client-allocated conversation_id', async () => {
    mockPost.mockResolvedValueOnce({ data: { conversation: { id: 'conv-3' } } });
    await conversationsApi.createProvisioningConversation('conv-3');
    expect(mockPost).toHaveBeenCalledWith(
      '/ai/conversations/provisioning',
      { conversation_id: 'conv-3' },
      undefined
    );
  });

  // The server 404s (conversations_controller.rb#create_provisioning) rather
  // than resolving 200 with a null conversation when no concierge agent is
  // configured — this rejects rather than resolving to null.
  it('createProvisioningConversation rejects when no concierge agent is configured', async () => {
    const notFound = { response: { status: 404, data: { error: 'No concierge agent configured' } } };
    mockPost.mockRejectedValueOnce(notFound);
    await expect(conversationsApi.createProvisioningConversation()).rejects.toEqual(notFound);
  });

  it('confirmConciergeAction posts action_type and action_params to /ai/conversations/:id/confirm_action', async () => {
    mockPost.mockResolvedValueOnce({ data: {} });
    await conversationsApi.confirmConciergeAction('conv-4', 'approve', { note: 'looks good' });
    expect(mockPost).toHaveBeenCalledWith(
      '/ai/conversations/conv-4/confirm_action',
      { action_type: 'approve', action_params: { note: 'looks good' } },
      undefined
    );
  });
});
