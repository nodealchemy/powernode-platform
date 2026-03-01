import React, { useState, useCallback } from 'react';
import { AgentListPanel } from './AgentListPanel';
import { AgentDetailPanel } from './AgentDetailPanel';
import { CreateAgentModal } from './CreateAgentModal';
import { EditAgentModal } from './EditAgentModal';
import { useAgentDetail } from '../hooks/useAgentDetail';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotification } from '@/shared/hooks/useNotification';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useChatWindow } from '@/features/ai/chat/context/ChatWindowContext';
import { useAiOrchestrationWebSocket } from '@/shared/hooks/useAiOrchestrationWebSocket';
import { agentsApi } from '@/shared/services/ai';
import type { AiAgent } from '@/shared/types/ai';

export const AgentsSplitPanel: React.FC = () => {
  const { hasPermission } = usePermissions();
  const { showNotification } = useNotification();
  const { openConversationMaximized } = useChatWindow();
  const { confirm, ConfirmationDialog } = useConfirmation();
  const canManage = hasPermission('ai.agents.manage');
  const canCreate = hasPermission('ai.agents.create');

  // Selection state
  const [selectedAgentId, setSelectedAgentId] = useState<string | null>(null);
  const [activeDetailTab, setActiveDetailTab] = useState('config');

  // Modal state
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showEditModal, setShowEditModal] = useState(false);

  // Refresh key for list panel
  const [refreshKey, setRefreshKey] = useState(0);

  // Detail data
  const { agent, stats, analytics, loading, error, reload } = useAgentDetail(selectedAgentId);

  // WebSocket for real-time agent events
  useAiOrchestrationWebSocket({
    onAgentEvent: (event) => {
      if (['agent_created', 'agent_updated', 'agent_deleted', 'agent_execution_completed'].includes(event.type)) {
        setRefreshKey(prev => prev + 1);
        // If currently-viewed agent was updated, reload detail
        if (selectedAgentId && (event.agent_id === selectedAgentId || event.data?.agent_id === selectedAgentId)) {
          reload();
        }
      }
    },
  });

  // Handlers
  const handleSelectAgent = useCallback((a: AiAgent) => {
    setSelectedAgentId(a.id);
  }, []);

  const handleCreateAgent = useCallback(() => {
    setShowCreateModal(true);
  }, []);

  const handleAgentCreated = useCallback((newAgent: AiAgent) => {
    setShowCreateModal(false);
    setRefreshKey(prev => prev + 1);
    setSelectedAgentId(newAgent.id);
  }, []);

  const handleEdit = useCallback(() => {
    setShowEditModal(true);
  }, []);

  const handleAgentUpdated = useCallback(() => {
    setShowEditModal(false);
    setRefreshKey(prev => prev + 1);
    reload();
  }, [reload]);

  const handleAgentDeleted = useCallback(() => {
    setShowEditModal(false);
    setSelectedAgentId(null);
    setRefreshKey(prev => prev + 1);
  }, []);

  const handleChat = useCallback(() => {
    if (agent) {
      openConversationMaximized(agent.id, agent.name);
    }
  }, [agent, openConversationMaximized]);

  const handleToggleStatus = useCallback(async () => {
    if (!agent) return;
    try {
      if (agent.status === 'active') {
        await agentsApi.pauseAgent(agent.id);
        showNotification(`${agent.name} paused`, 'success');
      } else {
        await agentsApi.resumeAgent(agent.id);
        showNotification(`${agent.name} resumed`, 'success');
      }
      setRefreshKey(prev => prev + 1);
      reload();
    } catch {
      showNotification('Failed to update agent status', 'error');
    }
  }, [agent, reload, showNotification]);

  const handleClone = useCallback(async () => {
    if (!agent) return;
    try {
      const cloned = await agentsApi.cloneAgent(agent.id);
      showNotification(`Cloned as "${cloned.name}"`, 'success');
      setRefreshKey(prev => prev + 1);
      setSelectedAgentId(cloned.id);
    } catch {
      showNotification('Failed to clone agent', 'error');
    }
  }, [agent, showNotification]);

  const handleArchive = useCallback(async () => {
    if (!agent) return;
    try {
      await agentsApi.archiveAgent(agent.id);
      showNotification(`${agent.name} archived`, 'success');
      setSelectedAgentId(null);
      setRefreshKey(prev => prev + 1);
    } catch {
      showNotification('Failed to archive agent', 'error');
    }
  }, [agent, showNotification]);

  const handleDelete = useCallback(() => {
    if (!agent) return;
    confirm({
      title: 'Delete Agent',
      message: `Are you sure you want to delete "${agent.name}"? This action cannot be undone.`,
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        await agentsApi.deleteAgent(agent.id);
        showNotification(`${agent.name} deleted`, 'success');
        setSelectedAgentId(null);
        setRefreshKey(prev => prev + 1);
      },
    });
  }, [agent, confirm, showNotification]);

  // Quick actions for list items (operate on arbitrary agent, not just selected)
  const handleQuickClone = useCallback(async (a: AiAgent) => {
    try {
      const cloned = await agentsApi.cloneAgent(a.id);
      showNotification(`Cloned as "${cloned.name}"`, 'success');
      setRefreshKey(prev => prev + 1);
    } catch {
      showNotification('Failed to clone agent', 'error');
    }
  }, [showNotification]);

  const handleQuickToggleStatus = useCallback(async (a: AiAgent) => {
    try {
      if (a.status === 'active') {
        await agentsApi.pauseAgent(a.id);
        showNotification(`${a.name} paused`, 'success');
      } else {
        await agentsApi.resumeAgent(a.id);
        showNotification(`${a.name} resumed`, 'success');
      }
      setRefreshKey(prev => prev + 1);
      if (selectedAgentId === a.id) reload();
    } catch {
      showNotification('Failed to update agent status', 'error');
    }
  }, [showNotification, selectedAgentId, reload]);

  const handleQuickArchive = useCallback(async (a: AiAgent) => {
    try {
      await agentsApi.archiveAgent(a.id);
      showNotification(`${a.name} archived`, 'success');
      if (selectedAgentId === a.id) setSelectedAgentId(null);
      setRefreshKey(prev => prev + 1);
    } catch {
      showNotification('Failed to archive agent', 'error');
    }
  }, [showNotification, selectedAgentId]);

  return (
    <>
      {/* Split panel layout */}
      <div className="flex h-[calc(100vh-280px)]">
        <AgentListPanel
          selectedAgentId={selectedAgentId}
          onSelectAgent={handleSelectAgent}
          onCreateAgent={canCreate ? handleCreateAgent : () => {}}
          refreshKey={refreshKey}
          onClone={handleQuickClone}
          onToggleStatus={handleQuickToggleStatus}
          onArchive={handleQuickArchive}
          canManage={canManage}
        />
        <AgentDetailPanel
          agent={agent}
          stats={stats}
          analytics={analytics}
          loading={loading}
          error={error}
          activeTab={activeDetailTab}
          onActiveTabChange={setActiveDetailTab}
          onChat={handleChat}
          onEdit={handleEdit}
          onClone={handleClone}
          onToggleStatus={handleToggleStatus}
          onDelete={handleDelete}
          onArchive={handleArchive}
          canManage={canManage}
        />
      </div>

      {/* Modals — outside flex container */}
      <CreateAgentModal
        isOpen={showCreateModal}
        onClose={() => setShowCreateModal(false)}
        onAgentCreated={handleAgentCreated}
      />

      <EditAgentModal
        isOpen={showEditModal}
        onClose={() => setShowEditModal(false)}
        agent={agent}
        onAgentUpdated={handleAgentUpdated}
        onAgentDeleted={handleAgentDeleted}
      />

      {ConfirmationDialog}
    </>
  );
};
