import { render, screen, within } from '@testing-library/react';
import {
  ApprovalChainSteps,
  ApprovalStepSummary,
  describeApprover,
} from './ApprovalChainSteps';
import type { ApprovalDecisionRecord, ApprovalStepStatus } from './approvalChainTypes';

// C3b oracle: "a two-step chain renders both steps". Plus the one rule the raw
// wire gets wrong on its own — every step is written `pending` at creation, so
// position decides whether a step is awaiting a decision or not reached yet.

const step = (overrides: Partial<ApprovalStepStatus> & { step_number: number }): ApprovalStepStatus => ({
  step_name: `Step ${overrides.step_number}`,
  approvers: ['*'],
  status: 'pending',
  required_approvals: 1,
  current_approvals: 0,
  ...overrides,
});

const states = () =>
  Array.from(document.querySelectorAll('[data-step-state]')).map((node) =>
    node.getAttribute('data-step-state')
  );

describe('ApprovalChainSteps', () => {
  it('renders BOTH steps of a two-step chain, with the second one current', () => {
    render(
      <ApprovalChainSteps
        currentStep={1}
        requestStatus="pending"
        stepStatuses={[
          step({ step_number: 0, step_name: 'SRE review', status: 'approved', current_approvals: 1 }),
          step({
            step_number: 1,
            step_name: 'Security sign-off',
            required_approvals: 2,
            current_approvals: 1,
            approvers: [{ type: 'permission', value: 'ai.autonomy.approve' }],
          }),
        ]}
      />
    );

    const list = screen.getByRole('list', { name: 'Approval chain steps' });
    expect(within(list).getAllByRole('listitem')).toHaveLength(2);
    expect(screen.getByText('Step 1: SRE review')).toBeInTheDocument();
    expect(screen.getByText('Step 2: Security sign-off')).toBeInTheDocument();
    expect(states()).toEqual(['approved', 'current']);
    expect(screen.getByText('1 of 2 approvals')).toBeInTheDocument();
    expect(screen.getByText('Approvers: anyone with ai.autonomy.approve')).toBeInTheDocument();
    expect(screen.getByText('Step 2 of 2 is awaiting a decision.')).toBeInTheDocument();
    expect(document.querySelector('[aria-current="step"]')?.getAttribute('data-step')).toBe('1');
  });

  it('calls a later step "not reached", never "pending", although the wire says pending', () => {
    render(
      <ApprovalChainSteps
        currentStep={0}
        requestStatus="pending"
        stepStatuses={[step({ step_number: 0 }), step({ step_number: 1 }), step({ step_number: 2 })]}
      />
    );

    expect(states()).toEqual(['current', 'not_reached', 'not_reached']);
    expect(screen.getAllByText('not reached')).toHaveLength(2);
    expect(screen.queryByText('pending')).not.toBeInTheDocument();
  });

  it('calls an undecided step "not decided" once the request itself is over', () => {
    render(
      <ApprovalChainSteps
        currentStep={1}
        requestStatus="expired"
        stepStatuses={[step({ step_number: 0, status: 'approved' }), step({ step_number: 1 })]}
      />
    );

    expect(states()).toEqual(['approved', 'undecided']);
    expect(screen.getByText('2-step chain. The request is expired.')).toBeInTheDocument();
    expect(document.querySelector('[aria-current="step"]')).toBeNull();
  });

  it('lists each decision under its own step', () => {
    const decisions: ApprovalDecisionRecord[] = [
      { id: 'd1', approver_id: 'u-1', step_number: 0, decision: 'approved', comments: 'looks fine', created_at: '2026-09-10T00:00:00Z' },
      { id: 'd2', approver_id: 'u-2', step_number: 1, decision: 'rejected', comments: null, created_at: '2026-09-10T01:00:00Z' },
    ];
    render(
      <ApprovalChainSteps
        currentStep={1}
        requestStatus="rejected"
        decisions={decisions}
        stepStatuses={[step({ step_number: 0, status: 'approved' }), step({ step_number: 1, status: 'rejected' })]}
      />
    );

    const first = screen.getByRole('list', { name: 'Decisions on step 1' });
    expect(within(first).getByText('approved')).toBeInTheDocument();
    expect(within(first).getByText(/looks fine/)).toBeInTheDocument();

    const second = screen.getByRole('list', { name: 'Decisions on step 2' });
    expect(within(second).getByText('rejected')).toBeInTheDocument();
    expect(within(second).queryByText(/looks fine/)).toBeNull();
  });

  it("renders an unknown step status with the server's own word", () => {
    render(
      <ApprovalChainSteps
        currentStep={0}
        requestStatus="pending"
        stepStatuses={[step({ step_number: 0, status: 'escalated' })]}
      />
    );

    expect(states()).toEqual(['unknown']);
    expect(screen.getByText('escalated')).toBeInTheDocument();
  });

  it('reads a delegated CURRENT step as still awaiting a decision, consistently (C3b1 review F6)', () => {
    render(
      <ApprovalChainSteps
        currentStep={1}
        requestStatus="pending"
        stepStatuses={[step({ step_number: 0, status: 'approved' }), step({ step_number: 1, status: 'delegated' })]}
      />
    );

    expect(states()).toEqual(['approved', 'delegated_current']);
    expect(screen.getByText('delegated — awaiting decision')).toBeInTheDocument();
    expect(document.querySelector('[aria-current="step"]')?.getAttribute('data-step')).toBe('1');
    expect(screen.getByText('Step 2 of 2 is awaiting a decision.')).toBeInTheDocument();
  });

  it('reads a delegated step on a request that is over as plainly delegated, not current', () => {
    render(
      <ApprovalChainSteps
        currentStep={0}
        requestStatus="expired"
        stepStatuses={[step({ step_number: 0, status: 'delegated' })]}
      />
    );

    expect(states()).toEqual(['delegated']);
    expect(document.querySelector('[aria-current="step"]')).toBeNull();
  });

  it('says so when a request reported no steps, instead of inventing one', () => {
    render(<ApprovalChainSteps currentStep={0} requestStatus="pending" stepStatuses={[]} />);

    expect(document.querySelector('[data-approval-chain="empty"]')).not.toBeNull();
    expect(screen.queryByRole('list', { name: 'Approval chain steps' })).toBeNull();
  });
});

describe('describeApprover', () => {
  it.each([
    ['*', 'any active user'],
    ['0199aaaa-bbbb-7ccc-8ddd-eeeeffff0000', 'user 0199aaaa…'],
    [{ type: 'permission', value: 'ai.autonomy.approve' }, 'anyone with ai.autonomy.approve'],
    [{ type: 'role', value: 'operator' }, 'role operator'],
    [{ type: 'user', value: '0199aaaa-bbbb-7ccc-8ddd-eeeeffff0000' }, 'user 0199aaaa…'],
  ] as const)('%p reads as %p', (spec, expected) => {
    expect(describeApprover(spec)).toBe(expected);
  });
});

describe('ApprovalStepSummary', () => {
  it('shows the position of a pending multi-step request', () => {
    render(<ApprovalStepSummary currentStep={1} totalSteps={3} status="pending" />);
    expect(screen.getByText('Step 2 of 3')).toBeInTheDocument();
  });

  it('shows the chain length, not a position, once the request is decided', () => {
    render(<ApprovalStepSummary currentStep={2} totalSteps={3} status="approved" />);
    expect(screen.getByText('3-step chain')).toBeInTheDocument();
  });

  it.each([
    ['a single-step request', 0, 1],
    ['a list row with no total', 0, null],
  ] as const)('renders nothing for %s', (_label, currentStep, totalSteps) => {
    const { container } = render(
      <ApprovalStepSummary currentStep={currentStep} totalSteps={totalSteps} status="pending" />
    );
    expect(container).toBeEmptyDOMElement();
  });
});
