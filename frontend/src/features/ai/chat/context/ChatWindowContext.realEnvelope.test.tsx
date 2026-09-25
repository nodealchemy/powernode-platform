import React from 'react';
import { renderHook, act } from '@testing-library/react';
import { ChatWindowProvider, useChatWindow } from './ChatWindowContext';

// fc-37 review round 3 (blocker): the sibling ChatWindowContext.test.tsx
// mocks agentsApi.createConversation directly, resolving a pre-unwrapped
// `{id: 'conv-new'}` — that passes whether or not AgentsApiService itself
// unwraps the real response envelope correctly, so it couldn't have caught
// the bug (createConversation returned {conversation: {...}}, not the
// conversation itself; every caller reading `.id` got undefined). This file
// mocks one layer deeper, at the apiClient HTTP layer, so the REAL
// AgentsApiService.createConversation/getActiveConversation run and their
// envelope-unwrapping is actually exercised.
const mockGet = jest.fn();
const mockPost = jest.fn();

jest.mock('@/shared/services/api', () => ({
  __esModule: true,
  api: {
    get: (...args: unknown[]) => mockGet(...args),
    post: (...args: unknown[]) => mockPost(...args),
    put: jest.fn(),
    patch: jest.fn(),
    delete: jest.fn(),
  },
}));

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: jest.fn() }),
}));

jest.mock('@/shared/hooks/useWebSocket', () => ({
  useWebSocket: () => ({
    isConnected: false,
    error: null,
    lastConnected: null,
    subscribe: jest.fn(() => () => {}),
    sendMessage: jest.fn(),
  }),
}));

describe('ChatWindowContext.openConversation against the real response envelope', () => {
  beforeEach(() => {
    localStorage.clear();
    mockGet.mockReset();
    mockPost.mockReset();
  });

  const wrapper: React.FC<{ children: React.ReactNode }> = ({ children }) => (
    <ChatWindowProvider>{children}</ChatWindowProvider>
  );

  it('opens a tab with a real conversation id, not undefined, from the real {conversation: {...}} create envelope', async () => {
    // GET /ai/agents/:id/conversations/active — no active conversation.
    mockGet.mockResolvedValueOnce({ data: { success: true, data: [] } });
    // POST /ai/agents/:id/conversations — the real server envelope
    // (conversations_controller.rb#create): {success, data: {conversation: {...}}}.
    mockPost.mockResolvedValueOnce({
      data: { success: true, data: { conversation: { id: 'conv-real-id', ai_agent: { id: 'agent-1', name: 'Assistant' } } } },
    });

    const { result } = renderHook(() => useChatWindow(), { wrapper });

    await act(async () => {
      await result.current.openConversation('agent-1', 'Assistant');
    });

    const tab = result.current.state.tabs.find(t => t.agentId === 'agent-1');
    expect(tab?.conversationId).toBe('conv-real-id');
    expect(tab?.conversationId).not.toBe('undefined');
    expect(tab?.id).toBe('tab-conv-real-id');
  });
});
