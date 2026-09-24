import { screen } from '@testing-library/react';
import { renderWithProviders } from '@/test-utils';
import { AIAgentsPage } from './AIAgentsPage';

// fc-10 review: the Autonomy tab's own sections are URL-addressable now, so a
// deep link's breadcrumb trail must name the section it actually opened —
// "Autonomy" alone would be true of every section, including the one the
// link did NOT open.
//
// Every child and data-fetching hook is stubbed to a bare marker or a no-op:
// what is under test is `getBreadcrumbs()`, not any one tab's own content
// (each has its own suite). `AutonomyDashboardPage` is a PARTIAL mock — only
// `AutonomyContent` is replaced; `autonomySectionLabel` stays real, since
// that is the exact function the breadcrumb trail calls.

jest.mock('@/features/ai/agents/components/CreateAgentModal', () => ({ CreateAgentModal: () => null }));
jest.mock('@/features/ai/agents/components/ExpandableStatsHeader', () => ({ ExpandableStatsHeader: () => null }));
jest.mock('@/features/ai/agents/components/AgentsIndexTable', () => ({ AgentsIndexTable: () => null }));
jest.mock('@/features/ai/agents/components/tabs/CardsTab', () => ({ CardsTab: () => null }));
jest.mock('@/features/ai/community-agents/pages/CommunityAgentsPage', () => ({ CommunityAgentsContent: () => null }));
jest.mock('@/features/ai/autonomy/pages/AutonomyDashboardPage', () => {
  const actual = jest.requireActual('@/features/ai/autonomy/pages/AutonomyDashboardPage');
  return {
    ...actual,
    AutonomyContent: () => <div data-testid="autonomy-content" />,
  };
});

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

describe('AIAgentsPage breadcrumbs name the Autonomy section', () => {
  afterEach(() => {
    window.history.replaceState({}, '', '/');
  });

  it('shows no section breadcrumb at the bare autonomy path', () => {
    renderPage('/app/ai/agents/autonomy');

    expect(screen.getByTestId('autonomy-content')).toBeInTheDocument();
    expect(screen.queryByText('Approvals')).not.toBeInTheDocument();
  });

  it("names the section in the breadcrumb trail for a section sub-path", () => {
    renderPage('/app/ai/agents/autonomy/approvals');

    expect(screen.getByTestId('autonomy-content')).toBeInTheDocument();
    // Only the breadcrumb can produce this text — AutonomyContent (the actual
    // sidebar/section renderer) is mocked away above.
    expect(screen.getByText('Approvals')).toBeInTheDocument();
  });
});
