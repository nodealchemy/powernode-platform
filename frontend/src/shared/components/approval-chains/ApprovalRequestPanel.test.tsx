import { render, screen, waitFor, fireEvent, act } from '@testing-library/react';
import { ApprovalRequestPanel } from './ApprovalRequestPanel';

const mockGet = jest.fn();
const mockPost = jest.fn();
jest.mock('@/shared/services/apiClient', () => ({
  __esModule: true,
  default: {
    get: (...args: unknown[]) => mockGet(...args),
    post: (...args: unknown[]) => mockPost(...args),
  },
}));

const baseRequest = {
  id: 'req-1',
  request_id: 'req-1',
  status: 'pending',
  current_step: 0,
  total_steps: 2,
  step_statuses: [
    {
      step_number: 0, step_name: 'SRE',
      approvers: [{ type: 'permission', value: 'system.infra_tasks.control' }],
      status: 'pending', required_approvals: 1, current_approvals: 0,
    },
    {
      step_number: 1, step_name: 'Manager',
      approvers: ['*'], status: 'pending', required_approvals: 1, current_approvals: 0,
    },
  ],
  decisions: [],
  current_step_can_approve: true,
  deferred_operation: {
    id: 'op-1', action_category: 'sdwan.peer_delete',
    executor_class: 'Sdwan::Executors::DeletePeer',
    status: 'pending', params: { peer_id: 'p-1' },
    preview: { summary: 'Delete SDWAN peer 10.0.0.5', impact: 'Removes peer' },
  },
  created_at: '2026-05-10T00:00:00Z',
};

describe('ApprovalRequestPanel', () => {
  beforeEach(() => {
    mockGet.mockReset();
    mockPost.mockReset();
  });

  it('renders step progress + executor preview', async () => {
    mockGet.mockResolvedValue({ data: { data: baseRequest } });
    render(<ApprovalRequestPanel approvalRequestId="req-1" />);

    await waitFor(() => {
      expect(screen.getByText(/Step 1 of 2: SRE/i)).toBeInTheDocument();
    });
    expect(screen.getByText('Delete SDWAN peer 10.0.0.5')).toBeInTheDocument();
    expect(screen.getByText(/Removes peer/)).toBeInTheDocument();
  });

  it('approve advances to the next step on multi-step chains', async () => {
    mockGet.mockResolvedValue({ data: { data: baseRequest } });
    const advanced = {
      ...baseRequest,
      current_step: 1,
      step_statuses: [
        { ...baseRequest.step_statuses[0], status: 'approved', current_approvals: 1 },
        baseRequest.step_statuses[1],
      ],
      decisions: [{ id: 'd1', approver_id: 'u1', step_number: 0, decision: 'approved', created_at: 'now' }],
    };
    mockPost.mockResolvedValue({ data: { data: advanced } });

    const onResolved = jest.fn();
    render(<ApprovalRequestPanel approvalRequestId="req-1" onResolved={onResolved} />);
    await waitFor(() => screen.getByText(/Step 1 of 2/));

    fireEvent.click(screen.getByRole('button', { name: /Approve/i }));
    await waitFor(() => {
      expect(screen.getByText(/Step 2 of 2: Manager/i)).toBeInTheDocument();
    });
    expect(onResolved).not.toHaveBeenCalled();  // chain not yet complete
  });

  it('disables buttons + shows guidance when user cannot approve at current step', async () => {
    mockGet.mockResolvedValue({
      data: { data: { ...baseRequest, current_step_can_approve: false } },
    });
    render(<ApprovalRequestPanel approvalRequestId="req-1" />);
    await waitFor(() => {
      expect(screen.getByText(/don't have permission to approve/i)).toBeInTheDocument();
    });
    expect(screen.queryByRole('button', { name: /Approve/i })).not.toBeInTheDocument();
  });

  it('calls onResolved when chain completes', async () => {
    mockGet.mockResolvedValue({ data: { data: baseRequest } });
    mockPost.mockResolvedValue({
      data: { data: { ...baseRequest, status: 'approved' } },
    });

    const onResolved = jest.fn();
    render(<ApprovalRequestPanel approvalRequestId="req-1" onResolved={onResolved} />);
    await waitFor(() => screen.getByRole('button', { name: /Approve/i }));

    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: /Approve/i }));
    });
    expect(onResolved).toHaveBeenCalled();
  });

  it('renders terminal status when request is already complete', async () => {
    mockGet.mockResolvedValue({
      data: { data: { ...baseRequest, status: 'approved' } },
    });
    render(<ApprovalRequestPanel approvalRequestId="req-1" />);
    await waitFor(() => {
      expect(screen.getByText(/Approval complete/i)).toBeInTheDocument();
    });
  });
});
