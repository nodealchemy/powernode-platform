import React, { useState, useEffect } from 'react';
import { User, Calendar, Shield, AlertCircle, Plus, Trash2, UserCheck, UserX } from 'lucide-react';

interface DelegatedUser {
  id: string;
  email: string;
  full_name: string;
}

interface Delegation {
  id: string;
  account: {
    id: string;
    name: string;
    subdomain: string;
  };
  delegated_user: DelegatedUser;
  delegated_by: DelegatedUser;
  role: string;
  status: string;
  expires_at: string | null;
  revoked_at: string | null;
  revoked_by: DelegatedUser | null;
  notes: string | null;
  is_active: boolean;
  is_expired: boolean;
  created_at: string;
  updated_at: string;
}

interface DelegationFormData {
  delegated_user_email: string;
  role: string;
  expires_at: string;
  notes: string;
}

export const DelegationsManagement: React.FC = () => {
DelegationsManagement.displayName = 'DelegationsManagement';
  const [delegations, setDelegations] = useState<Delegation[]>([]);
  const [showCreateForm, setShowCreateForm] = useState(false);
  // const [editingDelegation] = useState<Delegation | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  
  // Available roles for delegation (excluding admin which is system-only)
  const availableRoles = ['manager', 'member'];
  
  const [formData, setFormData] = useState<DelegationFormData>({
    delegated_user_email: '',
    role: '',
    expires_at: '',
    notes: ''
  });

  useEffect(() => {
    loadDelegations();
  }, []);

  const loadDelegations = async () => {
    try {
      setLoading(true);
      const token = localStorage.getItem('auth_token');
      const response = await fetch('/api/v1/accounts/current/delegations', {
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        }
      });
      
      if (response.ok) {
        const data = await response.json();
        setDelegations(data.delegations);
      } else {
        setError('Failed to load delegations');
      }
    } catch (err) {
      setError('Error loading delegations');
      console.error('Error loading delegations:', err);
    } finally {
      setLoading(false);
    }
  };


  const handleCreateDelegation = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      const token = localStorage.getItem('auth_token');
      const response = await fetch('/api/v1/accounts/current/delegations', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ delegation: formData })
      });
      
      if (response.ok) {
        setShowCreateForm(false);
        setFormData({
          delegated_user_email: '',
          role: '',
          expires_at: '',
          notes: ''
        });
        loadDelegations();
      } else {
        const error = await response.json();
        setError(error.message || 'Failed to create delegation');
      }
    } catch (err) {
      setError('Error creating delegation');
      console.error('Error creating delegation:', err);
    }
  };

  // TODO: Implement update delegation UI
  // const handleUpdateDelegation = async (delegationId: string, updates: Partial<DelegationFormData>) => {
  //   try {
  //     const token = localStorage.getItem('auth_token');
  //     const response = await fetch(`/api/v1/accounts/current/delegations/${delegationId}`, {
  //       method: 'PATCH',
  //       headers: {
  //         'Authorization': `Bearer ${token}`,
  //         'Content-Type': 'application/json'
  //       },
  //       body: JSON.stringify({ delegation: updates })
  //     });
  //     
  //     if (response.ok) {
  //       // setEditingDelegation(null);
  //       loadDelegations();
  //     } else {
  //       setError('Failed to update delegation');
  //     }
  //   } catch (err) {
  //     setError('Error updating delegation');
  //     console.error('Error updating delegation:', err);
  //   }
  // };

  const handleDelegationAction = async (delegationId: string, action: 'activate' | 'deactivate' | 'revoke') => {
    try {
      const token = localStorage.getItem('auth_token');
      const response = await fetch(`/api/v1/accounts/current/delegations/${delegationId}/${action}`, {
        method: 'PATCH',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        }
      });
      
      if (response.ok) {
        loadDelegations();
      } else {
        setError(`Failed to ${action} delegation`);
      }
    } catch (err) {
      setError(`Error ${action}ing delegation`);
      console.error(`Error ${action}ing delegation:`, err);
    }
  };

  const getStatusColor = (delegation: Delegation) => {
    if (delegation.status === 'revoked') return 'text-theme-error bg-theme-error-background';
    if (delegation.is_expired) return 'text-theme-warning bg-theme-warning-background';
    if (delegation.status === 'inactive') return 'text-theme-secondary bg-theme-surface';
    if (delegation.is_active) return 'text-theme-success bg-theme-success-background';
    return 'text-theme-secondary bg-theme-surface';
  };

  const getRoleColor = (roleName: string) => {
    switch (roleName.toLowerCase()) {
      case 'admin': return 'bg-theme-error bg-opacity-10 text-theme-error';
      case 'manager': return 'bg-theme-success bg-opacity-10 text-theme-success';
      case 'member': return 'bg-theme-info bg-opacity-10 text-theme-info';
      default: return 'bg-theme-info bg-opacity-10 text-theme-info';
    }
  };

  const formatDate = (dateString: string | null) => {
    if (!dateString) return 'Never';
    return new Date(dateString).toLocaleDateString('en-US', {
      year: 'numeric',
      month: 'short',
      day: 'numeric'
    });
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center p-8">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-primary"></div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold text-theme-primary">Account Delegations</h2>
          <p className="text-theme-secondary mt-1">
            Manage access delegation for external users and consultants
          </p>
        </div>
        <button
          onClick={() => setShowCreateForm(true)}
          className="bg-theme-interactive-primary text-white px-4 py-2 rounded-lg hover:bg-theme-interactive-primary-hover transition-colors flex items-center gap-2"
        >
          <Plus className="w-4 h-4" />
          Create Delegation
        </button>
      </div>

      {error && (
        <div className="bg-theme-error-background border border-theme-error-border rounded-lg p-4 flex items-center gap-2 text-theme-error">
          <AlertCircle className="w-5 h-5" />
          {error}
          <button
            onClick={() => setError(null)}
            className="ml-auto text-theme-error hover:text-theme-error"
          >
            ×
          </button>
        </div>
      )}

      {/* Create Delegation Form */}
      {showCreateForm && (
        <div className="bg-theme-surface border border-theme rounded-lg p-6">
          <h3 className="text-lg font-semibold text-theme-primary mb-4">Create New Delegation</h3>
          <form onSubmit={handleCreateDelegation} className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-theme-secondary mb-1">
                User Email
              </label>
              <input
                type="email"
                value={formData.delegated_user_email}
                onChange={(e) => setFormData({ ...formData, delegated_user_email: e.target.value })}
                className="w-full px-3 py-2 border border-theme rounded-lg focus:ring-2 focus:ring-theme-focus focus:border-transparent bg-theme-background"
                placeholder="Enter user email address"
                required
              />
            </div>
            
            <div>
              <label className="block text-sm font-medium text-theme-secondary mb-1">
                Role
              </label>
              <select
                value={formData.role}
                onChange={(e) => setFormData({ ...formData, role: e.target.value })}
                className="w-full px-3 py-2 border border-theme rounded-lg focus:ring-2 focus:ring-theme-focus focus:border-transparent bg-theme-background"
                required
              >
                <option value="">Select a role</option>
                {availableRoles.map(role => (
                  <option key={role} value={role}>
                    {role.charAt(0).toUpperCase() + role.slice(1)}
                  </option>
                ))}
              </select>
            </div>
            
            <div>
              <label className="block text-sm font-medium text-theme-secondary mb-1">
                Expires At (Optional)
              </label>
              <input
                type="datetime-local"
                value={formData.expires_at}
                onChange={(e) => setFormData({ ...formData, expires_at: e.target.value })}
                className="w-full px-3 py-2 border border-theme rounded-lg focus:ring-2 focus:ring-theme-focus focus:border-transparent bg-theme-background"
              />
            </div>
            
            <div>
              <label className="block text-sm font-medium text-theme-secondary mb-1">
                Notes (Optional)
              </label>
              <textarea
                value={formData.notes}
                onChange={(e) => setFormData({ ...formData, notes: e.target.value })}
                className="w-full px-3 py-2 border border-theme rounded-lg focus:ring-2 focus:ring-theme-focus focus:border-transparent bg-theme-background"
                rows={3}
                placeholder="Add any notes about this delegation"
              />
            </div>
            
            <div className="flex gap-2">
              <button
                type="submit"
                className="bg-theme-interactive-primary text-white px-4 py-2 rounded-lg hover:bg-theme-interactive-primary-hover transition-colors"
              >
                Create Delegation
              </button>
              <button
                type="button"
                onClick={() => setShowCreateForm(false)}
                className="bg-theme-surface text-theme-secondary px-4 py-2 rounded-lg hover:bg-theme-surface-hover transition-colors"
              >
                Cancel
              </button>
            </div>
          </form>
        </div>
      )}

      {/* Delegations List */}
      <div className="bg-theme-surface border border-theme rounded-lg overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-theme-surface">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">
                  User
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">
                  Role
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">
                  Status
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">
                  Expires
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-theme-tertiary uppercase tracking-wider">
                  Actions
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-200">
              {delegations.map(delegation => (
                <tr key={delegation.id} className="hover:bg-theme-surface">
                  <td className="px-6 py-4">
                    <div className="flex items-center gap-3">
                      <div className="w-8 h-8 bg-theme-interactive-primary rounded-full flex items-center justify-center">
                        <User className="w-4 h-4 text-white" />
                      </div>
                      <div>
                        <div className="font-medium text-theme-primary">{delegation.delegated_user.full_name}</div>
                        <div className="text-sm text-theme-secondary">{delegation.delegated_user.email}</div>
                      </div>
                    </div>
                  </td>
                  <td className="px-6 py-4">
                    {delegation.role ? (
                      <span className={`inline-flex items-center px-2 py-1 rounded-full text-xs ${getRoleColor(delegation.role)}`}>
                        <Shield className="w-3 h-3 mr-1" />
                        {delegation.role.charAt(0).toUpperCase() + delegation.role.slice(1)}
                      </span>
                    ) : (
                      <span className="text-theme-tertiary">No Role</span>
                    )}
                  </td>
                  <td className="px-6 py-4">
                    <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${getStatusColor(delegation)}`}>
                      {delegation.is_expired ? 'Expired' : delegation.status.charAt(0).toUpperCase() + delegation.status.slice(1)}
                    </span>
                  </td>
                  <td className="px-6 py-4 text-sm text-theme-secondary">
                    <div className="flex items-center gap-1">
                      <Calendar className="w-4 h-4" />
                      {formatDate(delegation.expires_at)}
                    </div>
                  </td>
                  <td className="px-6 py-4">
                    <div className="flex items-center gap-2">
                      {delegation.status === 'active' && !delegation.is_expired && (
                        <button
                          onClick={() => handleDelegationAction(delegation.id, 'deactivate')}
                          className="text-orange-600 hover:text-orange-800"
                          title="Deactivate"
                        >
                          <UserX className="w-4 h-4" />
                        </button>
                      )}
                      {delegation.status === 'inactive' && (
                        <button
                          onClick={() => handleDelegationAction(delegation.id, 'activate')}
                          className="text-theme-success hover:text-theme-success"
                          title="Activate"
                        >
                          <UserCheck className="w-4 h-4" />
                        </button>
                      )}
                      {delegation.status !== 'revoked' && (
                        <>
                          {/* TODO: Implement edit delegation functionality */}
                          <button
                            onClick={() => handleDelegationAction(delegation.id, 'revoke')}
                            className="text-theme-error hover:text-theme-error"
                            title="Revoke"
                          >
                            <Trash2 className="w-4 h-4" />
                          </button>
                        </>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          
          {delegations.length === 0 && (
            <div className="text-center py-12">
              <User className="w-12 h-12 text-theme-tertiary mx-auto mb-4" />
              <p className="text-theme-secondary">No delegations found</p>
              <p className="text-sm text-theme-tertiary mt-1">
                Create your first delegation to give external users access to your account
              </p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
};