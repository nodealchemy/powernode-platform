import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { ConfirmationModal, useConfirmation } from './ConfirmationModal';

// =============================================================================
// confirmDisabled (IMP-20b686717ec3)
//
// `loading` already disables both buttons while the action runs. confirmDisabled
// covers the state BEFORE it can start: a dialog body that collects something
// the action requires (a typed reason, an acknowledgement) and is not yet valid.
//
// The function form exists because `useConfirmation` snapshots its options into
// state, so a plain boolean captured at confirm() time can never change while
// the operator types.
// =============================================================================

describe('ConfirmationModal confirmDisabled', () => {
  const baseProps = {
    isOpen: true,
    onClose: jest.fn(),
    onConfirm: jest.fn(),
    title: 'Delete thing',
    message: 'Are you sure?',
    confirmLabel: 'Delete thing',
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('leaves the confirm button enabled by default', () => {
    render(<ConfirmationModal {...baseProps} />);

    expect(screen.getByRole('button', { name: 'Delete thing' })).not.toBeDisabled();
  });

  it('disables the confirm button when confirmDisabled is true', () => {
    render(<ConfirmationModal {...baseProps} confirmDisabled />);

    expect(screen.getByRole('button', { name: 'Delete thing' })).toBeDisabled();
  });

  it('leaves Cancel enabled while the confirm button is disabled', () => {
    render(<ConfirmationModal {...baseProps} confirmDisabled />);

    expect(screen.getByRole('button', { name: 'Cancel' })).not.toBeDisabled();
  });

  it('does not run onConfirm while confirmDisabled', () => {
    render(<ConfirmationModal {...baseProps} confirmDisabled />);

    fireEvent.click(screen.getByRole('button', { name: 'Delete thing' }));

    expect(baseProps.onConfirm).not.toHaveBeenCalled();
  });

  it('keeps the confirm button disabled while loading even if confirmDisabled is false', () => {
    // The OR this prop introduced must not let a predicate that has gone valid
    // re-enable the button mid-action.
    render(<ConfirmationModal {...baseProps} loading confirmDisabled={false} />);

    expect(screen.getByRole('button', { name: 'Processing...' })).toBeDisabled();
  });

  it('runs onConfirm once confirmDisabled is false', () => {
    render(<ConfirmationModal {...baseProps} confirmDisabled={false} />);

    fireEvent.click(screen.getByRole('button', { name: 'Delete thing' }));

    expect(baseProps.onConfirm).toHaveBeenCalledTimes(1);
  });
});

describe('useConfirmation confirmDisabled', () => {
  // A body that reports its value upward on every keystroke — the shape the
  // reason-carrying wrappers use, and the reason the predicate must be a
  // function rather than a value captured at confirm() time.
  const Harness: React.FC<{ onConfirm: () => void }> = ({ onConfirm }) => {
    const { confirm, ConfirmationDialog } = useConfirmation();
    const [reason, setReason] = React.useState('');
    const reasonRef = React.useRef('');

    const open = () => {
      reasonRef.current = '';
      setReason('');
      confirm({
        title: 'Clean up',
        message: (
          <input
            aria-label="reason"
            onChange={(e) => {
              reasonRef.current = e.target.value;
              setReason(e.target.value);
            }}
          />
        ),
        confirmLabel: 'Clean up now',
        confirmDisabled: () => reasonRef.current.trim() === '',
        onConfirm,
      });
    };

    return (
      <>
        <button onClick={open}>Open</button>
        <span data-testid="mirror">{reason}</span>
        {ConfirmationDialog}
      </>
    );
  };

  it('starts disabled and enables as the body becomes valid', async () => {
    const onConfirm = jest.fn();
    render(<Harness onConfirm={onConfirm} />);

    fireEvent.click(screen.getByRole('button', { name: 'Open' }));

    const confirmButton = await screen.findByRole('button', { name: 'Clean up now' });
    expect(confirmButton).toBeDisabled();

    fireEvent.change(screen.getByLabelText('reason'), { target: { value: 'disk full' } });

    await waitFor(() => expect(confirmButton).not.toBeDisabled());

    fireEvent.click(confirmButton);
    await waitFor(() => expect(onConfirm).toHaveBeenCalledTimes(1));
  });

  it('re-disables when the body goes back to invalid', async () => {
    render(<Harness onConfirm={jest.fn()} />);

    fireEvent.click(screen.getByRole('button', { name: 'Open' }));
    const confirmButton = await screen.findByRole('button', { name: 'Clean up now' });

    fireEvent.change(screen.getByLabelText('reason'), { target: { value: 'x' } });
    await waitFor(() => expect(confirmButton).not.toBeDisabled());

    fireEvent.change(screen.getByLabelText('reason'), { target: { value: '   ' } });
    await waitFor(() => expect(confirmButton).toBeDisabled());
  });

  it('leaves the confirm button enabled when no predicate is given', async () => {
    const Plain: React.FC = () => {
      const { confirm, ConfirmationDialog } = useConfirmation();
      return (
        <>
          <button
            onClick={() =>
              confirm({
                title: 'Delete',
                message: 'sure?',
                confirmLabel: 'Delete it',
                onConfirm: jest.fn(),
              })
            }
          >
            Open
          </button>
          {ConfirmationDialog}
        </>
      );
    };
    render(<Plain />);

    fireEvent.click(screen.getByRole('button', { name: 'Open' }));

    expect(await screen.findByRole('button', { name: 'Delete it' })).not.toBeDisabled();
  });
});
