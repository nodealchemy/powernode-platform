import React, { useState, useEffect, useCallback } from 'react';
import {
  delegationApi,
  Delegation,
  DelegationPermissionOption,
  Permission,
  deriveDelegationPermissions,
} from '@/features/delegations/services/delegationApi';
import { rolesApi } from '@/features/admin/roles/services/rolesApi';
import { formatDateTime } from '@/shared/utils/formatters';
import { useAuth } from '@/shared/hooks/useAuth';
import { hasPermissions } from '@/shared/utils/permissionUtils';

interface DelegationDetailsModalProps {
  delegation: Delegation;
  onClose: () => void;
  onRevoke: (id: string) => void;
  onActivate: (id: string) => void | Promise<void>;
  onDeactivate: (id: string) => void;
  // The permission-set editor derives every offer it makes from the `delegation` prop,
  // and the parent re-points that prop only once its reload has resolved -- so this is
  // awaited, and its return type must admit the promise the parent actually returns.
  onUpdate: () => void | Promise<void>;
}

export const DelegationDetailsModal: React.FC<DelegationDetailsModalProps> = ({
  delegation,
  onClose,
  onRevoke,
  onActivate,
  onDeactivate,
  onUpdate,
}) => {
  const { currentUser } = useAuth();
  const accountId = currentUser?.account?.id;
  // Catalog-derived permission labels, sourced from the catalog at runtime.
  const [permissionRefs, setPermissionRefs] = useState<DelegationPermissionOption[]>([]);
  const [addablePermissions, setAddablePermissions] = useState<Permission[]>([]);
  const [permissionToAdd, setPermissionToAdd] = useState('');
  const [savingPermissionSet, setSavingPermissionSet] = useState(false);
  const [permissionSetError, setPermissionSetError] = useState<string | null>(null);

  // PERMISSIONS ONLY, NEVER ROLES. Mirrors the pair
  // Api::V1::DelegationsController#authorize_delegation_management! enforces (through the
  // same hasPermissions helper the sidebar/Profile-tab gate uses), so the editor is
  // offered exactly to the operators whose writes the API will accept.
  const canManagePermissionSet = hasPermissions(currentUser ?? null, [ 'accounts.manage', 'admin.access' ]);

  const resolvedPermissionNames = (delegation.permissions || []).map(permission => permission.key);
  const stalePermissionNames = delegation.stale_permission_names || [];
  // THE STORED SET IS NOT THE RESOLVED SET. Only a `custom` row carries
  // delegation_permissions rows; a `role`-backed row stores nothing and confers its
  // role's whole set, so deriving a stored set from the resolved names there would
  // offer removals for rows that do not exist.
  //
  // UNKNOWN IS NOT EMPTY. A payload predating `permission_source` reports nothing about
  // what is stored, which is a different state from storing nothing -- the stale panel
  // above may be listing stored names at the same time. Both states offer no removals,
  // but only one of them may be DESCRIBED as an empty stored set.
  const storedSetIsKnown = delegation.permission_source !== undefined;
  const storedPermissionNames =
    delegation.permission_source === 'custom'
      ? [...resolvedPermissionNames, ...stalePermissionNames]
      : [];
  // THE SERVICE REFUSES ONLY A WIDENING REMOVAL, and emptying widens only where there is
  // a ROLE to fall back to. Accounts::DelegationService#widening_from_removal is a set
  // delta taken THROUGH Account::Delegation#configured_permissions_for, which answers
  // `role&.permission_names || []` for an empty custom set: with no role the delta is
  // empty, so the service explicitly allows a role-less delegation to empty to nothing
  // ("Removals that genuinely narrow (including emptying a role-LESS delegation down to
  // nothing) stay allowed"). Such a row is creatable from this very UI -- create_delegation
  // takes "either a role or specific permissions" -- so disabling its last removal would
  // block a write the API accepts and state a reason naming a role the row does not have.
  const removalWouldEmptySet = !!delegation.role && storedPermissionNames.length <= 1;
  const emptyingRemovalReason =
    `Removing the last stored permission would widen this delegation to the full ` +
    `${delegation.role?.name || 'delegated'} role, so the API refuses it. Add another ` +
    `permission first, or revoke the delegation instead.`;
  // Clearing the stale names in one PATCH is only a CLEAR while something survives it:
  // an empty `permission_names` is treated as absent by the API, so it would no-op.
  const canDropStaleNames =
    canManagePermissionSet && stalePermissionNames.length > 0 && resolvedPermissionNames.length > 0;

  useEffect(() => {
    let cancelled = false;
    rolesApi.getPermissions()
      .then(response => {
        if (cancelled) return;
        const derived = deriveDelegationPermissions(response.data || []);
        if (derived.length > 0) setPermissionRefs(derived);
      })
      .catch(() => {
        // Labels are non-critical; fall back to raw permission keys.
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const loadAddablePermissions = useCallback(async () => {
    if (!accountId) return;
    try {
      const permissions = await delegationApi.getAvailablePermissions(accountId, delegation.role?.id);
      setAddablePermissions(permissions || []);
    } catch (_error) {
      // The add control degrades to empty; removal and the stale rewrite still work.
      setAddablePermissions([]);
    }
  }, [accountId, delegation.role?.id]);

  useEffect(() => {
    if (!canManagePermissionSet) return;
    loadAddablePermissions();
  }, [canManagePermissionSet, loadAddablePermissions]);

  // Every write shares one refresh + error surface so a refusal is never swallowed: the
  // API's reasons (privilege escalation, out-of-role name, widening removal) are the only
  // explanation the operator gets for a set that did not change, and delegationApi's
  // error mapping carries them here out of the `details` array render_error puts them in.
  //
  // `onUpdate` is AWAITED. The controls below are offered against the `delegation` prop,
  // which the parent re-points only after its own reload resolves; clearing the saving
  // flag on the write alone would re-enable them against the pre-write stored set.
  const runPermissionSetWrite = async (write: () => Promise<unknown>) => {
    setSavingPermissionSet(true);
    setPermissionSetError(null);
    try {
      await write();
      setPermissionToAdd('');
      await loadAddablePermissions();
      await onUpdate();
    } catch (error) {
      setPermissionSetError(error instanceof Error ? error.message : 'The permission set could not be updated.');
    } finally {
      setSavingPermissionSet(false);
    }
  };

  const handleRemoveStoredPermission = (permissionName: string) => {
    if (!accountId) return;
    return runPermissionSetWrite(() => delegationApi.removePermissionFromDelegation(accountId, delegation.id, permissionName));
  };

  const handleAddStoredPermission = () => {
    if (!permissionToAdd || !accountId) return;
    return runPermissionSetWrite(() => delegationApi.addPermissionToDelegation(accountId, delegation.id, permissionToAdd));
  };

  const handleDropStaleNames = () => {
    if (!accountId) return;
    return runPermissionSetWrite(() =>
      delegationApi.updateDelegation(accountId, delegation.id, { permission_names: resolvedPermissionNames })
    );
  };

  const getPermissionLabel = (key: string) => {
    const permission = permissionRefs.find(p => p.key === key);
    return permission ? permission.label : key;
  };

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-theme-surface rounded-lg w-full max-w-4xl max-h-[90vh] overflow-hidden">
        <div className="p-6 border-b border-theme">
          <div className="flex items-center justify-between">
            <div>
              <h2 className="text-xl font-semibold text-theme-primary">
                {delegation.delegated_user.full_name || delegation.delegated_user.email}
              </h2>
              <p className="text-theme-secondary mt-1">{delegation.delegated_user.email}</p>
            </div>
            <button
              onClick={onClose}
              className="text-theme-secondary hover:text-theme-primary"
              aria-label="Close"
            >
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
        </div>

        <div className="p-6 overflow-y-auto max-h-[calc(90vh-200px)]">
          <div className="space-y-6">
              <div className="grid grid-cols-2 gap-6">
                <div>
                  <h3 className="text-sm font-medium text-theme-tertiary mb-1">Status</h3>
                  <div className="flex items-center space-x-2">
                    <span className={`text-sm px-2 py-1 rounded-full ${
                      delegation.is_expired
                        ? 'bg-theme-error-bg text-theme-error-fg'
                        : delegation.is_active
                        ? 'bg-theme-success-bg text-theme-success-fg'
                        : 'bg-theme-surface text-theme-tertiary'
                    }`}>
                      {delegation.is_expired
                        ? 'Expired'
                        : delegation.status.charAt(0).toUpperCase() + delegation.status.slice(1)}
                    </span>
                  </div>
                </div>

                <div>
                  <h3 className="text-sm font-medium text-theme-tertiary mb-1">Role</h3>
                  <p className="text-theme-primary">{delegation.role ? delegation.role.name : 'Custom permissions'}</p>
                </div>

                <div>
                  <h3 className="text-sm font-medium text-theme-tertiary mb-1">Created</h3>
                  <p className="text-theme-primary">{formatDateTime(delegation.created_at)}</p>
                  <p className="text-sm text-theme-secondary">by {delegation.delegated_by.full_name || delegation.delegated_by.email}</p>
                </div>

                <div>
                  <h3 className="text-sm font-medium text-theme-tertiary mb-1">Expires</h3>
                  <p className="text-theme-primary">
                    {delegation.expires_at ? formatDateTime(delegation.expires_at) : 'Never'}
                  </p>
                </div>

                {delegation.notes && (
                  <div className="col-span-2">
                    <h3 className="text-sm font-medium text-theme-tertiary mb-1">Notes</h3>
                    <p className="text-theme-primary">{delegation.notes}</p>
                  </div>
                )}
              </div>

              <div>
                {/* The API resolves the stored permission rows against the role LIVE, so
                    this list is the RESOLVED set — what the delegation actually confers —
                    not the rows stored against it. Naming it "Granted" hid that split. */}
                <h3 className="text-sm font-medium text-theme-tertiary mb-3">Resolved Permissions</h3>
                <div className="grid grid-cols-2 gap-3">
                  {(delegation.permissions || []).map((permission) => (
                    <div key={permission.key} className="bg-theme-background rounded-lg p-3">
                      <div className="flex items-center space-x-2">
                        <span className="text-theme-success-fg">✓</span>
                        <span className="text-theme-primary text-sm">{getPermissionLabel(permission.key)}</span>
                      </div>
                    </div>
                  ))}
                </div>
              </div>

              {/* Stored names the role no longer grants. They confer nothing but stay on
                  the row, so an operator cleaning up after a role change needs to SEE
                  them: these are the names to rewrite through the permission set. */}
              {(delegation.stale_permission_names?.length || 0) > 0 && (
                <div>
                  <h3 className="text-sm font-medium text-theme-tertiary mb-3">Stale Stored Permissions</h3>
                  {/* The remedy named here must be one the READER has. The permission-set
                      editor below is gated on the same permission the API enforces, so a
                      viewer without it is pointed at the permission, not at an editor that
                      will not render for them. */}
                  <p className="text-sm text-theme-warning-fg mb-3">
                    These permissions are stored on this delegation but are no longer granted by
                    its role, so they confer nothing. Clearing them means rewriting the stored
                    permission set{canManagePermissionSet
                      ? ' in the permission-set editor below.'
                      : ', which requires the delegations permission.'}
                  </p>
                  <div className="grid grid-cols-2 gap-3">
                    {(delegation.stale_permission_names || []).map((name) => (
                      <div key={name} className="bg-theme-warning-bg rounded-lg p-3">
                        <div className="flex items-center space-x-2">
                          <span className="text-theme-warning-fg">!</span>
                          {/* Same vocabulary as the resolved list above (getPermissionLabel
                              falls back to the raw key when the name has left the catalog);
                              the stored string stays available as the title. */}
                          <span className="text-theme-warning-fg text-sm" title={name}>{getPermissionLabel(name)}</span>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* PERMISSION-SET EDITOR.
                  The API exposes three write verbs over the stored set and, until this
                  editor, none had a call site: an operator could SEE a stale stored name
                  and had no way to clear it short of the raw API. All three are here
                  because they are not interchangeable -- add and remove act on one name,
                  while a `permission_names` rewrite is the ONLY way past the refusal that
                  protects the set from being emptied one name at a time. */}
              {canManagePermissionSet && (
                <div className="pt-6 border-t border-theme">
                  <h3 className="text-sm font-medium text-theme-tertiary mb-1">Stored Permission Set</h3>
                  {/* The role fallback -- and therefore the refusal it causes -- exists
                      only where there IS a role. On a role-less delegation the stored set
                      is the whole grant, and emptying it narrows to nothing, which the
                      service allows. */}
                  <p className="text-sm text-theme-secondary mb-3">
                    {delegation.role
                      ? `The permission names stored against this delegation. An empty stored set falls back to the whole ${delegation.role.name} role, so the API refuses the removal that would empty it.`
                      : 'The permission names stored against this delegation. It carries no role, so it confers exactly what is stored here and nothing else.'}
                  </p>

                  {permissionSetError && (
                    <p role="alert" className="text-sm text-theme-error-fg mb-3">
                      {permissionSetError}
                    </p>
                  )}

                  {storedPermissionNames.length === 0 ? (
                    <p className="text-sm text-theme-tertiary mb-3">
                      {storedSetIsKnown
                        ? 'This delegation stores no custom permissions, so it confers its role’s full set. Adding one narrows it to just the names you store.'
                        : 'This API response does not report which permissions are stored on this delegation, so the stored set cannot be listed here. Adding a permission still stores it.'}
                    </p>
                  ) : (
                    <ul className="space-y-2 mb-3">
                      {storedPermissionNames.map((name) => (
                        <li
                          key={name}
                          className="bg-theme-background rounded-lg p-3 flex items-center justify-between"
                        >
                          <span className="text-theme-primary text-sm" title={name}>
                            {getPermissionLabel(name)}
                            {stalePermissionNames.includes(name) && (
                              <span className="ml-2 text-xs px-2 py-0.5 rounded-full bg-theme-warning-bg text-theme-warning-fg">
                                stale
                              </span>
                            )}
                          </span>
                          <button
                            onClick={() => handleRemoveStoredPermission(name)}
                            disabled={savingPermissionSet || removalWouldEmptySet}
                            aria-label={`Remove ${name}`}
                            title={removalWouldEmptySet ? emptyingRemovalReason : undefined}
                            className="text-sm text-theme-error-fg hover:text-theme-error-hover disabled:opacity-50 disabled:cursor-not-allowed"
                          >
                            Remove
                          </button>
                        </li>
                      ))}
                    </ul>
                  )}

                  {storedPermissionNames.length > 0 && removalWouldEmptySet && (
                    <p className="text-sm text-theme-warning-fg mb-3">{emptyingRemovalReason}</p>
                  )}

                  {canDropStaleNames && (
                    <button
                      onClick={handleDropStaleNames}
                      disabled={savingPermissionSet}
                      className="btn-theme btn-theme-secondary text-sm mb-3 disabled:opacity-50"
                    >
                      Drop {stalePermissionNames.length} stale name
                      {stalePermissionNames.length === 1 ? '' : 's'} from the stored set
                    </button>
                  )}

                  <div className="flex items-end space-x-3">
                    <div className="flex-1">
                      <label
                        htmlFor="delegation-add-permission"
                        className="block text-sm font-medium text-theme-tertiary mb-1"
                      >
                        Add a permission
                      </label>
                      <select
                        id="delegation-add-permission"
                        value={permissionToAdd}
                        onChange={(e) => setPermissionToAdd(e.target.value)}
                        disabled={savingPermissionSet}
                        className="w-full px-3 py-2 bg-theme-background border border-theme rounded-lg text-theme-primary"
                      >
                        <option value="">Select a permission…</option>
                        {addablePermissions
                          .map((permission) => permission.key)
                          .filter((name) => !storedPermissionNames.includes(name))
                          .map((name) => {
                            const label = getPermissionLabel(name);
                            return (
                              <option key={name} value={name}>
                                {label === name ? name : `${label} (${name})`}
                              </option>
                            );
                          })}
                      </select>
                    </div>
                    <button
                      onClick={handleAddStoredPermission}
                      disabled={savingPermissionSet || !permissionToAdd}
                      className="btn-theme btn-theme-primary text-sm disabled:opacity-50 disabled:cursor-not-allowed"
                    >
                      Add Permission
                    </button>
                  </div>
                </div>
              )}

              {delegation.status !== 'revoked' && (
                <div className="pt-6 border-t border-theme flex items-center space-x-3">
                  {delegation.is_active && (
                    <button
                      onClick={() => onDeactivate(delegation.id)}
                      className="btn-theme btn-theme-secondary"
                    >
                      Deactivate
                    </button>
                  )}
                  {!delegation.is_active && !delegation.is_expired && (
                    <button
                      onClick={() => onActivate(delegation.id)}
                      className="btn-theme btn-theme-secondary"
                    >
                      Activate
                    </button>
                  )}
                  <button
                    onClick={() => onRevoke(delegation.id)}
                    className="btn-theme btn-theme-secondary text-theme-error-fg hover:bg-theme-error-bg hover:text-white"
                  >
                    Revoke Delegation
                  </button>
                </div>
              )}
          </div>
        </div>
      </div>
    </div>
  );
};