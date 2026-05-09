import React, { useCallback, useEffect, useMemo } from 'react';
import { AgentConversationComponent } from '@/features/ai/components/AgentConversationComponent';
import { ChannelConversationComponent } from './ChannelConversationComponent';
import { ChatWindowHeader } from './ChatWindowHeader';
import { ConversationCreator } from './ConversationCreator';
import { ChatWindowSidebar } from './ChatWindowSidebar';
import { SplitPanelContainer } from './SplitPanelContainer';
import { useChatWindow } from '../context/ChatWindowContext';
import { buildSyntheticConversation } from '../utils/buildSyntheticConversation';
import type { AiConversation } from '@/shared/types/ai';

interface ChatWindowProps {
  onDragStart?: (e: React.PointerEvent) => void;
}

export const ChatWindow: React.FC<ChatWindowProps> = ({ onDragStart }) => {
  const { state, dispatch } = useChatWindow();

  const isFloating = state.mode === 'floating';

  const handleNewMessage = useCallback((tabId: string) => {
    dispatch({ type: 'INCREMENT_UNREAD', payload: tabId });
  }, [dispatch]);

  // Build the initial conversation shape for each tab. AgentConversationComponent
  // fetches the full row server-side after mount and uses that for derivations
  // (isConcierge, isProvisioning, isWorkspace), so this synthesis is just a
  // first-paint placeholder. Logic is in a shared util to keep ChatWindow +
  // SplitPanelContainer in lockstep.
  const tabConversations = useMemo(() => {
    const map = new Map<string, AiConversation>();
    for (const tab of state.tabs) {
      map.set(tab.id, buildSyntheticConversation(tab));
    }
    return map;
  }, [state.tabs]);

  const activeTab = state.tabs.find(t => t.id === state.activeTabId);
  const activeConv = activeTab ? tabConversations.get(activeTab.id) : null;
  const hasNoTabs = state.tabs.length === 0;

  // Clear unread badge on the active tab when the window becomes visible.
  // ChatWindow only renders when the chat is open (not in 'closed' mode), so mount = user is viewing.
  useEffect(() => {
    if (activeTab && activeTab.unreadCount > 0) {
      dispatch({ type: 'MARK_READ', payload: activeTab.id });
    }
  }, [activeTab?.id, dispatch]);

  return (
    <div className="flex flex-col h-full bg-theme-background rounded-xl overflow-hidden" data-testid={state.mode === 'maximized' ? 'chat-maximized' : undefined}>
      <ChatWindowHeader onPointerDown={onDragStart} />
      <div className="flex-1 flex overflow-hidden">
        {/* Sidebar (all modes, toggled via header button) */}
        {state.showSidebar && (
          <ChatWindowSidebar />
        )}

        {isFloating ? (
          /* Floating mode: single panel, no tabs */
          <div className="flex-1 flex flex-col min-w-0">
            <div className="flex-1 relative overflow-hidden">
              {hasNoTabs || (!activeConv && !activeTab?.isChannel) ? (
                <ConversationCreator onComplete={() => {}} />
              ) : activeTab?.isChannel && activeTab.channelId && activeTab.teamId ? (
                <ChannelConversationComponent
                  key={activeTab.channelId}
                  teamId={activeTab.teamId}
                  channelId={activeTab.channelId}
                  channelName={activeTab.channelName}
                />
              ) : activeConv ? (
                <AgentConversationComponent
                  key={activeConv.id}
                  conversation={activeConv}
                  onNewMessage={() => handleNewMessage(activeTab!.id)}
                />
              ) : (
                <ConversationCreator onComplete={() => {}} />
              )}
            </div>
          </div>
        ) : (
          /* Maximized/Detached: split panel container */
          <SplitPanelContainer />
        )}
      </div>
    </div>
  );
};
