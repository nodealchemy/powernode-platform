import { render, screen, fireEvent, waitFor, within } from '@testing-library/react';
import { DelegationsManagement } from './DelegationsManagement';
import type { Delegation } from '@/features/delegations/services/delegationApi';

// Mock ConfirmationModal - auto-confirm by default
jest.mock('@/shared/components/ui/ConfirmationModal', () => ({
  useConfirmation: () => ({
    confirm: (opts: { onConfirm: () => void }) => { opts.onConfirm(); },
    ConfirmationDialog: null,
  }),
}));

// The component reads the caller's real account id, and gates itself, through
// useAuth() -- mutable per-test so the no-access-state case (fc-20 item 6) can
// render with a currentUser that lacks accounts.manage/admin.access.
const mockUseAuth = jest.fn();
jest.mock('@/shared/hooks/useAuth', () => ({
  useAuth: () => mockUseAuth(),
}));

// Mock delegation API. fc-20 review: getDelegationRequests/approveDelegationRequest/
// rejectDelegationRequest and the "outgoing/incoming" split were built against a
// `/api/v1/delegation-requests` surface that never existed server-side (no route, no
// controller, no model) -- deleted along with DelegationRequestModal, not fixed.
const mockGetDelegations = jest.fn();
const mockCreateDelegation = jest.fn();
const mockRevokeDelegation = jest.fn();
const mockActivateDelegation = jest.fn();
const mockDeactivateDelegation = jest.fn();

jest.mock('@/features/delegations/services/delegationApi', () => ({
  delegationApi: {
    getDelegations: (...args: unknown[]) => mockGetDelegations(...args),
    createDelegation: (...args: unknown[]) => mockCreateDelegation(...args),
    revokeDelegation: (...args: unknown[]) => mockRevokeDelegation(...args),
    activateDelegation: (...args: unknown[]) => mockActivateDelegation(...args),
    deactivateDelegation: (...args: unknown[]) => mockDeactivateDelegation(...args),
  },
  // Catalog labels the real catalog fetch (rolesApi.getPermissions ->
  // deriveDelegationPermissions) would derive at runtime -- no back-compat seed
  // constant to fall back on (fc-20 review item 7 removed DELEGATION_PERMISSIONS).
  deriveDelegationPermissions: () => [
    { key: 'reports.read', label: 'View Reports', description: 'View reports information' },
    { key: 'reports.manage', label: 'Manage Reports', description: 'Manage reports settings' },
  ],
}));

jest.mock('@/features/admin/roles/services/rolesApi', () => ({
  rolesApi: {
    getPermissions: () => Promise.resolve({ success: true, data: [] }),
  },
}));

// Mock child modals
jest.mock('./CreateDelegationModal', () => ({
  CreateDelegationModal: ({ onClose, onCreate }: { onClose: () => void; onCreate: (data: { delegated_user_email: string }) => void }) => (
    <div data-testid="create-delegation-modal">
      <button onClick={onClose}>Close Create Modal</button>
      <button onClick={() => onCreate({ delegated_user_email: 'new@example.com' })}>Create</button>
    </div>
  )
}));

jest.mock('./DelegationDetailsModal', () => ({
  // onRevoke/onActivate/onDeactivate now reject on failure -- fc-20 review round 2 moved
  // error DISPLAY into the real DelegationDetailsModal (pinned in its own spec), so this
  // stub just swallows the rejection the way the real component's runStatusAction does,
  // instead of leaving it unhandled here.
  DelegationDetailsModal: ({ delegation, onClose, onRevoke, onActivate, onDeactivate, onUpdate }: { delegation: { id: string; delegated_user: { email: string }; stale_permission_names?: string[] }; onClose: () => void; onRevoke: (id: string) => Promise<void>; onActivate: (id: string) => Promise<void>; onDeactivate: (id: string) => Promise<void>; onUpdate: () => void }) => (
    <div data-testid="delegation-details-modal">
      <span>Details: {delegation.delegated_user.email}</span>
      <span data-testid="details-stale">{(delegation.stale_permission_names || []).join(',')}</span>
      <button onClick={onClose}>Close Details</button>
      <button onClick={() => { onRevoke(delegation.id).catch(() => {}); }}>Revoke</button>
      <button onClick={() => { onActivate(delegation.id).catch(() => {}); }}>Activate</button>
      <button onClick={() => { onDeactivate(delegation.id).catch(() => {}); }}>Deactivate</button>
      <button onClick={onUpdate}>Signal Update</button>
    </div>
  )
}));

describe('DelegationsManagement', () => {
  const mockDelegations: Delegation[] = [
    {
      id: 'del-1',
      account: { id: 'acct-1', name: 'Acme', subdomain: 'acme' },
      delegated_user: { id: 'u-1', email: 'finance@example.com', full_name: 'Finance User' },
      delegated_by: { id: 'u-owner', email: 'owner@example.com', full_name: 'Owner User' },
      role: { id: 'r-1', name: 'Finance', description: 'Finance role' },
      status: 'active',
      // `permissions` is the RESOLVED set the API serializes (what the delegation
      // actually confers); `stale_permission_names` are stored rows the role no
      // longer grants and that therefore resolve to nothing.
      permissions: [
        { name: 'reports.read', key: 'reports.read', resource: 'reports', action: 'read', description: 'View reports' },
        { name: 'reports.manage', key: 'reports.manage', resource: 'reports', action: 'manage', description: 'Manage reports' },
      ],
      stale_permission_names: ['reports.export'],
      permission_source: 'custom',
      expires_at: '2025-12-31T00:00:00Z',
      revoked_at: null,
      revoked_by: null,
      notes: null,
      is_active: true,
      is_expired: false,
      created_at: '2025-01-01T00:00:00Z',
      updated_at: '2025-01-15T00:00:00Z',
    },
    {
      id: 'del-2',
      account: { id: 'acct-1', name: 'Acme', subdomain: 'acme' },
      delegated_user: { id: 'u-2', email: 'viewer@example.com', full_name: '' },
      delegated_by: { id: 'u-owner', email: 'owner@example.com', full_name: 'Owner User' },
      role: null,
      status: 'active',
      permissions: [ { name: 'users.read', key: 'users.read', resource: 'users', action: 'read', description: 'View users' } ],
      stale_permission_names: [],
      permission_source: 'custom',
      expires_at: null,
      revoked_at: null,
      revoked_by: null,
      notes: null,
      is_active: true,
      is_expired: false,
      created_at: '2025-01-05T00:00:00Z',
      updated_at: '2025-01-10T00:00:00Z',
    },
    {
      // Account::Delegation#active? is `status == "active" && !expired?`, so an
      // expired row's stored `status` STAYS "active" -- this is the exact case
      // fc-20 review item 2 named: bucketing on `status` alone mislabeled this
      // row as Active with a Revoke button.
      id: 'del-3',
      account: { id: 'acct-1', name: 'Acme', subdomain: 'acme' },
      delegated_user: { id: 'u-3', email: 'old@example.com', full_name: 'Old User' },
      delegated_by: { id: 'u-owner', email: 'owner@example.com', full_name: 'Owner User' },
      role: { id: 'r-1', name: 'Finance', description: 'Finance role' },
      status: 'active',
      permissions: [],
      stale_permission_names: [],
      permission_source: 'custom',
      expires_at: '2024-12-01T00:00:00Z',
      revoked_at: null,
      revoked_by: null,
      notes: null,
      is_active: false,
      is_expired: true,
      created_at: '2024-01-01T00:00:00Z',
      updated_at: '2024-12-01T00:00:00Z',
    },
    {
      // Deactivated, not expired, not revoked: `status` is genuinely "inactive".
      id: 'del-4',
      account: { id: 'acct-1', name: 'Acme', subdomain: 'acme' },
      delegated_user: { id: 'u-4', email: 'paused@example.com', full_name: 'Paused User' },
      delegated_by: { id: 'u-owner', email: 'owner@example.com', full_name: 'Owner User' },
      role: { id: 'r-1', name: 'Finance', description: 'Finance role' },
      status: 'inactive',
      permissions: [],
      stale_permission_names: [],
      permission_source: 'custom',
      expires_at: null,
      revoked_at: null,
      revoked_by: null,
      notes: null,
      is_active: false,
      is_expired: false,
      created_at: '2024-02-01T00:00:00Z',
      updated_at: '2024-02-15T00:00:00Z',
    },
    {
      id: 'del-5',
      account: { id: 'acct-1', name: 'Acme', subdomain: 'acme' },
      delegated_user: { id: 'u-5', email: 'gone@example.com', full_name: 'Gone User' },
      delegated_by: { id: 'u-owner', email: 'owner@example.com', full_name: 'Owner User' },
      role: null,
      status: 'revoked',
      permissions: [],
      stale_permission_names: [],
      permission_source: 'custom',
      expires_at: null,
      revoked_at: '2024-03-01T00:00:00Z',
      revoked_by: { id: 'u-owner', email: 'owner@example.com', full_name: 'Owner User' },
      notes: null,
      is_active: false,
      is_expired: false,
      created_at: '2024-01-01T00:00:00Z',
      updated_at: '2024-03-01T00:00:00Z',
    },
  ];

  beforeEach(() => {
    jest.clearAllMocks();
    mockUseAuth.mockReturnValue({ currentUser: { permissions: ['accounts.manage'], account: { id: 'acct-1' } } });
    mockGetDelegations.mockResolvedValue({ delegations: mockDelegations, meta: { total_count: 5, active_count: 2, expired_count: 1 } });
    mockCreateDelegation.mockResolvedValue({ delegation: mockDelegations[0], message: 'Delegation created successfully' });
    mockRevokeDelegation.mockResolvedValue({ delegation: { ...mockDelegations[0], status: 'revoked' }, message: 'Delegation revoked successfully' });
    mockActivateDelegation.mockResolvedValue({ delegation: { ...mockDelegations[3], status: 'active', is_active: true }, message: 'Delegation activated successfully' });
    mockDeactivateDelegation.mockResolvedValue({ delegation: { ...mockDelegations[0], status: 'inactive', is_active: false }, message: 'Delegation deactivated successfully' });
  });

  describe('no access', () => {
    it('shows a no-access state instead of the panel when the user lacks accounts.manage/admin.access', async () => {
      mockUseAuth.mockReturnValue({ currentUser: { permissions: [], account: { id: 'acct-1' } } });

      render(<DelegationsManagement />);

      expect(screen.getByText("You don't have permission to manage delegations")).toBeInTheDocument();
      expect(mockGetDelegations).not.toHaveBeenCalled();
    });

    it('renders the panel for a wildcard grant, same as the sidebar nav gate', async () => {
      mockUseAuth.mockReturnValue({ currentUser: { permissions: ['accounts.*'], account: { id: 'acct-1' } } });

      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Account Delegations')).toBeInTheDocument();
      });
    });
  });

  describe('loading state', () => {
    it('shows loading message while fetching delegations', () => {
      mockGetDelegations.mockImplementation(() => new Promise(() => {}));

      render(<DelegationsManagement />);

      expect(screen.getByText('Loading delegations...')).toBeInTheDocument();
    });
  });

  describe('main content', () => {
    it('shows title and description', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Account Delegations')).toBeInTheDocument();
      });
    });

    it('shows Create Delegation button', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Create Delegation')).toBeInTheDocument();
      });
    });

    it('loads delegations scoped to the real account id, not a "current" sentinel', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(mockGetDelegations).toHaveBeenCalledWith('acct-1');
      });
    });

    it('shows permissions reference section', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Available Permissions')).toBeInTheDocument();
      });
      expect(screen.getByText('View Reports')).toBeInTheDocument();
      expect(screen.getByText('Manage Reports')).toBeInTheDocument();
    });
  });

  describe('active delegations', () => {
    it('shows the delegated user, not a nonexistent name field', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Finance User')).toBeInTheDocument();
      });
    });

    it('falls back to email when the delegated user has no full name', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('viewer@example.com')).toBeInTheDocument();
      });
    });

    it('shows the role, or "Custom permissions" for a role-less delegation', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getAllByText('Finance').length).toBeGreaterThan(0);
      });
      const activeSection = screen.getByText('Active Delegations').closest('div')!;
      expect(within(activeSection).getByText('Custom permissions')).toBeInTheDocument();
    });

    it('labels the permission count as the RESOLVED set, not the stored rows', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('2 resolved permissions')).toBeInTheDocument();
      });
    });

    it('surfaces stale stored permission names so they can be rewritten', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText(/1 stored permission is no longer granted/i, { selector: 'p' })).toBeInTheDocument();
      });
      expect(screen.getByText('reports.export')).toBeInTheDocument();
    });

    it('points at the details modal, where the permission-set editor lives', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(
          screen.getByText(/Clearing it means rewriting the stored permission set in this delegation's details/i, { selector: 'p' })
        ).toBeInTheDocument();
      });
    });

    it('shows expiration date when present', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText(/Expires:/)).toBeInTheDocument();
      });
    });

    it('shows status badges', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getAllByText('Active').length).toBeGreaterThan(0);
      });
    });

    it('shows Manage link on delegation cards', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getAllByText('Manage →').length).toBeGreaterThan(0);
      });
    });

    it('buckets by `is_active`, never by `status` alone', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Finance User')).toBeInTheDocument();
      });

      // del-1 and del-2 are the only genuinely active rows.
      const activeSection = screen.getByText('Active Delegations').closest('div')!;
      expect(within(activeSection).getByText('Finance User')).toBeInTheDocument();
      expect(within(activeSection).getByText('viewer@example.com')).toBeInTheDocument();
      expect(within(activeSection).queryByText('Old User')).not.toBeInTheDocument();
      expect(within(activeSection).queryByText('Paused User')).not.toBeInTheDocument();
      expect(within(activeSection).queryByText('Gone User')).not.toBeInTheDocument();
    });
  });

  describe('inactive delegations (fc-20 item 2)', () => {
    it('shows inactive delegations section', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Inactive Delegations')).toBeInTheDocument();
      });
    });

    it('buckets a `status: "active"` row that has actually expired as INACTIVE, labeled Expired', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Old User')).toBeInTheDocument();
      });

      const inactiveSection = screen.getByText('Inactive Delegations').closest('div')!;
      expect(within(inactiveSection).getByText('Old User')).toBeInTheDocument();
      expect(within(inactiveSection).getByText('Expired')).toBeInTheDocument();
      // Never mislabeled as Active just because `status` still reads "active".
      const activeSection = screen.getByText('Active Delegations').closest('div')!;
      expect(within(activeSection).queryByText('Old User')).not.toBeInTheDocument();
    });

    it('labels a genuinely deactivated (non-expired) row as Inactive', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Paused User')).toBeInTheDocument();
      });

      const inactiveSection = screen.getByText('Inactive Delegations').closest('div')!;
      expect(within(inactiveSection).getByText('Inactive')).toBeInTheDocument();
    });

    it('labels a revoked row as Revoked, not "Revoked on…"', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Gone User')).toBeInTheDocument();
      });

      const inactiveSection = screen.getByText('Inactive Delegations').closest('div')!;
      expect(within(inactiveSection).getByText('Revoked')).toBeInTheDocument();
    });

    it('makes inactive rows clickable, opening the details modal', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Paused User')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Paused User').closest('div[class*="cursor-pointer"]')!);

      expect(screen.getByTestId('delegation-details-modal')).toBeInTheDocument();
      expect(screen.getByText('Details: paused@example.com')).toBeInTheDocument();
    });
  });

  describe('empty states', () => {
    it('shows empty state when no active delegations', async () => {
      mockGetDelegations.mockResolvedValue({
        delegations: [mockDelegations[2]], // Only expired
        meta: { total_count: 1, active_count: 0, expired_count: 1 },
      });

      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('No active delegations')).toBeInTheDocument();
      });
      expect(screen.getByText('Create a delegation to grant another user access to this account')).toBeInTheDocument();
    });

    it('shows empty state when no inactive delegations', async () => {
      mockGetDelegations.mockResolvedValue({
        delegations: [mockDelegations[0]], // Only active
        meta: { total_count: 1, active_count: 1, expired_count: 0 },
      });

      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('No inactive delegations')).toBeInTheDocument();
      });
      expect(screen.getByText('Expired, deactivated and revoked delegations will appear here')).toBeInTheDocument();
    });
  });

  describe('load errors', () => {
    it('surfaces the load failure instead of failing silently', async () => {
      mockGetDelegations.mockRejectedValue(new Error('Failed to load delegations: insufficient permissions'));

      render(<DelegationsManagement />);

      expect(await screen.findByRole('alert')).toHaveTextContent(/insufficient permissions/i);
    });
  });

  describe('create delegation modal', () => {
    it('opens modal when Create Delegation clicked', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Create Delegation')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Create Delegation'));

      expect(screen.getByTestId('create-delegation-modal')).toBeInTheDocument();
    });

    it('closes modal when Close clicked', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Create Delegation')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Create Delegation'));
      fireEvent.click(screen.getByText('Close Create Modal'));

      expect(screen.queryByTestId('create-delegation-modal')).not.toBeInTheDocument();
    });

    it('calls createDelegation with the real account id and reloads on create', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Create Delegation')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Create Delegation'));
      fireEvent.click(screen.getByText('Create'));

      await waitFor(() => {
        expect(mockCreateDelegation).toHaveBeenCalledWith('acct-1', { delegated_user_email: 'new@example.com' });
      });
      await waitFor(() => {
        expect(mockGetDelegations).toHaveBeenCalledTimes(2);
      });
    });
  });

  describe('delegation details modal', () => {
    it('opens details modal when delegation clicked', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Finance User')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Finance User').closest('div[class*="cursor-pointer"]')!);

      expect(screen.getByTestId('delegation-details-modal')).toBeInTheDocument();
      expect(screen.getByText('Details: finance@example.com')).toBeInTheDocument();
    });

    it('closes details modal when Close clicked', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Finance User')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Finance User').closest('div[class*="cursor-pointer"]')!);
      fireEvent.click(screen.getByText('Close Details'));

      expect(screen.queryByTestId('delegation-details-modal')).not.toBeInTheDocument();
    });

    it('re-syncs the open modal onto the refreshed row after a permission-set write', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Finance User')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Finance User').closest('div[class*="cursor-pointer"]')!);
      expect(screen.getByTestId('details-stale')).toHaveTextContent('reports.export');

      mockGetDelegations.mockResolvedValue({
        delegations: [ { ...mockDelegations[0], stale_permission_names: [] }, mockDelegations[1] ],
        meta: { total_count: 2, active_count: 2, expired_count: 0 },
      });
      fireEvent.click(screen.getByText('Signal Update'));

      await waitFor(() => {
        expect(screen.getByTestId('details-stale')).toHaveTextContent('');
      });
      expect(screen.getByText('Details: finance@example.com')).toBeInTheDocument();
    });

    it('keeps the modal open when the refreshed list no longer carries the row', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Finance User')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Finance User').closest('div[class*="cursor-pointer"]')!);

      mockGetDelegations.mockResolvedValue({ delegations: [], meta: { total_count: 0, active_count: 0, expired_count: 0 } });
      fireEvent.click(screen.getByText('Signal Update'));

      await waitFor(() => {
        expect(screen.queryByText('Finance User')).not.toBeInTheDocument();
      });
      expect(screen.getByText('Details: finance@example.com')).toBeInTheDocument();
    });

    it('calls revokeDelegation with the real account id when Revoke clicked, after confirmation', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Finance User')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Finance User').closest('div[class*="cursor-pointer"]')!);
      fireEvent.click(screen.getByText('Revoke'));

      // ConfirmationModal is mocked to auto-confirm; the real component still
      // routes every revoke through useConfirmation()'s confirm(), so this
      // pins the plumbing without needing a real dialog interaction.
      await waitFor(() => {
        expect(mockRevokeDelegation).toHaveBeenCalledWith('acct-1', 'del-1');
      });
    });

    // fc-20 review round 2: a revoke/activate/deactivate failure is no longer displayed
    // here -- this component's own error banner sits BEHIND the details modal's z-50
    // overlay, so it was never seen. The handler now rejects instead of swallowing the
    // failure into a local banner, letting DelegationDetailsModal catch and display it
    // (pinned in DelegationDetailsModal.test.tsx). What this component owns is simply:
    // don't treat a rejection as success -- the list is not reloaded and the modal is
    // not closed.
    it('does not reload the list or close the modal when revoke fails', async () => {
      mockRevokeDelegation.mockRejectedValue(new Error('Failed to revoke delegation: already revoked'));

      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Finance User')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Finance User').closest('div[class*="cursor-pointer"]')!);
      fireEvent.click(screen.getByText('Revoke'));

      await waitFor(() => {
        expect(mockRevokeDelegation).toHaveBeenCalledWith('acct-1', 'del-1');
      });
      expect(mockGetDelegations).toHaveBeenCalledTimes(1);
      expect(screen.getByTestId('delegation-details-modal')).toBeInTheDocument();
    });

    it('calls activateDelegation with the real account id when Activate clicked', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Paused User')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Paused User').closest('div[class*="cursor-pointer"]')!);
      fireEvent.click(screen.getByText('Activate'));

      await waitFor(() => {
        expect(mockActivateDelegation).toHaveBeenCalledWith('acct-1', 'del-4');
      });
    });

    it('does not reload the list when activate fails', async () => {
      mockActivateDelegation.mockRejectedValue(new Error('Failed to activate delegation: already revoked'));

      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Paused User')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Paused User').closest('div[class*="cursor-pointer"]')!);
      fireEvent.click(screen.getByText('Activate'));

      await waitFor(() => {
        expect(mockActivateDelegation).toHaveBeenCalledWith('acct-1', 'del-4');
      });
      expect(mockGetDelegations).toHaveBeenCalledTimes(1);
    });

    it('calls deactivateDelegation with the real account id when Deactivate clicked, after confirmation', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Finance User')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Finance User').closest('div[class*="cursor-pointer"]')!);
      fireEvent.click(screen.getByText('Deactivate'));

      await waitFor(() => {
        expect(mockDeactivateDelegation).toHaveBeenCalledWith('acct-1', 'del-1');
      });
    });

    it('does not reload the list when deactivate fails', async () => {
      mockDeactivateDelegation.mockRejectedValue(new Error('Failed to deactivate delegation: already revoked'));

      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Finance User')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Finance User').closest('div[class*="cursor-pointer"]')!);
      fireEvent.click(screen.getByText('Deactivate'));

      await waitFor(() => {
        expect(mockDeactivateDelegation).toHaveBeenCalledWith('acct-1', 'del-1');
      });
      expect(mockGetDelegations).toHaveBeenCalledTimes(1);
    });
  });
});
