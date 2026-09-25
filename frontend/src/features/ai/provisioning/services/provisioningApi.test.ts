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

import { provisioningApi } from './provisioningApi';

beforeEach(() => {
  mockGet.mockReset();
  mockPost.mockReset();
});

// fc-37: getConversationMessages/sendConversationMessage moved from a raw
// apiClient call to conversationsApi (the canonical /ai/conversations
// client), same endpoint. These assert the migrated calls still hit
// /ai/conversations/:id/messages with the same params, and that the
// response shape ProjectProvisioningChat's fallback unwrapping relies on
// (`payload?.data ?? payload ?? {}`, then `.messages`) still resolves.
describe('provisioningApi conversation message methods (fc-37 migration)', () => {
  it('getConversationMessages GETs /ai/conversations/:id/messages and exposes a .messages array', async () => {
    mockGet.mockResolvedValueOnce({
      data: { messages: [{ id: 'm-1', content: 'hi' }], pagination: { has_older: false, oldest_cursor: null, newest_cursor: 1, total_count: 1 } },
    });

    const payload = await provisioningApi.getConversationMessages('conv-1');

    expect(mockGet).toHaveBeenCalledWith('/ai/conversations/conv-1/messages', undefined);
    const data = ((payload as { data?: unknown } | undefined)?.data ?? payload ?? {}) as { messages?: unknown[] };
    expect(data.messages).toEqual([{ id: 'm-1', content: 'hi' }]);
  });

  it('sendConversationMessage posts the message body to /ai/conversations/:id/messages', async () => {
    mockPost.mockResolvedValueOnce({ data: {} });

    await provisioningApi.sendConversationMessage('conv-2', 'hello there');

    expect(mockPost).toHaveBeenCalledWith(
      '/ai/conversations/conv-2/messages',
      { message: { content: 'hello there' } },
      { timeout: 120000 }
    );
  });
});
