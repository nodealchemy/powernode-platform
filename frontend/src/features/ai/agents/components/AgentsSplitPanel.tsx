import React, { useState, useCallback } from 'react';
import { AgentListPanel } from './AgentListPanel';
import { AgentDetailPanel } from './AgentDetailPanel';
import { CreateAgentModal } from './CreateAgentModal';
import { EditAgentModal } from './EditAgentModal';
import { useAgentDetail } from '../hooks/useAgentDetail';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotification } from '@/shared/hooks/useNotification';
import { useChatWindow } from '@/features/ai/chat/context/ChatWindowContext';
import { useAiOrchestrationWebSocket } from '@/shared/hooks/useAiOrchestrationWebSocket';
import { agentsApi } from '@/shared/services/ai';
import type { AiAgent } from '@/shared/types/ai';

export const AgentsSplitPanel: React.FC = () => {
  const { hasPermission } = usePermissions();
  const { showNotification } = useNotification();
  const { openConversationMaximized } = useChatWindow();
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
  const { agent, stats, loading, error, reload } = useAgentDetail(selectedAgentId);

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

  const handleDelete = useCallback(async () => {
    if (!agent) return;
    if (!window.confirm(`Delete agent "${agent.name}"? This cannot be undone.`)) return;
    try {
      await agentsApi.deleteAgent(agent.id);
      showNotification(`${agent.name} deleted`, 'success');
      setSelectedAgentId(null);
      setRefreshKey(prev => prev + 1);
    } catch {
      showNotification('Failed to delete agent', 'error');
    }
  }, [agent, showNotification]);

  return (
    <>
      {/* Split panel layout */}
      <div className="flex h-[calc(100vh-280px)]">
        <AgentListPanel
          selectedAgentId={selectedAgentId}
          onSelectAgent={handleSelectAgent}
          onCreateAgent={canCreate ? handleCreateAgent : () => {}}
          refreshKey={refreshKey}
        />
        <AgentDetailPanel
          agent={agent}
          stats={stats}
          loading={loading}
          error={error}
          activeTab={activeDetailTab}
          onActiveTabChange={setActiveDetailTab}
          onChat={handleChat}
          onEdit={handleEdit}
          onToggleStatus={handleToggleStatus}
          onDelete={handleDelete}
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
    </>
  );
};
