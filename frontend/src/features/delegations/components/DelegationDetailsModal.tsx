import React, { useState, useEffect, useCallback } from 'react';
import {
  delegationApi,
  Delegation,
  DelegationActivity,
  DelegationPermissionOption,
  Permission,
  deriveDelegationPermissions,
  DELEGATION_PERMISSIONS
} from '@/features/delegations/services/delegationApi';
import { rolesApi } from '@/features/admin/roles/services/rolesApi';
import { formatDateTime } from '@/shared/utils/formatters';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useAuth } from '@/shared/hooks/useAuth';

interface DelegationDetailsModalProps {
  delegation: Delegation;
  onClose: () => void;
  onRevoke: (id: string) => void;
  // The permission-set editor derives every offer it makes from the `delegation` prop,
  // and the parent re-points that prop only once its reload has resolved -- so this is
  // awaited, and its return type must admit the promise the parent actually returns.
  onUpdate: () => void | Promise<void>;
}

interface DelegationUser {
  id: string;
  email: string;
  name: string;
}

export const DelegationDetailsModal: React.FC<DelegationDetailsModalProps> = ({
  delegation,
  onClose,
  onRevoke,
  onUpdate,
}) => {
  const { confirm, ConfirmationDialog } = useConfirmation();
  const { currentUser } = useAuth();
  const [activeTab, setActiveTab] = useState<'details' | 'users' | 'activity'>('details');
  const [activityLog, setActivityLog] = useState<DelegationActivity[]>([]);
  const [availableUsers, setAvailableUsers] = useState<DelegationUser[]>([]);
  const [selectedUsers, setSelectedUsers] = useState<string[]>([]);
  const [showAddUsers, setShowAddUsers] = useState(false);
  const [loading, setLoading] = useState(false);
  // Catalog-derived permission labels (seeded from the back-compat constant).
  const [permissionRefs, setPermissionRefs] = useState<DelegationPermissionOption[]>(DELEGATION_PERMISSIONS);
  const [addablePermissions, setAddablePermissions] = useState<Permission[]>([]);
  const [permissionToAdd, setPermissionToAdd] = useState('');
  const [savingPermissionSet, setSavingPermissionSet] = useState(false);
  const [permissionSetError, setPermissionSetError] = useState<string | null>(null);

  // PERMISSIONS ONLY, NEVER ROLES. This mirrors the pair
  // Api::V1::DelegationsController#authorize_delegation_management! enforces, so the
  // editor is offered exactly to the operators whose writes the API will accept.
  const canManagePermissionSet =
    (currentUser?.permissions?.includes('accounts.manage') ||
      currentUser?.permissions?.includes('admin.access')) ?? false;

  const resolvedPermissionNames = (delegation.permissions || []).map(
    permission => (typeof permission === 'string' ? permission : permission.key)
  );
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
    try {
      const permissions = await delegationApi.getAvailablePermissions(delegation.role?.id);
      setAddablePermissions(permissions || []);
    } catch (_error) {
      // The add control degrades to empty; removal and the stale rewrite still work.
      setAddablePermissions([]);
    }
  }, [delegation.role?.id]);

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

  const handleRemoveStoredPermission = (permissionName: string) =>
    runPermissionSetWrite(() => delegationApi.removePermissionFromDelegation(delegation.id, permissionName));

  const handleAddStoredPermission = () => {
    if (!permissionToAdd) return;
    return runPermissionSetWrite(() => delegationApi.addPermissionToDelegation(delegation.id, permissionToAdd));
  };

  const handleDropStaleNames = () =>
    runPermissionSetWrite(() =>
      delegationApi.updateDelegation(delegation.id, { permission_names: resolvedPermissionNames })
    );

  const loadActivityLog = useCallback(async () => {
    try {
      setLoading(true);
      const data = await delegationApi.getDelegationActivity(delegation.id);
      setActivityLog(data.activities || []);
    } catch (_error) {
    // Error silently ignored
  } finally {
      setLoading(false);
    }
  }, [delegation.id]);

  useEffect(() => {
    if (activeTab === 'activity') {
      loadActivityLog();
    }
  }, [activeTab, loadActivityLog]);

  const loadAvailableUsers = async () => {
    try {
      const data = await delegationApi.getAvailableUsers(delegation.sourceAccountId || delegation.account.id);
      const currentUserIds = delegation.users?.map(u => u.userId) || [];
      setAvailableUsers(data.users.filter((u: DelegationUser) => !currentUserIds.includes(u.id)));
    } catch (_error) {
    // Error silently ignored
  }
  };

  const handleAddUsers = async () => {
    if (selectedUsers.length === 0) return;

    try {
      await delegationApi.addUsersToDelegation(delegation.id, selectedUsers);
      setShowAddUsers(false);
      setSelectedUsers([]);
      onUpdate();
    } catch (_error) {
    // Error silently ignored
  }
  };

  const handleRemoveUser = (userId: string) => {
    confirm({
      title: 'Remove User',
      message: 'Are you sure you want to remove this user from the delegation?',
      confirmLabel: 'Remove',
      variant: 'danger',
      onConfirm: async () => {
        try {
          await delegationApi.removeUserFromDelegation(delegation.id, userId);
          onUpdate();
        } catch (_error) {
          // Error silently ignored
        }
      },
    });
  };

  const getPermissionLabel = (key: string) => {
    const permission = permissionRefs.find(p => p.key === key);
    return permission ? permission.label : key;
  };

  const getActivityIcon = (action: string) => {
    const icons = {
      created: '🆕',
      approved: '✅',
      rejected: '❌',
      revoked: '🚫',
      expired: '⏰',
      user_added: '👤',
      user_removed: '👤',
      permissions_changed: '🔐',
    };
    return icons[action as keyof typeof icons] || '📝';
  };

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-theme-surface rounded-lg w-full max-w-4xl max-h-[90vh] overflow-hidden">
        <div className="p-6 border-b border-theme">
          <div className="flex items-center justify-between">
            <div>
              <h2 className="text-xl font-semibold text-theme-primary">{delegation.name}</h2>
              <p className="text-theme-secondary mt-1">{delegation.description}</p>
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

          {/* Tab Navigation */}
          <div className="flex space-x-6 mt-6 border-b border-theme -mb-6">
            {['details', 'users', 'activity'].map((tab) => (
              <button
                key={tab}
                onClick={() => setActiveTab(tab as typeof activeTab)}
                className={`pb-3 px-1 font-medium text-sm transition-colors ${
                  activeTab === tab
                    ? 'text-theme-primary border-b-2 border-theme-interactive-primary'
                    : 'text-theme-secondary hover:text-theme-primary'
                }`}
              >
                {tab.charAt(0).toUpperCase() + tab.slice(1)}
                {tab === 'users' && (
                  <span className="ml-2 bg-theme-surface px-2 py-0.5 rounded-full text-xs">
                    {delegation.users?.length || 0}
                  </span>
                )}
              </button>
            ))}
          </div>
        </div>

        <div className="p-6 overflow-y-auto max-h-[calc(90vh-200px)]">
          {/* Details Tab */}
          {activeTab === 'details' && (
            <div className="space-y-6">
              <div className="grid grid-cols-2 gap-6">
                <div>
                  <h3 className="text-sm font-medium text-theme-tertiary mb-1">Status</h3>
                  <div className="flex items-center space-x-2">
                    <span className={`text-sm px-2 py-1 rounded-full ${
                      delegation.status === 'active' 
                        ? 'bg-theme-success-bg text-theme-success-fg'
                        : delegation.status === 'pending'
                        ? 'bg-theme-warning-bg text-theme-warning-fg'
                        : 'bg-theme-error-bg text-theme-error-fg'
                    }`}>
                      {delegation.status.charAt(0).toUpperCase() + delegation.status.slice(1)}
                    </span>
                  </div>
                </div>

                <div>
                  <h3 className="text-sm font-medium text-theme-tertiary mb-1">Created</h3>
                  <p className="text-theme-primary">{formatDateTime(delegation.createdAt || delegation.created_at)}</p>
                  <p className="text-sm text-theme-secondary">by {delegation.createdByName}</p>
                </div>

                <div>
                  <h3 className="text-sm font-medium text-theme-tertiary mb-1">Target Account</h3>
                  <p className="text-theme-primary">{delegation.targetAccountName}</p>
                </div>

                <div>
                  <h3 className="text-sm font-medium text-theme-tertiary mb-1">Expires</h3>
                  <p className="text-theme-primary">
                    {delegation.expiresAt ? formatDateTime(delegation.expiresAt) : 'Never'}
                  </p>
                </div>
              </div>

              <div>
                {/* The API resolves the stored permission rows against the role LIVE, so
                    this list is the RESOLVED set — what the delegation actually confers —
                    not the rows stored against it. Naming it "Granted" hid that split. */}
                <h3 className="text-sm font-medium text-theme-tertiary mb-3">Resolved Permissions</h3>
                <div className="grid grid-cols-2 gap-3">
                  {(delegation.permissions || []).map((permission) => (
                    <div key={typeof permission === 'string' ? permission : permission.key} className="bg-theme-background rounded-lg p-3">
                      <div className="flex items-center space-x-2">
                        <span className="text-theme-success-fg">✓</span>
                        <span className="text-theme-primary text-sm">{getPermissionLabel(typeof permission === 'string' ? permission : permission.key)}</span>
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

              {delegation.status === 'active' && (
                <div className="pt-6 border-t border-theme">
                  <button
                    onClick={() => onRevoke(delegation.id)}
                    className="btn-theme btn-theme-secondary text-theme-error-fg hover:bg-theme-error-bg hover:text-white"
                  >
                    Revoke Delegation
                  </button>
                </div>
              )}
            </div>
          )}

          {/* Users Tab */}
          {activeTab === 'users' && (
            <div className="space-y-6">
              <div className="flex justify-between items-center">
                <h3 className="text-lg font-medium text-theme-primary">Delegated Users</h3>
                {delegation.status === 'active' && (
                  <button
                    onClick={() => {
                      setShowAddUsers(true);
                      loadAvailableUsers();
                    }}className="btn-theme btn-theme-primary text-sm"
                  >
                    Add Users
                  </button>
                )}
              </div>

              {showAddUsers && (
                <div className="bg-theme-background rounded-lg p-4 border border-theme">
                  <h4 className="font-medium text-theme-primary mb-3">Select Users to Add</h4>
                  <div className="space-y-2 max-h-48 overflow-y-auto mb-4">
                    {availableUsers.map((user) => (
                      <label
                        key={user.id}
                        className="flex items-center space-x-3 p-2 hover:bg-theme-surface-hover rounded cursor-pointer"
                      >
                        <input
                          type="checkbox"
                          checked={selectedUsers.includes(user.id)}
                          onChange={(e) => {
                            if (e.target.checked) {
                              setSelectedUsers([...selectedUsers, user.id]);
                            } else {
                              setSelectedUsers(selectedUsers.filter(id => id !== user.id));
                            }
                          }}
                          className="rounded border-theme text-theme-interactive-primary"
                        />
                        <div className="flex-1">
                          <div className="text-theme-primary">{user.name}</div>
                          <div className="text-sm text-theme-secondary">{user.email}</div>
                        </div>
                      </label>
                    ))}
                  </div>
                  <div className="flex justify-end space-x-3">
                    <button
                      onClick={() => {
                        setShowAddUsers(false);
                        setSelectedUsers([]);
                      }}className="btn-theme btn-theme-secondary text-sm"
                    >
                      Cancel
                    </button>
                    <button
                      onClick={handleAddUsers}
                      disabled={selectedUsers.length === 0}
                      className="btn-theme btn-theme-primary text-sm disabled:opacity-50"
                    >
                      Add Selected
                    </button>
                  </div>
                </div>
              )}

              <div className="space-y-3">
                {(delegation.users || []).map((user) => (
                  <div key={user.userId || user.id} className="bg-theme-background rounded-lg p-4 flex items-center justify-between">
                    <div>
                      <div className="font-medium text-theme-primary">
                        {user.name}
                      </div>
                      <div className="text-sm text-theme-secondary">{user.email}</div>
                      <div className="text-xs text-theme-tertiary mt-1">
                        Added {user.addedAt && formatDateTime(user.addedAt)}
                      </div>
                    </div>
                    {delegation.status === 'active' && (
                      <button
                        onClick={() => handleRemoveUser(user.userId || user.id || '')}
                        className="text-theme-error-fg hover:text-theme-error-hover"
                      >
                        Remove
                      </button>
                    )}
                  </div>
                ))}

                {(delegation.users?.length || 0) === 0 && (
                  <div className="bg-theme-background rounded-lg p-8 text-center">
                    <p className="text-theme-secondary">No users added to this delegation</p>
                    <p className="text-sm text-theme-tertiary mt-1">
                      Add users to grant them delegated access
                    </p>
                  </div>
                )}
              </div>
            </div>
          )}

          {/* Activity Tab */}
          {activeTab === 'activity' && (
            <div className="space-y-4">
              {loading ? (
                <div className="text-center py-8 text-theme-secondary">Loading activity...</div>
              ) : activityLog.length > 0 ? (
                activityLog.map((activity) => (
                  <div key={activity.id} className="flex items-start space-x-3">
                    <div className="text-2xl">{getActivityIcon(activity.action)}</div>
                    <div className="flex-1">
                      <div className="flex items-center space-x-2">
                        <span className="font-medium text-theme-primary">
                          {activity.performedByName || activity.performed_by}
                        </span>
                        <span className="text-theme-secondary">
                          {activity.action.replace(/_/g, ' ')}
                        </span>
                      </div>
                      {activity.details && (
                        <p className="text-sm text-theme-secondary mt-1">{activity.details}</p>
                      )}
                      <p className="text-xs text-theme-tertiary mt-1">
                        {formatDateTime(activity.timestamp || activity.performedAt || activity.performed_at)}
                      </p>
                    </div>
                  </div>
                ))
              ) : (
                <div className="text-center py-8 text-theme-secondary">
                  No activity recorded yet
                </div>
              )}
            </div>
          )}
        </div>
      </div>
      {ConfirmationDialog}
    </div>
  );
};