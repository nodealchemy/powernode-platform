import React, { useState, useEffect } from 'react';
import { MessageSquare } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/shared/components/ui/Tabs';
import { agentsApi, conversationsApi } from '@/shared/services/ai';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { AiConversation, AiMessage } from '@/shared/types/ai';
import { MessageThread } from './MessageThread';
import { ConversationStatsPanel } from './ConversationStatsPanel';
import { ConversationActions } from './ConversationActions';

interface ConversationStats {
  message_count?: number;
  user_message_count?: number;
  ai_response_count?: number;
  avg_response_time?: number;
  total_tokens?: number;
  total_cost?: number;
  duration_minutes?: number;
}

export interface ConversationDetailModalProps {
  isOpen: boolean;
  onClose: () => void;
  agentId: string;
  conversationId: string;
  onContinue?: (conversationId: string) => void;
  onArchive?: (conversationId: string) => void;
  onExport?: (conversationId: string) => void;
}

export const ConversationDetailModal: React.FC<ConversationDetailModalProps> = ({
  isOpen,
  onClose,
  agentId,
  conversationId,
  onContinue,
  onArchive,
  onExport,
}) => {
  const { currentUser } = useAuth();
  const { addNotification } = useNotifications();

  const [conversation, setConversation] = useState<AiConversation | null>(null);
  const [messages, setMessages] = useState<AiMessage[]>([]);
  const [stats, setStats] = useState<ConversationStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const canManageConversations = currentUser?.permissions?.includes('ai.conversations.manage') || false;
  const canContinueConversations = currentUser?.permissions?.includes('ai.conversations.read') || false;

  const loadConversation = async () => {
    if (!conversationId || !isOpen) return;

    try {
      setLoading(true);
      setError(null);

      let effectiveAgentId = agentId;
      if (!effectiveAgentId) {
        try {
          const convData = await conversationsApi.getConversation(conversationId);
          effectiveAgentId = convData.ai_agent?.id || (convData as unknown as { agent_id?: string }).agent_id || '';
          if (!effectiveAgentId) throw new Error('Unable to determine agent for this conversation');
        } catch (_e) {
          setError('Failed to load conversation - agent information not available');
          setLoading(false);
          return;
        }
      }

      const conv = await agentsApi.getConversation(effectiveAgentId, conversationId);
      setConversation(conv);

      const response = await agentsApi.getMessages(effectiveAgentId, conversationId);
      setMessages(response.messages);

      try {
        const conversationStats = await conversationsApi.getConversationStats(conversationId);
        setStats(conversationStats);
      } catch (_error) {
        // Stats are optional
      }
    } catch (_error) {
      setError('Failed to load conversation details. Please try again.');
      addNotification({ type: 'error', title: 'Error', message: 'Failed to load conversation details' });
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (isOpen && conversationId) {
      setConversation(null);
      setMessages([]);
      setStats(null);
      setLoading(true);
      setError(null);
      loadConversation();
    }
  }, [isOpen, conversationId, agentId]);

  if (loading || !conversation) {
    return (
      <Modal isOpen={isOpen} onClose={onClose} title="Loading Conversation..." maxWidth="4xl" icon={<MessageSquare />}
        footer={<Button variant="outline" onClick={onClose}>Close</Button>}>
        <LoadingSpinner className="py-12" />
      </Modal>
    );
  }

  if (error) {
    return (
      <Modal isOpen={isOpen} onClose={onClose} title="Error Loading Conversation" maxWidth="md" icon={<MessageSquare />}
        footer={<Button variant="outline" onClick={onClose}>Close</Button>}>
        <div className="text-center py-8">
          <p className="text-theme-danger">{error}</p>
          <Button variant="outline" onClick={loadConversation} className="mt-4">Try Again</Button>
        </div>
      </Modal>
    );
  }

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={conversation.title || 'Conversation Details'}
      maxWidth="4xl"
      variant="centered"
      icon={<MessageSquare />}
      footer={
        <ConversationActions
          conversation={conversation}
          agentId={agentId}
          canManageConversations={canManageConversations}
          canContinueConversations={canContinueConversations}
          onClose={onClose}
          onContinue={onContinue}
          onArchive={onArchive}
          onExport={onExport}
        />
      }
    >
      <div className="space-y-6">
        <ConversationStatsPanel conversation={conversation} stats={stats} section="header" />

        <Tabs defaultValue="overview" className="space-y-6">
          <TabsList className="w-full justify-start">
            <TabsTrigger value="overview">Overview</TabsTrigger>
            <TabsTrigger value="messages">Recent Messages</TabsTrigger>
            <TabsTrigger value="stats">Statistics</TabsTrigger>
            <TabsTrigger value="settings">Details</TabsTrigger>
          </TabsList>

          <TabsContent value="overview" className="space-y-6">
            <ConversationStatsPanel conversation={conversation} stats={stats} section="overview" />
          </TabsContent>

          <TabsContent value="messages" className="space-y-4">
            <Card>
              <CardHeader title="Recent Messages" />
              <CardContent>
                <MessageThread messages={messages} conversation={conversation} />
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="stats" className="space-y-4">
            <Card>
              <CardHeader title="Detailed Statistics" />
              <CardContent>
                <ConversationStatsPanel conversation={conversation} stats={stats} section="stats" />
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="settings" className="space-y-4">
            <Card>
              <CardHeader title="Conversation Details" />
              <CardContent>
                <ConversationStatsPanel conversation={conversation} stats={stats} section="details" />
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>
      </div>
    </Modal>
  );
};
