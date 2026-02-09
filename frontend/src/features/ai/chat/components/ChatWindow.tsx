import React, { useState, useCallback, useMemo } from 'react';
import { AgentConversationComponent } from '@/features/ai/components/AgentConversationComponent';
import { ChatWindowHeader } from './ChatWindowHeader';
import { ChatWindowTabs } from './ChatWindowTabs';
import { NewConversationTab } from './NewConversationTab';
import { useChatWindow } from '../context/ChatWindowContext';
import type { AiConversation } from '@/shared/types/ai';

interface ChatWindowProps {
  onDragStart?: (e: React.PointerEvent) => void;
}

export const ChatWindow: React.FC<ChatWindowProps> = ({ onDragStart }) => {
  const { state, dispatch } = useChatWindow();
  const [showNewTab, setShowNewTab] = useState(false);

  const handleNewMessage = useCallback((tabId: string) => {
    dispatch({ type: 'INCREMENT_UNREAD', payload: tabId });
  }, [dispatch]);

  // Build conversation objects for each tab
  const tabConversations = useMemo(() => {
    const map = new Map<string, AiConversation>();
    for (const tab of state.tabs) {
      map.set(tab.id, {
        id: tab.conversationId,
        title: tab.title,
        status: 'active',
        ai_agent: { id: tab.agentId, name: tab.agentName, agent_type: 'assistant' },
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

  const hasNoTabs = state.tabs.length === 0;

  return (
    <div className="flex flex-col h-full bg-theme-background rounded-xl overflow-hidden">
      <ChatWindowHeader onPointerDown={onDragStart} />
      <ChatWindowTabs onNewTab={() => setShowNewTab(true)} />

      <div className="flex-1 relative overflow-hidden">
        {(hasNoTabs || showNewTab) && (
          <div className={`absolute inset-0 z-10 bg-theme-background ${!hasNoTabs ? '' : ''}`}>
            <NewConversationTab onComplete={() => setShowNewTab(false)} />
          </div>
        )}

        {state.tabs.map(tab => {
          const conv = tabConversations.get(tab.id);
          if (!conv) return null;
          const isActive = tab.id === state.activeTabId;
          return (
            <div
              key={tab.id}
              className={isActive && !showNewTab ? 'h-full' : 'hidden'}
            >
              <AgentConversationComponent
                conversation={conv}
                onNewMessage={() => handleNewMessage(tab.id)}
              />
            </div>
          );
        })}
      </div>
    </div>
  );
};
