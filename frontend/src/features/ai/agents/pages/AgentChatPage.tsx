import React, { useState, useEffect, useCallback } from 'react';
import { useParams } from 'react-router-dom';
import { Plus, MessageSquare, Clock } from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { Button } from '@/shared/components/ui/Button';
import { Loading } from '@/shared/components/ui/Loading';
import { Badge } from '@/shared/components/ui/Badge';
import { AgentConversationComponent } from '@/features/ai/components/AgentConversationComponent';
import { ConversationCreateModal } from '@/features/ai/conversations/components/ConversationCreateModal';
import { agentsApi } from '@/shared/services/ai';
import { cn } from '@/shared/utils/cn';
import type { AiAgent, AiConversation } from '@/shared/types/ai';

export const AgentChatPage: React.FC = () => {
  const { agentId } = useParams<{ agentId: string }>();
  const [agent, setAgent] = useState<AiAgent | null>(null);
  const [conversations, setConversations] = useState<AiConversation[]>([]);
  const [activeConversation, setActiveConversation] = useState<AiConversation | null>(null);
  const [loading, setLoading] = useState(true);
  const [showCreateModal, setShowCreateModal] = useState(false);

  const loadData = useCallback(async () => {
    if (!agentId) return;
    try {
      setLoading(true);
      const [agentRes, convsRes] = await Promise.all([
        agentsApi.getAgent(agentId),
        agentsApi.getConversations(agentId, { per_page: 50 }),
      ]);
      setAgent(agentRes);
      const items = convsRes.items || [];
      setConversations(items);

      // Auto-select most recent active conversation
      if (!activeConversation && items.length > 0) {
        const active = items.find((c: AiConversation) => c.status === 'active') || items[0];
        setActiveConversation(active);
      }
    } catch (_error) {
      // Error handled silently - empty state will show
    } finally {
      setLoading(false);
    }
  }, [agentId]);

  useEffect(() => {
    loadData();
  }, [loadData]);

  const handleConversationCreated = (conversation: AiConversation) => {
    setShowCreateModal(false);
    setConversations(prev => [conversation, ...prev]);
    setActiveConversation(conversation);
  };

  const formatTime = (dateStr?: string) => {
    if (!dateStr) return '';
    const date = new Date(dateStr);
    const now = new Date();
    const diff = now.getTime() - date.getTime();
    const mins = Math.floor(diff / 60000);
    if (mins < 60) return `${mins}m ago`;
    const hours = Math.floor(mins / 60);
    if (hours < 24) return `${hours}h ago`;
    const days = Math.floor(hours / 24);
    return `${days}d ago`;
  };

  const breadcrumbs = [
    { label: 'Dashboard', href: '/app' },
    { label: 'AI', href: '/app/ai' },
    { label: 'Agents', href: '/app/ai/agents' },
    { label: agent?.name || 'Agent' },
    { label: 'Chat' },
  ];

  if (loading) {
    return (
      <PageContainer title="Agent Chat" description="Loading..." breadcrumbs={breadcrumbs}>
        <div className="flex items-center justify-center p-12">
          <Loading size="lg" />
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer
      title={agent ? `Chat with ${agent.name}` : 'Agent Chat'}
      description={agent?.description || 'Full-page agent conversation interface'}
      breadcrumbs={breadcrumbs}
    >
      <div className="flex h-[calc(100vh-220px)] rounded-lg border border-theme-border overflow-hidden bg-theme-bg-primary">
        {/* Left Sidebar - Conversations */}
        <div className="w-72 border-r border-theme-border flex flex-col shrink-0">
          <div className="p-3 border-b border-theme-border">
            <Button
              variant="primary"
              size="sm"
              className="w-full flex items-center gap-2"
              onClick={() => setShowCreateModal(true)}
            >
              <Plus className="w-4 h-4" />
              New Conversation
            </Button>
          </div>

          <div className="flex-1 overflow-y-auto">
            {conversations.length === 0 ? (
              <div className="p-4 text-center text-sm text-theme-text-secondary">
                <MessageSquare className="w-8 h-8 mx-auto mb-2 opacity-40" />
                No conversations yet
              </div>
            ) : (
              <div className="divide-y divide-theme-border">
                {conversations.map((conv) => (
                  <button
                    key={conv.id}
                    className={cn(
                      'w-full text-left p-3 hover:bg-theme-bg-secondary transition-colors',
                      activeConversation?.id === conv.id && 'bg-theme-bg-secondary'
                    )}
                    onClick={() => setActiveConversation(conv)}
                  >
                    <div className="flex items-start justify-between gap-2">
                      <span className="text-sm font-medium text-theme-text-primary truncate">
                        {conv.title}
                      </span>
                      <Badge
                        variant={conv.status === 'active' ? 'success' : 'outline'}
                        size="sm"
                      >
                        {conv.status}
                      </Badge>
                    </div>
                    <div className="flex items-center gap-2 mt-1">
                      <span className="text-xs text-theme-text-secondary">
                        {conv.metadata?.total_messages || 0} messages
                      </span>
                      {conv.metadata?.last_activity && (
                        <span className="text-xs text-theme-text-secondary flex items-center gap-0.5">
                          <Clock className="w-3 h-3" />
                          {formatTime(conv.metadata.last_activity)}
                        </span>
                      )}
                    </div>
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>

        {/* Right Panel - Chat */}
        <div className="flex-1 min-w-0 flex flex-col">
          {activeConversation ? (
            <AgentConversationComponent
              conversation={activeConversation}
              onConversationUpdate={(updated) => {
                setActiveConversation(updated as AiConversation);
                setConversations(prev =>
                  prev.map(c => c.id === (updated as AiConversation).id ? updated as AiConversation : c)
                );
              }}
            />
          ) : (
            <div className="flex-1 flex items-center justify-center">
              <div className="text-center">
                <MessageSquare className="w-12 h-12 mx-auto mb-3 text-theme-text-secondary opacity-40" />
                <p className="text-theme-text-secondary">
                  {conversations.length > 0
                    ? 'Select a conversation to continue chatting'
                    : 'Start a new conversation to begin'}
                </p>
                <Button
                  variant="primary"
                  size="sm"
                  className="mt-4"
                  onClick={() => setShowCreateModal(true)}
                >
                  <Plus className="w-4 h-4 mr-2" />
                  New Conversation
                </Button>
              </div>
            </div>
          )}
        </div>
      </div>

      <ConversationCreateModal
        isOpen={showCreateModal}
        onClose={() => setShowCreateModal(false)}
        onConversationCreated={handleConversationCreated}
        preselectedAgentId={agentId}
      />
    </PageContainer>
  );
};

export default AgentChatPage;
