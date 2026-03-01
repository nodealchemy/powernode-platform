import React, { useState, useEffect, useCallback } from 'react';
import { useLocation } from 'react-router-dom';
import {
  Plus, LayoutDashboard, Brain, CreditCard, ArrowLeft, Globe, Shield,
} from 'lucide-react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { TeamBuilderModal } from '@/features/ai/agent-teams/components/TeamBuilderModal';
import { ExecuteTeamModal } from '@/features/ai/agent-teams/components/ExecuteTeamModal';
import { CreateAgentModal } from '@/features/ai/agents/components/CreateAgentModal';
import { AgentsOverviewTab } from '@/features/ai/agents/components/tabs/AgentsOverviewTab';
import { AgentsSplitPanel } from '@/features/ai/agents/components/AgentsSplitPanel';
import { CardsTab } from '@/features/ai/agents/components/tabs/CardsTab';
import { CommunityAgentsContent } from '@/features/ai/community-agents/pages/CommunityAgentsPage';
import { AutonomyContent } from '@/features/ai/autonomy/pages/AutonomyDashboardPage';
import { useAgentsList } from '@/features/ai/agents/hooks/useAgentsList';
import { useTeamsList } from '@/features/ai/agents/hooks/useTeamsList';
import { useAgentCards } from '@/features/ai/agents/hooks/useAgentCards';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useAiOrchestrationWebSocket } from '@/shared/hooks/useAiOrchestrationWebSocket';
import { useRefreshAction } from '@/shared/hooks/useRefreshAction';

const tabs = [
  { id: 'overview', label: 'Overview', icon: <LayoutDashboard size={16} />, path: '/' },
  { id: 'agents', label: 'Agents', icon: <Brain size={16} />, path: '/list' },
  { id: 'cards', label: 'Cards', icon: <CreditCard size={16} />, path: '/cards' },
  { id: 'community', label: 'Community', icon: <Globe size={16} />, path: '/community' },
  { id: 'autonomy', label: 'Autonomy', icon: <Shield size={16} />, path: '/autonomy' },
];

export const AIAgentsPage: React.FC = () => {
  const location = useLocation();
  const { hasPermission } = usePermissions();

  const canCreateAgents = hasPermission('ai.agents.create');

  // Hooks — agentsList still needed for overview tab stats
  const agentsList = useAgentsList();
  const teamsList = useTeamsList();
  const agentCards = useAgentCards();

  // Local modal state — only for overview tab's create modal
  const [showCreateAgentModal, setShowCreateAgentModal] = useState(false);

  // Tab routing
  const getActiveTab = () => {
    const path = location.pathname;
    if (path.includes('/agents/community')) return 'community';
    if (path.includes('/agents/autonomy')) return 'autonomy';
    if (path.includes('/agents/list')) return 'agents';
    if (path.includes('/agents/cards')) return 'cards';
    return 'overview';
  };

  const [activeTab, setActiveTab] = useState(getActiveTab());

  useEffect(() => {
    const newTab = getActiveTab();
    if (newTab !== activeTab) setActiveTab(newTab);
  }, [location.pathname]);

  // WebSocket for team events (agent events handled by AgentsSplitPanel)
  useAiOrchestrationWebSocket({
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

  // Agent created from overview tab
  const handleAgentCreated = () => {
    setShowCreateAgentModal(false);
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

  // Page actions — "Create Agent" only shown on overview tab (split panel has its own)
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
    ...(activeTab === 'overview' && canCreateAgents ? [{
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
          <AgentsSplitPanel />
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

        <TabPanel tabId="community" activeTab={activeTab}>
          <CommunityAgentsContent />
        </TabPanel>

        <TabPanel tabId="autonomy" activeTab={activeTab}>
          <AutonomyContent />
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

      {/* Create Agent Modal — only for overview tab */}
      <CreateAgentModal
        isOpen={showCreateAgentModal}
        onClose={() => setShowCreateAgentModal(false)}
        onAgentCreated={handleAgentCreated}
      />
    </PageContainer>
  );
};

export default AIAgentsPage;
