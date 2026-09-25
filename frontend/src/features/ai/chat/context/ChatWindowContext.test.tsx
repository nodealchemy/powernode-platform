import React from 'react';
import { renderHook, act } from '@testing-library/react';
import { ChatWindowProvider, useChatWindow } from './ChatWindowContext';

// fc-37: openConcierge/materializePendingTab moved from chatApi (a
// duplicate /ai/conversations client) to the canonical conversationsApi,
// with the same call shape. These tests assert the migrated callers still
// hit the canonical methods with the same params.
jest.mock('@/shared/services/ai/ConversationsApiService', () => ({
  conversationsApi: {
    createConciergeConversation: jest.fn(),
    createProvisioningConversation: jest.fn(),
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

import { conversationsApi } from '@/shared/services/ai/ConversationsApiService';

const mockCreateConcierge = conversationsApi.createConciergeConversation as jest.Mock;
const mockCreateProvisioning = conversationsApi.createProvisioningConversation as jest.Mock;

describe('ChatWindowContext conversation creation (fc-37 migration)', () => {
  beforeEach(() => {
    localStorage.clear();
    mockCreateConcierge.mockReset();
    mockCreateProvisioning.mockReset();
  });

  const wrapper: React.FC<{ children: React.ReactNode }> = ({ children }) => (
    <ChatWindowProvider>{children}</ChatWindowProvider>
  );

  it('openConcierge calls conversationsApi.createConciergeConversation with no params', async () => {
    mockCreateConcierge.mockResolvedValueOnce({
      id: 'conv-1',
      ai_agent: { id: 'agent-1', name: 'Assistant' },
    });

    const { result } = renderHook(() => useChatWindow(), { wrapper });

    await act(async () => {
      await result.current.openConcierge();
    });

    expect(mockCreateConcierge).toHaveBeenCalledWith();
    expect(result.current.state.tabs.some(t => t.conversationId === 'conv-1')).toBe(true);
  });

  it('materializePendingTab calls conversationsApi.createProvisioningConversation with the pending tab id', async () => {
    const { result } = renderHook(() => useChatWindow(), { wrapper });

    await act(async () => {
      await result.current.openProvisioning();
    });

    const pendingTab = result.current.state.tabs[0];
    expect(pendingTab.isPending).toBe(true);

    mockCreateProvisioning.mockResolvedValueOnce({
      id: pendingTab.conversationId,
      ai_agent: { id: 'agent-2', name: 'Provisioning Agent' },
    });

    await act(async () => {
      await result.current.materializePendingTab(pendingTab.id);
    });

    expect(mockCreateProvisioning).toHaveBeenCalledWith(pendingTab.conversationId);
  });
});
