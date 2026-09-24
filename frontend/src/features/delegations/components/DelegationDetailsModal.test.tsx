import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { DelegationDetailsModal } from './DelegationDetailsModal';
import type { Delegation } from '@/features/delegations/services/delegationApi';

jest.mock('@/shared/components/ui/ConfirmationModal', () => ({
  useConfirmation: () => ({
    confirm: (opts: { onConfirm: () => void }) => { opts.onConfirm(); },
    ConfirmationDialog: null,
  }),
}));

const mockGetAvailablePermissions = jest.fn();
const mockAddPermissionToDelegation = jest.fn();
const mockRemovePermissionFromDelegation = jest.fn();
const mockUpdateDelegation = jest.fn();

// The editor is gated on the delegations permission the API itself enforces
// (Api::V1::DelegationsController#authorize_delegation_management!). Permissions
// only -- never roles.
let mockPermissions: string[] = [];
jest.mock('@/shared/hooks/useAuth', () => ({
  useAuth: () => ({ currentUser: { permissions: mockPermissions, account: { id: 'acct-1' } } }),
}));

jest.mock('@/features/delegations/services/delegationApi', () => ({
  delegationApi: {
    getAvailablePermissions: (...args: unknown[]) => mockGetAvailablePermissions(...args),
    addPermissionToDelegation: (...args: unknown[]) => mockAddPermissionToDelegation(...args),
    removePermissionFromDelegation: (...args: unknown[]) => mockRemovePermissionFromDelegation(...args),
    updateDelegation: (...args: unknown[]) => mockUpdateDelegation(...args),
  },
  // Catalog labels the real catalog fetch (rolesApi.getPermissions ->
  // deriveDelegationPermissions) would derive at runtime -- no back-compat seed
  // constant to fall back on now (fc-20 review item 7 removed it).
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

// A delegation whose stored custom permission set has drifted from its role: the API
// resolves `permissions` against the role LIVE, so `reports.export` is carried
// by the stored row but confers nothing and is reported in `stale_permission_names`.
const delegation = {
  id: 'del-1',
  account: { id: 'acct-1', name: 'Acme', subdomain: 'acme' },
  delegated_user: { id: 'u-1', email: 'a@example.com', full_name: 'A User' },
  delegated_by: { id: 'u-2', email: 'b@example.com', full_name: 'B User' },
  role: { id: 'r-1', name: 'Finance', description: 'Finance role' },
  permissions: [
    { name: 'reports.read', key: 'reports.read', resource: 'reports', action: 'read', description: 'View reports' },
    { name: 'reports.manage', key: 'reports.manage', resource: 'reports', action: 'manage', description: 'Manage reports' },
  ],
  stale_permission_names: ['reports.export'],
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
} as unknown as Delegation;

const renderModal = (overrides: Partial<Delegation> = {}) =>
  render(
    <DelegationDetailsModal
      delegation={{ ...delegation, ...overrides }}
      onClose={jest.fn()}
      onRevoke={jest.fn()}
      onActivate={jest.fn()}
      onDeactivate={jest.fn()}
      onUpdate={jest.fn()}
    />
  );

// fc-20 review: the header and details grid used to read fields
// (delegation.name/description/targetAccountName/createdByName) the real
// API never sends -- they came from a legacy, never-implemented "delegation
// requests" data model. Pins that the modal now reads the real payload
// (delegated_user, delegated_by, role) instead of rendering blank.
describe('DelegationDetailsModal header and details', () => {
  beforeEach(() => {
    mockPermissions = [];
  });

  it('titles the modal with who the delegation is TO, not a nonexistent name field', () => {
    renderModal();

    expect(screen.getByRole('heading', { name: 'A User' })).toBeInTheDocument();
    expect(screen.getByText('a@example.com')).toBeInTheDocument();
  });

  it('falls back to the email when the delegated user has no full name', () => {
    renderModal({
      delegated_user: { id: 'u-1', email: 'noname@example.com', full_name: '' },
    } as unknown as Partial<Delegation>);

    expect(screen.getByRole('heading', { name: 'noname@example.com' })).toBeInTheDocument();
  });

  it('shows the role, falling back to "Custom permissions" for a role-less delegation', () => {
    renderModal();
    expect(screen.getByText('Finance')).toBeInTheDocument();

    renderModal({ role: null });
    expect(screen.getByText('Custom permissions')).toBeInTheDocument();
  });

  it('shows who granted the delegation, not the nonexistent createdByName field', () => {
    renderModal();

    expect(screen.getByText('by B User')).toBeInTheDocument();
  });

  it('shows notes when present, and omits the section when absent', () => {
    const { rerender } = renderModal({ notes: 'Renewed for Q3' });
    expect(screen.getByText('Renewed for Q3')).toBeInTheDocument();

    rerender(
      <DelegationDetailsModal
        delegation={{ ...delegation, notes: null }}
        onClose={jest.fn()}
        onRevoke={jest.fn()}
      onActivate={jest.fn()}
      onDeactivate={jest.fn()}
        onUpdate={jest.fn()}
      />
    );
    expect(screen.queryByText('Notes')).not.toBeInTheDocument();
  });
});

describe('DelegationDetailsModal permission disclosure', () => {
  beforeEach(() => {
    mockPermissions = [];
  });

  it('labels the permission list as the RESOLVED set, not the stored rows', () => {
    renderModal();

    expect(screen.getByText('Resolved Permissions')).toBeInTheDocument();
  });

  it('lists the stale stored permission names an operator must rewrite', () => {
    renderModal();

    expect(screen.getByText('Stale Stored Permissions')).toBeInTheDocument();
    expect(screen.getByText('reports.export')).toBeInTheDocument();
  });

  it('omits the stale section when every stored name still resolves', () => {
    renderModal({ stale_permission_names: [] });

    expect(screen.queryByText('Stale Stored Permissions')).not.toBeInTheDocument();
  });

  it('renders stale names in the same vocabulary as the resolved list', async () => {
    // The two lists sit side by side; showing a catalog label in one and the raw
    // dotted key in the other makes one permission look like two different things.
    // The label resolves from the async catalog fetch, so this awaits it settling.
    renderModal({ permissions: [], stale_permission_names: ['reports.manage'] } as unknown as Partial<Delegation>);

    await waitFor(() => expect(screen.getByText('Manage Reports')).toBeInTheDocument());
    expect(screen.queryByText('reports.manage')).not.toBeInTheDocument();
    expect(screen.getByTitle('reports.manage')).toBeInTheDocument();
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
    mockGetAvailablePermissions.mockResolvedValue([
      { name: 'reports.read', key: 'reports.read', resource: 'reports', action: 'read', description: 'View reports' },
      { name: 'reports.manage', key: 'reports.manage', resource: 'reports', action: 'manage', description: 'Manage reports' },
      { name: 'reports.refund', key: 'reports.refund', resource: 'reports', action: 'refund', description: 'Refund' },
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
    expect(screen.getByRole('button', { name: 'Remove reports.read' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Remove reports.manage' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Remove reports.export' })).toBeInTheDocument();
  });

  it('removes a stored name through the API and refreshes the delegation', async () => {
    const onUpdate = jest.fn();
    render(
      <DelegationDetailsModal
        delegation={delegation}
        onClose={jest.fn()}
        onRevoke={jest.fn()}
      onActivate={jest.fn()}
      onDeactivate={jest.fn()}
        onUpdate={onUpdate}
      />
    );

    fireEvent.click(screen.getByRole('button', { name: 'Remove reports.export' }));

    await waitFor(() => {
      expect(mockRemovePermissionFromDelegation).toHaveBeenCalledWith('acct-1', 'del-1', 'reports.export');
    });
    await waitFor(() => expect(onUpdate).toHaveBeenCalled());
  });

  it('refuses the removal that would EMPTY the stored set, as the API does', async () => {
    // Account::Delegation#configured_permissions_for falls back to the ROLE's full
    // set on an empty custom set, so dropping the last stored name WIDENS the
    // delegation -- DelegationService#remove_permission_from_delegation refuses it.
    renderModal({ permissions: [], stale_permission_names: ['reports.export'] } as unknown as Partial<Delegation>);

    const remove = screen.getByRole('button', { name: 'Remove reports.export' });
    expect(remove).toBeDisabled();
    expect(screen.getByText(/would widen this delegation to the full Finance role/i)).toBeInTheDocument();

    fireEvent.click(remove);
    expect(mockRemovePermissionFromDelegation).not.toHaveBeenCalled();
  });

  it('adds a permission the role grants and that is not stored yet', async () => {
    renderModal();

    await waitFor(() => expect(mockGetAvailablePermissions).toHaveBeenCalledWith('acct-1', 'r-1'));

    const select = await screen.findByLabelText('Add a permission');
    // Already-stored names must not be offered again.
    expect(screen.queryByRole('option', { name: /business\.billing\.read/ })).not.toBeInTheDocument();

    fireEvent.change(select, { target: { value: 'reports.refund' } });
    fireEvent.click(screen.getByRole('button', { name: 'Add Permission' }));

    await waitFor(() => {
      expect(mockAddPermissionToDelegation).toHaveBeenCalledWith('acct-1', 'del-1', 'reports.refund');
    });
  });

  it('drops every stale name in ONE update, the only way to clear a set one-by-one removal cannot', async () => {
    renderModal();

    fireEvent.click(screen.getByRole('button', { name: /Drop 1 stale name/i }));

    await waitFor(() => {
      expect(mockUpdateDelegation).toHaveBeenCalledWith('acct-1', 'del-1', {
        permission_names: ['reports.read', 'reports.manage'],
      });
    });
  });

  it('never offers the stale-name drop when it would leave the stored set empty', () => {
    // Every stored name is stale: PATCHing permission_names: [] is a no-op on the
    // API (`permission_names.present?`), so offering it would promise a clear that
    // never happens.
    renderModal({ permissions: [], stale_permission_names: ['reports.export'] } as unknown as Partial<Delegation>);

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

    fireEvent.click(screen.getByRole('button', { name: 'Remove reports.export' }));

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
      { name: 'reports.read', key: 'reports.read', resource: 'reports', action: 'read', description: 'View reports' },
    ],
    stale_permission_names: [],
    permission_source: 'custom',
  } as unknown as Partial<Delegation>;

  it('ENABLES the last removal on a role-less delegation, which the service permits', () => {
    renderModal(rolelessSingleName);

    expect(screen.getByRole('button', { name: 'Remove reports.read' })).toBeEnabled();
  });

  it('never claims a role fallback on a delegation that HAS no role', () => {
    renderModal(rolelessSingleName);

    expect(screen.queryByText(/would widen this delegation/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/falls back to the whole delegated role/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/\bdelegated role\b/i)).not.toBeInTheDocument();
  });

  it('sends the removal through the API rather than blocking it in the client', async () => {
    renderModal(rolelessSingleName);

    fireEvent.click(screen.getByRole('button', { name: 'Remove reports.read' }));

    await waitFor(() => {
      expect(mockRemovePermissionFromDelegation).toHaveBeenCalledWith('acct-1', 'del-1', 'reports.read');
    });
  });

  it('still refuses the emptying removal when a ROLE is there to fall back to', () => {
    renderModal({ permissions: [], stale_permission_names: ['reports.export'] } as unknown as Partial<Delegation>);

    expect(screen.getByRole('button', { name: 'Remove reports.export' })).toBeDisabled();
    expect(screen.getByText(/would widen this delegation to the full Finance role/i)).toBeInTheDocument();
  });
});

describe('DelegationDetailsModal permission-set editor: staleness windows', () => {
  beforeEach(() => {
    mockPermissions = ['accounts.manage'];
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
      onActivate={jest.fn()}
      onDeactivate={jest.fn()}
        onUpdate={onUpdate}
      />
    );

    fireEvent.click(screen.getByRole('button', { name: 'Remove reports.export' }));

    await waitFor(() => expect(onUpdate).toHaveBeenCalled());
    expect(screen.getByRole('button', { name: 'Remove reports.read' })).toBeDisabled();

    releaseParentRefresh();
    await waitFor(() =>
      expect(screen.getByRole('button', { name: 'Remove reports.read' })).toBeEnabled()
    );
  });

  it('does not assert an EMPTY stored set on a payload that never reported one', () => {
    // `permission_source` predates neither the stale list nor the stored rows: a payload
    // without it tells us nothing about what is stored. Saying "stores no custom
    // permissions" there contradicts the Stale Stored Permissions panel directly above,
    // which is listing stored names.
    const { container } = renderModal({
      permission_source: undefined,
      stale_permission_names: ['reports.export'],
    } as unknown as Partial<Delegation>);

    expect(screen.getByText('Stale Stored Permissions')).toBeInTheDocument();
    expect(screen.queryByText(/stores no custom permissions/i)).not.toBeInTheDocument();
    expect(container.textContent).toMatch(/does not report/i);
  });
});

// fc-20 review item 3: activate/deactivate wired into the modal so the flow works end
// to end. Availability mirrors Accounts::DelegationService's own refusal rules
// (activate refuses on revoked OR expired; deactivate refuses only on revoked; revoke
// is always offered unless already revoked).
describe('DelegationDetailsModal action buttons', () => {
  beforeEach(() => {
    mockPermissions = [];
  });

  it('shows Deactivate (not Activate) and Revoke for an active delegation', () => {
    renderModal({ is_active: true, is_expired: false, status: 'active' });

    expect(screen.getByRole('button', { name: 'Deactivate' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Activate' })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Revoke Delegation' })).toBeInTheDocument();
  });

  it('shows Activate (not Deactivate) and Revoke for an inactive, non-expired delegation', () => {
    renderModal({ is_active: false, is_expired: false, status: 'inactive' });

    expect(screen.getByRole('button', { name: 'Activate' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Deactivate' })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Revoke Delegation' })).toBeInTheDocument();
  });

  it('shows neither Activate nor Deactivate for an expired delegation, only Revoke', () => {
    renderModal({ is_active: false, is_expired: true, status: 'active' });

    expect(screen.queryByRole('button', { name: 'Activate' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Deactivate' })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Revoke Delegation' })).toBeInTheDocument();
  });

  it('shows no action buttons at all for an already-revoked delegation', () => {
    renderModal({ is_active: false, is_expired: false, status: 'revoked' });

    expect(screen.queryByRole('button', { name: 'Activate' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Deactivate' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Revoke Delegation' })).not.toBeInTheDocument();
  });

  it('calls onActivate with the delegation id when Activate is clicked', () => {
    const onActivate = jest.fn();
    render(
      <DelegationDetailsModal
        delegation={{ ...delegation, is_active: false, is_expired: false, status: 'inactive' }}
        onClose={jest.fn()}
        onRevoke={jest.fn()}
        onActivate={onActivate}
        onDeactivate={jest.fn()}
        onUpdate={jest.fn()}
      />
    );

    fireEvent.click(screen.getByRole('button', { name: 'Activate' }));

    expect(onActivate).toHaveBeenCalledWith('del-1');
  });

  it('calls onDeactivate with the delegation id when Deactivate is clicked', () => {
    // The confirm-before-deactivate UX (fc-20 item 3) lives one level up, in
    // DelegationsManagement's handleDeactivateDelegation -- this modal just
    // forwards the click to whatever onDeactivate it was given.
    const onDeactivate = jest.fn();
    render(
      <DelegationDetailsModal
        delegation={{ ...delegation, is_active: true, is_expired: false, status: 'active' }}
        onClose={jest.fn()}
        onRevoke={jest.fn()}
        onActivate={jest.fn()}
        onDeactivate={onDeactivate}
        onUpdate={jest.fn()}
      />
    );

    fireEvent.click(screen.getByRole('button', { name: 'Deactivate' }));

    expect(onDeactivate).toHaveBeenCalledWith('del-1');
  });
});

// fc-20 review round 2 (MED): activate/deactivate/revoke are only reachable from THIS
// modal, whose z-50 overlay sits above everything DelegationsManagement renders -- an
// error banner rendered by the parent would never be seen. Activate in particular can
// refuse for a reason the UI cannot predict (e.g. Accounts::DelegationService's
// unconferrable_reason, when the activator can no longer grant what the row carries),
// so a silently-swallowed rejection there is a real, reachable failure mode, not a
// theoretical one.
describe('DelegationDetailsModal action buttons: refusal is shown INSIDE this modal', () => {
  beforeEach(() => {
    mockPermissions = [];
  });

  it('shows the activate refusal reason inside the modal, not just on the console', async () => {
    const onActivate = jest.fn().mockRejectedValue(
      new Error('Cannot activate: the grantor no longer holds reports.refund')
    );
    render(
      <DelegationDetailsModal
        delegation={{ ...delegation, is_active: false, is_expired: false, status: 'inactive' }}
        onClose={jest.fn()}
        onRevoke={jest.fn()}
        onActivate={onActivate}
        onDeactivate={jest.fn()}
        onUpdate={jest.fn()}
      />
    );

    fireEvent.click(screen.getByRole('button', { name: 'Activate' }));

    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('Cannot activate: the grantor no longer holds reports.refund');
  });

  it('shows the deactivate refusal reason inside the modal', async () => {
    const onDeactivate = jest.fn().mockRejectedValue(new Error('Cannot deactivate: already revoked'));
    render(
      <DelegationDetailsModal
        delegation={{ ...delegation, is_active: true, is_expired: false, status: 'active' }}
        onClose={jest.fn()}
        onRevoke={jest.fn()}
        onActivate={jest.fn()}
        onDeactivate={onDeactivate}
        onUpdate={jest.fn()}
      />
    );

    fireEvent.click(screen.getByRole('button', { name: 'Deactivate' }));

    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('Cannot deactivate: already revoked');
  });

  it('shows the revoke refusal reason inside the modal', async () => {
    const onRevoke = jest.fn().mockRejectedValue(new Error('Cannot revoke: already revoked'));
    render(
      <DelegationDetailsModal
        delegation={{ ...delegation, is_active: true, is_expired: false, status: 'active' }}
        onClose={jest.fn()}
        onRevoke={onRevoke}
        onActivate={jest.fn()}
        onDeactivate={jest.fn()}
        onUpdate={jest.fn()}
      />
    );

    fireEvent.click(screen.getByRole('button', { name: 'Revoke Delegation' }));

    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('Cannot revoke: already revoked');
  });

  it('clears a stale action error once a later action succeeds', async () => {
    const onActivate = jest.fn().mockRejectedValueOnce(new Error('temporary refusal'));
    render(
      <DelegationDetailsModal
        delegation={{ ...delegation, is_active: false, is_expired: false, status: 'inactive' }}
        onClose={jest.fn()}
        onRevoke={jest.fn()}
        onActivate={onActivate}
        onDeactivate={jest.fn()}
        onUpdate={jest.fn()}
      />
    );

    fireEvent.click(screen.getByRole('button', { name: 'Activate' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('temporary refusal');

    onActivate.mockResolvedValueOnce(undefined);
    fireEvent.click(screen.getByRole('button', { name: 'Activate' }));

    await waitFor(() => {
      expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    });
  });
});
