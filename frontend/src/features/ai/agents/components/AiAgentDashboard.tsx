import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Brain, Plus, Play, Pause, Settings, BarChart3, Users, Clock, MessageSquare } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { EmptyState } from '@/shared/components/ui/EmptyState';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { agentsApi } from '@/shared/services/ai';
import { CreateAgentModal } from './CreateAgentModal';
import { EditAgentModal } from './EditAgentModal';
import { ConversationContinueModal } from '@/features/ai/conversations/components/ConversationContinueModal';
import { ConversationCreateModal } from '@/features/ai/conversations/components/ConversationCreateModal';

import type { AiAgent, AiConversation } from '@/shared/types/ai';

interface AiAgentDashboardProps {
  showCreateModal?: boolean;
  onShowCreateModalChange?: (show: boolean) => void;
}

export const AiAgentDashboard: React.FC<AiAgentDashboardProps> = ({
  showCreateModal: externalShowCreateModal,
  onShowCreateModalChange
}) => {
  const [agents, setAgents] = useState<AiAgent[]>([]);
  const [loading, setLoading] = useState(true);
  const [stats, setStats] = useState({
    total_agents: 0,
    active_agents: 0,
    total_executions: 0,
    success_rate: 0
  });
  const [internalShowCreateModal, setInternalShowCreateModal] = useState(false);
  const [showEditModal, setShowEditModal] = useState(false);
  const [selectedAgent, setSelectedAgent] = useState<AiAgent | null>(null);
  const [chatAgent, setChatAgent] = useState<AiAgent | null>(null);
  const [chatConversation, setChatConversation] = useState<AiConversation | null>(null);
  const [showChatModal, setShowChatModal] = useState(false);
  const [showCreateConversationModal, setShowCreateConversationModal] = useState(false);
  const navigate = useNavigate();

  // Use external state if provided, otherwise use internal state
  const showCreateModal = externalShowCreateModal !== undefined ? externalShowCreateModal : internalShowCreateModal;
  const setShowCreateModal = (show: boolean) => {
    if (onShowCreateModalChange) {
      onShowCreateModalChange(show);
    } else {
      setInternalShowCreateModal(show);
    }
  };

  const { hasPermission } = usePermissions();
  const { addNotification } = useNotifications();

  const canCreateAgents = hasPermission('ai.agents.create');
  const canManageAgents = hasPermission('ai.agents.manage');

  useEffect(() => {
    loadDashboardData();
     
  }, []);

  const loadDashboardData = async () => {
    try {
      setLoading(true);

      // Load agents from API - automatic response unwrapping
      const { items: agentsData } = await agentsApi.getAgents({ per_page: 20 });

      // Check if we received agents data
      if (!agentsData || !Array.isArray(agentsData) || agentsData.length === 0) {
        setAgents([]);
        setStats({
          total_agents: 0,
          active_agents: 0,
          total_executions: 0,
          success_rate: 0
        });
        return;
      }

      // API now returns data in the correct format - use directly
      setAgents(agentsData as AiAgent[]);

      // Calculate stats from loaded agents
      const activeAgents = agentsData.filter((a: AiAgent) => a.status === 'active').length;
      const totalExecutions = agentsData.reduce((sum: number, agent: AiAgent) =>
        sum + (agent.execution_stats?.total_executions || 0), 0
      );
      const avgSuccessRate = agentsData.length > 0 ?
        agentsData.reduce((sum: number, agent: AiAgent) =>
          sum + (agent.execution_stats?.success_rate || 0), 0
        ) / agentsData.length : 0;

      setStats({
        total_agents: agentsData.length,
        active_agents: activeAgents,
        total_executions: totalExecutions,
        success_rate: Math.round(avgSuccessRate)
      });
    } catch (error) {
      // Check if it's an authentication error
      const httpError = error as { response?: { status?: number } };
      const isAuthError = httpError?.response?.status === 401;
      const errorMessage = isAuthError
        ? 'Please log in to view AI agents data'
        : 'Failed to load AI agents from server';

      // Clear data on error - don't show fake data
      setAgents([]);
      setStats({
        total_agents: 0,
        active_agents: 0,
        total_executions: 0,
        success_rate: 0
      });

      addNotification({
        type: isAuthError ? 'warning' : 'error',
        title: isAuthError ? 'Authentication Required' : 'Error',
        message: errorMessage
      });
    } finally {
      setLoading(false);
    }
  };

  const getAgentStatusBadge = (status: string) => {
    switch (status) {
      case 'active':
        return <Badge variant="success" size="sm">Active</Badge>;
      case 'paused':
      case 'inactive':
        return <Badge variant="secondary" size="sm">Inactive</Badge>;
      case 'error':
        return <Badge variant="danger" size="sm">Error</Badge>;
      default:
        return <Badge variant="outline" size="sm">Unknown</Badge>;
    }
  };

  const handleCreateAgent = () => {
    setShowCreateModal(true);
  };

  const handleEditAgent = (agent: AiAgent) => {
    setSelectedAgent(agent);
    setShowEditModal(true);
  };

  const handleAgentCreated = () => {
    setShowCreateModal(false);
    loadDashboardData(); // Refresh the list
  };

  const handleAgentUpdated = () => {
    setShowEditModal(false);
    setSelectedAgent(null);
    loadDashboardData(); // Refresh the list
  };

  const handleAgentDeleted = () => {
    setShowEditModal(false);
    setSelectedAgent(null);
    loadDashboardData(); // Refresh the list
  };

  const handleToggleAgentStatus = async (agent: AiAgent) => {
    try {
      if (agent.status === 'active') {
        await agentsApi.pauseAgent(agent.id);
        addNotification({
          type: 'success',
          title: 'Success',
          message: `${agent.name} has been paused`
        });
      } else {
        await agentsApi.resumeAgent(agent.id);
        addNotification({
          type: 'success',
          title: 'Success',
          message: `${agent.name} has been resumed`
        });
      }
      loadDashboardData(); // Refresh the list
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to update agent status'
      });
    }
  };

  const handleChatWithAgent = async (agent: AiAgent) => {
    try {
      setChatAgent(agent);
      const response = await agentsApi.getActiveConversations(agent.id);
      const conversations = response.items || [];
      if (conversations.length > 0) {
        setChatConversation(conversations[0]);
        setShowChatModal(true);
      } else {
        setShowCreateConversationModal(true);
      }
    } catch (_error) {
      // Fallback: open create modal
      setChatAgent(agent);
      setShowCreateConversationModal(true);
    }
  };

  const handleConversationCreatedForChat = (conversation: AiConversation) => {
    setShowCreateConversationModal(false);
    setChatConversation(conversation);
    setShowChatModal(true);
  };

  if (loading) {
    return (
      <LoadingSpinner size="lg" className="py-12" message="Loading AI agents..." />
    );
  }

  return (
    <>
      {/* Stats Overview */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">Total Agents</p>
              <p className="text-2xl font-semibold text-theme-primary">{stats.total_agents}</p>
            </div>
            <div className="h-10 w-10 bg-theme-info bg-opacity-10 rounded-lg flex items-center justify-center">
              <Brain className="h-5 w-5 text-theme-info" />
            </div>
          </div>
        </Card>

        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">Active Agents</p>
              <p className="text-2xl font-semibold text-theme-primary">{stats.active_agents}</p>
            </div>
            <div className="h-10 w-10 bg-theme-success bg-opacity-10 rounded-lg flex items-center justify-center">
              <Play className="h-5 w-5 text-theme-success" />
            </div>
          </div>
        </Card>

        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">Total Executions</p>
              <p className="text-2xl font-semibold text-theme-primary">{stats.total_executions}</p>
            </div>
            <div className="h-10 w-10 bg-theme-warning bg-opacity-10 rounded-lg flex items-center justify-center">
              <BarChart3 className="h-5 w-5 text-theme-warning" />
            </div>
          </div>
        </Card>

        <Card className="p-4">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-theme-tertiary">Success Rate</p>
              <p className="text-2xl font-semibold text-theme-primary">{stats.success_rate}%</p>
            </div>
            <div className="h-10 w-10 bg-theme-success bg-opacity-10 rounded-lg flex items-center justify-center">
              <Users className="h-5 w-5 text-theme-success" />
            </div>
          </div>
        </Card>
      </div>

      {/* Recent Agents */}
      <div className="mb-6">
        <h2 className="text-lg font-semibold text-theme-primary mb-4">Recent Agents</h2>

        {agents.length === 0 ? (
          <EmptyState
            icon={Brain}
            title="No AI agents found"
            description="Create your first AI agent to get started with automation"
            action={
              canCreateAgents ? (
                <Button
                  variant="primary"
                  size="md"
                  className="flex items-center gap-2"
                  onClick={handleCreateAgent}
                >
                  <Plus className="h-4 w-4" />
                  Create Agent
                </Button>
              ) : undefined
            }
          />
        ) : (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            {agents.map((agent) => (
              <Card key={agent.id} className="p-6">
                <div className="flex items-start justify-between mb-4">
                  <div className="flex items-start gap-3">
                    <div className="h-10 w-10 bg-theme-info bg-opacity-10 rounded-lg flex items-center justify-center">
                      <Brain className="h-5 w-5 text-theme-info" />
                    </div>
                    <div>
                      <h3 className="font-semibold text-theme-primary">{agent.name}</h3>
                      <p className="text-sm text-theme-tertiary">{agent.description}</p>
                    </div>
                  </div>
                  {getAgentStatusBadge(agent.status)}
                </div>

                <div className="space-y-3">
                  <div className="flex items-center justify-between text-sm">
                    <span className="text-theme-tertiary">AI Provider</span>
                    <span className="text-theme-primary">{agent.provider?.name || 'N/A'}</span>
                  </div>

                  <div className="flex items-center justify-between text-sm">
                    <span className="text-theme-tertiary">Model</span>
                    <span className="text-theme-primary">
                      {agent.model || 'N/A'}
                    </span>
                  </div>

                  <div className="flex items-center justify-between text-sm">
                    <span className="text-theme-tertiary">Executions</span>
                    <span className="text-theme-primary">{agent.execution_stats?.total_executions || 0}</span>
                  </div>

                  {agent.updated_at && (
                    <div className="flex items-center justify-between text-sm">
                      <span className="text-theme-tertiary">Last Updated</span>
                      <span className="text-theme-primary flex items-center gap-1">
                        <Clock className="h-3 w-3" />
                        {new Date(agent.updated_at).toLocaleDateString()}
                      </span>
                    </div>
                  )}
                </div>

                <div className="flex items-center justify-between mt-4 pt-4 border-t border-theme">
                  <div className="flex items-center gap-2">
                    {canManageAgents && (
                      <Button
                        variant={agent.status === 'active' ? 'warning' : 'success'}
                        size="sm"
                        className="flex items-center gap-1.5 min-w-[100px] justify-center"
                        onClick={() => handleToggleAgentStatus(agent)}
                      >
                        {agent.status === 'active' ? (
                          <>
                            <Pause className="h-3 w-3" />
                            Pause
                          </>
                        ) : (
                          <>
                            <Play className="h-3 w-3" />
                            Start
                          </>
                        )}
                      </Button>
                    )}
                    <Button
                      variant="outline"
                      size="sm"
                      className="flex items-center gap-1.5 min-w-[80px] justify-center"
                      onClick={() => handleChatWithAgent(agent)}
                    >
                      <MessageSquare className="h-3 w-3" />
                      Chat
                    </Button>
                  </div>

                  <div className="flex items-center gap-2">
                    <Button
                      variant="outline"
                      size="sm"
                      className="flex items-center gap-1.5 min-w-[80px] justify-center"
                      onClick={() => navigate(`/app/ai/agents/${agent.id}/chat`)}
                    >
                      Full Chat
                    </Button>
                    <Button
                      variant="outline"
                      size="sm"
                      className="flex items-center gap-1.5 min-w-[80px] justify-center"
                      onClick={() => handleEditAgent(agent)}
                    >
                      <Settings className="h-3 w-3" />
                      Manage
                    </Button>
                  </div>
                </div>
              </Card>
            ))}
          </div>
        )}
      </div>

      {/* Modals */}
      <CreateAgentModal
        isOpen={showCreateModal}
        onClose={() => setShowCreateModal(false)}
        onAgentCreated={handleAgentCreated}
      />

      <EditAgentModal
        isOpen={showEditModal}
        onClose={() => setShowEditModal(false)}
        agent={selectedAgent}
        onAgentUpdated={handleAgentUpdated}
        onAgentDeleted={handleAgentDeleted}
      />

      {chatConversation && (
        <ConversationContinueModal
          isOpen={showChatModal}
          onClose={() => {
            setShowChatModal(false);
            setChatConversation(null);
            setChatAgent(null);
          }}
          conversation={chatConversation}
        />
      )}

      <ConversationCreateModal
        isOpen={showCreateConversationModal}
        onClose={() => {
          setShowCreateConversationModal(false);
          setChatAgent(null);
        }}
        onConversationCreated={handleConversationCreatedForChat}
        preselectedAgentId={chatAgent?.id}
      />
    </>
  );
};
