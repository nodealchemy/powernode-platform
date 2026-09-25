import { render, screen } from '@testing-library/react';

let mockAllowed: string[] = [];
const mockUseAiOpsRecentErrors = jest.fn();

jest.mock('@/shared/hooks/usePermissions', () => ({
  usePermissions: () => ({ hasPermission: (p: string) => mockAllowed.includes(p) }),
}));
jest.mock('@/features/ai/aiops', () => ({
  useAiOpsRecentErrors: (...args: unknown[]) => mockUseAiOpsRecentErrors(...args),
}));
jest.mock('@/features/ai/autonomy/components/CircuitBreakerStatusPanel', () => ({
  CircuitBreakerStatusPanel: () => <div data-testid="agent-breakers-leaf" />,
}));
jest.mock('./ProviderCircuitBreakersPanel', () => ({
  ProviderCircuitBreakersPanel: () => <div data-testid="provider-breakers-leaf" />,
}));

import { CircuitBreakersTab } from './CircuitBreakersTab';

describe('CircuitBreakersTab', () => {
  beforeEach(() => {
    mockUseAiOpsRecentErrors.mockReturnValue({ data: undefined });
  });

  it('shows both breaker panels under distinct labels when both permissions are held', () => {
    mockAllowed = ['ai.agents.read', 'ai.monitoring.read'];
    render(<CircuitBreakersTab />);

    expect(screen.getByText('Agent Circuit Breakers')).toBeInTheDocument();
    expect(screen.getByTestId('agent-breakers-leaf')).toBeInTheDocument();
    expect(screen.getByText('Provider Circuit Breakers')).toBeInTheDocument();
    expect(screen.getByTestId('provider-breakers-leaf')).toBeInTheDocument();
  });

  // Mutant proof: a version that gated BOTH panels on one shared permission
  // (e.g. always `ai.monitoring.read`) would pass the "both shown" test above.
  // These two checks hold each panel's gate independently, matching the two
  // different backend endpoints (ai.agents.read vs ai.monitoring.read).
  it('shows only the agent panel when the viewer lacks ai.monitoring.read', () => {
    mockAllowed = ['ai.agents.read'];
    render(<CircuitBreakersTab />);

    expect(screen.getByTestId('agent-breakers-leaf')).toBeInTheDocument();
    expect(screen.queryByTestId('provider-breakers-leaf')).not.toBeInTheDocument();
    expect(screen.queryByText('Provider Circuit Breakers')).not.toBeInTheDocument();
  });

  it('shows only the provider panel when the viewer lacks ai.agents.read', () => {
    mockAllowed = ['ai.monitoring.read'];
    render(<CircuitBreakersTab />);

    expect(screen.queryByTestId('agent-breakers-leaf')).not.toBeInTheDocument();
    expect(screen.queryByText('Agent Circuit Breakers')).not.toBeInTheDocument();
    expect(screen.getByTestId('provider-breakers-leaf')).toBeInTheDocument();
  });

  it('shows a permission-denied message with neither permission', () => {
    mockAllowed = [];
    render(<CircuitBreakersTab />);

    expect(screen.queryByTestId('agent-breakers-leaf')).not.toBeInTheDocument();
    expect(screen.queryByTestId('provider-breakers-leaf')).not.toBeInTheDocument();
    expect(screen.getByText(/don't have permission to view circuit breakers/i)).toBeInTheDocument();
  });

  // fc-42 review fix: recent errors is gated on ai.aiops.read — the
  // permission Api::V1::Ai::AiOpsController#recent_errors actually enforces —
  // NOT ai.monitoring.read (the provider-breakers permission). A viewer can
  // hold either without the other.
  it('shows the recent-errors feed only when the viewer holds ai.aiops.read and errors exist', () => {
    mockAllowed = ['ai.monitoring.read', 'ai.aiops.read'];
    mockUseAiOpsRecentErrors.mockReturnValue({
      data: [{ execution_id: 'e1', agent_name: 'Researcher', error: 'boom', failed_at: '2026-06-18T01:00:00Z' }],
    });
    render(<CircuitBreakersTab />);

    expect(screen.getByText('Recent Errors')).toBeInTheDocument();
    expect(screen.getByText('boom')).toBeInTheDocument();
  });

  it('hides the recent-errors feed without ai.aiops.read, even if data is present', () => {
    mockAllowed = ['ai.agents.read', 'ai.monitoring.read'];
    mockUseAiOpsRecentErrors.mockReturnValue({
      data: [{ execution_id: 'e1', agent_name: 'Researcher', error: 'boom', failed_at: '2026-06-18T01:00:00Z' }],
    });
    render(<CircuitBreakersTab />);

    expect(screen.queryByText('Recent Errors')).not.toBeInTheDocument();
  });

  // The old version called useAiOpsRecentErrors() with no `enabled` at all,
  // so the request fired for every viewer regardless of permission.
  it('passes enabled=true to useAiOpsRecentErrors only when the viewer holds ai.aiops.read', () => {
    mockAllowed = ['ai.aiops.read'];
    render(<CircuitBreakersTab />);
    expect(mockUseAiOpsRecentErrors).toHaveBeenLastCalledWith(20, true);
  });

  it('passes enabled=false to useAiOpsRecentErrors without ai.aiops.read', () => {
    mockAllowed = ['ai.agents.read', 'ai.monitoring.read'];
    render(<CircuitBreakersTab />);
    expect(mockUseAiOpsRecentErrors).toHaveBeenLastCalledWith(20, false);
  });
});
