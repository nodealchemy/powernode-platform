import { render, screen, fireEvent } from '@testing-library/react';
import { ExecutionPill } from './ExecutionPill';

describe('ExecutionPill', () => {
  it('renders progress text with completed/total counts', () => {
    render(
      <ExecutionPill
        missionId="m-1"
        totalSteps={5}
        completedSteps={2}
        onClick={jest.fn()}
      />
    );
    expect(screen.getByText(/Provisioning… 2 of 5 steps/i)).toBeInTheDocument();
  });

  it('exposes the mission id via data attribute', () => {
    render(
      <ExecutionPill
        missionId="mission-abc"
        totalSteps={3}
        completedSteps={0}
        onClick={jest.fn()}
      />
    );
    const pill = screen.getByTestId('execution-pill');
    expect(pill).toHaveAttribute('data-mission-id', 'mission-abc');
  });

  it('clamps completedSteps to totalSteps', () => {
    render(
      <ExecutionPill
        missionId="m-1"
        totalSteps={3}
        completedSteps={99}
        onClick={jest.fn()}
      />
    );
    expect(screen.getByText(/3 of 3 steps/)).toBeInTheDocument();
  });

  it('calls onClick when the pill is clicked', () => {
    const onClick = jest.fn();
    render(
      <ExecutionPill
        missionId="m-1"
        totalSteps={3}
        completedSteps={1}
        onClick={onClick}
      />
    );
    fireEvent.click(screen.getByLabelText('Open provisioning plan'));
    expect(onClick).toHaveBeenCalledTimes(1);
  });

  it('renders close button only when onClose is provided', () => {
    const { rerender } = render(
      <ExecutionPill
        missionId="m-1"
        totalSteps={1}
        completedSteps={0}
        onClick={jest.fn()}
      />
    );
    expect(screen.queryByLabelText('Dismiss')).not.toBeInTheDocument();

    const onClose = jest.fn();
    rerender(
      <ExecutionPill
        missionId="m-1"
        totalSteps={1}
        completedSteps={0}
        onClick={jest.fn()}
        onClose={onClose}
      />
    );
    expect(screen.getByLabelText('Dismiss')).toBeInTheDocument();
  });

  it('onClose click does not trigger onClick', () => {
    const onClick = jest.fn();
    const onClose = jest.fn();
    render(
      <ExecutionPill
        missionId="m-1"
        totalSteps={1}
        completedSteps={0}
        onClick={onClick}
        onClose={onClose}
      />
    );
    fireEvent.click(screen.getByLabelText('Dismiss'));
    expect(onClose).toHaveBeenCalledTimes(1);
    expect(onClick).not.toHaveBeenCalled();
  });

  it('uses z-40 so it sits above content but below modals (z-50)', () => {
    render(
      <ExecutionPill
        missionId="m-1"
        totalSteps={1}
        completedSteps={0}
        onClick={jest.fn()}
      />
    );
    const pill = screen.getByTestId('execution-pill');
    expect(pill.className).toMatch(/z-40/);
  });
});
