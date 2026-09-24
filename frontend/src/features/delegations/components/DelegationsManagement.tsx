import React, { useState, useEffect } from 'react';
import {
  delegationApi,
  Delegation,
  DelegationFormData,
  DelegationPermissionOption,
  deriveDelegationPermissions,
} from '@/features/delegations/services/delegationApi';
import { rolesApi } from '@/features/admin/roles/services/rolesApi';
import { formatDate } from '@/shared/utils/formatters';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useAuth } from '@/shared/hooks/useAuth';
import { hasPermissions } from '@/shared/utils/permissionUtils';
import { CreateDelegationModal } from './CreateDelegationModal';
import { DelegationDetailsModal } from './DelegationDetailsModal';

// Extracts the API's actual refusal reason (delegationApi's error mapping
// carries it through from ApiResponse#render_error's `details`), falling
// back to a generic message for anything that never reached the server.
const errorMessage = (error: unknown, fallback: string): string =>
  error instanceof Error ? error.message : fallback;

// A row is EXPIRED independently of its stored `status`: Account::Delegation#active?
// is `status == "active" && !expired?`, so a row can sit at status "active" past its
// expires_at and still be inactive. `is_expired` is the only field that says so.
const statusLabel = (delegation: Delegation): string =>
  delegation.is_expired ? 'Expired' : delegation.status.charAt(0).toUpperCase() + delegation.status.slice(1);

export const DelegationsManagement: React.FC = () => {
  const { currentUser } = useAuth();
  const { confirm, ConfirmationDialog } = useConfirmation();
  const [delegations, setDelegations] = useState<Delegation[]>([]);
  const [selectedDelegation, setSelectedDelegation] = useState<Delegation | null>(null);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showDetailsModal, setShowDetailsModal] = useState(false);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  // Delegatable permissions shown in the reference section, sourced from the catalog at
  // runtime -- empty until the first successful fetch resolves.
  const [permissionRefs, setPermissionRefs] = useState<DelegationPermissionOption[]>([]);

  const accountId = currentUser?.account?.id;
  // Mirrors Api::V1::DelegationsController#authorize_delegation_management!
  // exactly (accounts.manage OR admin.access), through the same hasPermissions
  // helper the sidebar nav item uses -- so system.admin and wildcard grants
  // behave identically in both places.
  const canManageDelegations = hasPermissions(currentUser ?? null, [ 'accounts.manage', 'admin.access' ]);

  useEffect(() => {
    if (!canManageDelegations || !accountId) return;
    loadDelegations();
    loadPermissionRefs();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [canManageDelegations, accountId]);

  const loadPermissionRefs = async () => {
    try {
      const response = await rolesApi.getPermissions();
      const derived = deriveDelegationPermissions(response.data || []);
      if (derived.length > 0) {
        setPermissionRefs(derived);
      }
    } catch (_error) {
      // Reference list is non-critical; keep the existing (possibly empty) list.
    }
  };

  const loadDelegations = async (): Promise<Delegation[]> => {
    if (!accountId) return [];
    try {
      setLoading(true);
      setLoadError(null);
      const data = await delegationApi.getDelegations(accountId);
      const list = data.delegations || [];
      setDelegations(list);
      return list;
    } catch (error) {
      setLoadError(errorMessage(error, 'Failed to load delegations.'));
      return [];
    } finally {
      setLoading(false);
    }
  };

  // A child modal reporting a write reloads the LIST, but the details modal renders
  // the row held in `selectedDelegation` — a separate copy that a list reload does not
  // touch. Its permission-set editor derives what it offers from that row, so leaving
  // it on the pre-write copy kept offering a removal for a stored name the operator had
  // just cleared. Re-point it at the refreshed row; if the row has left the list (it was
  // revoked, or a filter dropped it) KEEP the copy on screen rather than blanking the
  // modal out from under an operator mid-edit.
  const handleDelegationUpdated = async () => {
    const list = await loadDelegations();
    setSelectedDelegation(current =>
      current ? list.find(delegation => delegation.id === current.id) || current : current
    );
  };

  const handleCreateDelegation = async (data: DelegationFormData) => {
    if (!accountId) return;
    await delegationApi.createDelegation(accountId, data);
    await loadDelegations();
    setShowCreateModal(false);
  };

  const handleRevokeDelegation = (delegationId: string) => {
    confirm({
      title: 'Revoke Delegation',
      message: 'Are you sure you want to revoke this delegation? The delegated user will immediately lose the access it grants.',
      confirmLabel: 'Revoke',
      variant: 'danger',
      onConfirm: async () => {
        if (!accountId) return;
        try {
          setActionError(null);
          await delegationApi.revokeDelegation(accountId, delegationId);
          await loadDelegations();
          setShowDetailsModal(false);
        } catch (error) {
          setActionError(errorMessage(error, 'Failed to revoke delegation.'));
        }
      },
    });
  };

  const handleActivateDelegation = async (delegationId: string) => {
    if (!accountId) return;
    try {
      setActionError(null);
      await delegationApi.activateDelegation(accountId, delegationId);
      await handleDelegationUpdated();
    } catch (error) {
      setActionError(errorMessage(error, 'Failed to activate delegation.'));
    }
  };

  const handleDeactivateDelegation = (delegationId: string) => {
    confirm({
      title: 'Deactivate Delegation',
      message: 'Are you sure you want to deactivate this delegation? The delegated user will lose the access it grants until it is reactivated.',
      confirmLabel: 'Deactivate',
      variant: 'danger',
      onConfirm: async () => {
        if (!accountId) return;
        try {
          setActionError(null);
          await delegationApi.deactivateDelegation(accountId, delegationId);
          await handleDelegationUpdated();
        } catch (error) {
          setActionError(errorMessage(error, 'Failed to deactivate delegation.'));
        }
      },
    });
  };

  const getStatusBadge = (delegation: Delegation) => {
    const variant = delegation.is_expired
      ? 'bg-theme-error-bg text-theme-error-fg'
      : delegation.is_active
      ? 'bg-theme-success-bg text-theme-success-fg'
      : 'bg-theme-surface text-theme-tertiary';

    return (
      <span className={`text-xs px-2 py-1 rounded-full ${variant}`}>
        {statusLabel(delegation)}
      </span>
    );
  };

  const delegatedUserLabel = (delegation: Delegation) =>
    delegation.delegated_user.full_name || delegation.delegated_user.email;

  const openDetails = (delegation: Delegation) => {
    setSelectedDelegation(delegation);
    setShowDetailsModal(true);
  };

  if (!canManageDelegations) {
    return (
      <div className="bg-theme-surface rounded-lg p-8 text-center">
        <span className="text-4xl">🔒</span>
        <p className="text-theme-secondary mt-2">You don&apos;t have permission to manage delegations</p>
        <p className="text-theme-tertiary text-sm mt-1">
          Managing delegations requires the accounts.manage permission.
        </p>
      </div>
    );
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-theme-secondary">Loading delegations...</div>
      </div>
    );
  }

  const activeDelegations = delegations.filter(d => d.is_active);
  const inactiveDelegations = delegations.filter(d => !d.is_active);

  return (
    <div className="space-y-6">
      <div className="bg-theme-surface rounded-lg p-6">
        <div className="flex justify-between items-center mb-6">
          <div>
            <h2 className="text-xl font-semibold text-theme-primary">Account Delegations</h2>
            <p className="text-theme-secondary mt-1">Grant another user access to this account, scoped to a role or specific permissions</p>
          </div>
          <button
            onClick={() => setShowCreateModal(true)}
            className="btn-theme btn-theme-primary"
          >
            Create Delegation
          </button>
        </div>

        {loadError && (
          <div role="alert" className="mb-6 bg-theme-error-bg border border-theme-error-border rounded-lg p-4">
            <p className="text-sm text-theme-error-fg">{loadError}</p>
          </div>
        )}

        {actionError && (
          <div role="alert" className="mb-6 bg-theme-error-bg border border-theme-error-border rounded-lg p-4">
            <p className="text-sm text-theme-error-fg">{actionError}</p>
          </div>
        )}

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Active Delegations */}
          <div>
            <h3 className="text-lg font-medium text-theme-primary mb-4">Active Delegations</h3>
            <div className="space-y-3">
              {activeDelegations.map((delegation) => (
                <div
                  key={delegation.id}
                  className="bg-theme-background rounded-lg p-4 border border-theme hover:border-theme-focus transition-colors cursor-pointer"
                  onClick={() => openDetails(delegation)}>
                  <div className="flex items-center justify-between mb-2">
                    <h4 className="font-medium text-theme-primary">{delegatedUserLabel(delegation)}</h4>
                    {getStatusBadge(delegation)}
                  </div>
                  <p className="text-sm text-theme-secondary mb-3">
                    {delegation.role ? delegation.role.name : 'Custom permissions'}
                  </p>
                  <div className="flex items-center justify-between text-sm">
                    <span
                      className="text-theme-tertiary"
                      title="Permissions this delegation currently confers. The API resolves the stored permission rows against the role LIVE, so this is the resolved set, not a count of stored rows."
                    >
                      {delegation.permissions?.length || 0} resolved permission{(delegation.permissions?.length || 0) !== 1 ? 's' : ''}
                    </span>
                    <span className="text-theme-link hover:text-theme-link-hover">
                      Manage →
                    </span>
                  </div>
                  {(delegation.stale_permission_names?.length || 0) > 0 && (
                    <div className="mt-2 pt-2 border-t border-theme">
                      <p className="text-xs text-theme-warning-fg">
                        {delegation.stale_permission_names?.length} stored permission
                        {(delegation.stale_permission_names?.length || 0) !== 1 ? 's are' : ' is'} no longer
                        granted by this delegation&apos;s role and confer
                        {(delegation.stale_permission_names?.length || 0) !== 1 ? ' ' : 's '}nothing.
                      </p>
                      <p className="mt-1 text-xs text-theme-tertiary">
                        Clearing {(delegation.stale_permission_names?.length || 0) !== 1 ? 'them' : 'it'} means
                        rewriting the stored permission set in this delegation&apos;s details.
                      </p>
                      <div className="mt-1 flex flex-wrap gap-1">
                        {(delegation.stale_permission_names || []).map((name) => (
                          <span
                            key={name}
                            className="text-xs px-2 py-0.5 rounded-full bg-theme-warning-bg text-theme-warning-fg"
                          >
                            {name}
                          </span>
                        ))}
                      </div>
                    </div>
                  )}
                  {delegation.expires_at && (
                    <div className="mt-2 pt-2 border-t border-theme">
                      <span className="text-xs text-theme-tertiary">
                        Expires: {formatDate(delegation.expires_at)}
                      </span>
                    </div>
                  )}
                </div>
              ))}

              {activeDelegations.length === 0 && (
                <div className="bg-theme-background rounded-lg p-8 text-center border border-theme">
                  <span className="text-4xl">🔐</span>
                  <p className="text-theme-secondary mt-2">No active delegations</p>
                  <p className="text-theme-tertiary text-sm mt-1">
                    Create a delegation to grant another user access to this account
                  </p>
                </div>
              )}
            </div>
          </div>

          {/* Expired/Inactive/Revoked Delegations */}
          <div>
            <h3 className="text-lg font-medium text-theme-primary mb-4">Inactive Delegations</h3>
            <div className="space-y-3">
              {inactiveDelegations.map((delegation) => (
                <div
                  key={delegation.id}
                  className="bg-theme-background rounded-lg p-4 border border-theme opacity-75 hover:border-theme-focus hover:opacity-100 transition-colors cursor-pointer"
                  onClick={() => openDetails(delegation)}
                >
                  <div className="flex items-center justify-between mb-2">
                    <h4 className="font-medium text-theme-primary">{delegatedUserLabel(delegation)}</h4>
                    {getStatusBadge(delegation)}
                  </div>
                  <p className="text-sm text-theme-secondary">
                    {delegation.role ? delegation.role.name : 'Custom permissions'}
                  </p>
                  <div className="mt-2 text-xs text-theme-tertiary">
                    {statusLabel(delegation)} — last updated {formatDate(delegation.updated_at)}
                  </div>
                </div>
              ))}

              {inactiveDelegations.length === 0 && (
                <div className="bg-theme-background rounded-lg p-8 text-center border border-theme">
                  <span className="text-4xl">📋</span>
                  <p className="text-theme-secondary mt-2">No inactive delegations</p>
                  <p className="text-theme-tertiary text-sm mt-1">
                    Expired, deactivated and revoked delegations will appear here
                  </p>
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Permissions Reference */}
        <div className="mt-8 pt-6 border-t border-theme">
          <h3 className="text-lg font-medium text-theme-primary mb-4">Available Permissions</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
            {permissionRefs.map((permission) => (
              <div key={permission.key} className="bg-theme-background rounded-lg p-3">
                <h4 className="font-medium text-theme-primary text-sm">{permission.label}</h4>
                <p className="text-xs text-theme-secondary mt-1">{permission.description}</p>
              </div>
            ))}
          </div>
        </div>
      </div>

      {ConfirmationDialog}

      {/* Modals */}
      {showCreateModal && (
        <CreateDelegationModal
          onClose={() => setShowCreateModal(false)}
          onCreate={handleCreateDelegation}
        />
      )}

      {showDetailsModal && selectedDelegation && (
        <DelegationDetailsModal
          delegation={selectedDelegation}
          onClose={() => {
            setShowDetailsModal(false);
            setSelectedDelegation(null);
          }}
          onRevoke={handleRevokeDelegation}
          onActivate={handleActivateDelegation}
          onDeactivate={handleDeactivateDelegation}
          onUpdate={handleDelegationUpdated}
        />
      )}
    </div>
  );
};
