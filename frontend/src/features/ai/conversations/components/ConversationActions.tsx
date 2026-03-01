import React from 'react';
import { MessageCircle, Archive, Download } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { agentsApi } from '@/shared/services/ai';
import { useNotifications } from '@/shared/hooks/useNotifications';
import type { AiConversation } from '@/shared/types/ai';

interface ConversationActionsProps {
  conversation: AiConversation;
  agentId: string;
  canManageConversations: boolean;
  canContinueConversations: boolean;
  onClose: () => void;
  onContinue?: (conversationId: string) => void;
  onArchive?: (conversationId: string) => void;
  onExport?: (conversationId: string) => void;
}

export const ConversationActions: React.FC<ConversationActionsProps> = ({
  conversation,
  agentId,
  canManageConversations,
  canContinueConversations,
  onClose,
  onContinue,
  onArchive,
  onExport,
}) => {
  const { addNotification } = useNotifications();

  const handleContinue = () => {
    onContinue?.(conversation.id);
    onClose();
  };

  const handleArchive = async () => {
    try {
      if (conversation.status === 'archived') {
        await agentsApi.resumeConversation(agentId, conversation.id);
      } else {
        await agentsApi.archiveConversation(agentId, conversation.id);
      }
      addNotification({
        type: 'success',
        title: `Conversation ${conversation.status === 'archived' ? 'Resumed' : 'Archived'}`,
        message: `Successfully ${conversation.status === 'archived' ? 'resumed' : 'archived'} the conversation`,
      });
      onArchive?.(conversation.id);
      onClose();
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Action Failed',
        message: 'Failed to update conversation status',
      });
    }
  };

  const handleExport = async () => {
    try {
      const response = await agentsApi.exportConversation(agentId, conversation.id);
      if (response.download_url) {
        window.open(response.download_url, '_blank');
      }
      addNotification({
        type: 'success',
        title: 'Export Started',
        message: 'Conversation export has been initiated',
      });
      onExport?.(conversation.id);
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Export Failed',
        message: 'Failed to export conversation',
      });
    }
  };

  return (
    <div className="flex gap-3">
      <Button variant="outline" onClick={onClose}>
        Close
      </Button>
      {canManageConversations && (
        <>
          <Button variant="outline" onClick={handleExport}>
            <Download className="h-4 w-4 mr-2" />
            Export
          </Button>
          <Button variant="outline" onClick={handleArchive}>
            <Archive className="h-4 w-4 mr-2" />
            {conversation.status === 'archived' ? 'Unarchive' : 'Archive'}
          </Button>
        </>
      )}
      {canContinueConversations && conversation.status === 'active' && (
        <Button
          onClick={handleContinue}
          className="bg-theme-interactive-primary hover:bg-theme-interactive-primary/80"
        >
          <MessageCircle className="h-4 w-4 mr-2" />
          Continue Chat
        </Button>
      )}
    </div>
  );
};
