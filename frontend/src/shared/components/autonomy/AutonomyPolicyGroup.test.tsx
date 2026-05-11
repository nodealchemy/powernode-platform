import { render, screen, fireEvent } from '@testing-library/react';
import { AutonomyPolicyGroup } from './AutonomyPolicyGroup';
import type { AutonomyLevel } from '@/shared/types/autonomy';

describe('AutonomyPolicyGroup', () => {
  const baseProps = {
    label: 'Test Domain',
    agentName: 'Test Agent',
    actions: ['test.action_one', 'test.action_two'],
    actionLabels: { 'test.action_one': 'First action' },
    getPolicy: jest.fn((_a: string, _x: string): AutonomyLevel => 'require_approval'),
    updatePolicy: jest.fn(),
    onDirty: jest.fn(),
  };

  it('renders the label and action count', () => {
    render(<AutonomyPolicyGroup {...baseProps} />);
    expect(screen.getByText('Test Domain')).toBeInTheDocument();
    expect(screen.getByText('2 actions')).toBeInTheDocument();
  });

  it('uses actionLabels when provided, falls back to action key otherwise', () => {
    render(<AutonomyPolicyGroup {...baseProps} />);
    expect(screen.getByText('First action')).toBeInTheDocument();
    expect(screen.getByText('test.action_two')).toBeInTheDocument();
  });

  it('calls updatePolicy + onDirty on per-action change', () => {
    render(<AutonomyPolicyGroup {...baseProps} />);
    const selects = screen.getAllByRole('combobox');
    // First combobox is "Set all", remaining are per-action
    fireEvent.change(selects[1], { target: { value: 'auto_approve' } });
    expect(baseProps.updatePolicy).toHaveBeenCalledWith('Test Agent', 'test.action_one', 'auto_approve');
    expect(baseProps.onDirty).toHaveBeenCalled();
  });

  it('bulk-set applies the level to every action', () => {
    render(<AutonomyPolicyGroup {...baseProps} />);
    const setAll = screen.getAllByRole('combobox')[0];
    fireEvent.change(setAll, { target: { value: 'block' } });
    expect(baseProps.updatePolicy).toHaveBeenCalledWith('Test Agent', 'test.action_one', 'block');
    expect(baseProps.updatePolicy).toHaveBeenCalledWith('Test Agent', 'test.action_two', 'block');
  });

  it('renders Save button when onSave is provided', () => {
    const onSave = jest.fn().mockResolvedValue(undefined);
    render(<AutonomyPolicyGroup {...baseProps} onSave={onSave} isDirty={true} />);
    const button = screen.getByRole('button', { name: /Save Permissions/i });
    expect(button).not.toBeDisabled();
    fireEvent.click(button);
    expect(onSave).toHaveBeenCalled();
  });

  it('disables Save when not dirty', () => {
    const onSave = jest.fn();
    render(<AutonomyPolicyGroup {...baseProps} onSave={onSave} isDirty={false} />);
    expect(screen.getByRole('button', { name: /Save Permissions/i })).toBeDisabled();
  });
});
