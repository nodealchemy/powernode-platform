import React, { useState, useEffect, useCallback } from 'react';
import { useLocation } from 'react-router-dom';
import {
  Plus, LayoutDashboard, Brain, Users, CreditCard, ArrowLeft,
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { TeamBuilderModal } from '@/features/ai/agent-teams/components/TeamBuilderModal';
import { ExecuteTeamModal } from '@/features/ai/agent-teams/components/ExecuteTeamModal';
import { CreateAgentModal } from '@/features/ai/agents/components/CreateAgentModal';
import { EditAgentModal } from '@/features/ai/agents/components/EditAgentModal';
import { ConversationContinueModal } from '@/features/ai/conversations/components/ConversationContinueModal';
import { ConversationCreateModal } from '@/features/ai/conversations/components/ConversationCreateModal';
import { AgentsOverviewTab } from '@/features/ai/agents/components/tabs/AgentsOverviewTab';
import { AgentsListTab } from '@/features/ai/agents/components/tabs/AgentsListTab';
import { TeamsTab } from '@/features/ai/agents/components/tabs/TeamsTab';
import { CardsTab } from '@/features/ai/agents/components/tabs/CardsTab';
import { useAgentsList } from '@/features/ai/agents/hooks/useAgentsList';
import { useTeamsList } from '@/features/ai/agents/hooks/useTeamsList';
import { useAgentCards } from '@/features/ai/agents/hooks/useAgentCards';
import { useAgentChat } from '@/features/ai/agents/hooks/useAgentChat';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useAiOrchestrationWebSocket } from '@/shared/hooks/useAiOrchestrationWebSocket';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';
import type { AiAgent } from '@/shared/types/ai';

const tabs = [
  { id: 'overview', label: 'Overview', icon: <LayoutDashboard size={16} />, path: '/' },
  { id: 'agents', label: 'Agents', icon: <Brain size={16} />, path: '/list' },
  { id: 'teams', label: 'Teams', icon: <Users size={16} />, path: '/teams' },
  { id: 'cards', label: 'Cards', icon: <CreditCard size={16} />, path: '/cards' },
];

export const AIAgentsPage: React.FC = () => {
  const location = useLocation();
  const { hasPermission } = usePermissions();

  const canCreateAgents = hasPermission('ai.agents.create');
  const canManageAgents = hasPermission('ai.agents.manage');

  // Hooks
  const agentsList = useAgentsList();
  const teamsList = useTeamsList();
  const agentCards = useAgentCards();
  const agentChat = useAgentChat();

  // Local modal state
  const [showCreateAgentModal, setShowCreateAgentModal] = useState(false);
  const [showEditModal, setShowEditModal] = useState(false);
  const [selectedAgent, setSelectedAgent] = useState<AiAgent | null>(null);

  // Tab routing
  const getActiveTab = () => {
    const path = location.pathname;
    if (path.includes('/agents/list')) return 'agents';
    if (path.includes('/agents/teams')) return 'teams';
    if (path.includes('/agents/cards')) return 'cards';
    return 'overview';
  };

  const [activeTab, setActiveTab] = useState(getActiveTab());

  useEffect(() => {
    const newTab = getActiveTab();
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname]);

  // WebSocket for real-time updates
  useAiOrchestrationWebSocket({
    onAgentEvent: (event) => {
      if (['agent_created', 'agent_updated', 'agent_deleted', 'agent_execution_completed'].includes(event.type)) {
        agentsList.loadAgents();
      }
    },
    onAgentTeamEvent: (event) => {
      if (['team_created', 'team_updated', 'team_deleted', 'team_execution_completed'].includes(event.type)) {
        teamsList.loadTeams();
      }
    },
  });

  // Initial load
  useEffect(() => {
    agentsList.loadAgents();
    teamsList.loadTeams();
  }, []);

  useEffect(() => {
    teamsList.loadTeams();
  }, [teamsList.statusFilter, teamsList.typeFilter]);

  // Refresh
  const handleRefresh = useCallback(async () => {
    await Promise.all([agentsList.loadAgents(), teamsList.loadTeams()]);
  }, [agentsList.loadAgents, teamsList.loadTeams]);

  const { refreshAction } = useRefreshAction({
    onRefresh: handleRefresh,
    loading: agentsList.agentsLoading || teamsList.teamsLoading,
  });

  // Agent modal handlers
  const handleEditAgent = (agent: AiAgent) => {
    setSelectedAgent(agent);
    setShowEditModal(true);
  };

  const handleAgentCreated = () => {
    setShowCreateAgentModal(false);
    agentsList.loadAgents();
  };

  const handleAgentUpdated = () => {
    setShowEditModal(false);
    setSelectedAgent(null);
    agentsList.loadAgents();
  };

  const handleAgentDeleted = () => {
    setShowEditModal(false);
    setSelectedAgent(null);
    agentsList.loadAgents();
  };

  // Breadcrumbs
  const getBreadcrumbs = () => {
    const base: Array<{ label: string; href?: string }> = [
      { label: 'Dashboard', href: '/app' },
      { label: 'AI', href: '/app/ai' },
    ];
    const activeTabInfo = tabs.find(t => t.id === activeTab);
    if (activeTab === 'overview') {
      base.push({ label: 'Agents' });
    } else if (activeTab === 'cards') {
      base.push({ label: 'Agents', href: '/app/ai/agents' });
      base.push({ label: 'Agent Cards' });
    } else {
      base.push({ label: 'Agents', href: '/app/ai/agents' });
      if (activeTabInfo) {
        base.push({ label: activeTabInfo.label });
      }
    }
    return base;
  };

  // Page actions
  const pageActions = [
    refreshAction,
    ...(activeTab === 'cards' && agentCards.cardViewMode !== 'list' ? [{
      id: 'back-to-card-list',
      label: 'Back to List',
      onClick: agentCards.handleBackToCardList,
      variant: 'secondary' as const,
      icon: ArrowLeft,
    }] : []),
    ...(activeTab === 'cards' && agentCards.cardViewMode === 'list' && canCreateAgents ? [{
      id: 'create-agent-card',
      label: 'Create Agent Card',
      onClick: agentCards.handleCreateCard,
      variant: 'primary' as const,
      icon: Plus,
    }] : []),
    ...(activeTab !== 'cards' && canCreateAgents ? [{
      id: 'create-agent',
      label: 'Create Agent',
      onClick: () => setShowCreateAgentModal(true),
      variant: 'primary' as const,
      icon: Plus,
    }] : []),
  ];

  return (
    <PageContainer
      title="AI Agents"
      description="Manage AI agents and multi-agent teams"
      breadcrumbs={getBreadcrumbs()}
      actions={pageActions}
    >
      <TabContainer
        tabs={tabs}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        basePath="/app/ai/agents"
        variant="underline"
        className="mb-6"
      >
        <TabPanel tabId="overview" activeTab={activeTab}>
          <AgentsOverviewTab agentStats={agentsList.agentStats} teamStats={teamsList.teamStats} />
        </TabPanel>

        <TabPanel tabId="agents" activeTab={activeTab}>
          <AgentsListTab
            filteredAgents={agentsList.filteredAgents}
            agentsLoading={agentsList.agentsLoading}
            agentSearchQuery={agentsList.agentSearchQuery}
            onSearchChange={agentsList.setAgentSearchQuery}
            agentViewMode={agentsList.agentViewMode}
            onViewModeChange={agentsList.setAgentViewMode}
            canCreateAgents={canCreateAgents}
            canManageAgents={canManageAgents}
            onCreateAgent={() => setShowCreateAgentModal(true)}
            onToggleStatus={agentsList.handleToggleAgentStatus}
            onEditAgent={handleEditAgent}
            onChatWithAgent={agentChat.handleChatWithAgent}
          />
        </TabPanel>

        <TabPanel tabId="cards" activeTab={activeTab}>
          <CardsTab
            cardViewMode={agentCards.cardViewMode}
            selectedCard={agentCards.selectedCard}
            cardListKey={agentCards.cardListKey}
            onSelectCard={agentCards.handleSelectCard}
            onEditCard={agentCards.handleEditCard}
            onSaveCard={agentCards.handleSaveCard}
            onCancelCard={agentCards.handleCardCancel}
            onBackToList={agentCards.handleBackToCardList}
          />
        </TabPanel>

        <TabPanel tabId="teams" activeTab={activeTab}>
          <TeamsTab
            filteredTeams={teamsList.filteredTeams}
            teamsLoading={teamsList.teamsLoading}
            statusFilter={teamsList.statusFilter}
            onStatusFilterChange={teamsList.setStatusFilter}
            typeFilter={teamsList.typeFilter}
            onTypeFilterChange={teamsList.setTypeFilter}
            teamSearchQuery={teamsList.teamSearchQuery}
            onSearchChange={teamsList.setTeamSearchQuery}
            teamViewMode={teamsList.teamViewMode}
            onViewModeChange={teamsList.setTeamViewMode}
            expandedTeamId={teamsList.expandedTeamId}
            executingTeamIds={teamsList.executingTeamIds}
            onOpenBuilder={() => teamsList.setIsBuilderOpen(true)}
            onToggleExpand={teamsList.handleToggleExpand}
            onDeleteTeam={teamsList.handleDeleteTeam}
            onRequestExecute={teamsList.handleRequestExecute}
            onExecuteTeam={teamsList.handleExecuteTeam}
            onExecutionComplete={teamsList.handleExecutionComplete}
            onDismissMonitor={teamsList.handleDismissMonitor}
            onTeamUpdated={teamsList.loadTeams}
          />
        </TabPanel>
      </TabContainer>

      {/* Team Builder Modal */}
      <TeamBuilderModal
        isOpen={teamsList.isBuilderOpen}
        onClose={teamsList.handleCloseBuilder}
        onSave={teamsList.handleSaveTeam}
      />

      {/* Execute Team Modal */}
      <ExecuteTeamModal
        isOpen={!!teamsList.executeModalTeam}
        team={teamsList.executeModalTeam}
        onClose={() => teamsList.setExecuteModalTeam(null)}
        onExecute={teamsList.handleExecuteTeam}
      />

      {/* Agent Modals */}
      <CreateAgentModal
        isOpen={showCreateAgentModal}
        onClose={() => setShowCreateAgentModal(false)}
        onAgentCreated={handleAgentCreated}
      />

      <EditAgentModal
        isOpen={showEditModal}
        onClose={() => setShowEditModal(false)}
        agent={selectedAgent}
        onAgentUpdated={handleAgentUpdated}
        onAgentDeleted={handleAgentDeleted}
      />

      {agentChat.chatConversation && (
        <ConversationContinueModal
          isOpen={agentChat.showChatModal}
          onClose={agentChat.closeChatModal}
          conversation={agentChat.chatConversation}
        />
      )}

      <ConversationCreateModal
        isOpen={agentChat.showCreateConversationModal}
        onClose={agentChat.closeCreateConversationModal}
        onConversationCreated={agentChat.handleConversationCreatedForChat}
        preselectedAgentId={agentChat.chatAgent?.id}
      />
    </PageContainer>
  );
};

export default AIAgentsPage;
