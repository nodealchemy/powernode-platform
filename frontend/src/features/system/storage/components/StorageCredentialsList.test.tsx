import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { StorageCredentialsList } from './StorageCredentialsList';
import type { StorageCredential } from '../types';

// =============================================================================
// Mocks
// =============================================================================

const mockDispatch = jest.fn();
jest.mock('react-redux', () => ({
  useDispatch: () => mockDispatch,
}));

const mockCredentialsList = jest.fn();
const mockCredentialsRotate = jest.fn();

jest.mock('../services/storageCredentialsApi', () => ({
  storageCredentialsApi: {
    list: (...args: unknown[]) => mockCredentialsList(...args),
    get: jest.fn(),
    rotate: (...args: unknown[]) => mockCredentialsRotate(...args),
  },
}));

// =============================================================================
// Fixtures
// =============================================================================

const ACTIVE_CRED: StorageCredential = {
  id: 'cred-1',
  storage_assignment_id: 'sa-1',
  node_instance_id: 'inst-1',
  kind: 'smb_password',
  status: 'active',
  expires_at: '2026-10-01T00:00:00Z',
  last_rotated_at: '2026-07-01T00:00:00Z',
  needs_rotation: false,
  metadata: {},
};

const STALE_CRED: StorageCredential = {
  ...ACTIVE_CRED,
  id: 'cred-0',
  status: 'retired',
  needs_rotation: true,
};

beforeEach(() => {
  jest.clearAllMocks();
  mockCredentialsList.mockResolvedValue({ credentials: [ACTIVE_CRED, STALE_CRED] });
});

// =============================================================================
// Tests
// =============================================================================

describe('StorageCredentialsList', () => {
  it('fetches credentials for the assignment and renders kind/status rows', async () => {
    render(
      <StorageCredentialsList assignmentId="sa-1" activeCredentialId="cred-1" canRotate />
    );

    expect(await screen.findAllByText('smb_password')).toHaveLength(2);
    expect(screen.getByText('active')).toBeInTheDocument();
    expect(screen.getByText('retired')).toBeInTheDocument();
    expect(mockCredentialsList).toHaveBeenCalledWith({
      storage_assignment_id: 'sa-1',
      per_page: 100,
    });
  });

  it('marks the assignment-active credential', async () => {
    render(
      <StorageCredentialsList assignmentId="sa-1" activeCredentialId="cred-1" canRotate />
    );

    await screen.findAllByText('smb_password');
    expect(screen.getByText('in use')).toBeInTheDocument();
  });

  it('flags credentials needing rotation', async () => {
    render(
      <StorageCredentialsList assignmentId="sa-1" activeCredentialId="cred-1" canRotate />
    );

    await screen.findAllByText('smb_password');
    expect(screen.getByText('needs rotation')).toBeInTheDocument();
  });

  it('shows an empty state when the assignment has no credentials', async () => {
    mockCredentialsList.mockResolvedValue({ credentials: [] });

    render(<StorageCredentialsList assignmentId="sa-1" canRotate />);

    expect(await screen.findByText(/No credentials/i)).toBeInTheDocument();
  });

  it('rotates a credential via arm-then-confirm and refreshes the list', async () => {
    mockCredentialsRotate.mockResolvedValue({ ...ACTIVE_CRED, id: 'cred-9' });

    render(
      <StorageCredentialsList assignmentId="sa-1" activeCredentialId="cred-1" canRotate />
    );
    await screen.findAllByText('smb_password');

    const rotateButtons = screen.getAllByRole('button', { name: /Rotate/i });
    // First click arms, second click fires.
    fireEvent.click(rotateButtons[0]);
    fireEvent.click(screen.getByRole('button', { name: /confirm/i }));

    await waitFor(() => expect(mockCredentialsRotate).toHaveBeenCalledWith('cred-1'));
    await waitFor(() => expect(mockCredentialsList).toHaveBeenCalledTimes(2));
    expect(mockDispatch).toHaveBeenCalled();
  });

  it('hides rotate controls without the rotate permission', async () => {
    render(<StorageCredentialsList assignmentId="sa-1" canRotate={false} />);

    await screen.findAllByText('smb_password');
    expect(screen.queryByRole('button', { name: /Rotate/i })).not.toBeInTheDocument();
  });
});
