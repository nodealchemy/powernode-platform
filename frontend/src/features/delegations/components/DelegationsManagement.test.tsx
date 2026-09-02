
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { DelegationsManagement } from './DelegationsManagement';

// Mock ConfirmationModal - auto-confirm by default
jest.mock('@/shared/components/ui/ConfirmationModal', () => ({
  useConfirmation: () => ({
    confirm: (opts: { onConfirm: () => void }) => { opts.onConfirm(); },
    ConfirmationDialog: null,
  }),
}));

// Mock delegation API
const mockGetDelegations = jest.fn();
const mockGetDelegationRequests = jest.fn();
const mockCreateDelegation = jest.fn();
const mockRevokeDelegation = jest.fn();
const mockApproveDelegationRequest = jest.fn();
const mockRejectDelegationRequest = jest.fn();

jest.mock('@/features/delegations/services/delegationApi', () => ({
  delegationApi: {
    getDelegations: (...args: unknown[]) => mockGetDelegations(...args),
    getDelegationRequests: (...args: unknown[]) => mockGetDelegationRequests(...args),
    createDelegation: (...args: unknown[]) => mockCreateDelegation(...args),
    revokeDelegation: (...args: unknown[]) => mockRevokeDelegation(...args),
    approveDelegationRequest: (...args: unknown[]) => mockApproveDelegationRequest(...args),
    rejectDelegationRequest: (...args: unknown[]) => mockRejectDelegationRequest(...args)
  },
  DELEGATION_PERMISSIONS: [
    { key: 'business.billing.read', label: 'View Billing', description: 'View billing information' },
    { key: 'business.billing.manage', label: 'Manage Billing', description: 'Manage billing settings' },
    { key: 'users.read', label: 'View Users', description: 'View team members' }
  ]
}));

// Mock child modals
jest.mock('./CreateDelegationModal', () => ({
  CreateDelegationModal: ({ onClose, onCreate }: { onClose: () => void; onCreate: (data: { name: string }) => void }) => (
    <div data-testid="create-delegation-modal">
      <button onClick={onClose}>Close Create Modal</button>
      <button onClick={() => onCreate({ name: 'Test' })}>Create</button>
    </div>
  )
}));

jest.mock('./DelegationDetailsModal', () => ({
  DelegationDetailsModal: ({ delegation, onClose, onRevoke, onUpdate }: { delegation: { id: string; name: string; stale_permission_names?: string[] }; onClose: () => void; onRevoke: (id: string) => void; onUpdate: () => void }) => (
    <div data-testid="delegation-details-modal">
      <span>Details: {delegation.name}</span>
      <span data-testid="details-stale">{(delegation.stale_permission_names || []).join(',')}</span>
      <button onClick={onClose}>Close Details</button>
      <button onClick={() => onRevoke(delegation.id)}>Revoke</button>
      <button onClick={onUpdate}>Signal Update</button>
    </div>
  )
}));

jest.mock('./DelegationRequestModal', () => ({
  DelegationRequestModal: ({ request, onClose, onApprove, onReject }: { request: { id: string; requestedByName?: string }; onClose: () => void; onApprove: (id: string) => void; onReject: (id: string, reason: string) => void }) => (
    <div data-testid="delegation-request-modal">
      <span>Request: {request.requestedByName}</span>
      <button onClick={onClose}>Close Request</button>
      <button onClick={() => onApprove(request.id)}>Approve</button>
      <button onClick={() => onReject(request.id, 'Rejected')}>Reject</button>
    </div>
  )
}));

describe('DelegationsManagement', () => {
  const mockDelegations = [
    {
      id: 'del-1',
      name: 'Finance Access',
      description: 'Access to financial reports',
      status: 'active',
      sourceAccountId: 'current',
      targetAccountId: 'other-1',
      users: ['user-1', 'user-2'],
      // `permissions` is the RESOLVED set the API serializes (what the delegation
      // actually confers); `stale_permission_names` are stored rows the role no
      // longer grants and that therefore resolve to nothing.
      permissions: ['business.billing.read', 'business.billing.manage'],
      stale_permission_names: ['business.billing.export'],
      expiresAt: '2025-12-31T00:00:00Z',
      updatedAt: '2025-01-15T00:00:00Z'
    },
    {
      id: 'del-2',
      name: 'Team View',
      description: 'View team members',
      status: 'active',
      sourceAccountId: 'other-2',
      targetAccountId: 'current',
      users: ['user-3'],
      permissions: ['users.read'],
      expiresAt: null,
      updatedAt: '2025-01-10T00:00:00Z'
    },
    {
      id: 'del-3',
      name: 'Expired Access',
      description: 'Old delegation',
      status: 'expired',
      sourceAccountId: 'current',
      targetAccountId: 'other-3',
      users: [],
      permissions: [],
      updatedAt: '2024-12-01T00:00:00Z'
    }
  ];

  const mockRequests = [
    {
      id: 'req-1',
      requestedByName: 'John Doe',
      delegation: {
        sourceAccountName: 'Acme Corp'
      }
    },
    {
      id: 'req-2',
      requestedByName: 'Jane Smith',
      delegation: {
        sourceAccountName: 'Beta Inc'
      }
    }
  ];

  beforeEach(() => {
    jest.clearAllMocks();
    mockGetDelegations.mockResolvedValue({ delegations: mockDelegations });
    mockGetDelegationRequests.mockResolvedValue({ requests: mockRequests });
    mockCreateDelegation.mockResolvedValue({ success: true });
    mockRevokeDelegation.mockResolvedValue({ success: true });
    mockApproveDelegationRequest.mockResolvedValue({ success: true });
    mockRejectDelegationRequest.mockResolvedValue({ success: true });
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
      expect(screen.getByText('Manage cross-account access and delegations')).toBeInTheDocument();
    });

    it('shows Create Delegation button', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Create Delegation')).toBeInTheDocument();
      });
    });

    it('shows tab navigation', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Outgoing Delegations')).toBeInTheDocument();
      });
      expect(screen.getByText('Incoming Access')).toBeInTheDocument();
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

  describe('tab switching', () => {
    it('defaults to outgoing tab', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Active Delegations')).toBeInTheDocument();
      });
    });

    it('switches to incoming tab when clicked', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Outgoing Delegations')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Incoming Access'));

      expect(screen.getByText('Granted Access')).toBeInTheDocument();
    });

    it('filters delegations by tab', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Finance Access')).toBeInTheDocument();
      });

      // Outgoing tab should show Finance Access (sourceAccountId === 'current')
      expect(screen.getByText('Finance Access')).toBeInTheDocument();

      // Switch to incoming
      fireEvent.click(screen.getByText('Incoming Access'));

      // Incoming tab should show Team View (targetAccountId === 'current')
      expect(screen.getByText('Team View')).toBeInTheDocument();
    });
  });

  describe('active delegations', () => {
    it('shows delegation names', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Finance Access')).toBeInTheDocument();
      });
    });

    it('shows delegation descriptions', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Access to financial reports')).toBeInTheDocument();
      });
    });

    it('shows user count', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('2 users')).toBeInTheDocument();
      });
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
        // Scoped to the notice paragraph: a bare regex also matches every ancestor
        // whose textContent contains it, which makes the query ambiguous.
        expect(screen.getByText(/1 stored permission is no longer granted/i, { selector: 'p' })).toBeInTheDocument();
      });
      expect(screen.getByText('business.billing.export')).toBeInTheDocument();
    });

    it('points at the details modal, where the permission-set editor now lives', async () => {
      // The card is a summary, not an editor: it must name the affordance that
      // exists (the editor in DelegationDetailsModal) rather than the raw API, and
      // must not resurrect the "no permission-set editor yet" claim now that one
      // ships. The card also renders on the incoming tab, so it never promises the
      // viewer can edit -- only where the editor is.
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(
          screen.getByText(/Clearing it means rewriting the stored permission set in this delegation's details/i, { selector: 'p' })
        ).toBeInTheDocument();
      });
      expect(screen.queryByText(/no permission-set editor yet/i)).not.toBeInTheDocument();
      expect(screen.queryByText(/through the delegations API/i)).not.toBeInTheDocument();
    });

    it('pluralises the stale notice when several stored names no longer resolve', async () => {
      // The plural arm is unreachable from the shared fixture (one stale name), so
      // render a card of its own rather than leaving the branch unexecuted.
      mockGetDelegations.mockResolvedValue({
        delegations: [
          {
            ...mockDelegations[0],
            id: 'del-plural',
            name: 'Plural Stale',
            stale_permission_names: ['business.billing.export', 'business.billing.archive']
          }
        ]
      });

      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(
          screen.getByText(/2 stored permissions are no longer granted/i, { selector: 'p' })
        ).toBeInTheDocument();
      });
      expect(screen.getByText(/Clearing them means rewriting/i, { selector: 'p' })).toBeInTheDocument();
      expect(screen.getByText('business.billing.archive')).toBeInTheDocument();
    });

    it('shows no stale notice on a delegation whose stored names all resolve', async () => {
      // Both no-notice shapes must actually RENDER on the default (outgoing) tab to
      // pin the hide-when-empty guard: an empty array, and the key omitted entirely.
      // The shared fixture renders only del-1 here, and del-1 carries a stale name,
      // so counting notices across it proves nothing.
      mockGetDelegations.mockResolvedValue({
        delegations: [
          { ...mockDelegations[0], id: 'del-empty', name: 'Empty Stale', stale_permission_names: [] },
          { ...mockDelegations[0], id: 'del-absent', name: 'Absent Stale', stale_permission_names: undefined }
        ]
      });

      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Empty Stale')).toBeInTheDocument();
      });
      expect(screen.getByText('Absent Stale')).toBeInTheDocument();
      expect(
        screen.queryAllByText(/no longer granted by this delegation's role/i, { selector: 'p' })
      ).toHaveLength(0);
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
        expect(screen.getByText('Active')).toBeInTheDocument();
      });
    });

    it('shows Manage link on delegation cards', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Manage →')).toBeInTheDocument();
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
        expect(screen.getByText('Expired Access')).toBeInTheDocument();
      });
      expect(screen.getByText('Expired')).toBeInTheDocument();
    });
  });

  describe('empty states', () => {
    it('shows empty state when no active delegations', async () => {
      mockGetDelegations.mockResolvedValue({
        delegations: [mockDelegations[2]] // Only expired
      });

      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('No active delegations')).toBeInTheDocument();
      });
      expect(screen.getByText('Create a delegation to grant access to other accounts')).toBeInTheDocument();
    });

    it('shows empty state when no inactive delegations', async () => {
      mockGetDelegations.mockResolvedValue({
        delegations: [mockDelegations[0]] // Only active
      });

      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('No inactive delegations')).toBeInTheDocument();
      });
      expect(screen.getByText('Expired and revoked delegations will appear here')).toBeInTheDocument();
    });
  });

  describe('pending requests', () => {
    it('shows pending requests alert when requests exist', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Pending Delegation Requests')).toBeInTheDocument();
      });
    });

    it('shows request count in alert', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText(/You have 2 pending delegation requests/)).toBeInTheDocument();
      });
    });

    it('shows requester names', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('John Doe')).toBeInTheDocument();
      });
    });

    it('shows source account names', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('from Acme Corp')).toBeInTheDocument();
      });
    });

    it('hides alert when no pending requests', async () => {
      mockGetDelegationRequests.mockResolvedValue({ requests: [] });

      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Account Delegations')).toBeInTheDocument();
      });

      expect(screen.queryByText('Pending Delegation Requests')).not.toBeInTheDocument();
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
        expect(mockCreateDelegation).toHaveBeenCalledWith({ name: 'Test' });
      });
    });
  });

  describe('delegation details modal', () => {
    it('opens details modal when delegation clicked', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Finance Access')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Finance Access').closest('div[class*="cursor-pointer"]')!);

      expect(screen.getByTestId('delegation-details-modal')).toBeInTheDocument();
      expect(screen.getByText('Details: Finance Access')).toBeInTheDocument();
    });

    it('closes details modal when Close clicked', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Finance Access')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Finance Access').closest('div[class*="cursor-pointer"]')!);
      fireEvent.click(screen.getByText('Close Details'));

      expect(screen.queryByTestId('delegation-details-modal')).not.toBeInTheDocument();
    });

    it('re-syncs the open modal onto the refreshed row after a permission-set write', async () => {
      // The permission-set editor writes through the API and then asks the parent to
      // reload. Reloading only the LIST left the modal rendering the pre-write row, so
      // a name the operator had just removed was still offered for removal.
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Finance Access')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Finance Access').closest('div[class*="cursor-pointer"]')!);
      expect(screen.getByTestId('details-stale')).toHaveTextContent('business.billing.export');

      mockGetDelegations.mockResolvedValue({
        delegations: [{ ...mockDelegations[0], stale_permission_names: [] }, mockDelegations[1]]
      });
      fireEvent.click(screen.getByText('Signal Update'));

      await waitFor(() => {
        expect(screen.getByTestId('details-stale')).toHaveTextContent('');
      });
      expect(screen.getByText('Details: Finance Access')).toBeInTheDocument();
    });

    it('keeps the modal open when the refreshed list no longer carries the row', async () => {
      // A row that has left the list (revoked elsewhere, filtered out) must not blank
      // the modal out from under the operator mid-edit.
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Finance Access')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Finance Access').closest('div[class*="cursor-pointer"]')!);

      mockGetDelegations.mockResolvedValue({ delegations: [] });
      fireEvent.click(screen.getByText('Signal Update'));

      await waitFor(() => {
        expect(screen.queryByText('Finance Access')).not.toBeInTheDocument();
      });
      expect(screen.getByText('Details: Finance Access')).toBeInTheDocument();
    });

    it('calls revokeDelegation when Revoke clicked', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('Finance Access')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('Finance Access').closest('div[class*="cursor-pointer"]')!);
      fireEvent.click(screen.getByText('Revoke'));

      await waitFor(() => {
        expect(mockRevokeDelegation).toHaveBeenCalledWith('del-1');
      });
    });
  });

  describe('delegation request modal', () => {
    it('opens request modal when request clicked', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('John Doe')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('John Doe').closest('button')!);

      expect(screen.getByTestId('delegation-request-modal')).toBeInTheDocument();
      expect(screen.getByText('Request: John Doe')).toBeInTheDocument();
    });

    it('calls approveDelegationRequest when Approve clicked', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('John Doe')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('John Doe').closest('button')!);
      fireEvent.click(screen.getByText('Approve'));

      await waitFor(() => {
        expect(mockApproveDelegationRequest).toHaveBeenCalledWith('req-1', undefined);
      });
    });

    it('calls rejectDelegationRequest when Reject clicked', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('John Doe')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByText('John Doe').closest('button')!);
      fireEvent.click(screen.getByText('Reject'));

      await waitFor(() => {
        expect(mockRejectDelegationRequest).toHaveBeenCalledWith('req-1', 'Rejected');
      });
    });
  });
});
