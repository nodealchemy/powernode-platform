import React, { useState, useEffect, useCallback } from 'react';
import { Bot, X } from 'lucide-react';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { AgentSelector } from './AgentSelector';
import { AgentChatSlideout } from './AgentChatSlideout';

const STORAGE_KEY = 'powernode_chat_agent_id';

export const FloatingChatWidget: React.FC = () => {
  const currentUser = useSelector((state: RootState) => state.auth.user);
  const [isExpanded, setIsExpanded] = useState(false);
  const [selectedAgentId, setSelectedAgentId] = useState<string>('');
  const [selectedAgentName, setSelectedAgentName] = useState<string>('');
  const [isChatOpen, setIsChatOpen] = useState(false);

  // Permission check
  const hasPermission = currentUser?.permissions?.includes('ai.conversations.create');

  // Restore selected agent from localStorage
  useEffect(() => {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored) {
      try {
        const parsed = JSON.parse(stored);
        setSelectedAgentId(parsed.id || '');
        setSelectedAgentName(parsed.name || '');
      } catch {
        // Invalid stored data
      }
    }
  }, []);

  const handleAgentSelect = useCallback((agentId: string) => {
    setSelectedAgentId(agentId);
    // Store selection
    localStorage.setItem(STORAGE_KEY, JSON.stringify({ id: agentId, name: '' }));
  }, []);

  const handleOpenChat = useCallback(() => {
    if (selectedAgentId) {
      setIsChatOpen(true);
      setIsExpanded(false);
    }
  }, [selectedAgentId]);

  if (!hasPermission) return null;

  return (
    <>
      {/* Floating button / expanded widget */}
      <div className="fixed bottom-4 right-4 z-50">
        {isExpanded ? (
          <div className="w-[380px] bg-theme-surface border border-theme rounded-xl shadow-2xl">
            {/* Widget header */}
            <div className="flex items-center justify-between px-4 py-3 border-b border-theme bg-primary-500/5">
              <span className="text-sm font-semibold text-theme-primary">AI Chat</span>
              <button
                type="button"
                onClick={() => setIsExpanded(false)}
                className="p-1 rounded-md hover:bg-theme-surface-hover text-theme-secondary transition-colors"
                aria-label="Close widget"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            {/* Agent selector */}
            <div className="p-3">
              <AgentSelector
                selectedAgentId={selectedAgentId}
                onSelect={handleAgentSelect}
              />
            </div>

            {/* Open chat button */}
            <div className="px-3 pb-3">
              <button
                type="button"
                onClick={handleOpenChat}
                disabled={!selectedAgentId}
                className="w-full py-2 text-sm font-medium text-white bg-theme-interactive-primary rounded-lg hover:bg-theme-interactive-primary-hover disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
              >
                Start Conversation
              </button>
            </div>
          </div>
        ) : (
          <button
            type="button"
            onClick={() => setIsExpanded(true)}
            className="h-12 w-12 rounded-full bg-theme-interactive-primary text-white shadow-lg hover:bg-theme-interactive-primary-hover flex items-center justify-center transition-all hover:scale-105"
            aria-label="Open AI Chat"
          >
            <Bot className="h-6 w-6" />
          </button>
        )}
      </div>

      {/* Chat slideout */}
      <AgentChatSlideout
        agentId={selectedAgentId}
        agentName={selectedAgentName || 'AI Agent'}
        isOpen={isChatOpen}
        onClose={() => setIsChatOpen(false)}
      />
    </>
  );
};
