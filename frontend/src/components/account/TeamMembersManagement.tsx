import React, { useState, useEffect } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store';
import { usersApi, User } from '../../services/usersApi';

interface TeamMembersManagementProps {
  accountId?: string;
}

export const TeamMembersManagement: React.FC<TeamMembersManagementProps> = ({ accountId }) => {
  const { user: currentUser } = useSelector((state: RootState) => state.auth);
  const [teamMembers, setTeamMembers] = useState<User[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedMember, setSelectedMember] = useState<User | null>(null);
  const [showEditModal, setShowEditModal] = useState(false);

  // Check if current user can manage team members (owner or admin of the account)
  const canManageTeam = currentUser?.roles.includes('owner') || currentUser?.roles.includes('admin');

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
      console.error('Failed to load team members:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleRoleChange = async (userId: string, newRoles: string[]) => {
    if (!canManageTeam) {
      alert('You do not have permission to change user roles');
      return;
    }

    try {
      await usersApi.updateUserRoles(userId, newRoles, accountId || currentUser?.account?.id);
      loadTeamMembers();
      setShowEditModal(false);
    } catch (error) {
      console.error('Failed to update user roles:', error);
    }
  };

  const handleRemoveMember = async (userId: string) => {
    if (!canManageTeam) {
      alert('You do not have permission to remove team members');
      return;
    }

    if (window.confirm('Are you sure you want to remove this team member?')) {
      try {
        await usersApi.removeFromAccount(userId, accountId || currentUser?.account?.id);
        loadTeamMembers();
      } catch (error) {
        console.error('Failed to remove team member:', error);
      }
    }
  };

  const getRoleBadge = (role: string) => {
    const roleColors = {
      owner: 'bg-theme-interactive-secondary bg-opacity-10 text-theme-interactive-secondary',
      admin: 'bg-theme-interactive-primary bg-opacity-10 text-theme-interactive-primary',
      manager: 'bg-theme-info bg-opacity-10 text-theme-info',
      member: 'bg-theme-surface text-theme-secondary',
      viewer: 'bg-theme-surface text-theme-tertiary',
    };

    return (
      <span className={`text-xs px-2 py-1 rounded-full font-medium ${roleColors[role as keyof typeof roleColors] || roleColors.member}`}>
        {role.charAt(0).toUpperCase() + role.slice(1)}
      </span>
    );
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
            {teamMembers.filter(m => m.roles.includes('admin') || m.roles.includes('owner')).length}
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
                        {member.first_name?.[0]}{member.last_name?.[0]}
                      </span>
                    </div>
                    <div>
                      <p className="font-medium text-theme-primary">
                        {member.first_name} {member.last_name}
                      </p>
                      <p className="text-sm text-theme-secondary">{member.email}</p>
                    </div>
                  </div>
                </td>
                <td className="py-3 px-4">
                  <div className="flex flex-wrap gap-1">
                    {member.roles.map(role => getRoleBadge(role)).map((badge, index) => (
                      <span key={index}>{badge}</span>
                    ))}
                  </div>
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
                              setShowEditModal(true);
                            }}
                            className="text-theme-link hover:text-theme-link-hover text-sm"
                            disabled={member.roles.includes('owner')}
                          >
                            Edit
                          </button>
                          {!member.roles.includes('owner') && (
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
              Edit Team Member Role
            </h3>
            <div className="mb-4">
              <p className="text-theme-secondary">
                {selectedMember.first_name} {selectedMember.last_name}
              </p>
              <p className="text-sm text-theme-tertiary">{selectedMember.email}</p>
            </div>
            <div className="mb-6">
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Role
              </label>
              <select
                className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary"
                defaultValue={selectedMember.roles[0] || 'member'}
                onChange={(e) => handleRoleChange(selectedMember.id, [e.target.value])}
              >
                <option value="admin">Admin</option>
                <option value="manager">Manager</option>
                <option value="member">Member</option>
                <option value="viewer">Viewer</option>
              </select>
              <div className="mt-2 text-xs text-theme-secondary space-y-1">
                <p><strong>Admin:</strong> Full account management access</p>
                <p><strong>Manager:</strong> Can manage team and billing</p>
                <p><strong>Member:</strong> Standard access to resources</p>
                <p><strong>Viewer:</strong> Read-only access</p>
              </div>
            </div>
            <div className="flex justify-end space-x-3">
              <button
                onClick={() => {
                  setShowEditModal(false);
                  setSelectedMember(null);
                }}
                className="btn-theme btn-theme-secondary"
              >
                Cancel
              </button>
              <button
                onClick={() => handleRoleChange(selectedMember.id, selectedMember.roles || ['member'])}
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

export default TeamMembersManagement;