import React, { useState, useEffect, useCallback } from 'react';
import {
  MessageSquare,
  Plus,
  Download,
  Archive,
  Copy,
  Trash2,
  Eye,
  MessageCircle,
  CheckCircle,
  XCircle,
  Bot
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { DataTable } from '@/shared/components/ui/DataTable';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { SearchInput } from '@/shared/components/ui/SearchInput';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import { agentsApi, conversationsApi, GlobalConversationFilters } from '@/shared/services/ai';
import { ConversationBase } from '@/shared/services/ai/ConversationsApiService';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { useAiOrchestrationWebSocket } from '@/shared/hooks/useAiOrchestrationWebSocket';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { AiAgent } from '@/shared/types/ai';
import { ConversationCreateModal } from '@/features/ai/conversations/components/ConversationCreateModal';
import { ConversationDetailModal } from '@/features/ai/conversations/components/ConversationDetailModal';
import { ConversationContinueModal } from '@/features/ai/conversations/components/ConversationContinueModal';

// Local filter type for the page
interface PageFilters {
  status?: 'active' | 'paused' | 'completed' | 'archived';
  agent_id?: string;
}

export const AIConversationsPage: React.FC = () => {
  const { currentUser } = useAuth();
  const { addNotification } = useNotifications();
  const { confirm, ConfirmationDialog } = useConfirmation();

  // WebSocket for real-time conversation updates
  useAiOrchestrationWebSocket({
    onAgentEvent: (event) => {
      // Refresh conversation list when agent messages are received or conversations end
      if (['agent_message_received', 'agent_execution_completed', 'agent_execution_failed'].includes(event.type)) {
        loadConversations(pagination.currentPage, pagination.perPage);
      }
    },
  });

  const [conversations, setConversations] = useState<ConversationBase[]>([]);
  const [availableAgents, setAvailableAgents] = useState<AiAgent[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [filters, setFilters] = useState<PageFilters>({});
  const [pagination, setPagination] = useState({
    currentPage: 1,
    totalPages: 1,
    totalCount: 0,
    perPage: 25
  });
  const [isCreateModalOpen, setIsCreateModalOpen] = useState(false);
  const [selectedConversationId, setSelectedConversationId] = useState<string | null>(null);
  const [chatConversationId, setChatConversationId] = useState<string | null>(null);

  // Check permissions
  const canCreateConversations = currentUser?.permissions?.includes('ai.conversations.create') || false;
  const canManageConversations = currentUser?.permissions?.includes('ai.conversations.manage') || false;

  // Load conversations function
  const loadConversations = async (page = 1, perPage = 25) => {
    try {
      setLoading(true);

      // Build filter object for API call
      const apiFilters: GlobalConversationFilters = {
        page,
        per_page: perPage,
        ...(searchQuery && { search: searchQuery }),
        ...(filters.status && { status: filters.status }),
        ...(filters.agent_id && { agent_id: filters.agent_id })
      };

      const response = await conversationsApi.getConversations(apiFilters);

      setConversations(response.items || []);
      setPagination({
        currentPage: response.pagination.current_page,
        totalPages: response.pagination.total_pages,
        totalCount: response.pagination.total_count,
        perPage: response.pagination.per_page
      });
    } catch (_error) {
      setConversations([]);
      setPagination({
        currentPage: 1,
        totalPages: 1,
        totalCount: 0,
        perPage: 25
      });
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to load conversations. Please try again.'
      });
    } finally {
      setLoading(false);
    }
  };

  // Load agents for filters
  const loadAgents = async () => {
    try {
      const response = await agentsApi.getAgents({ page: 1, per_page: 100 });
      // Response is PaginatedResponse<AiAgent> with items array
      setAvailableAgents(response.items || []);
    } catch (_error) {
      setAvailableAgents([]);
    }
  };

  // Initial load
  useEffect(() => {
    loadConversations(1, pagination.perPage);
    loadAgents();
  }, []);

  // Handle search
  const handleSearch = useCallback((query: string) => {
    setSearchQuery(query);
  }, []);

  // Debounced effect for search
  useEffect(() => {
    if (searchQuery === '') return;

    const timeoutId = setTimeout(() => {
      loadConversations(1, pagination.perPage);
    }, 300);

    return () => clearTimeout(timeoutId);
  }, [searchQuery]);

  // Handle filter changes
  const handleFilterChange = useCallback((key: keyof PageFilters, value: string | undefined) => {
    setFilters(prev => ({
      ...prev,
      [key]: value || undefined
    }));
  }, []);

  // Effect to reload conversations when filters change
  useEffect(() => {
    if (Object.keys(filters).length > 0 || Object.values(filters).some(v => v !== undefined && v !== '')) {
      loadConversations(1, pagination.perPage);
    }
  }, [filters]);

  // Handle conversation actions
  const handleViewConversation = (_conversation: ConversationBase) => {
    setSelectedConversationId(_conversation.id);
  };

  const handleContinueConversation = (conversationId: string) => {
    setChatConversationId(conversationId);
  };

  const handleExportConversation = async (_conversation: ConversationBase) => {
    try {
      const response = await agentsApi.exportConversation(_conversation.id, 'json');
      window.open(response.download_url, '_blank');

      addNotification({
        type: 'success',
        title: 'Export Started',
        message: 'Conversation export has been initiated'
      });
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Export Failed',
        message: 'Failed to export conversation'
      });
    }
  };

  const handleArchiveConversation = async (_conversation: ConversationBase) => {
    try {
      if (_conversation.status === 'archived') {
        await conversationsApi.unarchiveConversation(_conversation.id);
      } else {
        await conversationsApi.archiveConversation(_conversation.id);
      }

      addNotification({
        type: 'success',
        title: `Conversation ${_conversation.status === 'archived' ? 'Restored' : 'Archived'}`,
        message: `Successfully ${_conversation.status === 'archived' ? 'restored' : 'archived'} the conversation`
      });

      loadConversations(pagination.currentPage, pagination.perPage);
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Action Failed',
        message: 'Failed to update conversation status'
      });
    }
  };

  const handleDuplicateConversation = async (_conversation: ConversationBase) => {
    try {
      await conversationsApi.duplicateConversation(_conversation.id, {
        title: `Copy of ${_conversation.title || 'Conversation'}`,
        include_messages: false
      });

      addNotification({
        type: 'success',
        title: 'Conversation Duplicated',
        message: 'Successfully created a copy of the conversation'
      });

      loadConversations(pagination.currentPage, pagination.perPage);
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Duplicate Failed',
        message: 'Failed to duplicate conversation'
      });
    }
  };

  const handleDeleteConversation = (conversation: ConversationBase) => {
    confirm({
      title: 'Delete Conversation',
      message: `Are you sure you want to delete "${conversation.title || 'this conversation'}"? This action cannot be undone.`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        try {
          await conversationsApi.deleteConversation(conversation.id);

          addNotification({
            type: 'success',
            title: 'Conversation Deleted',
            message: 'Conversation has been permanently deleted'
          });

          loadConversations(pagination.currentPage, pagination.perPage);
        } catch (_error) {
          addNotification({
            type: 'error',
            title: 'Delete Failed',
            message: 'Failed to delete conversation'
          });
        }
      }
    });
  };

  // Handle conversation creation - accepts any conversation type since we just refresh the list
  const handleConversationCreated = () => {
    // Refresh the conversations list to show the new conversation
    loadConversations(1, pagination.perPage);
  };

  // Status badge rendering with theme-aware variants
  const renderStatusBadge = (status: string) => {
    const statusConfig = {
      active: { variant: 'success' as const, icon: CheckCircle },
      completed: { variant: 'info' as const, icon: CheckCircle },
      archived: { variant: 'secondary' as const, icon: Archive },
      error: { variant: 'danger' as const, icon: XCircle }
    };

    const config = statusConfig[status as keyof typeof statusConfig] || statusConfig.active;
    const IconComponent = config.icon;

    return (
      <Badge variant={config.variant} size="sm" className="min-w-fit whitespace-nowrap">
        <div className="flex items-center gap-1.5">
          <IconComponent className="h-3 w-3 flex-shrink-0" />
          <span className="flex-shrink-0">{status.charAt(0).toUpperCase() + status.slice(1)}</span>
        </div>
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

  // Format last activity
  const formatLastActivity = (timestamp: string) => {
    const date = new Date(timestamp);
    const now = new Date();
    const diffMs = now.getTime() - date.getTime();
    const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
    const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));

    if (diffHours < 1) {
      return 'Just now';
    } else if (diffHours < 24) {
      return `${diffHours}h ago`;
    } else if (diffDays === 1) {
      return 'Yesterday';
    } else if (diffDays < 7) {
      return `${diffDays}d ago`;
    } else {
      return date.toLocaleDateString();
    }
  };

  // Table columns
  const columns = [
    {
      key: 'title',
      header: 'Conversation',
      width: '35%',
      render: (conversation: ConversationBase) => (
        <div className="min-w-0">
          <div className="font-medium text-theme-primary whitespace-normal">
            {conversation.title}
          </div>
          <div className="text-sm text-theme-muted leading-relaxed whitespace-normal flex items-center gap-2">
            <Bot className="h-3 w-3 flex-shrink-0" />
            {conversation.ai_agent?.name || 'Unknown Agent'}
          </div>
        </div>
      )
    },
    {
      key: 'status',
      header: 'Status',
      width: '10%',
      render: (conversation: ConversationBase) => renderStatusBadge(conversation.status)
    },
    {
      key: 'stats',
      header: 'Messages',
      width: '10%',
      render: (conversation: ConversationBase) => (
        <div className="text-sm">
          <div className="text-theme-primary">{conversation.message_count || 0}</div>
          <div className="text-theme-muted">{(conversation.total_tokens || 0).toLocaleString()} tokens</div>
        </div>
      )
    },
    {
      key: 'cost',
      header: 'Cost',
      width: '10%',
      render: (conversation: ConversationBase) => (
        <div className="text-sm">
          <div className="text-theme-primary font-mono">
            {formatCurrency(conversation.total_cost || 0)}
          </div>
        </div>
      )
    },
    {
      key: 'lastActivity',
      header: 'Last Activity',
      width: '15%',
      render: (conversation: ConversationBase) => (
        <div className="text-sm">
          <div className="text-theme-primary">
            {formatLastActivity(conversation.last_activity_at || conversation.created_at)}
          </div>
          <div className="text-theme-muted">{new Date(conversation.created_at).toLocaleDateString()}</div>
        </div>
      )
    },
    {
      key: 'actions',
      header: 'Actions',
      width: '20%',
      render: (conversation: ConversationBase) => (
        <div className="flex items-center gap-2">
          <Button
            variant="ghost"
            size="sm"
            onClick={(e) => {
              e.stopPropagation();
              handleViewConversation(conversation);
            }}
            title="View Details"
          >
            <Eye className="h-4 w-4" />
          </Button>
          {conversation.status === 'active' && (
            <Button
              variant="ghost"
              size="sm"
              onClick={(e) => {
                e.stopPropagation();
                handleContinueConversation(conversation.id);
              }}
              title="Continue Conversation"
              className="text-theme-success hover:text-theme-success/80"
            >
              <MessageCircle className="h-4 w-4" />
            </Button>
          )}
          {canManageConversations && (
            <>
              <Button
                variant="ghost"
                size="sm"
                onClick={(e) => {
                  e.stopPropagation();
                  handleExportConversation(conversation);
                }}
                title="Export Conversation"
              >
                <Download className="h-4 w-4" />
              </Button>
              <Button
                variant="ghost"
                size="sm"
                onClick={(e) => {
                  e.stopPropagation();
                  handleDuplicateConversation(conversation);
                }}
                title="Duplicate Conversation"
              >
                <Copy className="h-4 w-4" />
              </Button>
              <Button
                variant="ghost"
                size="sm"
                onClick={(e) => {
                  e.stopPropagation();
                  handleArchiveConversation(conversation);
                }}
                title={conversation.status === 'archived' ? 'Unarchive' : 'Archive'}
              >
                <Archive className="h-4 w-4" />
              </Button>
              <Button
                variant="ghost"
                size="sm"
                onClick={(e) => {
                  e.stopPropagation();
                  handleDeleteConversation(conversation);
                }}
                title="Delete Conversation"
                className="text-theme-danger hover:text-theme-danger/80"
              >
                <Trash2 className="h-4 w-4" />
              </Button>
            </>
          )}
        </div>
      )
    }
  ];

  // Get the conversation for the continue modal
  const chatConversation = chatConversationId ? conversations.find(c => c.id === chatConversationId) : null;

  const { refreshAction } = useRefreshAction({
    onRefresh: () => loadConversations(pagination.currentPage, pagination.perPage),
    loading,
  });

  return (
    <PageContainer
      title="AI Conversations"
      description="Manage and review your AI conversation history"
      breadcrumbs={[
        { label: 'Dashboard', href: '/app' },
        { label: 'AI', href: '/app/ai' },
        { label: 'Conversations' }
      ]}
      actions={[
        refreshAction,
        ...(canCreateConversations ? [{
          id: 'create-conversation',
          label: 'Start Conversation',
          onClick: () => setIsCreateModalOpen(true),
          icon: Plus,
          variant: 'primary' as const
        }] : [])
      ]}
    >
      <div className="space-y-4">
        {/* Filters */}
        <div className="flex flex-col sm:flex-row gap-4">
          <div className="flex-1">
            <SearchInput
              placeholder="Search conversations..."
              value={searchQuery}
              onChange={handleSearch}
            />
          </div>
          <div className="flex gap-2">
            <EnhancedSelect
              placeholder="Status"
              value={filters.status || ''}
              onChange={(value) => handleFilterChange('status', value || undefined)}
              options={[
                { value: '', label: 'All Statuses' },
                { value: 'active', label: 'Active' },
                { value: 'completed', label: 'Completed' },
                { value: 'archived', label: 'Archived' },
                { value: 'error', label: 'Error' }
              ]}
              className="w-40"
            />
            <EnhancedSelect
              placeholder="Agent"
              value={filters.agent_id || ''}
              onChange={(value) => handleFilterChange('agent_id', value || undefined)}
              options={[
                { value: '', label: 'All Agents' },
                ...availableAgents.map(agent => ({
                  value: agent.id,
                  label: agent.name
                }))
              ]}
              className="w-40"
            />
          </div>
        </div>

        {/* Data Table */}
        <DataTable
          columns={columns}
          data={conversations || []}
          loading={loading}
          pagination={{
            current_page: pagination.currentPage,
            total_pages: pagination.totalPages,
            total_count: pagination.totalCount,
            per_page: pagination.perPage
          }}
          onPageChange={(page) => loadConversations(page, pagination.perPage)}
          onRowClick={(conversation: ConversationBase) => handleViewConversation(conversation)}
          emptyState={{
            icon: MessageSquare,
            title: 'No conversations found',
            description: canCreateConversations
              ? 'Get started by creating your first AI conversation.'
              : 'No conversations have been created yet.',
            action: canCreateConversations ? {
              label: 'Start Conversation',
              onClick: () => setIsCreateModalOpen(true)
            } : undefined
          }}
        />
      </div>

      {/* Create Conversation Modal */}
      <ConversationCreateModal
        isOpen={isCreateModalOpen}
        onClose={() => setIsCreateModalOpen(false)}
        onConversationCreated={handleConversationCreated}
      />

      {/* Conversation Detail Modal - Always rendered, visibility controlled by isOpen */}
      <ConversationDetailModal
        isOpen={!!selectedConversationId}
        onClose={() => setSelectedConversationId(null)}
        agentId={conversations.find(c => c.id === selectedConversationId)?.ai_agent?.id || ''}
        conversationId={selectedConversationId || ''}
        onContinue={handleContinueConversation}
        onArchive={() => {
          loadConversations(pagination.currentPage, pagination.perPage);
          setSelectedConversationId(null);
        }}
        onExport={() => {
          setSelectedConversationId(null);
        }}
      />

      {/* Conversation Continue Modal - Only rendered when conversation exists */}
      {chatConversation && (
        <ConversationContinueModal
          isOpen={!!chatConversationId}
          onClose={() => setChatConversationId(null)}
          conversation={chatConversation}
          onConversationUpdate={() => {
            // Reload conversations list when a conversation is updated
            loadConversations(pagination.currentPage, pagination.perPage);
          }}
        />
      )}
      {ConfirmationDialog}
    </PageContainer>
  );
};

export default AIConversationsPage;