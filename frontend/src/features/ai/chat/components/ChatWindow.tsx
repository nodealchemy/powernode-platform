import React, { useCallback, useMemo } from 'react';
import { AgentConversationComponent } from '@/features/ai/components/AgentConversationComponent';
import { ChatWindowHeader } from './ChatWindowHeader';
import { NewConversationTab } from './NewConversationTab';
import { ChatWindowSidebar } from './ChatWindowSidebar';
import { SplitPanelContainer } from './SplitPanelContainer';
import { useChatWindow } from '../context/ChatWindowContext';
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

  // Build conversation objects for each tab (only used in floating mode)
  const tabConversations = useMemo(() => {
    const map = new Map<string, AiConversation>();
    for (const tab of state.tabs) {
      map.set(tab.id, {
        id: tab.conversationId,
        title: tab.title,
        status: 'active',
        conversation_type: tab.isWorkspace ? 'team' : 'agent',
        ai_agent: { id: tab.agentId, name: tab.agentName, agent_type: 'assistant', is_concierge: tab.isConcierge },
        agent_team: tab.teamId ? { id: tab.teamId, name: tab.title } : undefined,
        metadata: {
          created_by: '',
          total_messages: 0,
          total_tokens: 0,
          total_cost: 0,
          last_activity: new Date().toISOString(),
        },
        created_at: new Date(tab.createdAt).toISOString(),
        updated_at: new Date().toISOString(),
      });
    }
    return map;
  }, [state.tabs]);

  const activeTab = state.tabs.find(t => t.id === state.activeTabId);
  const activeConv = activeTab ? tabConversations.get(activeTab.id) : null;
  const hasNoTabs = state.tabs.length === 0;

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
              {hasNoTabs || !activeConv ? (
                <NewConversationTab onComplete={() => {}} />
              ) : (
                <AgentConversationComponent
                  key={activeConv.id}
                  conversation={activeConv}
                  onNewMessage={() => handleNewMessage(activeTab!.id)}
                />
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
