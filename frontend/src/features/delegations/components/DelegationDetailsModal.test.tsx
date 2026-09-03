import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { DelegationDetailsModal } from './DelegationDetailsModal';
import type { Delegation } from '@/features/delegations/services/delegationApi';

jest.mock('@/shared/components/ui/ConfirmationModal', () => ({
  useConfirmation: () => ({
    confirm: (opts: { onConfirm: () => void }) => { opts.onConfirm(); },
    ConfirmationDialog: null,
  }),
}));

const mockGetDelegationActivity = jest.fn();
const mockGetAvailablePermissions = jest.fn();
const mockAddPermissionToDelegation = jest.fn();
const mockRemovePermissionFromDelegation = jest.fn();
const mockUpdateDelegation = jest.fn();

// The editor is gated on the delegations permission the API itself enforces
// (Api::V1::DelegationsController#authorize_delegation_management!). Permissions
// only -- never roles.
let mockPermissions: string[] = [];
jest.mock('@/shared/hooks/useAuth', () => ({
  useAuth: () => ({ currentUser: { permissions: mockPermissions } }),
}));

jest.mock('@/features/delegations/services/delegationApi', () => ({
  delegationApi: {
    getDelegationActivity: (...args: unknown[]) => mockGetDelegationActivity(...args),
    getAvailableUsers: jest.fn(),
    addUsersToDelegation: jest.fn(),
    removeUserFromDelegation: jest.fn(),
    getAvailablePermissions: (...args: unknown[]) => mockGetAvailablePermissions(...args),
    addPermissionToDelegation: (...args: unknown[]) => mockAddPermissionToDelegation(...args),
    removePermissionFromDelegation: (...args: unknown[]) => mockRemovePermissionFromDelegation(...args),
    updateDelegation: (...args: unknown[]) => mockUpdateDelegation(...args),
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
  permission_source: 'custom',
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
    mockPermissions = [];
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

  it('names the delegations permission, not a missing editor, for a viewer who cannot edit', () => {
    // The editor now exists, so the old "this UI has no permission-set editor yet"
    // copy is false. What a viewer WITHOUT the delegations permission lacks is the
    // permission, and that is what the disclosure must say.
    renderModal();

    expect(screen.queryByText(/no permission-set editor yet/i)).not.toBeInTheDocument();
    expect(screen.getByText(/requires the delegations permission/i)).toBeInTheDocument();
  });

  it('points a viewer who CAN edit at the editor below', () => {
    mockPermissions = ['accounts.manage'];
    mockGetAvailablePermissions.mockResolvedValue([]);

    renderModal();

    expect(screen.getByText(/in the permission-set editor below/i)).toBeInTheDocument();
  });
});

describe('DelegationDetailsModal permission-set editor', () => {
  beforeEach(() => {
    mockPermissions = ['accounts.manage'];
    mockGetDelegationActivity.mockResolvedValue({ activities: [] });
    mockGetAvailablePermissions.mockResolvedValue([
      { name: 'business.billing.read', key: 'business.billing.read', resource: 'business.billing', action: 'read', description: 'View billing' },
      { name: 'business.billing.manage', key: 'business.billing.manage', resource: 'business.billing', action: 'manage', description: 'Manage billing' },
      { name: 'business.billing.refund', key: 'business.billing.refund', resource: 'business.billing', action: 'refund', description: 'Refund' },
    ]);
    mockAddPermissionToDelegation.mockResolvedValue({});
    mockRemovePermissionFromDelegation.mockResolvedValue({});
    mockUpdateDelegation.mockResolvedValue({});
  });

  it('is hidden from a viewer without the delegations permission', () => {
    mockPermissions = [];

    renderModal();

    expect(screen.queryByRole('heading', { name: 'Stored Permission Set' })).not.toBeInTheDocument();
  });

  it('is shown to an admin, who holds the API bypass rather than accounts.manage', () => {
    mockPermissions = ['admin.access'];

    renderModal();

    expect(screen.getByRole('heading', { name: 'Stored Permission Set' })).toBeInTheDocument();
  });

  it('lists every STORED name -- the resolved ones and the stale ones alike', () => {
    renderModal();

    // The stored set is what a removal acts on, so it must include the stale name
    // that resolves to nothing as well as the two that still resolve.
    expect(screen.getByRole('button', { name: 'Remove business.billing.read' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Remove business.billing.manage' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Remove business.billing.export' })).toBeInTheDocument();
  });

  it('removes a stored name through the API and refreshes the delegation', async () => {
    const onUpdate = jest.fn();
    render(
      <DelegationDetailsModal
        delegation={delegation}
        onClose={jest.fn()}
        onRevoke={jest.fn()}
        onUpdate={onUpdate}
      />
    );

    fireEvent.click(screen.getByRole('button', { name: 'Remove business.billing.export' }));

    await waitFor(() => {
      expect(mockRemovePermissionFromDelegation).toHaveBeenCalledWith('del-1', 'business.billing.export');
    });
    await waitFor(() => expect(onUpdate).toHaveBeenCalled());
  });

  it('refuses the removal that would EMPTY the stored set, as the API does', async () => {
    // Account::Delegation#configured_permissions_for falls back to the ROLE's full
    // set on an empty custom set, so dropping the last stored name WIDENS the
    // delegation -- DelegationService#remove_permission_from_delegation refuses it.
    renderModal({ permissions: [], stale_permission_names: ['business.billing.export'] } as unknown as Partial<Delegation>);

    const remove = screen.getByRole('button', { name: 'Remove business.billing.export' });
    expect(remove).toBeDisabled();
    expect(screen.getByText(/would widen this delegation to the full Finance role/i)).toBeInTheDocument();

    fireEvent.click(remove);
    expect(mockRemovePermissionFromDelegation).not.toHaveBeenCalled();
  });

  it('adds a permission the role grants and that is not stored yet', async () => {
    renderModal();

    await waitFor(() => expect(mockGetAvailablePermissions).toHaveBeenCalledWith('r-1'));

    const select = await screen.findByLabelText('Add a permission');
    // Already-stored names must not be offered again.
    expect(screen.queryByRole('option', { name: /business\.billing\.read/ })).not.toBeInTheDocument();

    fireEvent.change(select, { target: { value: 'business.billing.refund' } });
    fireEvent.click(screen.getByRole('button', { name: 'Add Permission' }));

    await waitFor(() => {
      expect(mockAddPermissionToDelegation).toHaveBeenCalledWith('del-1', 'business.billing.refund');
    });
  });

  it('drops every stale name in ONE update, the only way to clear a set one-by-one removal cannot', async () => {
    renderModal();

    fireEvent.click(screen.getByRole('button', { name: /Drop 1 stale name/i }));

    await waitFor(() => {
      expect(mockUpdateDelegation).toHaveBeenCalledWith('del-1', {
        permission_names: ['business.billing.read', 'business.billing.manage'],
      });
    });
  });

  it('never offers the stale-name drop when it would leave the stored set empty', () => {
    // Every stored name is stale: PATCHing permission_names: [] is a no-op on the
    // API (`permission_names.present?`), so offering it would promise a clear that
    // never happens.
    renderModal({ permissions: [], stale_permission_names: ['business.billing.export'] } as unknown as Partial<Delegation>);

    expect(screen.queryByRole('button', { name: /Drop .* stale name/i })).not.toBeInTheDocument();
  });

  it('surfaces the API refusal instead of failing silently', async () => {
    // The message shape here is the one delegationApi ACTUALLY throws: the controller's
    // generic `error` label joined to the service reason it puts in `details`
    // (pinned end-to-end in delegationApi.test.ts). Asserting against a bare service
    // string would be a fabricated wire value -- the envelope has no such field.
    mockRemovePermissionFromDelegation.mockRejectedValue(
      new Error('Failed to remove permission: Removing this permission would widen the delegation')
    );

    renderModal();

    fireEvent.click(screen.getByRole('button', { name: 'Remove business.billing.export' }));

    expect(await screen.findByRole('alert')).toHaveTextContent(/would widen the delegation/i);
  });

  it('stores nothing to remove on a role-backed row, and says so', () => {
    // permission_source 'role' means zero stored rows: the delegation confers the
    // whole role. Deriving a stored set from the resolved list there would offer
    // removals for names no row carries.
    renderModal({ permission_source: 'role', stale_permission_names: [] } as unknown as Partial<Delegation>);

    expect(screen.queryByRole('button', { name: /^Remove business/ })).not.toBeInTheDocument();
    expect(screen.getByText(/stores no custom permissions/i)).toBeInTheDocument();
  });
});

describe('DelegationDetailsModal permission-set editor: the API refuses only a WIDENING removal', () => {
  beforeEach(() => {
    mockPermissions = ['accounts.manage'];
    mockGetDelegationActivity.mockResolvedValue({ activities: [] });
    mockGetAvailablePermissions.mockResolvedValue([]);
    mockAddPermissionToDelegation.mockResolvedValue({});
    mockRemovePermissionFromDelegation.mockResolvedValue({});
    mockUpdateDelegation.mockResolvedValue({});
  });

  // Accounts::DelegationService#widening_from_removal computes a SET DELTA through
  // Account::Delegation#configured_permissions_for, which returns `role&.permission_names
  // || []` on an empty custom set. With no role that is [], so emptying a role-LESS
  // delegation gains nothing and the service explicitly ALLOWS it
  // (delegation_service.rb: "Removals that genuinely narrow (including emptying a
  // role-LESS delegation down to nothing) stay allowed"). Such a row is creatable from
  // this very UI -- create_delegation takes "either a role or specific permissions".
  const rolelessSingleName = {
    role: null,
    permissions: [
      { name: 'business.billing.read', key: 'business.billing.read', resource: 'business.billing', action: 'read', description: 'View billing' },
    ],
    stale_permission_names: [],
    permission_source: 'custom',
  } as unknown as Partial<Delegation>;

  it('ENABLES the last removal on a role-less delegation, which the service permits', () => {
    renderModal(rolelessSingleName);

    expect(screen.getByRole('button', { name: 'Remove business.billing.read' })).toBeEnabled();
  });

  it('never claims a role fallback on a delegation that HAS no role', () => {
    renderModal(rolelessSingleName);

    expect(screen.queryByText(/would widen this delegation/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/falls back to the whole delegated role/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/\bdelegated role\b/i)).not.toBeInTheDocument();
  });

  it('sends the removal through the API rather than blocking it in the client', async () => {
    renderModal(rolelessSingleName);

    fireEvent.click(screen.getByRole('button', { name: 'Remove business.billing.read' }));

    await waitFor(() => {
      expect(mockRemovePermissionFromDelegation).toHaveBeenCalledWith('del-1', 'business.billing.read');
    });
  });

  it('still refuses the emptying removal when a ROLE is there to fall back to', () => {
    renderModal({ permissions: [], stale_permission_names: ['business.billing.export'] } as unknown as Partial<Delegation>);

    expect(screen.getByRole('button', { name: 'Remove business.billing.export' })).toBeDisabled();
    expect(screen.getByText(/would widen this delegation to the full Finance role/i)).toBeInTheDocument();
  });
});

describe('DelegationDetailsModal permission-set editor: staleness windows', () => {
  beforeEach(() => {
    mockPermissions = ['accounts.manage'];
    mockGetDelegationActivity.mockResolvedValue({ activities: [] });
    mockGetAvailablePermissions.mockResolvedValue([]);
    mockRemovePermissionFromDelegation.mockResolvedValue({});
  });

  it('stays disabled until the PARENT refresh completes, not merely until the write returns', async () => {
    // The editor derives every offer it makes from the `delegation` prop, and the parent
    // re-points that prop only after its reload resolves. Clearing `savingPermissionSet`
    // on the write alone re-enables the controls against the PRE-write stored set.
    let releaseParentRefresh: () => void = () => {};
    const onUpdate = jest.fn(
      () => new Promise<void>((resolve) => { releaseParentRefresh = () => resolve(); })
    );

    render(
      <DelegationDetailsModal
        delegation={delegation}
        onClose={jest.fn()}
        onRevoke={jest.fn()}
        onUpdate={onUpdate}
      />
    );

    fireEvent.click(screen.getByRole('button', { name: 'Remove business.billing.export' }));

    await waitFor(() => expect(onUpdate).toHaveBeenCalled());
    expect(screen.getByRole('button', { name: 'Remove business.billing.read' })).toBeDisabled();

    releaseParentRefresh();
    await waitFor(() =>
      expect(screen.getByRole('button', { name: 'Remove business.billing.read' })).toBeEnabled()
    );
  });

  it('does not assert an EMPTY stored set on a payload that never reported one', () => {
    // `permission_source` predates neither the stale list nor the stored rows: a payload
    // without it tells us nothing about what is stored. Saying "stores no custom
    // permissions" there contradicts the Stale Stored Permissions panel directly above,
    // which is listing stored names.
    const { container } = renderModal({
      permission_source: undefined,
      stale_permission_names: ['business.billing.export'],
    } as unknown as Partial<Delegation>);

    expect(screen.getByText('Stale Stored Permissions')).toBeInTheDocument();
    expect(screen.queryByText(/stores no custom permissions/i)).not.toBeInTheDocument();
    expect(container.textContent).toMatch(/does not report/i);
  });
});
