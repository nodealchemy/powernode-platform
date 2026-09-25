import { screen } from '@testing-library/react';
import { renderWithProviders } from '@/test-utils';
import { AIAgentsPage } from './AIAgentsPage';

// Every child and data-fetching hook is stubbed to a bare marker or a no-op:
// what is under test is the page's tabs and breadcrumb trail, not any one
// tab's own content (each has its own suite).

jest.mock('@/features/ai/agents/components/CreateAgentModal', () => ({ CreateAgentModal: () => null }));
jest.mock('@/features/ai/agents/components/ExpandableStatsHeader', () => ({ ExpandableStatsHeader: () => null }));
jest.mock('@/features/ai/agents/components/AgentsIndexTable', () => ({ AgentsIndexTable: () => null }));
jest.mock('@/features/ai/agents/components/tabs/CardsTab', () => ({ CardsTab: () => null }));
jest.mock('@/features/ai/community-agents/pages/CommunityAgentsPage', () => ({ CommunityAgentsContent: () => null }));

jest.mock('@/features/ai/agents/hooks/useAgentsList', () => ({
  useAgentsList: () => ({
    agentStats: {}, agentsLoading: false, loadAgents: jest.fn(),
  }),
}));
jest.mock('@/features/ai/agents/hooks/useTeamsList', () => ({
  useTeamsList: () => ({
    teamStats: {}, teamsLoading: false, loadTeams: jest.fn(),
    statusFilter: undefined, typeFilter: undefined,
    isBuilderOpen: false, handleCloseBuilder: jest.fn(), handleSaveTeam: jest.fn(),
    executeModalTeam: null, setExecuteModalTeam: jest.fn(), handleExecuteTeam: jest.fn(),
  }),
}));
jest.mock('@/features/ai/agents/hooks/useAgentCards', () => ({
  useAgentCards: () => ({
    cardViewMode: 'list', selectedCard: null, cardListKey: 0,
    handleSelectCard: jest.fn(), handleEditCard: jest.fn(), handleSaveCard: jest.fn(),
    handleCardCancel: jest.fn(), handleBackToCardList: jest.fn(), handleCreateCard: jest.fn(),
  }),
}));
jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({ hasPermission: () => false }),
}));
jest.mock('@/shared/hooks/useRefreshAction', () => ({
  useRefreshAction: () => ({ refreshAction: { label: 'Refresh', onClick: jest.fn() } }),
}));

const renderPage = (path: string) => {
  window.history.pushState({}, '', path);
  return renderWithProviders(<AIAgentsPage />, {
    preloadedState: {
      auth: { user: { id: 'u-1', permissions: [] }, isAuthenticated: true, isLoading: false },
    },
  });
};

// fc-41: Autonomy left the Agents page for AI → Control; the Agents page keeps
// its own three views and no longer mounts autonomy content at all.
describe('AIAgentsPage — agents views only', () => {
  afterEach(() => {
    window.history.replaceState({}, '', '/');
  });

  it('offers the Agents, Cards and Community tabs, and no Autonomy tab', () => {
    renderPage('/app/ai/agents');

    expect(screen.getAllByRole('tab').map((t) => t.textContent?.trim())).toEqual(['Agents', 'Cards', 'Community']);
    expect(screen.queryByText('Autonomy')).not.toBeInTheDocument();
  });

  it('names the active tab in the breadcrumb trail', () => {
    renderPage('/app/ai/agents/community');

    expect(screen.getAllByText('Community').length).toBeGreaterThan(1);
  });
});
