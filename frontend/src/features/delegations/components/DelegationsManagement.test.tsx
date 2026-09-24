import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { DelegationsManagement } from './DelegationsManagement';
import type { Delegation } from '@/features/delegations/services/delegationApi';

// Mock ConfirmationModal - auto-confirm by default
jest.mock('@/shared/components/ui/ConfirmationModal', () => ({
  useConfirmation: () => ({
    confirm: (opts: { onConfirm: () => void }) => { opts.onConfirm(); },
    ConfirmationDialog: null,
  }),
}));

// Mock delegation API. fc-20 review: getDelegationRequests/approveDelegationRequest/
// rejectDelegationRequest and the "outgoing/incoming" split were built against a
// `/api/v1/delegation-requests` surface that never existed server-side (no route, no
// controller, no model) -- deleted along with DelegationRequestModal, not fixed.
const mockGetDelegations = jest.fn();
const mockCreateDelegation = jest.fn();
const mockRevokeDelegation = jest.fn();

jest.mock('@/features/delegations/services/delegationApi', () => ({
  delegationApi: {
    getDelegations: (...args: unknown[]) => mockGetDelegations(...args),
    createDelegation: (...args: unknown[]) => mockCreateDelegation(...args),
    revokeDelegation: (...args: unknown[]) => mockRevokeDelegation(...args)
  },
  DELEGATION_PERMISSIONS: [
    { key: 'business.billing.read', label: 'View Billing', description: 'View billing information' },
    { key: 'business.billing.manage', label: 'Manage Billing', description: 'Manage billing settings' },
    { key: 'users.read', label: 'View Users', description: 'View team members' }
  ]
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
  DelegationDetailsModal: ({ delegation, onClose, onRevoke, onUpdate }: { delegation: { id: string; delegated_user: { email: string }; stale_permission_names?: string[] }; onClose: () => void; onRevoke: (id: string) => void; onUpdate: () => void }) => (
    <div data-testid="delegation-details-modal">
      <span>Details: {delegation.delegated_user.email}</span>
      <span data-testid="details-stale">{(delegation.stale_permission_names || []).join(',')}</span>
      <button onClick={onClose}>Close Details</button>
      <button onClick={() => onRevoke(delegation.id)}>Revoke</button>
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
        { name: 'business.billing.read', key: 'business.billing.read', resource: 'business.billing', action: 'read', description: 'View billing' },
        { name: 'business.billing.manage', key: 'business.billing.manage', resource: 'business.billing', action: 'manage', description: 'Manage billing' },
      ],
      stale_permission_names: ['business.billing.export'],
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
      id: 'del-3',
      account: { id: 'acct-1', name: 'Acme', subdomain: 'acme' },
      delegated_user: { id: 'u-3', email: 'old@example.com', full_name: 'Old User' },
      delegated_by: { id: 'u-owner', email: 'owner@example.com', full_name: 'Owner User' },
      role: { id: 'r-1', name: 'Finance', description: 'Finance role' },
      status: 'expired',
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
  ];

  beforeEach(() => {
    jest.clearAllMocks();
    mockGetDelegations.mockResolvedValue({ delegations: mockDelegations, meta: { total_count: 3, active_count: 2, expired_count: 1 } });
    mockCreateDelegation.mockResolvedValue({ delegation: mockDelegations[0], message: 'Delegation created successfully' });
    mockRevokeDelegation.mockResolvedValue({ delegation: { ...mockDelegations[0], status: 'revoked' }, message: 'Delegation revoked successfully' });
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

    it('shows permissions reference section', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Available Permissions')).toBeInTheDocument();
      });
      expect(screen.getByText('View Billing')).toBeInTheDocument();
      expect(screen.getByText('Manage Billing')).toBeInTheDocument();
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
      expect(screen.getByText('Custom permissions')).toBeInTheDocument();
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
      expect(screen.getByText('business.billing.export')).toBeInTheDocument();
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
  });

  describe('inactive delegations', () => {
    it('shows inactive delegations section', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Inactive Delegations')).toBeInTheDocument();
      });
    });

    it('shows expired delegations with status', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Old User')).toBeInTheDocument();
      });
      expect(screen.getByText('Expired')).toBeInTheDocument();
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
      expect(screen.getByText('Expired and revoked delegations will appear here')).toBeInTheDocument();
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

    it('calls createDelegation and reloads on create', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Create Delegation')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Create Delegation'));
      fireEvent.click(screen.getByText('Create'));

      await waitFor(() => {
        expect(mockCreateDelegation).toHaveBeenCalledWith({ delegated_user_email: 'new@example.com' });
      });
      await waitFor(() => {
        expect(mockGetDelegations).toHaveBeenCalledTimes(2);
      });
    });

    it('surfaces a create failure instead of failing silently', async () => {
      mockCreateDelegation.mockRejectedValue(new Error('Failed to create delegation: unknown email'));

      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Create Delegation')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Create Delegation'));
      fireEvent.click(screen.getByText('Create'));

      expect(await screen.findByRole('alert')).toHaveTextContent(/unknown email/i);
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
      expect(screen.getByTestId('details-stale')).toHaveTextContent('business.billing.export');

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

    it('calls revokeDelegation when Revoke clicked, after confirmation', async () => {
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
        expect(mockRevokeDelegation).toHaveBeenCalledWith('del-1');
      });
    });

    it('surfaces a revoke failure instead of failing silently', async () => {
      mockRevokeDelegation.mockRejectedValue(new Error('Failed to revoke delegation: already revoked'));

      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Finance User')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Finance User').closest('div[class*="cursor-pointer"]')!);
      fireEvent.click(screen.getByText('Revoke'));

      expect(await screen.findByRole('alert')).toHaveTextContent(/already revoked/i);
    });
  });
});
