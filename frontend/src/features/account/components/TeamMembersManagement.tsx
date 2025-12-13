import React, { useState, useEffect } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { usersApi, User } from '@/features/users/services/usersApi';
import { getUserInitials } from '@/shared/utils/userUtils';

interface TeamMembersManagementProps {
  accountId?: string;
}

export const TeamMembersManagement: React.FC<TeamMembersManagementProps> = ({ accountId }) => {
  const { user: currentUser } = useSelector((state: RootState) => state.auth);
  const [teamMembers, setTeamMembers] = useState<User[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedMember, setSelectedMember] = useState<User | null>(null);
  const [showEditModal, setShowEditModal] = useState(false);
  const [selectedRole, setSelectedRole] = useState<string>('');

  // Check if current user can manage team members based on permissions only
  const canManageTeam = currentUser?.permissions?.includes('users.manage') || currentUser?.permissions?.includes('users.update') || currentUser?.permissions?.includes('team.manage');

  useEffect(() => {
    loadTeamMembers();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [accountId]);

  const loadTeamMembers = async () => {
    try {
      setLoading(true);
      // Get users for current account only
      const response = await usersApi.getAccountUsers(accountId || currentUser?.account?.id);
      if (response.success) {
        setTeamMembers(response.data);
      }
    } catch (error) {
    } finally {
      setLoading(false);
    }
  };

  const handleRoleChange = async (userId: string, newRole: string) => {
    if (!currentUser?.permissions?.includes('users.update') && !currentUser?.permissions?.includes('users.manage')) {
      alert('You do not have permission to change user roles');
      return;
    }

    try {
      await usersApi.updateUserRole(userId, newRole, accountId || currentUser?.account?.id);
      loadTeamMembers();
      setShowEditModal(false);
      setSelectedMember(null);
      setSelectedRole('');
    } catch (error) {
    }
  };

  const handleRemoveMember = async (userId: string) => {
    if (!currentUser?.permissions?.includes('users.delete') && !currentUser?.permissions?.includes('users.manage')) {
      alert('You do not have permission to remove team members');
      return;
    }

    if (window.confirm('Are you sure you want to remove this team member?')) {
      try {
        await usersApi.removeFromAccount(userId, accountId || currentUser?.account?.id);
        loadTeamMembers();
      } catch (error) {
      }
    }
  };

  const getRoleBadgeColor = (role: string) => {
    if (role.includes('system.admin') || role.includes('admin')) {
      return 'bg-theme-error bg-opacity-10 text-theme-error';
    } else if (role.includes('account.manager') || role.includes('manager')) {
      return 'bg-theme-success bg-opacity-10 text-theme-success';
    } else {
      return 'bg-theme-info bg-opacity-10 text-theme-info';
    }
  };

  const formatRoleName = (role: string) => {
    return role.replace('.', ' ').replace(/\b\w/g, l => l.toUpperCase());
  };

  const getStatusBadge = (status: string) => {
    const statusColors = {
      active: 'bg-theme-success bg-opacity-10 text-theme-success',
      invited: 'bg-theme-warning bg-opacity-10 text-theme-warning',
      suspended: 'bg-theme-error bg-opacity-10 text-theme-error',
      inactive: 'bg-theme-surface text-theme-tertiary',
    };

    return (
      <span className={`text-xs px-2 py-1 rounded-full ${statusColors[status as keyof typeof statusColors] || statusColors.inactive}`}>
        {status.charAt(0).toUpperCase() + status.slice(1)}
      </span>
    );
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-theme-secondary">Loading team members...</div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Team Statistics */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <div className="bg-theme-background rounded-lg p-4">
          <h3 className="text-sm font-medium text-theme-tertiary mb-1">Total Members</h3>
          <p className="text-2xl font-bold text-theme-primary">{teamMembers.length}</p>
        </div>
        <div className="bg-theme-background rounded-lg p-4">
          <h3 className="text-sm font-medium text-theme-tertiary mb-1">Active</h3>
          <p className="text-2xl font-bold text-theme-success">
            {teamMembers.filter(m => m.status === 'active').length}
          </p>
        </div>
        <div className="bg-theme-background rounded-lg p-4">
          <h3 className="text-sm font-medium text-theme-tertiary mb-1">Admins</h3>
          <p className="text-2xl font-bold text-theme-interactive-primary">
            {teamMembers.filter(m => m.roles?.some(role => role.includes('admin') || role.includes('manager'))).length}
          </p>
        </div>
        <div className="bg-theme-background rounded-lg p-4">
          <h3 className="text-sm font-medium text-theme-tertiary mb-1">Seats Used</h3>
          <p className="text-2xl font-bold text-theme-primary">
            {teamMembers.length} / 10
          </p>
          <div className="mt-2 w-full bg-theme-surface rounded-full h-2">
            <div 
              className="bg-theme-interactive-primary h-2 rounded-full" 
              style={{ width: `${(teamMembers.length / 10) * 100}%` }} 
            />
          </div>
        </div>
      </div>

      {/* Team Members List */}
      <div className="bg-theme-background rounded-lg overflow-hidden">
        <table className="w-full">
          <thead className="bg-theme-surface border-b border-theme">
            <tr>
              <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Member</th>
              <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Role</th>
              <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Status</th>
              <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Last Active</th>
              {canManageTeam && (
                <th className="text-left py-3 px-4 text-sm font-medium text-theme-primary">Actions</th>
              )}
            </tr>
          </thead>
          <tbody className="divide-y divide-theme">
            {teamMembers.map((member) => (
              <tr key={member.id} className="hover:bg-theme-surface-hover">
                <td className="py-3 px-4">
                  <div className="flex items-center space-x-3">
                    <div className="h-8 w-8 rounded-full bg-gradient-to-br from-theme-interactive-primary to-theme-interactive-secondary flex items-center justify-center">
                      <span className="text-white text-xs font-bold">
                        {getUserInitials(member)}
                      </span>
                    </div>
                    <div>
                      <p className="font-medium text-theme-primary">
                        {member.name}
                      </p>
                      <p className="text-sm text-theme-secondary">{member.email}</p>
                    </div>
                  </div>
                </td>
                <td className="py-3 px-4">
                  {member.roles && member.roles.length > 0 ? (
                    <div className="flex flex-wrap gap-1">
                      {member.roles.slice(0, 2).map((role, index) => (
                        <span key={index} className={`text-xs px-2 py-1 rounded-full ${getRoleBadgeColor(role)}`}>
                          {formatRoleName(role)}
                        </span>
                      ))}
                      {member.roles.length > 2 && (
                        <span className="text-xs px-2 py-1 rounded-full bg-theme-surface text-theme-tertiary">
                          +{member.roles.length - 2}
                        </span>
                      )}
                    </div>
                  ) : (
                    <span className="text-xs px-2 py-1 rounded-full bg-theme-surface text-theme-tertiary">
                      No roles
                    </span>
                  )}
                </td>
                <td className="py-3 px-4">
                  {getStatusBadge(member.status)}
                </td>
                <td className="py-3 px-4 text-sm text-theme-secondary">
                  {member.last_login_at ? new Date(member.last_login_at).toLocaleDateString() : 'Never'}
                </td>
                {canManageTeam && (
                  <td className="py-3 px-4">
                    <div className="flex items-center space-x-2">
                      {member.id !== currentUser?.id && (
                        <>
                          <button
                            onClick={() => {
                              setSelectedMember(member);
                              setSelectedRole(member.roles?.[0] || 'account.member');
                              setShowEditModal(true);
                            }}className="text-theme-link hover:text-theme-link-hover text-sm"
                            disabled={!canManageTeam}
                          >
                            Edit
                          </button>
                          {(canManageTeam && member.id !== currentUser?.id) && (
                            <button
                              onClick={() => handleRemoveMember(member.id)}
                              className="text-theme-error hover:text-theme-error-hover text-sm"
                            >
                              Remove
                            </button>
                          )}
                        </>
                      )}
                    </div>
                  </td>
                )}
              </tr>
            ))}
          </tbody>
        </table>

        {teamMembers.length === 0 && (
          <div className="p-8 text-center">
            <p className="text-theme-secondary">No team members found</p>
            <p className="text-sm text-theme-tertiary mt-1">
              Invite team members to collaborate on your account
            </p>
          </div>
        )}
      </div>

      {/* Edit Role Modal */}
      {showEditModal && selectedMember && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
          <div className="bg-theme-surface rounded-lg p-6 w-full max-w-md">
            <h3 className="text-lg font-semibold text-theme-primary mb-4">
              Edit Team Member Roles
            </h3>
            <div className="mb-4">
              <p className="text-theme-secondary">
                {selectedMember.name}
              </p>
              <p className="text-sm text-theme-tertiary">{selectedMember.email}</p>
            </div>
            <div className="mb-6">
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Roles
              </label>
              <select
                className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary"
                value={selectedRole}
                onChange={(e) => setSelectedRole(e.target.value)}
              >
                <option value="system.admin">System Admin</option>
                <option value="account.manager">Account Manager</option>
                <option value="account.member">Account Member</option>
                <option value="billing.manager">Billing Manager</option>
              </select>
              <div className="mt-2 text-xs text-theme-secondary space-y-1">
                <p><strong>System Admin:</strong> Full system access across all accounts</p>
                <p><strong>Account Manager:</strong> Full account management and user administration</p>
                <p><strong>Account Member:</strong> Standard access to account resources</p>
                <p><strong>Billing Manager:</strong> Billing and payment management access</p>
              </div>
            </div>
            <div className="flex justify-end space-x-3">
              <button
                onClick={() => {
                  setShowEditModal(false);
                  setSelectedMember(null);
                }}className="btn-theme btn-theme-secondary"
              >
                Cancel
              </button>
              <button
                onClick={() => handleRoleChange(selectedMember.id, selectedRole)}
                className="btn-theme btn-theme-primary"
              >
                Save Changes
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

