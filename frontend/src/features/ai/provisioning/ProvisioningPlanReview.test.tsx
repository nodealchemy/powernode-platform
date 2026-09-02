import React from 'react';
import { act, render, screen, fireEvent, waitFor } from '@testing-library/react';
import { ProvisioningPlanReview } from './ProvisioningPlanReview';
import type { ProvisioningPlan, ProjectBrief } from './types';

jest.mock('@xyflow/react', () => ({
  ReactFlow: ({ children }: { children?: React.ReactNode }) => (
    <div data-testid="react-flow">{children}</div>
  ),
  Background: () => <div data-testid="flow-background" />,
  Controls: () => <div data-testid="flow-controls" />,
  MarkerType: { ArrowClosed: 'arrowclosed' },
  Handle: () => null,
  Position: { Top: 'top', Bottom: 'bottom' }
}));

const buildPlan = (overrides: Partial<ProvisioningPlan> = {}): ProvisioningPlan => ({
  plan_id: 'plan-abc123def456',
  dag: {
    nodes: [
      { id: 's1', name: 'Provision compute', description: 'Create 2 VMs', skill: 'compute_provision', status: 'pending' },
      { id: 's2', name: 'Configure networking', skill: 'network_configure', status: 'pending' }
    ],
    edges: [{ source: 's1', target: 's2' }]
  },
  cost_estimate: {
    monthly_usd: 425.5,
    one_time_usd: 75,
    confidence: 'high',
    by_resource: [
      { resource_type: 'compute.vm', name: 'web', monthly_usd: 200, count: 2 },
      { resource_type: 'volume.ssd', name: 'data', monthly_usd: 75, count: 1 }
    ],
    last_priced_at: '2026-05-07T12:00:00Z'
  },
  topology_preview: {
    nodes: [{ id: 'n1', type: 'compute', label: 'Web' }],
    edges: [],
    regions: [{ id: 'us-east-1', name: 'us-east-1' }]
  },
  risk: {
    score: 42,
    severity: 'med',
    factors: [
      { name: 'cost_overrun', weight: 0.6, severity: 'med', explanation: 'Burst pricing on cache.' }
    ]
  },
  ...overrides
});

const brief: ProjectBrief = {
  intent: 'host saas app',
  use_case: 'multi-tenant',
  scale: { initial: 100, target: 1000 },
  regions: ['us-east-1'],
  budget_cap_usd_monthly: 800
};

describe('ProvisioningPlanReview', () => {
  let onApprove: jest.Mock;
  let onReject: jest.Mock;
  let onModify: jest.Mock;
  let onClose: jest.Mock;
  let onEditStep: jest.Mock;

  beforeEach(() => {
    onApprove = jest.fn().mockResolvedValue(undefined);
    onReject = jest.fn().mockResolvedValue(undefined);
    onModify = jest.fn();
    onClose = jest.fn();
    onEditStep = jest.fn();
  });

  it('renders the modal scaffold and brief summary when open', () => {
    render(
      <ProvisioningPlanReview
        isOpen
        missionId="m-1"
        plan={buildPlan()}
        brief={brief}
        onApprove={onApprove}
        onReject={onReject}
        onModify={onModify}
        onClose={onClose}
      />
    );
    expect(screen.getByTestId('provisioning-plan-review')).toBeInTheDocument();
    expect(screen.getByText('Review provisioning plan')).toBeInTheDocument();
    expect(screen.getByTestId('provisioning-brief-summary')).toHaveTextContent('host saas app');
    expect(screen.getByTestId('provisioning-brief-summary')).toHaveTextContent('us-east-1');
    expect(screen.getByTestId('provisioning-brief-summary')).toHaveTextContent('$800/mo cap');
  });

  it('does not render when isOpen=false', () => {
    render(
      <ProvisioningPlanReview
        isOpen={false}
        missionId="m-1"
        plan={buildPlan()}
        onApprove={onApprove}
        onReject={onReject}
        onModify={onModify}
        onClose={onClose}
      />
    );
    expect(screen.queryByTestId('provisioning-plan-review')).not.toBeInTheDocument();
  });

  // IMP-842b56d3a5d4 — a step parked on an approval carries the server's
  // `awaiting_approval` status (Ai::GoalPlanStep::STATUSES). PlanStepStatus
  // did not model it, so it fell through stepIcon's `default` and rendered
  // as the pending circle — indistinguishable from "not started yet".
  it('renders a parked step with its own awaiting-approval icon', () => {
    const plan = buildPlan({
      dag: {
        nodes: [
          { id: 's1', name: 'Provision compute', skill: 'compute_provision', status: 'awaiting_approval' }
        ],
        edges: []
      }
    });

    render(
      <ProvisioningPlanReview
        isOpen
        missionId="m-1"
        plan={plan}
        onApprove={onApprove}
        onReject={onReject}
        onModify={onModify}
        onClose={onClose}
      />
    );

    expect(screen.getByLabelText('awaiting approval')).toBeInTheDocument();
  });

  // REVIEW FINDING (IMP-842b56d3a5d4) — the snapshot serves the RAW step
  // column (plan_snapshot_service.rb:200) and Ai::GoalPlanStep::STATUSES names
  // the in-flight state `executing`, not `running`. PlanStepStatus modelled
  // only `running`, so an in-flight step hit stepIcon's `default` and rendered
  // the pending circle — the identical defect one case-arm away.
  it('renders an executing step as in-flight, not pending', () => {
    const plan = buildPlan({
      dag: {
        nodes: [
          { id: 's1', name: 'Provision compute', skill: 'compute_provision', status: 'executing' }
        ],
        edges: []
      }
    });

    render(
      <ProvisioningPlanReview
        isOpen
        missionId="m-1"
        plan={plan}
        onApprove={onApprove}
        onReject={onReject}
        onModify={onModify}
        onClose={onClose}
      />
    );

    expect(screen.getByLabelText('running')).toBeInTheDocument();
    expect(screen.queryByLabelText('pending')).not.toBeInTheDocument();
  });

  it('renders one entry per DAG step with status icons + per-step Edit', () => {
    render(
      <ProvisioningPlanReview
        isOpen
        missionId="m-1"
        plan={buildPlan()}
        onApprove={onApprove}
        onReject={onReject}
        onModify={onModify}
        onClose={onClose}
        onEditStep={onEditStep}
      />
    );
    expect(screen.getByTestId('provisioning-step-s1')).toHaveTextContent('Provision compute');
    expect(screen.getByTestId('provisioning-step-s2')).toHaveTextContent('Configure networking');

    fireEvent.click(screen.getByTestId('provisioning-step-edit-s1'));
    expect(onEditStep).toHaveBeenCalledWith('s1');
  });

  it('renders the topology section, cost breakdown, and risk chip', () => {
    render(
      <ProvisioningPlanReview
        isOpen
        missionId="m-1"
        plan={buildPlan()}
        onApprove={onApprove}
        onReject={onReject}
        onModify={onModify}
        onClose={onClose}
      />
    );
    expect(screen.getByTestId('provisioning-topology')).toBeInTheDocument();
    expect(screen.getByTestId('cost-breakdown')).toBeInTheDocument();
    expect(screen.getByTestId('risk-factor-cost_overrun')).toHaveTextContent('Burst pricing');
    expect(screen.getByTestId('provisioning-risk')).toHaveTextContent('Medium risk');
  });

  it('shows the authorization line with the plan totals', () => {
    render(
      <ProvisioningPlanReview
        isOpen
        missionId="m-1"
        plan={buildPlan()}
        onApprove={onApprove}
        onReject={onReject}
        onModify={onModify}
        onClose={onClose}
      />
    );
    const authLine = screen.getByTestId('provisioning-authorization');
    expect(authLine).toHaveTextContent('$425.5/mo');
    expect(authLine).toHaveTextContent('$75');
  });

  it('invokes onApprove when Approve & Provision is clicked', async () => {
    render(
      <ProvisioningPlanReview
        isOpen
        missionId="m-1"
        plan={buildPlan()}
        onApprove={onApprove}
        onReject={onReject}
        onModify={onModify}
        onClose={onClose}
      />
    );
    await act(async () => {
      fireEvent.click(screen.getByTestId('provisioning-approve-btn'));
    });
    expect(onApprove).toHaveBeenCalled();
  });

  it('first click on Reject reveals the rejection-note input; second click submits with the note', async () => {
    render(
      <ProvisioningPlanReview
        isOpen
        missionId="m-1"
        plan={buildPlan()}
        onApprove={onApprove}
        onReject={onReject}
        onModify={onModify}
        onClose={onClose}
      />
    );
    fireEvent.click(screen.getByTestId('provisioning-reject-btn'));
    const note = await screen.findByTestId('provisioning-rejection-note');
    fireEvent.change(note, { target: { value: 'over budget' } });
    await act(async () => {
      fireEvent.click(screen.getByTestId('provisioning-reject-btn'));
    });
    await waitFor(() => expect(onReject).toHaveBeenCalledWith('over budget'));
  });

  it('Modify in chat header button triggers onModify', () => {
    render(
      <ProvisioningPlanReview
        isOpen
        missionId="m-1"
        plan={buildPlan()}
        onApprove={onApprove}
        onReject={onReject}
        onModify={onModify}
        onClose={onClose}
      />
    );
    fireEvent.click(screen.getByTestId('provisioning-modify-header'));
    expect(onModify).toHaveBeenCalled();
  });

  it('renders an empty-state message when DAG has no steps', () => {
    const emptyPlan = buildPlan({ dag: { nodes: [], edges: [] } });
    render(
      <ProvisioningPlanReview
        isOpen
        missionId="m-1"
        plan={emptyPlan}
        onApprove={onApprove}
        onReject={onReject}
        onModify={onModify}
        onClose={onClose}
      />
    );
    expect(screen.getByTestId('provisioning-steps')).toHaveTextContent('No steps composed yet.');
  });

  it('renders a fallback subtitle when no brief is provided', () => {
    render(
      <ProvisioningPlanReview
        isOpen
        missionId="m-1"
        plan={buildPlan()}
        onApprove={onApprove}
        onReject={onReject}
        onModify={onModify}
        onClose={onClose}
      />
    );
    // Without a brief, the header still renders the fallback recap.
    expect(screen.getByTestId('provisioning-brief-summary')).toHaveTextContent(
      'Plan composed from concierge intent capture.'
    );
  });
});
