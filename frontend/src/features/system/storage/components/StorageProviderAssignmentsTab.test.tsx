import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { StorageProviderAssignmentsTab } from './StorageProviderAssignmentsTab';
import type { StorageAssignment } from '../types';

// =============================================================================
// Mocks
// =============================================================================

const mockDispatch = jest.fn();
jest.mock('react-redux', () => ({ useDispatch: () => mockDispatch }));

jest.mock('@/shared/services/slices/uiSlice', () => ({
  addNotification: (payload: unknown) => ({ type: 'ui/addNotification', payload }),
}));

let mockPermissions: string[] = [];
jest.mock('@/shared/hooks/useAuth', () => ({
  useAuth: () => ({ currentUser: { permissions: mockPermissions } }),
}));

// Collapse the two-click armed-confirm to a single immediate trigger so the
// delete path is testable here. The armed-confirm hook has its own core unit
// coverage; this tab only needs to wire its callback through.
jest.mock('@/shared/hooks/useArmedConfirm', () => ({
  useArmedConfirm: (cb: () => void) => ({ armed: false, trigger: cb }),
}));

const mockList = jest.fn();
const mockRotate = jest.fn();
const mockDestroy = jest.fn();
jest.mock('../services/storageAssignmentsApi', () => ({
  storageAssignmentsApi: {
    list: (...a: unknown[]) => mockList(...a),
    rotateCredential: (...a: unknown[]) => mockRotate(...a),
    destroy: (...a: unknown[]) => mockDestroy(...a),
  },
}));

// Stub the child dialog so we can assert it opens and fires its callbacks.
jest.mock('./BulkAssignDialog', () => ({
  BulkAssignDialog: ({ onClose, onCreated }: { onClose: () => void; onCreated: () => void }) => (
    <div data-testid="bulk-dialog">
      <button onClick={onClose}>close-bulk</button>
      <button onClick={onCreated}>created-bulk</button>
    </div>
  ),
}));

const ASSIGNMENT: StorageAssignment = {
  id: 'sa-1',
  file_storage_id: 'fs-1',
  node_instance_id: 'instance-abcdef12',
  mount_path: '/mnt/data',
  status: 'mounted',
  encryption_mode: 'luks',
  enabled: true,
  auto_mount: true,
  read_only: false,
  last_status_at: '2026-01-01T00:00:00Z',
};

describe('StorageProviderAssignmentsTab', () => {
  beforeEach(() => {
    mockDispatch.mockReset();
    mockList.mockReset();
    mockRotate.mockReset();
    mockDestroy.mockReset();
    mockPermissions = [];
  });

  it('shows a loading state then the empty state when there are no assignments', async () => {
    mockList.mockResolvedValue({ assignments: [] });
    render(<StorageProviderAssignmentsTab storageId="fs-1" />);
    expect(screen.getByText('Loading…')).toBeInTheDocument();
    await waitFor(() => expect(screen.getByText(/No assignments yet/)).toBeInTheDocument());
    expect(mockList).toHaveBeenCalledWith({ file_storage_id: 'fs-1' });
  });

  it('renders a row per assignment with status, mount path, encryption and truncated instance id', async () => {
    mockList.mockResolvedValue({ assignments: [ASSIGNMENT] });
    render(<StorageProviderAssignmentsTab storageId="fs-1" />);
    await waitFor(() => expect(screen.getByText('/mnt/data')).toBeInTheDocument());
    expect(screen.getByText('mounted')).toBeInTheDocument();
    expect(screen.getByText('luks')).toBeInTheDocument();
    // node_instance_id is truncated to the first 8 chars
    expect(screen.getByText('instance')).toBeInTheDocument();
  });

  it('hides the Assign button without create permission', async () => {
    mockList.mockResolvedValue({ assignments: [] });
    render(<StorageProviderAssignmentsTab storageId="fs-1" />);
    await waitFor(() => expect(screen.getByText(/No assignments yet/)).toBeInTheDocument());
    expect(
      screen.queryByRole('button', { name: /assign to instances/i }),
    ).not.toBeInTheDocument();
  });

  it('shows the Assign button with create permission and opens the bulk dialog', async () => {
    mockList.mockResolvedValue({ assignments: [] });
    mockPermissions = ['system.storage.assignments.create'];
    render(<StorageProviderAssignmentsTab storageId="fs-1" />);
    await waitFor(() =>
      expect(screen.getByRole('button', { name: /assign to instances/i })).toBeInTheDocument(),
    );
    fireEvent.click(screen.getByRole('button', { name: /assign to instances/i }));
    expect(screen.getByTestId('bulk-dialog')).toBeInTheDocument();
  });

  it('reloads the list after the bulk dialog reports created', async () => {
    mockList.mockResolvedValue({ assignments: [] });
    mockPermissions = ['system.storage.assignments.create'];
    render(<StorageProviderAssignmentsTab storageId="fs-1" />);
    await waitFor(() =>
      expect(screen.getByRole('button', { name: /assign to instances/i })).toBeInTheDocument(),
    );
    expect(mockList).toHaveBeenCalledTimes(1);
    fireEvent.click(screen.getByRole('button', { name: /assign to instances/i }));
    fireEvent.click(screen.getByText('created-bulk'));
    await waitFor(() => expect(mockList).toHaveBeenCalledTimes(2));
  });

  it('dispatches an error notification when loading fails', async () => {
    mockList.mockRejectedValue(new Error('nope'));
    render(<StorageProviderAssignmentsTab storageId="fs-1" />);
    await waitFor(() =>
      expect(mockDispatch).toHaveBeenCalledWith({
        type: 'ui/addNotification',
        payload: { type: 'error', message: 'Failed to load assignments' },
      }),
    );
  });

  it('rotates a credential when Rotate is clicked (with permission)', async () => {
    mockList.mockResolvedValue({ assignments: [ASSIGNMENT] });
    mockRotate.mockResolvedValue({});
    mockPermissions = ['system.storage.assignments.rotate_credential'];
    render(<StorageProviderAssignmentsTab storageId="fs-1" />);
    await waitFor(() => expect(screen.getByText('Rotate')).toBeInTheDocument());
    fireEvent.click(screen.getByText('Rotate'));
    await waitFor(() => expect(mockRotate).toHaveBeenCalledWith('sa-1'));
    expect(mockDispatch).toHaveBeenCalledWith({
      type: 'ui/addNotification',
      payload: { type: 'success', message: 'Credential rotated' },
    });
  });

  it('deletes an assignment when Delete is triggered (with permission)', async () => {
    mockList.mockResolvedValue({ assignments: [ASSIGNMENT] });
    mockDestroy.mockResolvedValue(undefined);
    mockPermissions = ['system.storage.assignments.delete'];
    render(<StorageProviderAssignmentsTab storageId="fs-1" />);
    await waitFor(() => expect(screen.getByText('Delete')).toBeInTheDocument());
    fireEvent.click(screen.getByText('Delete'));
    await waitFor(() => expect(mockDestroy).toHaveBeenCalledWith('sa-1'));
    expect(mockDispatch).toHaveBeenCalledWith({
      type: 'ui/addNotification',
      payload: { type: 'success', message: 'Assignment deleted' },
    });
  });

  it('hides Rotate and Delete actions without their permissions', async () => {
    mockList.mockResolvedValue({ assignments: [ASSIGNMENT] });
    render(<StorageProviderAssignmentsTab storageId="fs-1" />);
    await waitFor(() => expect(screen.getByText('/mnt/data')).toBeInTheDocument());
    expect(screen.queryByText('Rotate')).not.toBeInTheDocument();
    expect(screen.queryByText('Delete')).not.toBeInTheDocument();
  });

  it('shows an em dash when last_status_at is absent', async () => {
    mockList.mockResolvedValue({ assignments: [{ ...ASSIGNMENT, last_status_at: null }] });
    render(<StorageProviderAssignmentsTab storageId="fs-1" />);
    await waitFor(() => expect(screen.getByText('/mnt/data')).toBeInTheDocument());
    expect(screen.getByText('—')).toBeInTheDocument();
  });
});
