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
});
