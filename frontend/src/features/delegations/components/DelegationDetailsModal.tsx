import React, { useState, useEffect, useCallback } from 'react';
import { delegationApi, Delegation, DelegationActivity, DELEGATION_PERMISSIONS } from '@/features/delegations/services/delegationApi';

interface DelegationDetailsModalProps {
  delegation: Delegation;
  onClose: () => void;
  onRevoke: (id: string) => void;
  onUpdate: () => void;
}

interface User {
  id: string;
  email: string;
  first_name: string;
  last_name: string;
  roles: string[];
}

interface DelegationUser {
  id: string;
  email: string;
  first_name: string;
  last_name: string;
}

export const DelegationDetailsModal: React.FC<DelegationDetailsModalProps> = ({
  delegation,
  onClose,
  onRevoke,
  onUpdate,
}) => {
  const [activeTab, setActiveTab] = useState<'details' | 'users' | 'activity'>('details');
  const [activityLog, setActivityLog] = useState<DelegationActivity[]>([]);
  const [availableUsers, setAvailableUsers] = useState<DelegationUser[]>([]);
  const [selectedUsers, setSelectedUsers] = useState<string[]>([]);
  const [showAddUsers, setShowAddUsers] = useState(false);
  const [loading, setLoading] = useState(false);

  const loadActivityLog = useCallback(async () => {
    try {
      setLoading(true);
      const data = await delegationApi.getDelegationActivity(delegation.id);
      setActivityLog(data.activities || []);
    } catch (error) {
      console.error('Failed to load activity log:', error);
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
    } catch (error) {
      console.error('Failed to load available users:', error);
    }
  };

  const handleAddUsers = async () => {
    if (selectedUsers.length === 0) return;

    try {
      await delegationApi.addUsersToDelegation(delegation.id, selectedUsers);
      setShowAddUsers(false);
      setSelectedUsers([]);
      onUpdate();
    } catch (error) {
      console.error('Failed to add users:', error);
    }
  };

  const handleRemoveUser = async (userId: string) => {
    if (window.confirm('Are you sure you want to remove this user from the delegation?')) {
      try {
        await delegationApi.removeUserFromDelegation(delegation.id, userId);
        onUpdate();
      } catch (error) {
        console.error('Failed to remove user:', error);
      }
    }
  };

  const formatDate = (date: string) => {
    return new Date(date).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  };

  const getPermissionLabel = (key: string) => {
    const permission = DELEGATION_PERMISSIONS.find(p => p.key === key);
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
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
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
                onClick={() => setActiveTab(tab as any)}
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
                        ? 'bg-theme-success bg-opacity-10 text-theme-success'
                        : delegation.status === 'pending'
                        ? 'bg-theme-warning bg-opacity-10 text-theme-warning'
                        : 'bg-theme-error bg-opacity-10 text-theme-error'
                    }`}>
                      {delegation.status.charAt(0).toUpperCase() + delegation.status.slice(1)}
                    </span>
                  </div>
                </div>

                <div>
                  <h3 className="text-sm font-medium text-theme-tertiary mb-1">Created</h3>
                  <p className="text-theme-primary">{formatDate(delegation.createdAt || delegation.created_at)}</p>
                  <p className="text-sm text-theme-secondary">by {delegation.createdByName}</p>
                </div>

                <div>
                  <h3 className="text-sm font-medium text-theme-tertiary mb-1">Target Account</h3>
                  <p className="text-theme-primary">{delegation.targetAccountName}</p>
                </div>

                <div>
                  <h3 className="text-sm font-medium text-theme-tertiary mb-1">Expires</h3>
                  <p className="text-theme-primary">
                    {delegation.expiresAt ? formatDate(delegation.expiresAt) : 'Never'}
                  </p>
                </div>
              </div>

              <div>
                <h3 className="text-sm font-medium text-theme-tertiary mb-3">Granted Permissions</h3>
                <div className="grid grid-cols-2 gap-3">
                  {(delegation.permissions || []).map((permission) => (
                    <div key={typeof permission === 'string' ? permission : permission.id || permission.key} className="bg-theme-background rounded-lg p-3">
                      <div className="flex items-center space-x-2">
                        <span className="text-theme-success">✓</span>
                        <span className="text-theme-primary text-sm">{getPermissionLabel(typeof permission === 'string' ? permission : permission.key)}</span>
                      </div>
                    </div>
                  ))}
                </div>
              </div>

              {delegation.status === 'active' && (
                <div className="pt-6 border-t border-theme">
                  <button
                    onClick={() => onRevoke(delegation.id)}
                    className="btn-theme btn-theme-secondary text-theme-error hover:bg-theme-error hover:text-white"
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
                          <div className="text-theme-primary">{user.first_name} {user.last_name}</div>
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
                        {user.name || `${user.first_name || ''} ${user.last_name || ''}`.trim()}
                      </div>
                      <div className="text-sm text-theme-secondary">{user.email}</div>
                      <div className="text-xs text-theme-tertiary mt-1">
                        Added {user.addedAt && formatDate(user.addedAt)}
                      </div>
                    </div>
                    {delegation.status === 'active' && (
                      <button
                        onClick={() => handleRemoveUser(user.userId || user.id || '')}
                        className="text-theme-error hover:text-theme-error-hover"
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
                        {formatDate(activity.timestamp || activity.performedAt || activity.performed_at)}
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
    </div>
  );
};