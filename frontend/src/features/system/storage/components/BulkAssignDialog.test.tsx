import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { BulkAssignDialog } from './BulkAssignDialog';

// =============================================================================
// Mocks
//
// The dialog dispatches Redux notifications and calls storageAssignmentsApi.
// We mock react-redux's useDispatch to capture dispatched actions, stub the
// uiSlice action-creator to a tagged plain object, and stub the API surface.
// =============================================================================

const mockDispatch = jest.fn();
jest.mock('react-redux', () => ({ useDispatch: () => mockDispatch }));

jest.mock('@/shared/services/slices/uiSlice', () => ({
  addNotification: (payload: unknown) => ({ type: 'ui/addNotification', payload }),
}));

const mockBulkCreate = jest.fn();
jest.mock('../services/storageAssignmentsApi', () => ({
  storageAssignmentsApi: {
    bulkCreate: (...args: unknown[]) => mockBulkCreate(...args),
  },
}));

function renderDialog(props: Partial<React.ComponentProps<typeof BulkAssignDialog>> = {}) {
  const onClose = jest.fn();
  const onCreated = jest.fn();
  render(
    <BulkAssignDialog storageId="fs-1" onClose={onClose} onCreated={onCreated} {...props} />,
  );
  return { onClose, onCreated };
}

const TEXTAREA = /0190a3b4/; // placeholder fragment for the UUID textarea

describe('BulkAssignDialog', () => {
  beforeEach(() => {
    mockDispatch.mockReset();
    mockBulkCreate.mockReset();
  });

  it('renders with the default mount path and zero parsed instances', () => {
    renderDialog();
    expect(screen.getByText('Assign to instances')).toBeInTheDocument();
    expect(screen.getByText('0 instance(s) parsed')).toBeInTheDocument();
    expect(screen.getByDisplayValue('/mnt/data')).toBeInTheDocument();
  });

  it('parses instance UUIDs split on whitespace, commas, and newlines', () => {
    renderDialog();
    fireEvent.change(screen.getByPlaceholderText(TEXTAREA), {
      target: { value: 'a-1\nb-2, c-3   d-4' },
    });
    expect(screen.getByText('4 instance(s) parsed')).toBeInTheDocument();
  });

  it('disables the submit button when no instances are parsed', () => {
    renderDialog();
    expect(screen.getByRole('button', { name: /assign to 0/i })).toBeDisabled();
  });

  it('shows the provider type when provided', () => {
    renderDialog({ providerType: 'nfs' });
    expect(screen.getByText('nfs')).toBeInTheDocument();
  });

  it('submits via bulkCreate with index-substituted mount paths and notifies success', async () => {
    mockBulkCreate.mockResolvedValue({ created: [{}, {}], errors: [] });
    const { onCreated } = renderDialog();

    fireEvent.change(screen.getByPlaceholderText(TEXTAREA), { target: { value: 'a-1\nb-2' } });
    fireEvent.change(screen.getByDisplayValue('/mnt/data'), {
      target: { value: '/mnt/vol-{index}' },
    });

    fireEvent.click(screen.getByRole('button', { name: /assign to 2/i }));

    await waitFor(() => expect(mockBulkCreate).toHaveBeenCalledTimes(1));
    expect(mockBulkCreate).toHaveBeenCalledWith([
      {
        file_storage_id: 'fs-1',
        node_instance_id: 'a-1',
        mount_path: '/mnt/vol-1',
        encryption_mode: 'inherit',
        sdwan_network_id: undefined,
        sdwan_virtual_ip_id: undefined,
      },
      {
        file_storage_id: 'fs-1',
        node_instance_id: 'b-2',
        mount_path: '/mnt/vol-2',
        encryption_mode: 'inherit',
        sdwan_network_id: undefined,
        sdwan_virtual_ip_id: undefined,
      },
    ]);
    await waitFor(() =>
      expect(mockDispatch).toHaveBeenCalledWith({
        type: 'ui/addNotification',
        payload: { type: 'success', message: 'Assigned to 2 instance(s)' },
      }),
    );
    expect(onCreated).toHaveBeenCalledTimes(1);
  });

  it('includes the selected encryption mode in the payload', async () => {
    mockBulkCreate.mockResolvedValue({ created: [{}], errors: [] });
    renderDialog();
    fireEvent.change(screen.getByPlaceholderText(TEXTAREA), { target: { value: 'a-1' } });
    fireEvent.change(screen.getByRole('combobox'), { target: { value: 'luks' } });
    fireEvent.click(screen.getByRole('button', { name: /assign to 1/i }));
    await waitFor(() => expect(mockBulkCreate).toHaveBeenCalled());
    expect(mockBulkCreate.mock.calls[0][0][0].encryption_mode).toBe('luks');
  });

  it('passes optional sdwan network and vip ids when filled', async () => {
    mockBulkCreate.mockResolvedValue({ created: [{}], errors: [] });
    renderDialog();
    fireEvent.change(screen.getByPlaceholderText(TEXTAREA), { target: { value: 'a-1' } });
    const optional = screen.getAllByPlaceholderText('optional');
    fireEvent.change(optional[0], { target: { value: 'net-1' } });
    fireEvent.change(optional[1], { target: { value: 'vip-1' } });
    fireEvent.click(screen.getByRole('button', { name: /assign to 1/i }));
    await waitFor(() => expect(mockBulkCreate).toHaveBeenCalled());
    expect(mockBulkCreate.mock.calls[0][0][0]).toMatchObject({
      sdwan_network_id: 'net-1',
      sdwan_virtual_ip_id: 'vip-1',
    });
  });

  it('notifies a warning with counts when some assignments fail', async () => {
    mockBulkCreate.mockResolvedValue({ created: [{}], errors: [{ index: 1, errors: ['x'] }] });
    renderDialog();
    fireEvent.change(screen.getByPlaceholderText(TEXTAREA), { target: { value: 'a-1\nb-2' } });
    fireEvent.click(screen.getByRole('button', { name: /assign to 2/i }));
    await waitFor(() =>
      expect(mockDispatch).toHaveBeenCalledWith({
        type: 'ui/addNotification',
        payload: { type: 'warning', message: 'Created 1 of 2 (1 failed)' },
      }),
    );
  });

  it('notifies an error when bulkCreate throws', async () => {
    mockBulkCreate.mockRejectedValue(new Error('boom'));
    const { onCreated } = renderDialog();
    fireEvent.change(screen.getByPlaceholderText(TEXTAREA), { target: { value: 'a-1' } });
    fireEvent.click(screen.getByRole('button', { name: /assign to 1/i }));
    await waitFor(() =>
      expect(mockDispatch).toHaveBeenCalledWith({
        type: 'ui/addNotification',
        payload: { type: 'error', message: 'Bulk assignment failed' },
      }),
    );
    expect(onCreated).not.toHaveBeenCalled();
  });

  it('calls onClose when Cancel is clicked', () => {
    const { onClose } = renderDialog();
    fireEvent.click(screen.getByRole('button', { name: /cancel/i }));
    expect(onClose).toHaveBeenCalledTimes(1);
  });
});
