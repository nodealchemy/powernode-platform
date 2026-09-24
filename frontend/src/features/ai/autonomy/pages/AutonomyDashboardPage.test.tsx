import { render, screen, fireEvent } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AutonomyContent } from './AutonomyDashboardPage';

// fc-10: SIDEBAR_ITEMS used to be local useState, so a section could never be
// linked directly — a shared link always landed on Overview. These pin the
// URL as the source of truth: the base path is Overview, and each sidebar
// item's own sub-path renders that section and nothing else.
//
// Every data-fetching panel is mocked to a bare marker: what is under test is
// the URL → section mapping, not any one panel's own behaviour (each has its
// own suite).

jest.mock('../api/autonomyApi', () => ({
  useAutonomyStats: () => ({
    data: {
      total_agents: 3, supervised: 1, monitored: 1, trusted: 1, autonomous: 0,
      pending_promotions: 0, pending_demotions: 0,
    },
    isLoading: false,
  }),
  useTrustScores: () => ({ data: [], isLoading: false }),
  useAgentBudgets: () => ({ data: [], isLoading: false }),
  useAgentLineage: () => ({ data: null, isLoading: false }),
  useAgentLineageForest: () => ({ data: { trees: [], orphans: [] }, isLoading: false }),
}));

jest.mock('../components/TrustScoreCard', () => ({ TrustScoreCard: () => null }));
jest.mock('../components/AgentLineageTree', () => ({ AgentLineageTree: () => null }));
jest.mock('../components/BudgetAllocationPanel', () => ({ BudgetAllocationPanel: () => null }));
jest.mock('../components/BudgetRegimeIndicator', () => ({ BudgetRegimeIndicator: () => null }));
jest.mock('../components/CapabilityMatrixViewer', () => ({ CapabilityMatrixViewer: () => null }));
jest.mock('../components/CircuitBreakerStatusPanel', () => ({ CircuitBreakerStatusPanel: () => null }));
jest.mock('../components/BehavioralFingerprintChart', () => ({ BehavioralFingerprintChart: () => null }));
jest.mock('@/features/ai/approvals/components/ApprovalQueuePanel', () => ({
  ApprovalQueuePanel: () => <div data-testid="section-approvals" />,
}));
jest.mock('../components/DelegationPolicyPanel', () => ({ DelegationPolicyPanel: () => null }));
jest.mock('../components/TelemetryEventStream', () => ({
  TelemetryEventStream: () => <div data-testid="section-telemetry" />,
}));
jest.mock('../components/KillSwitchPanel', () => ({ KillSwitchPanel: () => <div data-testid="section-killswitch" /> }));
jest.mock('../components/GoalsPanel', () => ({ GoalsPanel: () => <div data-testid="section-goals" /> }));
jest.mock('../components/ProposalsPanel', () => ({ ProposalsPanel: () => <div data-testid="section-proposals" /> }));
jest.mock('../components/EscalationsPanel', () => ({ EscalationsPanel: () => <div data-testid="section-escalations" /> }));
jest.mock('../components/FeedbackPanel', () => ({ FeedbackPanel: () => <div data-testid="section-feedback" /> }));
jest.mock('../components/InterventionPoliciesPanel', () => ({
  InterventionPoliciesPanel: () => <div data-testid="section-policies" />,
}));
jest.mock('../components/ShadowModeResultsPanel', () => ({
  ShadowModeResultsPanel: () => <div data-testid="section-shadow" />,
}));

// Renders alongside AutonomyContent so a click's effect on the URL — not just
// on the rendered section — can be asserted directly, without reaching into
// the MemoryRouter's internals.
const LocationProbe = () => {
  const location = useLocation();
  return <div data-testid="location-probe">{location.pathname}</div>;
};

const renderAt = (path: string) =>
  render(
    <MemoryRouter initialEntries={[path]}>
      <LocationProbe />
      <AutonomyContent />
    </MemoryRouter>
  );

describe('AutonomyContent — URL-addressable sections', () => {
  it('renders Overview at the bare autonomy path', () => {
    renderAt('/app/ai/agents/autonomy');

    expect(screen.getByText('Total Agents')).toBeInTheDocument();
    expect(screen.queryByTestId('section-goals')).not.toBeInTheDocument();
  });

  it('renders the section named by the URL, not Overview', () => {
    renderAt('/app/ai/agents/autonomy/goals');

    expect(screen.getByTestId('section-goals')).toBeInTheDocument();
    expect(screen.queryByText('Total Agents')).not.toBeInTheDocument();
  });

  it('renders Approvals for the approvals sub-path (RemediationTab / pending-approval toast target)', () => {
    renderAt('/app/ai/agents/autonomy/approvals');

    expect(screen.getByTestId('section-approvals')).toBeInTheDocument();
  });

  it('renders Telemetry for the telemetry sub-path', () => {
    renderAt('/app/ai/agents/autonomy/telemetry');

    expect(screen.getByTestId('section-telemetry')).toBeInTheDocument();
  });

  it('falls back to Overview for a segment no sidebar item owns, instead of rendering nothing', () => {
    renderAt('/app/ai/agents/autonomy/not-a-real-section');

    expect(screen.getByText('Total Agents')).toBeInTheDocument();
  });

  it("clicking a sidebar section changes the URL to that section's path, not just the rendered content", () => {
    renderAt('/app/ai/agents/autonomy');
    expect(screen.getByTestId('location-probe')).toHaveTextContent('/app/ai/agents/autonomy');

    fireEvent.click(screen.getByRole('button', { name: 'Goals' }));

    expect(screen.getByTestId('location-probe')).toHaveTextContent('/app/ai/agents/autonomy/goals');
    expect(screen.getByTestId('section-goals')).toBeInTheDocument();
  });
});
