import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { AdaptationCard, type AdaptationProposal } from './AdaptationCard';

const noop = jest.fn();
const asyncNoop = () => jest.fn().mockResolvedValue(undefined);

const baseProposal: AdaptationProposal = {
  id: 'prop-1',
  project_name: 'saas-api',
  signal: 'EU-west node CPU > 85% for 4 of last 7 days',
  trigger: 'utilization sensor (auto)',
  proposed_change: {
    summary: 'Add 1 NodeInstance to EU-west; update load balancer weights',
    blast_radius: 'low',
    reversible: true,
    cost_delta_monthly_usd: 30,
    resources_changed: 2,
    resources_destroyed: 0,
  },
  proposed_at: new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString(),
};

const renderCard = (overrides: Partial<{
  proposal: AdaptationProposal;
  onApprove: jest.Mock;
  onReject: jest.Mock;
  onShowDetails: jest.Mock;
  onSnooze: jest.Mock;
}> = {}) => {
  const onApprove = overrides.onApprove ?? asyncNoop();
  const onReject = overrides.onReject ?? asyncNoop();
  const onShowDetails = overrides.onShowDetails ?? jest.fn();
  const onSnooze = overrides.onSnooze ?? asyncNoop();
  const proposal = overrides.proposal ?? baseProposal;
  const utils = render(
    <AdaptationCard
      proposal={proposal}
      onApprove={onApprove}
      onReject={onReject}
      onShowDetails={onShowDetails}
      onSnooze={onSnooze}
    />
  );
  return { ...utils, onApprove, onReject, onShowDetails, onSnooze };
};

describe('AdaptationCard', () => {
  beforeEach(() => {
    noop.mockReset();
  });

  it('renders header tag, project name, signal, trigger, and proposed change', () => {
    renderCard();
    expect(screen.getByTestId('adaptation-card')).toBeInTheDocument();
    expect(screen.getByTestId('adaptation-header-tag')).toHaveTextContent(/ADAPTATION/);
    expect(screen.getByText(/saas-api/)).toBeInTheDocument();
    expect(screen.getByTestId('adaptation-signal')).toHaveTextContent(/CPU > 85%/);
    expect(screen.getByTestId('adaptation-trigger')).toHaveTextContent(/utilization sensor/);
    expect(screen.getByTestId('adaptation-proposed-change')).toHaveTextContent(/Add 1 NodeInstance/);
  });

  it('renders LOW blast radius badge with success styling', () => {
    renderCard();
    const badge = screen.getByTestId('adaptation-blast-radius');
    expect(badge).toHaveTextContent('LOW');
    expect(badge.className).toMatch(/theme-success/);
  });

  it('renders HIGH blast radius badge with danger styling for high-risk proposals', () => {
    renderCard({
      proposal: {
        ...baseProposal,
        proposed_change: {
          ...baseProposal.proposed_change,
          blast_radius: 'high',
          reversible: false,
        },
      },
    });
    const badge = screen.getByTestId('adaptation-blast-radius');
    expect(badge).toHaveTextContent('HIGH');
    expect(badge.className).toMatch(/theme-danger/);
    expect(screen.getByTestId('adaptation-reversible')).toHaveTextContent('irreversible');
  });

  it('formats positive cost delta as +$30.00 / mo', () => {
    renderCard();
    expect(screen.getByTestId('adaptation-cost-delta')).toHaveTextContent('+$30.00 / mo');
  });

  it('formats negative cost delta with minus sign', () => {
    renderCard({
      proposal: {
        ...baseProposal,
        proposed_change: { ...baseProposal.proposed_change, cost_delta_monthly_usd: -120 },
      },
    });
    expect(screen.getByTestId('adaptation-cost-delta')).toHaveTextContent('−$120.00 / mo');
  });

  it('renders relative time when proposed_at is set', () => {
    renderCard();
    expect(screen.getByText(/proposed 2h ago/)).toBeInTheDocument();
  });

  it('omits relative time when proposed_at is absent', () => {
    const { proposed_at: _omit, ...rest } = baseProposal;
    renderCard({ proposal: rest as AdaptationProposal });
    expect(screen.queryByText(/proposed.*ago/)).not.toBeInTheDocument();
  });

  it('calls onApprove with proposal id when Approve & Apply is clicked', async () => {
    const onApprove = jest.fn().mockResolvedValue(undefined);
    renderCard({ onApprove });
    fireEvent.click(screen.getByTestId('adaptation-approve'));
    await waitFor(() => expect(onApprove).toHaveBeenCalledWith('prop-1'));
  });

  it('calls onReject with proposal id when Reject is clicked', async () => {
    const onReject = jest.fn().mockResolvedValue(undefined);
    renderCard({ onReject });
    fireEvent.click(screen.getByTestId('adaptation-reject'));
    await waitFor(() => expect(onReject).toHaveBeenCalledWith('prop-1'));
  });

  it('calls onShowDetails synchronously when Why? is clicked', () => {
    const onShowDetails = jest.fn();
    renderCard({ onShowDetails });
    fireEvent.click(screen.getByTestId('adaptation-why'));
    expect(onShowDetails).toHaveBeenCalledWith('prop-1');
  });

  it('calls onSnooze with 7 days when Snooze 7d is clicked', async () => {
    const onSnooze = jest.fn().mockResolvedValue(undefined);
    renderCard({ onSnooze });
    fireEvent.click(screen.getByTestId('adaptation-snooze'));
    await waitFor(() => expect(onSnooze).toHaveBeenCalledWith('prop-1', 7));
  });

  it('disables all actions while a button is pending', async () => {
    let resolveApprove: () => void = () => undefined;
    const onApprove = jest.fn().mockImplementation(
      () =>
        new Promise<void>((resolve) => {
          resolveApprove = resolve;
        })
    );
    renderCard({ onApprove });
    fireEvent.click(screen.getByTestId('adaptation-approve'));
    await waitFor(() => {
      expect(screen.getByTestId('adaptation-approve')).toBeDisabled();
      expect(screen.getByTestId('adaptation-reject')).toBeDisabled();
      expect(screen.getByTestId('adaptation-snooze')).toBeDisabled();
    });
    resolveApprove();
    await waitFor(() => expect(screen.getByTestId('adaptation-approve')).not.toBeDisabled());
  });

  it('renders resources_changed and resources_destroyed counts in meta line', () => {
    renderCard({
      proposal: {
        ...baseProposal,
        proposed_change: {
          ...baseProposal.proposed_change,
          resources_changed: 5,
          resources_destroyed: 2,
        },
      },
    });
    expect(screen.getByText(/5 changed, 2 destroyed/)).toBeInTheDocument();
  });
});
