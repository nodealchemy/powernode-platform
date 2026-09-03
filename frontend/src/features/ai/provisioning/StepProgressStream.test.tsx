import { render, screen, act } from '@testing-library/react';
import { StepProgressStream } from './StepProgressStream';
import type { PlanStep } from './StepProgressStream';

interface SubscribeOptions {
  channel: string;
  params?: Record<string, unknown>;
  onMessage?: (data: unknown) => void;
  onError?: (err: string) => void;
}

const mockSubscribe = jest.fn<() => void, [SubscribeOptions]>(() => jest.fn());

jest.mock('@/shared/hooks/useWebSocket', () => ({
  useWebSocket: () => ({
    isConnected: true,
    error: null,
    lastConnected: new Date(),
    subscribe: mockSubscribe,
    sendMessage: jest.fn(),
  }),
}));

const STEPS: PlanStep[] = [
  { id: 'step-1', label: 'Provision VPC' },
  { id: 'step-2', label: 'Create cluster' },
  { id: 'step-3', label: 'Deploy app' },
];

const getOnMessage = (): ((data: unknown) => void) => {
  const call = mockSubscribe.mock.calls[mockSubscribe.mock.calls.length - 1];
  if (!call || !call[0].onMessage) {
    throw new Error('onMessage not registered');
  }
  return call[0].onMessage!;
};

const emit = (event: string, payload: Record<string, unknown>) => {
  const onMessage = getOnMessage();
  act(() => {
    onMessage({ event, payload });
  });
};

beforeEach(() => {
  mockSubscribe.mockClear();
});

describe('StepProgressStream', () => {
  it('subscribes to MissionChannel with mission_id', () => {
    render(<StepProgressStream missionId="mission-1" steps={STEPS} />);
    expect(mockSubscribe).toHaveBeenCalledTimes(1);
    const sub = mockSubscribe.mock.calls[0][0];
    expect(sub.channel).toBe('MissionChannel');
    expect(sub.params).toEqual({ mission_id: 'mission-1' });
  });

  it('renders all steps as pending initially', () => {
    render(<StepProgressStream missionId="mission-1" steps={STEPS} />);
    expect(screen.getByText('Provision VPC')).toBeInTheDocument();
    expect(screen.getByText('Create cluster')).toBeInTheDocument();
    expect(screen.getByText('Deploy app')).toBeInTheDocument();

    expect(screen.getByTestId('step-step-1')).toHaveAttribute('data-status', 'pending');
    expect(screen.getByText('0 of 3 steps')).toBeInTheDocument();
  });

  it('updates step status from provisioning_step_changed events', () => {
    render(<StepProgressStream missionId="mission-1" steps={STEPS} />);

    emit('provisioning_step_changed', {
      mission_id: 'mission-1',
      step_id: 'step-1',
      status: 'running',
    });
    expect(screen.getByTestId('step-step-1')).toHaveAttribute('data-status', 'running');

    emit('provisioning_step_changed', {
      mission_id: 'mission-1',
      step_id: 'step-1',
      status: 'completed',
    });
    expect(screen.getByTestId('step-step-1')).toHaveAttribute('data-status', 'completed');
    expect(screen.getByText('1 of 3 steps')).toBeInTheDocument();
  });

  it('ignores events for a different mission_id', () => {
    render(<StepProgressStream missionId="mission-1" steps={STEPS} />);
    emit('provisioning_step_changed', {
      mission_id: 'mission-OTHER',
      step_id: 'step-1',
      status: 'completed',
    });
    expect(screen.getByTestId('step-step-1')).toHaveAttribute('data-status', 'pending');
  });

  it('fires onStepFailed once when a step fails', () => {
    const onStepFailed = jest.fn();
    render(
      <StepProgressStream missionId="mission-1" steps={STEPS} onStepFailed={onStepFailed} />
    );

    emit('provisioning_step_changed', {
      mission_id: 'mission-1',
      step_id: 'step-2',
      status: 'failed',
      error: 'Cluster quota exceeded',
    });
    emit('provisioning_step_changed', {
      mission_id: 'mission-1',
      step_id: 'step-2',
      status: 'failed',
      error: 'Cluster quota exceeded',
    });

    expect(onStepFailed).toHaveBeenCalledTimes(1);
    expect(onStepFailed).toHaveBeenCalledWith('step-2', 'Cluster quota exceeded');
  });

  it('renders rolled_back state with warning styling and toggle for outputs', () => {
    render(<StepProgressStream missionId="mission-1" steps={STEPS} />);
    emit('provisioning_step_changed', {
      mission_id: 'mission-1',
      step_id: 'step-3',
      status: 'rolled_back',
      outputs: { reason: 'Failed dependency' },
    });
    const li = screen.getByTestId('step-step-3');
    expect(li).toHaveAttribute('data-status', 'rolled_back');
    expect(screen.getByTestId('step-toggle-step-3')).toBeInTheDocument();
  });

  it('fires onAllComplete once when every step is completed', () => {
    const onAllComplete = jest.fn();
    render(
      <StepProgressStream missionId="mission-1" steps={STEPS} onAllComplete={onAllComplete} />
    );

    for (const id of ['step-1', 'step-2', 'step-3']) {
      emit('provisioning_step_changed', {
        mission_id: 'mission-1',
        step_id: id,
        status: 'completed',
      });
    }

    expect(onAllComplete).toHaveBeenCalledTimes(1);
    expect(screen.getByText('3 of 3 steps')).toBeInTheDocument();
    expect(screen.getByText('100%')).toBeInTheDocument();
  });
  // IMP-842b56d3a5d4 — `awaiting_approval` is a real server status
  // (Ai::GoalPlanStep::STATUSES / SkillCompositionRunner::PARKED_STATUS,
  // broadcast verbatim by #park_step!). It was absent from
  // ProvisioningStepStatus, so a parked step fell through StatusIcon's
  // `default` and rendered as PENDING — the one reading that hides the fact
  // that the run is blocked on a human.
  describe('a step parked on an approval', () => {
    it('renders a distinct awaiting_approval icon, not the pending one', () => {
      render(<StepProgressStream missionId="mission-1" steps={STEPS} />);
      emit('provisioning_step_changed', {
        mission_id: 'mission-1',
        step_id: 'step-2',
        status: 'awaiting_approval',
      });

      expect(screen.getByTestId('step-icon-awaiting_approval')).toBeInTheDocument();
      expect(screen.getByTestId('step-step-2')).toHaveAttribute('data-status', 'awaiting_approval');
    });

    it('labels the icon so it is not read as pending', () => {
      render(<StepProgressStream missionId="mission-1" steps={STEPS} />);
      emit('provisioning_step_changed', {
        mission_id: 'mission-1',
        step_id: 'step-2',
        status: 'awaiting_approval',
      });

      expect(screen.getByLabelText('Awaiting approval')).toBeInTheDocument();
    });

    it('renders rollback_failed with its own icon, not the pending circle', () => {
      // REVIEW FINDING (IMP-842b56d3a5d4) — SkillCompositionRunner announces
      // `rollback_failed` (skill_composition_runner.rb:587, :599) when a
      // compensating rollback ITSELF failed. The union omitted it, so a leaked
      // un-compensated resource fell through StatusIcon's `default` and read as
      // "not started" — strictly worse than the parked case.
      render(<StepProgressStream missionId="mission-1" steps={STEPS} />);
      emit('provisioning_step_changed', {
        mission_id: 'mission-1',
        step_id: 'step-2',
        status: 'rollback_failed',
        error: 'terminate call failed',
      });

      expect(screen.getByTestId('step-icon-rollback_failed')).toBeInTheDocument();
      expect(screen.getByLabelText('Rollback failed')).toBeInTheDocument();
      expect(screen.getByTestId('step-step-2')).toHaveAttribute('data-status', 'rollback_failed');
    });

    it('renders the server-side executing status without falling back to pending', () => {
      // `executing` is the real Ai::GoalPlanStep::STATUSES in-flight value;
      // `running` is the client-side alias. A plan snapshot hands the raw
      // column through (plan_snapshot_service.rb:200), so both must render.
      render(<StepProgressStream missionId="mission-1" steps={STEPS} />);
      emit('provisioning_step_changed', {
        mission_id: 'mission-1',
        step_id: 'step-2',
        status: 'executing',
      });

      expect(screen.getByTestId('step-icon-running')).toBeInTheDocument();
      expect(screen.getByTestId('step-step-2')).toHaveAttribute('data-status', 'executing');
    });

    it('does not count a parked step toward completion', () => {
      const onAllComplete = jest.fn();
      render(
        <StepProgressStream missionId="mission-1" steps={STEPS} onAllComplete={onAllComplete} />
      );

      emit('provisioning_step_changed', { mission_id: 'mission-1', step_id: 'step-1', status: 'completed' });
      emit('provisioning_step_changed', { mission_id: 'mission-1', step_id: 'step-2', status: 'awaiting_approval' });
      emit('provisioning_step_changed', { mission_id: 'mission-1', step_id: 'step-3', status: 'completed' });

      expect(onAllComplete).not.toHaveBeenCalled();
      expect(screen.getByText('2 of 3 steps')).toBeInTheDocument();
    });
  });
});
