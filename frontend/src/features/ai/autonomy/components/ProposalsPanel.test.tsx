import { render, screen, fireEvent } from '@testing-library/react';
import { ProposalsPanel } from './ProposalsPanel';
import type { AgentProposal } from '../types/autonomy';

const mockUseProposals = jest.fn();
const mockMutation = { mutateAsync: jest.fn(), isPending: false };

jest.mock('../api/autonomyApi', () => ({
  useProposals: (...args: unknown[]) => mockUseProposals(...args),
  useApproveProposal: () => mockMutation,
  useRejectProposal: () => mockMutation,
  useWithdrawProposal: () => mockMutation,
  useBatchReviewProposals: () => mockMutation,
}));
jest.mock('@/shared/hooks/useNotifications', () => ({ useNotifications: () => ({ addNotification: jest.fn() }) }));
jest.mock('@/shared/components/entity', () => ({ EntityLink: ({ label }: { label: string }) => label }));

const base: AgentProposal = {
  id: 'p1', proposal_type: 'feature', title: 'Do a thing', description: 'd', status: 'pending_review',
  priority: 'medium', impact_assessment: {}, proposed_changes: {}, created_at: '2026-10-01T00:00:00Z',
  updated_at: '2026-10-01T00:00:00Z',
};

describe('ProposalsPanel', () => {
  beforeEach(() => mockUseProposals.mockReset());

  it('offers an Expired filter and queries by it', () => {
    mockUseProposals.mockReturnValue({ data: [], isLoading: false });
    render(<ProposalsPanel />);

    expect(screen.getByRole('option', { name: 'Expired' })).toBeInTheDocument();
    fireEvent.change(screen.getByRole('combobox'), { target: { value: 'expired' } });
    expect(mockUseProposals).toHaveBeenLastCalledWith({ status: 'expired' });
  });

  it('labels an expired proposal Expired, not withdrawn', () => {
    mockUseProposals.mockReturnValue({ data: [{ ...base, status: 'expired' }], isLoading: false });
    render(<ProposalsPanel />);

    expect(screen.getAllByText('Expired').length).toBeGreaterThan(0);
    expect(screen.queryByText(/withdrawn/i, { selector: 'span.rounded' })).toBeNull();
  });

  it('marks an acknowledgement-only approval as such', () => {
    mockUseProposals.mockReturnValue({
      data: [{
        ...base, status: 'approved',
        handoff: { kind: 'acknowledged', id: null, label: 'Acknowledged only: nothing was started', acknowledged_only: true },
      }],
      isLoading: false,
    });
    render(<ProposalsPanel />);

    expect(screen.getByTestId('proposal-handoff')).toHaveTextContent('Acknowledged only: nothing was started');
  });

  it('shows what a real handoff started', () => {
    mockUseProposals.mockReturnValue({
      data: [{
        ...base, status: 'approved',
        handoff: { kind: 'dev_task', id: 't1', label: 'Queued as a dev-improve task', acknowledged_only: false },
      }],
      isLoading: false,
    });
    render(<ProposalsPanel />);

    expect(screen.getByTestId('proposal-handoff')).toHaveTextContent('Queued as a dev-improve task');
  });

  it('shows the tier and tool families an agent_create approval would create', () => {
    mockUseProposals.mockReturnValue({
      data: [{ ...base, proposal_type: 'agent_create', agent_spec: { slug: 's', tier: 'light', tool_families: ['knowledge', 'memory'], tools: ['search_knowledge'], unknown: ['bogus'] } }],
      isLoading: false,
    });
    render(<ProposalsPanel />);
    fireEvent.click(screen.getByText('Do a thing'));

    expect(screen.getByTestId('agent-spec')).toHaveTextContent('light');
    expect(screen.getByTestId('agent-spec')).toHaveTextContent('Tool families: knowledge, memory');
    expect(screen.getByTestId('agent-spec')).toHaveTextContent('Tools: search_knowledge');
    expect(screen.getByTestId('agent-spec')).toHaveTextContent('Unrecognised (approval will be refused): bogus');
  });
});
