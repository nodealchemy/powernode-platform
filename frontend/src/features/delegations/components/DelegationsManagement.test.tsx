
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { DelegationsManagement } from './DelegationsManagement';

// Mock delegation API
const mockGetDelegations = jest.fn();
const mockGetDelegationRequests = jest.fn();
const mockCreateDelegation = jest.fn();
const mockRevokeDelegation = jest.fn();
const mockApproveDelegationRequest = jest.fn();
const mockRejectDelegationRequest = jest.fn();

jest.mock('@/features/delegations/services/delegationApi', () => ({
  delegationApi: {
    getDelegations: (...args: any[]) => mockGetDelegations(...args),
    getDelegationRequests: (...args: any[]) => mockGetDelegationRequests(...args),
    createDelegation: (...args: any[]) => mockCreateDelegation(...args),
    revokeDelegation: (...args: any[]) => mockRevokeDelegation(...args),
    approveDelegationRequest: (...args: any[]) => mockApproveDelegationRequest(...args),
    rejectDelegationRequest: (...args: any[]) => mockRejectDelegationRequest(...args)
  },
  DELEGATION_PERMISSIONS: [
    { key: 'billing.read', label: 'View Billing', description: 'View billing information' },
    { key: 'billing.manage', label: 'Manage Billing', description: 'Manage billing settings' },
    { key: 'users.read', label: 'View Users', description: 'View team members' }
  ]
}));

// Mock child modals
jest.mock('./CreateDelegationModal', () => ({
  CreateDelegationModal: ({ onClose, onCreate }: any) => (
    <div data-testid="create-delegation-modal">
      <button onClick={onClose}>Close Create Modal</button>
      <button onClick={() => onCreate({ name: 'Test' })}>Create</button>
    </div>
  )
}));

jest.mock('./DelegationDetailsModal', () => ({
  DelegationDetailsModal: ({ delegation, onClose, onRevoke }: any) => (
    <div data-testid="delegation-details-modal">
      <span>Details: {delegation.name}</span>
      <button onClick={onClose}>Close Details</button>
      <button onClick={() => onRevoke(delegation.id)}>Revoke</button>
    </div>
  )
}));

jest.mock('./DelegationRequestModal', () => ({
  DelegationRequestModal: ({ request, onClose, onApprove, onReject }: any) => (
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
      permissions: ['billing.read', 'billing.manage'],
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

    it('shows permission count', async () => {
      render(<DelegationsManagement />);

      await waitFor(() => {
        expect(screen.getByText('2 permissions')).toBeInTheDocument();
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

    it('calls revokeDelegation when Revoke clicked', async () => {
      window.confirm = jest.fn(() => true);

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
