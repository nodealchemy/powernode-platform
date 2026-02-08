import React, { useState, useEffect, useMemo } from 'react';
import { X, Loader2 } from 'lucide-react';
import { AgentConversationComponent } from '@/features/ai/components/AgentConversationComponent';
import { chatApi, ChatConversation } from '../services/chatApi';
import type { AiConversation } from '@/shared/types/ai';

interface AgentChatSlideoutProps {
  agentId: string;
  agentName: string;
  isOpen: boolean;
  onClose: () => void;
}

export const AgentChatSlideout: React.FC<AgentChatSlideoutProps> = ({
  agentId,
  agentName,
  isOpen,
  onClose
}) => {
  const [rawConversation, setRawConversation] = useState<ChatConversation | null>(null);
  const [loading, setLoading] = useState(false);

  const conversationInput = useMemo((): AiConversation | null => {
    if (!rawConversation) return null;
    return {
      id: rawConversation.id,
      title: 'Chat Session',
      status: rawConversation.status as AiConversation['status'],
      ai_agent: { id: agentId, name: agentName, agent_type: 'assistant' },
      metadata: {
        created_by: '',
        total_messages: rawConversation.messages?.length ?? 0,
        total_tokens: 0,
        total_cost: 0,
        last_activity: rawConversation.created_at,
      },
      created_at: rawConversation.created_at,
      updated_at: rawConversation.created_at,
      message_count: rawConversation.messages?.length ?? 0,
    };
  }, [rawConversation, agentId, agentName]);

  useEffect(() => {
    if (isOpen && agentId) {
      const init = async () => {
        setLoading(true);
        try {
          const conv = await chatApi.getOrCreateConversation(agentId);
          setRawConversation(conv);
        } catch {
          // Error handled silently
        } finally {
          setLoading(false);
        }
      };
      init();
    }
  }, [isOpen, agentId]);

  return (
    <>
      {/* Overlay */}
      {isOpen && (
        <div
          className="fixed inset-0 bg-black/30 z-40 transition-opacity"
          onClick={onClose}
        />
      )}

      {/* Slide-out panel */}
      <div
        className={`fixed top-0 right-0 h-full w-[400px] bg-theme-background border-l border-theme shadow-xl z-50 flex flex-col transition-transform duration-300 ease-in-out ${
          isOpen ? 'translate-x-0' : 'translate-x-full'
        }`}
      >
        {/* Header */}
        <div className="flex items-center justify-between px-4 py-3 border-b border-theme bg-theme-surface">
          <div className="flex items-center gap-2">
            <div className="h-2 w-2 rounded-full bg-theme-success" />
            <h3 className="text-sm font-semibold text-theme-primary truncate">{agentName}</h3>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="p-1 rounded-md hover:bg-theme-surface-hover text-theme-secondary transition-colors"
            aria-label="Close chat"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Body */}
        <div className="flex-1 overflow-hidden">
          {loading ? (
            <div className="flex items-center justify-center h-full">
              <Loader2 className="h-6 w-6 animate-spin text-theme-primary" />
            </div>
          ) : conversationInput ? (
            <AgentConversationComponent
              conversation={conversationInput}
            />
          ) : (
            <div className="flex items-center justify-center h-full text-theme-secondary text-sm">
              Unable to load conversation
            </div>
          )}
        </div>
      </div>
    </>
  );
};
