import React, { useEffect } from 'react';
import { X } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { AgentConversationComponent } from '@/features/ai/components/AgentConversationComponent';
import type { AiConversation } from '@/shared/types/ai';
import type { ConversationBase } from '@/shared/services/ai/ConversationsApiService';

// Union type to accept either conversation format
type ConversationInput = AiConversation | ConversationBase;

interface ConversationContinueModalProps {
  isOpen: boolean;
  onClose: () => void;
  conversation: ConversationInput;
  onConversationUpdate?: (conversation: ConversationInput) => void;
}

export const ConversationContinueModal: React.FC<ConversationContinueModalProps> = ({
  isOpen,
  onClose,
  conversation,
  onConversationUpdate
}) => {
  // Handle escape key
  useEffect(() => {
    const handleEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        onClose();
      }
    };

    if (isOpen) {
      document.addEventListener('keydown', handleEscape);
      // Prevent body scroll
      document.body.style.overflow = 'hidden';
    }

    return () => {
      document.removeEventListener('keydown', handleEscape);
      document.body.style.overflow = 'unset';
    };
  }, [isOpen, onClose]);

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 z-[9999] bg-theme-background flex flex-col">
      {/* Header with Close Button */}
      <div className="flex items-center justify-between p-4 border-b border-theme/20 bg-theme-surface/40 backdrop-blur-sm shrink-0 relative z-10">
        <div className="flex items-center gap-3">
          <h2 className="text-lg font-semibold text-theme-primary">
            {conversation.title}
          </h2>
          <span className="text-sm text-theme-secondary">
            with {conversation.ai_agent?.name || 'AI Agent'}
          </span>
        </div>
        <Button
          variant="ghost"
          size="sm"
          onClick={onClose}
          className="h-10 w-10 p-0 rounded-full hover:bg-theme-surface-hover"
          title="Close conversation"
        >
          <X className="h-5 w-5" />
        </Button>
      </div>

      {/* Chat Interface - Full height minus header */}
      <div className="flex-1 min-h-0 overflow-hidden">
        <AgentConversationComponent
          conversation={conversation}
          onConversationUpdate={onConversationUpdate}
        />
      </div>
    </div>
  );
};