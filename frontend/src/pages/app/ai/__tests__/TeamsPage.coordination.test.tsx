import { screen } from '@testing-library/react';
import { Routes, Route, useLocation } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render } from '@/test-utils';

// Team coordination (stigmergic signals, pressure fields, restructure events)
// moved here from the deleted Governance page: it is how teams coordinate,
// not a control. /app/ai/teams stays the team list; the Coordination tab is
// its own URL and is offered only to ai.manage holders, the permission the
// coordination endpoints check.

jest.mock('@/features/ai/agent-teams/components/TeamsIndexTable', () => ({
  TeamsIndexTable: () => <div data-testid="teams-table" />,
}));
jest.mock('@/shared/services/ai/IntelligenceApiService', () => ({
  intelligenceApi: {
    getCoordinationSummary: () => Promise.resolve({ summary: {
      signals: { active: 3, fading: 1 },
      pressure_fields: { actionable: 1, avg_pressure: 0.5, total: 2 },
      team_events: { total: 0, recent_24h: 0 },
    } }),
    getSignals: () => Promise.resolve({ items: [] }),
    getPressureFields: () => Promise.resolve({ items: [] }),
    getTeamEvents: () => Promise.resolve({ items: [] }),
  },
}));

import TeamsPage from '../TeamsPage';

let currentPath = '';
const LocationProbe = () => {
  currentPath = useLocation().pathname;
  return null;
};

function renderAt(path: string, permissions: string[]) {
  // test-utils mounts a BrowserRouter, so the path is set on the window.
  window.history.pushState({}, '', path);
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={queryClient}>
      <Routes>
        <Route path="/app/ai/teams/*" element={<><TeamsPage /><LocationProbe /></>} />
      </Routes>
    </QueryClientProvider>,
    {
      preloadedState: { auth: { user: { permissions }, isLoading: false, isAuthenticated: true } },
    }
  );
}

describe('TeamsPage — Coordination tab', () => {
  it('keeps the team list at /app/ai/teams', () => {
    renderAt('/app/ai/teams', ['ai.teams.read', 'ai.manage']);

    expect(screen.getByTestId('teams-table')).toBeInTheDocument();
    expect(currentPath).toBe('/app/ai/teams');
  });

  it('renders team coordination at its own URL', async () => {
    renderAt('/app/ai/teams/coordination', ['ai.teams.read', 'ai.manage']);

    expect(await screen.findByText('Active Signals')).toBeInTheDocument();
    expect(screen.queryByTestId('teams-table')).not.toBeInTheDocument();
  });

  it('offers no Coordination tab without ai.manage', () => {
    renderAt('/app/ai/teams', ['ai.teams.read']);

    expect(screen.queryByRole('tab', { name: /coordination/i })).not.toBeInTheDocument();
    expect(screen.queryByText('Coordination')).not.toBeInTheDocument();
  });

  it('does not open coordination from its URL without ai.manage', () => {
    renderAt('/app/ai/teams/coordination', ['ai.teams.read']);

    expect(screen.queryByText('Active Signals')).not.toBeInTheDocument();
    expect(screen.getByTestId('teams-table')).toBeInTheDocument();
  });
});
