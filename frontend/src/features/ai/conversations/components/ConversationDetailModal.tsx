import React, { useState, useEffect } from 'react';
import {
  MessageSquare,
  Bot,
  User,
  BarChart3,
  Activity,
  MessageCircle,
  DollarSign,
  Archive,
  Download
} from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/shared/components/ui/Tabs';
import { agentsApi, conversationsApi } from '@/shared/services/ai';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { AiConversation, AiMessage } from '@/shared/types/ai';

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
  onExport
}) => {
  const { currentUser } = useAuth();
  const { addNotification } = useNotifications();

  const [conversation, setConversation] = useState<AiConversation | null>(null);
  const [messages, setMessages] = useState<AiMessage[]>([]);
  const [stats, setStats] = useState<ConversationStats | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Check permissions
  const canManageConversations = currentUser?.permissions?.includes('ai.conversations.manage') || false;
  const canContinueConversations = currentUser?.permissions?.includes('ai.conversations.read') || false;

  // Load conversation details
  const loadConversation = async () => {
    if (!conversationId || !isOpen) return;

    try {
      setLoading(true);
      setError(null);

      // Determine the agentId to use - either from prop or we need to fetch it
      let effectiveAgentId = agentId;

      // If agentId is not provided, try to get the conversation first to get the agentId
      if (!effectiveAgentId) {
        try {
          // Use conversationsApi to get the conversation without agentId
          const convData = await conversationsApi.getConversation(conversationId);
          effectiveAgentId = convData.ai_agent?.id || (convData as unknown as { agent_id?: string }).agent_id || '';
          if (!effectiveAgentId) {
            throw new Error('Unable to determine agent for this conversation');
          }
        } catch (_e) {
          setError('Failed to load conversation - agent information not available');
          setLoading(false);
          return;
        }
      }

      // Load conversation details
      const conversation = await agentsApi.getConversation(effectiveAgentId, conversationId);
      setConversation(conversation);

      // Load recent messages
      const messages = await agentsApi.getMessages(effectiveAgentId, conversationId);
      setMessages(messages);

      // Load conversation stats
      try {
        const conversationStats = await conversationsApi.getConversationStats(conversationId);
        setStats(conversationStats);
      } catch (_error) {
        // Stats are optional - don't fail the whole load if they're not available
      }

    } catch (_error) {
      setError('Failed to load conversation details. Please try again.');
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to load conversation details'
      });
    } finally {
      setLoading(false);
    }
  };

  // Reset state and load when modal opens
  useEffect(() => {
    if (isOpen && conversationId) {
      // Reset state for fresh load
      setConversation(null);
      setMessages([]);
      setStats(null);
      setLoading(true);
      setError(null);
      loadConversation();
    }
  }, [isOpen, conversationId, agentId]);  

  // Handle actions
  const handleContinue = () => {
    if (!conversation) return;
    onContinue?.(conversation.id);
    onClose();
  };

  const handleArchive = async () => {
    if (!conversation) return;

    try {
      if (conversation.status === 'archived') {
        await agentsApi.resumeConversation(agentId, conversation.id);
      } else {
        await agentsApi.archiveConversation(agentId, conversation.id);
      }

      addNotification({
        type: 'success',
        title: `Conversation ${conversation.status === 'archived' ? 'Resumed' : 'Archived'}`,
        message: `Successfully ${conversation.status === 'archived' ? 'resumed' : 'archived'} the conversation`
      });

      onArchive?.(conversation.id);
      onClose();
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Action Failed',
        message: 'Failed to update conversation status'
      });
    }
  };

  const handleExport = async () => {
    if (!conversation) return;

    try {
      const response = await agentsApi.exportConversation(agentId, conversation.id);

      // Handle export response - may have download_url or blob data
      if (response.download_url) {
        window.open(response.download_url, '_blank');
      }

      addNotification({
        type: 'success',
        title: 'Export Started',
        message: 'Conversation export has been initiated'
      });

      onExport?.(conversation.id);
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Export Failed',
        message: 'Failed to export conversation'
      });
    }
  };

  // Status badge rendering
  const renderStatusBadge = (status: string) => {
    const statusConfig = {
      active: { variant: 'success' as const, label: 'Active' },
      completed: { variant: 'info' as const, label: 'Completed' },
      archived: { variant: 'secondary' as const, label: 'Archived' },
      error: { variant: 'danger' as const, label: 'Error' }
    };

    const config = statusConfig[status as keyof typeof statusConfig] || statusConfig.active;

    return (
      <Badge variant={config.variant} size="sm">
        {config.label}
      </Badge>
    );
  };

  // Format currency
  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: 4
    }).format(amount);
  };

  // Format date safely
  const formatDate = (dateStr: string | undefined | null, format: 'date' | 'time' | 'full' = 'full') => {
    if (!dateStr) return 'N/A';
    const date = new Date(dateStr);
    if (isNaN(date.getTime())) return 'N/A';

    switch (format) {
      case 'date':
        return date.toLocaleDateString();
      case 'time':
        return date.toLocaleTimeString();
      case 'full':
      default:
        return date.toLocaleString();
    }
  };

  // Modal footer with actions
  const footer = (
    <div className="flex gap-3">
      <Button variant="outline" onClick={onClose}>
        Close
      </Button>
      {canManageConversations && conversation && (
        <>
          <Button
            variant="outline"
            onClick={handleExport}
          >
            <Download className="h-4 w-4 mr-2" />
            Export
          </Button>
          <Button
            variant="outline"
            onClick={handleArchive}
          >
            <Archive className="h-4 w-4 mr-2" />
            {conversation.status === 'archived' ? 'Unarchive' : 'Archive'}
          </Button>
        </>
      )}
      {canContinueConversations && conversation?.status === 'active' && (
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

  // Loading state
  if (loading || !conversation) {
    return (
      <Modal
        isOpen={isOpen}
        onClose={onClose}
        title="Loading Conversation..."
        maxWidth="4xl"
        icon={<MessageSquare />}
        footer={
          <Button variant="outline" onClick={onClose}>
            Close
          </Button>
        }
      >
        <div className="flex items-center justify-center py-12">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-interactive-primary"></div>
        </div>
      </Modal>
    );
  }

  // Error state
  if (error) {
    return (
      <Modal
        isOpen={isOpen}
        onClose={onClose}
        title="Error Loading Conversation"
        maxWidth="md"
        icon={<MessageSquare />}
        footer={
          <Button variant="outline" onClick={onClose}>
            Close
          </Button>
        }
      >
        <div className="text-center py-8">
          <p className="text-theme-danger">{error}</p>
          <Button
            variant="outline"
            onClick={loadConversation}
            className="mt-4"
          >
            Try Again
          </Button>
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
      footer={footer}
    >
      <div className="space-y-6">
        {/* Header Stats */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          <Card>
            <CardContent className="p-4">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm text-theme-muted">Status</p>
                  {renderStatusBadge(conversation.status)}
                </div>
                <Activity className="h-5 w-5 text-theme-muted" />
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-4">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm text-theme-muted">Messages</p>
                  <p className="text-lg font-semibold text-theme-primary">
                    {conversation.metadata?.total_messages || conversation.message_count || 0}
                  </p>
                </div>
                <MessageCircle className="h-5 w-5 text-theme-muted" />
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-4">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm text-theme-muted">Total Cost</p>
                  <p className="text-lg font-semibold text-theme-primary">
                    {formatCurrency(conversation.metadata?.total_cost || 0)}
                  </p>
                </div>
                <DollarSign className="h-5 w-5 text-theme-muted" />
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardContent className="p-4">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm text-theme-muted">Tokens Used</p>
                  <p className="text-lg font-semibold text-theme-primary">
                    {(conversation.metadata?.total_tokens || 0).toLocaleString()}
                  </p>
                </div>
                <BarChart3 className="h-5 w-5 text-theme-muted" />
              </div>
            </CardContent>
          </Card>
        </div>

        {/* Main Content Tabs */}
        <Tabs defaultValue="overview" className="space-y-6">
          <TabsList className="w-full justify-start">
            <TabsTrigger value="overview">Overview</TabsTrigger>
            <TabsTrigger value="messages">Recent Messages</TabsTrigger>
            <TabsTrigger value="stats">Statistics</TabsTrigger>
            <TabsTrigger value="settings">Details</TabsTrigger>
          </TabsList>

          <TabsContent value="overview" className="space-y-6">
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
              <Card>
                <CardHeader title="Conversation Information" />
                <CardContent className="space-y-4">
                  <div>
                    <label className="text-sm font-medium text-theme-muted">AI Agent</label>
                    <div className="mt-1 flex items-center gap-2">
                      <Bot className="h-4 w-4 text-theme-muted" />
                      <span className="text-theme-primary">{conversation.ai_agent?.name || 'Unknown Agent'}</span>
                      {conversation.ai_agent?.agent_type && (
                        <Badge variant="outline" size="sm">
                          {conversation.ai_agent.agent_type.replace('_', ' ')}
                        </Badge>
                      )}
                    </div>
                  </div>

                  <div>
                    <label className="text-sm font-medium text-theme-muted">Status</label>
                    <p className="mt-1 text-theme-primary capitalize">{conversation.status}</p>
                  </div>

                  <div>
                    <label className="text-sm font-medium text-theme-muted">Created</label>
                    <p className="mt-1 text-theme-primary">
                      {formatDate(conversation.created_at, 'date')} at{' '}
                      {formatDate(conversation.created_at, 'time')}
                    </p>
                  </div>

                  <div>
                    <label className="text-sm font-medium text-theme-muted">Last Activity</label>
                    <p className="mt-1 text-theme-primary">
                      {formatDate(conversation.metadata?.last_activity || conversation.updated_at)}
                    </p>
                  </div>
                </CardContent>
              </Card>

              <Card>
                <CardHeader title="Usage Statistics" />
                <CardContent className="space-y-4">
                  <div className="flex justify-between">
                    <span className="text-theme-muted">Total Messages:</span>
                    <span className="font-medium text-theme-primary">
                      {conversation.metadata?.total_messages || conversation.message_count || 0}
                    </span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-theme-muted">Total Tokens:</span>
                    <span className="font-medium text-theme-primary">
                      {(conversation.metadata?.total_tokens || 0).toLocaleString()}
                    </span>
                  </div>
                  <div className="flex justify-between">
                    <span className="text-theme-muted">Total Cost:</span>
                    <span className="font-medium text-theme-primary">
                      {formatCurrency(conversation.metadata?.total_cost || 0)}
                    </span>
                  </div>
                  {stats && (
                    <>
                      <div className="flex justify-between">
                        <span className="text-theme-muted">Avg Response Time:</span>
                        <span className="font-medium text-theme-primary">
                          {stats.avg_response_time ? `${stats.avg_response_time}ms` : 'N/A'}
                        </span>
                      </div>
                      <div className="flex justify-between">
                        <span className="text-theme-muted">Duration:</span>
                        <span className="font-medium text-theme-primary">
                          {stats.duration_minutes ? `${Math.round(stats.duration_minutes)} min` : 'N/A'}
                        </span>
                      </div>
                    </>
                  )}
                </CardContent>
              </Card>
            </div>
          </TabsContent>

          <TabsContent value="messages" className="space-y-4">
            <Card>
              <CardHeader title="Recent Messages" />
              <CardContent>
                {messages && messages.length > 0 ? (
                  <div className="space-y-4">
                    {messages.map((message) => (
                      <div
                        key={message.id}
                        className={`p-3 rounded-lg border ${
                          message.sender_type === 'user'
                            ? 'bg-theme-primary-subtle border-theme-primary/20 ml-8'
                            : 'bg-theme-surface border-theme/20 mr-8'
                        }`}
                      >
                        <div className="flex items-center gap-2 mb-2">
                          <div className="flex-shrink-0 flex items-center justify-center w-5 h-5">
                            {message.sender_type === 'user' ? (
                              <User className="h-4 w-4 text-theme-primary" />
                            ) : (
                              <Bot className="h-4 w-4 text-theme-muted" />
                            )}
                          </div>
                          <span className="text-sm font-medium text-theme-primary">
                            {message.sender_type === 'user'
                              ? message.sender_info?.name || 'User'
                              : conversation.ai_agent?.name || 'AI Assistant'
                            }
                          </span>
                          <span className="text-xs text-theme-muted">
                            {formatDate(message.created_at, 'time')}
                          </span>
                        </div>
                        <p className="text-theme-primary text-sm">{message.content}</p>
                        {message.metadata?.tokens_used && (
                          <div className="mt-2 text-xs text-theme-muted">
                            Tokens: {message.metadata.tokens_used}
                            {message.metadata?.cost_estimate && (
                              <> • Cost: {formatCurrency(message.metadata.cost_estimate)}</>
                            )}
                          </div>
                        )}
                      </div>
                    ))}
                  </div>
                ) : (
                  <p className="text-theme-muted">No messages found in this conversation.</p>
                )}
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="stats" className="space-y-4">
            <Card>
              <CardHeader title="Detailed Statistics" />
              <CardContent>
                {stats ? (
                  <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                    <div className="space-y-3">
                      <h4 className="font-medium text-theme-primary">Message Statistics</h4>
                      <div className="space-y-2 text-sm">
                        <div className="flex justify-between">
                          <span className="text-theme-muted">Total Messages:</span>
                          <span className="text-theme-primary">{stats.message_count}</span>
                        </div>
                        <div className="flex justify-between">
                          <span className="text-theme-muted">User Messages:</span>
                          <span className="text-theme-primary">{stats.user_message_count}</span>
                        </div>
                        <div className="flex justify-between">
                          <span className="text-theme-muted">AI Responses:</span>
                          <span className="text-theme-primary">{stats.ai_response_count}</span>
                        </div>
                      </div>
                    </div>

                    <div className="space-y-3">
                      <h4 className="font-medium text-theme-primary">Performance</h4>
                      <div className="space-y-2 text-sm">
                        <div className="flex justify-between">
                          <span className="text-theme-muted">Avg Response Time:</span>
                          <span className="text-theme-primary">
                            {stats.avg_response_time ? `${stats.avg_response_time}ms` : 'N/A'}
                          </span>
                        </div>
                        <div className="flex justify-between">
                          <span className="text-theme-muted">Total Tokens:</span>
                          <span className="text-theme-primary">{stats.total_tokens?.toLocaleString()}</span>
                        </div>
                        <div className="flex justify-between">
                          <span className="text-theme-muted">Total Cost:</span>
                          <span className="text-theme-primary">{formatCurrency(stats.total_cost || 0)}</span>
                        </div>
                        <div className="flex justify-between">
                          <span className="text-theme-muted">Duration:</span>
                          <span className="text-theme-primary">
                            {stats.duration_minutes ? `${Math.round(stats.duration_minutes)} minutes` : 'N/A'}
                          </span>
                        </div>
                      </div>
                    </div>
                  </div>
                ) : (
                  <p className="text-theme-muted">No detailed statistics available for this conversation.</p>
                )}
              </CardContent>
            </Card>
          </TabsContent>

          <TabsContent value="settings" className="space-y-4">
            <Card>
              <CardHeader title="Conversation Details" />
              <CardContent className="space-y-4">
                <div>
                  <label className="text-sm font-medium text-theme-muted">Conversation ID</label>
                  <p className="mt-1 text-theme-primary font-mono text-sm">{conversation.id}</p>
                </div>

                <div>
                  <label className="text-sm font-medium text-theme-muted">AI Agent ID</label>
                  <p className="mt-1 text-theme-primary font-mono text-sm">{conversation.ai_agent?.id || 'N/A'}</p>
                </div>

                <div>
                  <label className="text-sm font-medium text-theme-muted">Created At</label>
                  <p className="mt-1 text-theme-primary">{formatDate(conversation.created_at)}</p>
                </div>

                <div>
                  <label className="text-sm font-medium text-theme-muted">Last Updated</label>
                  <p className="mt-1 text-theme-primary">{formatDate(conversation.updated_at)}</p>
                </div>

                {conversation.metadata && Object.keys(conversation.metadata).length > 0 && (
                  <div>
                    <label className="text-sm font-medium text-theme-muted">Additional Metadata</label>
                    <pre className="mt-1 text-xs bg-theme-surface p-3 rounded border text-theme-primary overflow-x-auto">
                      {JSON.stringify(conversation.metadata, null, 2)}
                    </pre>
                  </div>
                )}
              </CardContent>
            </Card>
          </TabsContent>
        </Tabs>
      </div>
    </Modal>
  );
};