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
import { Modal } from '@/shared/components/ui/Modal';
import { DataTable } from '@/shared/components/ui/DataTable';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { SearchInput } from '@/shared/components/ui/SearchInput';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import { agentsApi } from '@/shared/services/ai';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { AiConversation, AiAgent, ConversationsFilters } from '@/shared/types/ai';
import { ConversationCreateModal } from './ConversationCreateModal';
import { ConversationDetailModal } from './ConversationDetailModal';
import { ConversationContinueModal } from './ConversationContinueModal';

interface AIConversationsModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export const AIConversationsModal: React.FC<AIConversationsModalProps> = ({
  isOpen,
  onClose
}) => {
  const { currentUser } = useAuth();
  const { addNotification } = useNotifications();

  const [conversations, setConversations] = useState<AiConversation[]>([]);
  const [availableAgents, setAvailableAgents] = useState<AiAgent[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchQuery, setSearchQuery] = useState('');
  const [filters, setFilters] = useState<ConversationsFilters>({});
  const [pagination, setPagination] = useState({
    current_page: 1,
    total_pages: 1,
    total_count: 0,
    per_page: 25
  });
  const [isCreateModalOpen, setIsCreateModalOpen] = useState(false);
  const [selectedConversationId, setSelectedConversationId] = useState<string | null>(null);
  const [chatConversationId, setChatConversationId] = useState<string | null>(null);

  // Check permissions
  const canCreateConversations = currentUser?.permissions?.includes('ai.conversations.create') || false;
  const canManageConversations = currentUser?.permissions?.includes('ai.conversations.manage') || false;

  // Load conversations function - uses global conversations endpoint
  const loadConversations = async (page = 1, perPage = 25) => {
    try {
      setLoading(true);

      const response = await agentsApi.getGlobalConversations({
        page,
        per_page: perPage,
        status: filters.status as 'active' | 'archived' | 'paused' | 'completed' | undefined,
        agent_id: filters.agent_id,
        search: searchQuery || undefined
      });

      setConversations(response.items || []);
      setPagination(response.pagination);
    } catch (error) {
      console.error('Failed to load conversations:', error);
      setConversations([]);
      setPagination({
        current_page: 1,
        total_pages: 1,
        total_count: 0,
        per_page: 25
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
      // PaginatedResponse structure: { items: T[], pagination: {...} }
      const agents = response.items || [];
      setAvailableAgents(agents);
    } catch (error) {
      console.error('Failed to load agents:', error);
      setAvailableAgents([]);
    }
  };

  // Initial load when modal opens
  // eslint-disable-next-line react-hooks/exhaustive-deps -- Load when modal opens
  useEffect(() => {
    if (isOpen) {
      loadConversations(1, pagination.per_page);
      loadAgents();
    }
  }, [isOpen]);

  // Handle search
  const handleSearch = useCallback((query: string) => {
    setSearchQuery(query);
  }, []);

  // Debounced effect for search
  // eslint-disable-next-line react-hooks/exhaustive-deps -- Only trigger on search query change
  useEffect(() => {
    if (searchQuery === '') return;
    const timeoutId = setTimeout(() => {
      loadConversations(1, pagination.per_page);
    }, 300);
    return () => clearTimeout(timeoutId);
  }, [searchQuery]);

  // Handle filter changes
  const handleFilterChange = useCallback((key: keyof ConversationsFilters, value: any) => {
    setFilters(prev => ({
      ...prev,
      [key]: value
    }));
  }, []);

  // Effect to reload conversations when filters change
  // eslint-disable-next-line react-hooks/exhaustive-deps -- Only trigger on filter changes
  useEffect(() => {
    if (Object.keys(filters).length > 0 || Object.values(filters).some(v => v !== undefined && v !== '')) {
      loadConversations(1, pagination.per_page);
    }
  }, [filters]);

  // Handle conversation actions
  const handleViewConversation = (conversation: AiConversation) => {
    setSelectedConversationId(conversation.id);
  };

  const handleContinueConversation = (conversationId: string) => {
    setChatConversationId(conversationId);
  };

  const handleExportConversation = async (conversation: AiConversation) => {
    try {
      // Export requires agentId - get it from conversation.ai_agent
      if (!conversation.ai_agent?.id) {
        addNotification({
          type: 'error',
          title: 'Export Failed',
          message: 'Cannot export conversation without associated agent'
        });
        return;
      }

      const response = await agentsApi.exportConversation(conversation.ai_agent.id, conversation.id);
      window.open(response.download_url, '_blank');
      addNotification({
        type: 'success',
        title: 'Export Started',
        message: 'Conversation export has been initiated'
      });
    } catch (error) {
      console.error('Failed to export conversation:', error);
      addNotification({
        type: 'error',
        title: 'Export Failed',
        message: 'Failed to export conversation'
      });
    }
  };

  const handleArchiveConversation = async (conversation: AiConversation) => {
    try {
      if (conversation.status === 'archived') {
        await agentsApi.unarchiveGlobalConversation(conversation.id);
        addNotification({
          type: 'success',
          title: 'Conversation Restored',
          message: 'Conversation has been restored from archive'
        });
      } else {
        await agentsApi.archiveGlobalConversation(conversation.id);
        addNotification({
          type: 'success',
          title: 'Conversation Archived',
          message: 'Conversation has been archived'
        });
      }
      // Reload conversations to reflect changes
      loadConversations(pagination.current_page, pagination.per_page);
    } catch (error) {
      console.error('Failed to archive/unarchive conversation:', error);
      addNotification({
        type: 'error',
        title: 'Action Failed',
        message: 'Failed to update conversation status'
      });
    }
  };

  const handleDuplicateConversation = async (conversation: AiConversation) => {
    try {
      const newTitle = `Copy of ${conversation.title || 'Untitled Conversation'}`;
      await agentsApi.duplicateGlobalConversation(conversation.id, {
        title: newTitle,
        include_messages: true
      });
      addNotification({
        type: 'success',
        title: 'Conversation Duplicated',
        message: 'Conversation has been successfully duplicated'
      });
      // Reload conversations to show the new one
      loadConversations(1, pagination.per_page);
    } catch (error) {
      console.error('Failed to duplicate conversation:', error);
      addNotification({
        type: 'error',
        title: 'Duplication Failed',
        message: 'Failed to duplicate conversation'
      });
    }
  };

  const handleDeleteConversation = async (conversation: AiConversation) => {
    if (!window.confirm(`Are you sure you want to delete "${conversation.title || 'Untitled Conversation'}"? This action cannot be undone.`)) {
      return;
    }

    try {
      await agentsApi.deleteGlobalConversation(conversation.id);
      addNotification({
        type: 'success',
        title: 'Conversation Deleted',
        message: 'Conversation has been permanently deleted'
      });
      // Reload conversations to reflect deletion
      loadConversations(pagination.current_page, pagination.per_page);
    } catch (error) {
      console.error('Failed to delete conversation:', error);
      addNotification({
        type: 'error',
        title: 'Deletion Failed',
        message: 'Failed to delete conversation'
      });
    }
  };

  // Handle conversation creation
  const handleConversationCreated = (_conversation: AiConversation) => {
    // Refresh the conversations list to show the new conversation
    loadConversations(1, pagination.per_page);
    setIsCreateModalOpen(false);
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
      render: (conversation: AiConversation) => (
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
      render: (conversation: AiConversation) => renderStatusBadge(conversation.status)
    },
    {
      key: 'stats',
      header: 'Messages',
      width: '15%',
      render: (conversation: AiConversation) => (
        <div className="text-sm">
          <div className="text-theme-primary">{conversation.metadata?.total_messages || conversation.message_count || 0}</div>
          <div className="text-theme-muted">{(conversation.metadata?.total_tokens || 0).toLocaleString()} tokens</div>
        </div>
      )
    },
    {
      key: 'cost',
      header: 'Cost',
      width: '10%',
      render: (conversation: AiConversation) => (
        <div className="text-sm">
          <div className="text-theme-primary font-mono">
            {formatCurrency(conversation.metadata?.total_cost || 0)}
          </div>
        </div>
      )
    },
    {
      key: 'lastActivity',
      header: 'Last Activity',
      width: '15%',
      render: (conversation: AiConversation) => (
        <div className="text-sm">
          <div className="text-theme-primary">
            {formatLastActivity(conversation.metadata?.last_activity || conversation.updated_at)}
          </div>
          <div className="text-theme-muted">{new Date(conversation.created_at).toLocaleDateString()}</div>
        </div>
      )
    },
    {
      key: 'actions',
      header: 'Actions',
      width: '20%',
      render: (conversation: AiConversation) => (
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

  return (
    <>
      <Modal
        isOpen={isOpen}
        onClose={onClose}
        title="AI Conversations"
        maxWidth="full"
        variant="fullscreen"
        className="flex flex-col h-full"
      >
        <div className="flex-1 flex flex-col space-y-4 min-h-0">
          {/* Header Actions */}
          <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
            <p className="text-theme-muted">
              Manage and review your AI conversation history
            </p>

            {canCreateConversations && (
              <Button
                variant="primary"
                onClick={() => setIsCreateModalOpen(true)}
                className="flex items-center gap-2"
              >
                <Plus className="h-4 w-4" />
                Start Conversation
              </Button>
            )}
          </div>

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
          <div className="flex-1 min-h-0">
            <DataTable
              columns={columns}
              data={conversations || []}
              loading={loading}
              pagination={pagination}
              onPageChange={(page) => loadConversations(page, pagination.per_page)}
              onRowClick={(conversation: AiConversation) => handleViewConversation(conversation)}
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
        </div>
      </Modal>

      {/* Create Conversation Modal */}
      <ConversationCreateModal
        isOpen={isCreateModalOpen}
        onClose={() => setIsCreateModalOpen(false)}
        onConversationCreated={handleConversationCreated}
      />

      {/* Conversation Detail Modal */}
      {selectedConversationId && (
        <ConversationDetailModal
          isOpen={!!selectedConversationId}
          onClose={() => setSelectedConversationId(null)}
          agentId="" // TODO: Implement global conversations - agentId not available for global conversations
          conversationId={selectedConversationId}
          onContinue={handleContinueConversation}
          onArchive={() => {
            loadConversations(pagination.current_page, pagination.per_page);
            setSelectedConversationId(null);
          }}
          onExport={() => {
            loadConversations(pagination.current_page, pagination.per_page);
          }}
        />
      )}

      {/* Conversation Continue Modal */}
      {chatConversation && (
        <ConversationContinueModal
          isOpen={!!chatConversationId}
          onClose={() => setChatConversationId(null)}
          conversation={chatConversation}
          onConversationUpdate={(updated) => {
            setConversations(prev =>
              prev.map(c => c.id === updated.id ? (updated as AiConversation) : c)
            );
          }}
        />
      )}
    </>
  );
};
