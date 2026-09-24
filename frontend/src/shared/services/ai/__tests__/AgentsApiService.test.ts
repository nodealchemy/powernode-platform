import { agentsApi } from '../AgentsApiService';

// fc-01 follow-up: the four "Global Conversations" methods build
// `const path = '/api/v1/ai/conversations...'` by hand instead of using
// `buildPath()`/`baseNamespace` like every other method in this file, then
// pass it to `this.get`/`this.patch`/`this.delete`, which call `this.client`
// (BaseApiService.client = api, @/shared/services/api -- baseURL already
// '/api/v1'). The hardcoded prefix double-prefixes the request the same way
// invitationsApi.ts did. No caller of these 4 methods exists anywhere in the
// tree today (verified via repo-wide grep), but a 404 in production
// shouldn't wait for a caller to exist or for fc-37 (which later deletes
// these methods) to land.
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

beforeEach(() => {
  mockGet.mockReset();
  mockPost.mockReset();
  mockPut.mockReset();
  mockPatch.mockReset();
  mockDelete.mockReset();
});

describe('AgentsApiService global conversation methods', () => {
  // BaseApiService.get() always forwards a (possibly-undefined) config as
  // its 2nd arg to this.client.get -- match that shape rather than the 1-arg
  // form so a real path fix isn't masked by an arg-count mismatch.
  it('getGlobalConversations gets /ai/conversations, not /api/v1/ai/conversations', async () => {
    mockGet.mockResolvedValueOnce({ data: { items: [], pagination: {} } });
    await agentsApi.getGlobalConversations();
    expect(mockGet).toHaveBeenCalledWith('/ai/conversations', undefined);
  });

  it('getGlobalConversations forwards filters as a query string on /ai/conversations', async () => {
    mockGet.mockResolvedValueOnce({ data: { items: [], pagination: {} } });
    await agentsApi.getGlobalConversations({ status: 'active' });
    expect(mockGet).toHaveBeenCalledWith('/ai/conversations?status=active', undefined);
  });

  it('getGlobalConversation gets /ai/conversations/:id, not /api/v1/ai/conversations/:id', async () => {
    mockGet.mockResolvedValueOnce({ data: {} });
    await agentsApi.getGlobalConversation('conv-1');
    expect(mockGet).toHaveBeenCalledWith('/ai/conversations/conv-1', undefined);
  });

  it('updateGlobalConversation patches /ai/conversations/:id, not /api/v1/ai/conversations/:id', async () => {
    mockPatch.mockResolvedValueOnce({ data: {} });
    await agentsApi.updateGlobalConversation('conv-1', { title: 'New title' });
    // BaseApiService.patch() always forwards a (possibly-undefined) config as
    // its 3rd arg to this.client.patch -- match that shape rather than the
    // 2-arg form so a real path fix isn't masked by an arg-count mismatch.
    expect(mockPatch).toHaveBeenCalledWith(
      '/ai/conversations/conv-1',
      { conversation: { title: 'New title' } },
      undefined
    );
  });

  it('deleteGlobalConversation deletes /ai/conversations/:id, not /api/v1/ai/conversations/:id', async () => {
    mockDelete.mockResolvedValueOnce({ data: undefined });
    await agentsApi.deleteGlobalConversation('conv-1');
    // BaseApiService.delete() always forwards a (possibly-undefined) config
    // as its 2nd arg to this.client.delete -- see note above.
    expect(mockDelete).toHaveBeenCalledWith('/ai/conversations/conv-1', undefined);
  });

  // Same "Global Conversations" section, same hand-built '/api/v1' prefix,
  // same fix.
  it('archiveGlobalConversation posts to /ai/conversations/:id/archive, not /api/v1/...', async () => {
    mockPost.mockResolvedValueOnce({ data: {} });
    await agentsApi.archiveGlobalConversation('conv-1');
    expect(mockPost).toHaveBeenCalledWith('/ai/conversations/conv-1/archive', {}, undefined);
  });

  it('unarchiveGlobalConversation posts to /ai/conversations/:id/unarchive, not /api/v1/...', async () => {
    mockPost.mockResolvedValueOnce({ data: {} });
    await agentsApi.unarchiveGlobalConversation('conv-1');
    expect(mockPost).toHaveBeenCalledWith('/ai/conversations/conv-1/unarchive', {}, undefined);
  });

  it('duplicateGlobalConversation posts to /ai/conversations/:id/duplicate, not /api/v1/...', async () => {
    mockPost.mockResolvedValueOnce({ data: {} });
    await agentsApi.duplicateGlobalConversation('conv-1', { title: 'Copy' });
    expect(mockPost).toHaveBeenCalledWith('/ai/conversations/conv-1/duplicate', { title: 'Copy' }, undefined);
  });
});
