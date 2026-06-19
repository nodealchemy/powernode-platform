import { screen } from '@testing-library/react';
import { ReactElement } from 'react';
import { renderWithProviders, mockAuthenticatedState } from '@/shared/utils/test-utils';
import { RalphLiveExecutionPanel } from './RalphLiveExecutionPanel';
import type { RalphIteration } from '@/shared/services/ai/types/ralph-types';

// RalphLiveExecutionPanel is presentational, but Badge/Card pull in shared UI
// primitives, so render through the standard provider wrapper for parity with
// the rest of the suite.
const render = (ui: ReactElement) =>
  renderWithProviders(ui, { preloadedState: mockAuthenticatedState });

const buildIteration = (overrides: Partial<RalphIteration> = {}): RalphIteration => ({
  id: 'iter-1',
  ralph_loop_id: 'loop-1',
  iteration_number: 11,
  status: 'completed',
  created_at: '2026-06-19T07:37:40Z',
  ...overrides,
});

describe('RalphLiveExecutionPanel', () => {
  it('shows the idle/drained state when running with an empty live feed and all tasks complete', () => {
    render(
      <RalphLiveExecutionPanel
        iterations={[]}
        isRunning
        taskCount={10}
        completedTaskCount={10}
      />
    );

    // The misleading "Running / Waiting for iteration results..." must NOT appear
    // once the queue is drained.
    expect(screen.queryByText(/Waiting for iteration results/i)).not.toBeInTheDocument();
    expect(screen.queryByText('Running')).not.toBeInTheDocument();

    // Instead: an Idle badge + a drained message with the N/N count.
    expect(screen.getByText('Idle')).toBeInTheDocument();
    const idle = screen.getByTestId('ralph-live-idle');
    expect(idle.textContent).toMatch(/queue drained/i);
    expect(idle.textContent).toMatch(/10\/10/);
  });

  it('still shows the genuine pre-iteration wait when tasks remain and nothing is live', () => {
    render(
      <RalphLiveExecutionPanel
        iterations={[]}
        isRunning
        taskCount={10}
        completedTaskCount={3}
      />
    );

    // Work is queued but no iteration is mid-flight yet → legitimately "waiting".
    expect(screen.getByText(/Waiting for iteration results/i)).toBeInTheDocument();
    expect(screen.getByText('Running')).toBeInTheDocument();
    expect(screen.queryByTestId('ralph-live-idle')).not.toBeInTheDocument();
  });

  it('does not treat a brand-new loop with no tasks as drained', () => {
    render(
      <RalphLiveExecutionPanel
        iterations={[]}
        isRunning
        taskCount={0}
        completedTaskCount={0}
      />
    );

    expect(screen.queryByTestId('ralph-live-idle')).not.toBeInTheDocument();
    expect(screen.getByText(/Waiting for iteration results/i)).toBeInTheDocument();
  });

  it('renders live iterations and never shows idle while a feed is present', () => {
    render(
      <RalphLiveExecutionPanel
        iterations={[buildIteration({ task_key: 'IMP-74feec2af139' })]}
        isRunning={false}
        taskCount={10}
        completedTaskCount={10}
      />
    );

    expect(screen.getByText('#11')).toBeInTheDocument();
    expect(screen.getByText('IMP-74feec2af139')).toBeInTheDocument();
    expect(screen.queryByTestId('ralph-live-idle')).not.toBeInTheDocument();
  });

  it('renders nothing when idle is impossible (not running, no iterations)', () => {
    render(
      <RalphLiveExecutionPanel iterations={[]} isRunning={false} />
    );

    expect(screen.queryByText('Live Execution')).not.toBeInTheDocument();
  });
});
