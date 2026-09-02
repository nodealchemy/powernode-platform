import { render, screen } from '@testing-library/react';
import { DelegationDetailsModal } from './DelegationDetailsModal';
import type { Delegation } from '@/features/delegations/services/delegationApi';

jest.mock('@/shared/components/ui/ConfirmationModal', () => ({
  useConfirmation: () => ({
    confirm: (opts: { onConfirm: () => void }) => { opts.onConfirm(); },
    ConfirmationDialog: null,
  }),
}));

const mockGetDelegationActivity = jest.fn();

jest.mock('@/features/delegations/services/delegationApi', () => ({
  delegationApi: {
    getDelegationActivity: (...args: unknown[]) => mockGetDelegationActivity(...args),
    getAvailableUsers: jest.fn(),
    addUsersToDelegation: jest.fn(),
    removeUserFromDelegation: jest.fn(),
  },
  DELEGATION_PERMISSIONS: [
    { key: 'business.billing.read', label: 'View Billing', description: 'View billing information' },
    { key: 'business.billing.manage', label: 'Manage Billing', description: 'Manage billing settings' },
  ],
  deriveDelegationPermissions: () => [],
}));

jest.mock('@/features/admin/roles/services/rolesApi', () => ({
  rolesApi: {
    getPermissions: () => Promise.resolve({ success: true, data: [] }),
  },
}));

// A delegation whose stored custom permission set has drifted from its role: the API
// resolves `permissions` against the role LIVE, so `business.billing.export` is carried
// by the stored row but confers nothing and is reported in `stale_permission_names`.
const delegation = {
  id: 'del-1',
  account: { id: 'acct-1', name: 'Acme', subdomain: 'acme' },
  delegated_user: { id: 'u-1', email: 'a@example.com', full_name: 'A User' },
  delegated_by: { id: 'u-2', email: 'b@example.com', full_name: 'B User' },
  role: { id: 'r-1', name: 'Finance', description: 'Finance role' },
  permissions: [
    { name: 'business.billing.read', key: 'business.billing.read', resource: 'business.billing', action: 'read', description: 'View billing' },
    { name: 'business.billing.manage', key: 'business.billing.manage', resource: 'business.billing', action: 'manage', description: 'Manage billing' },
  ],
  stale_permission_names: ['business.billing.export'],
  status: 'active',
  expires_at: null,
  revoked_at: null,
  revoked_by: null,
  notes: null,
  is_active: true,
  is_expired: false,
  created_at: '2025-01-01T00:00:00Z',
  updated_at: '2025-01-02T00:00:00Z',
  name: 'Finance Access',
  description: 'Access to financial reports',
  targetAccountName: 'Beta Inc',
  createdByName: 'B User',
  users: [],
} as unknown as Delegation;

const renderModal = (overrides: Partial<Delegation> = {}) =>
  render(
    <DelegationDetailsModal
      delegation={{ ...delegation, ...overrides }}
      onClose={jest.fn()}
      onRevoke={jest.fn()}
      onUpdate={jest.fn()}
    />
  );

describe('DelegationDetailsModal permission disclosure', () => {
  beforeEach(() => {
    mockGetDelegationActivity.mockResolvedValue({ activities: [] });
  });

  it('labels the permission list as the RESOLVED set, not the stored rows', () => {
    renderModal();

    expect(screen.getByText('Resolved Permissions')).toBeInTheDocument();
  });

  it('lists the stale stored permission names an operator must rewrite', () => {
    renderModal();

    expect(screen.getByText('Stale Stored Permissions')).toBeInTheDocument();
    expect(screen.getByText('business.billing.export')).toBeInTheDocument();
  });

  it('omits the stale section when every stored name still resolves', () => {
    renderModal({ stale_permission_names: [] });

    expect(screen.queryByText('Stale Stored Permissions')).not.toBeInTheDocument();
  });

  it('renders stale names in the same vocabulary as the resolved list', () => {
    // The two lists sit side by side; showing a catalog label in one and the raw
    // dotted key in the other makes one permission look like two different things.
    renderModal({ permissions: [], stale_permission_names: ['business.billing.manage'] } as unknown as Partial<Delegation>);

    expect(screen.getByText('Manage Billing')).toBeInTheDocument();
    expect(screen.queryByText('business.billing.manage')).not.toBeInTheDocument();
    expect(screen.getByTitle('business.billing.manage')).toBeInTheDocument();
  });

  it('does not tell the operator to rewrite the permission set, which this UI cannot do', () => {
    // Nothing in the frontend calls updateDelegation / addPermissionToDelegation /
    // removePermissionFromDelegation, so the disclosure must not name that affordance.
    renderModal();

    expect(screen.queryByText(/Rewrite the permission set to clear them/i)).not.toBeInTheDocument();
    expect(screen.getByText(/no permission-set editor yet/i)).toBeInTheDocument();
  });
});
