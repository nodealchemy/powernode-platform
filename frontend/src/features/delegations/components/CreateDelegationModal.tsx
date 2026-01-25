import React, { useState, useEffect } from 'react';
import { delegationApi, Role, Permission, CreateDelegationData } from '@/features/delegations/services/delegationApi';
import { PermissionSelector } from '@/features/account/components/PermissionSelector';

interface CreateDelegationModalProps {
  onClose: () => void;
  onCreate: (data: CreateDelegationData) => void;
}

// interface Account {
//   id: string;
//   name: string;
//   domain?: string;
// }

// interface User {
//   id: string;
//   email: string;
//   firstName: string;
//   lastName: string;
//   roles: string[];
// }

export const CreateDelegationModal: React.FC<CreateDelegationModalProps> = ({ onClose, onCreate }) => {
  const [step, setStep] = useState(1);
  const [formData, setFormData] = useState({
    delegated_user_email: '',
    role_id: '',
    permission_ids: [] as string[],
    expires_at: '',
    notes: '',
  });
  const [availableRoles, setAvailableRoles] = useState<Role[]>([]);
  const [availablePermissions, setAvailablePermissions] = useState<Permission[]>([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    loadInitialData();
  }, []);

  const loadInitialData = async () => {
    try {
      setLoading(true);
      const [rolesData, permissionsData] = await Promise.all([
        delegationApi.getAvailableRoles(),
        delegationApi.getAvailablePermissions()
      ]);
      setAvailableRoles(rolesData);
      setAvailablePermissions(permissionsData);
    } catch (error) {
    } finally {
      setLoading(false);
    }
  };

  const handleRoleChange = (roleId: string) => {
    setFormData(prev => ({ ...prev, role_id: roleId }));
  };

  const handlePermissionChange = (permissionIds: string[]) => {
    setFormData(prev => ({ ...prev, permission_ids: permissionIds }));
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    onCreate(formData);
  };

  const isStepValid = () => {
    switch (step) {
      case 1:
        return formData.delegated_user_email.trim() !== '';
      case 2:
        return formData.role_id || formData.permission_ids.length > 0;
      default:
        return false;
    }
  };

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-theme-surface rounded-lg w-full max-w-2xl max-h-[90vh] overflow-hidden">
        <div className="p-6 border-b border-theme">
          <div className="flex items-center justify-between">
            <h2 className="text-xl font-semibold text-theme-primary">Create Delegation</h2>
            <button
              onClick={onClose}
              className="text-theme-secondary hover:text-theme-primary"
            >
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
          
          {/* Step Indicator */}
          <div className="flex items-center justify-center mt-6 space-x-2">
            {[1, 2].map((s) => (
              <React.Fragment key={s}>
                <div className={`flex items-center justify-center w-8 h-8 rounded-full ${
                  s === step ? 'bg-theme-interactive-primary text-white' :
                  s < step ? 'bg-theme-success text-white' :
                  'bg-theme-surface-hover text-theme-secondary'
                }`}>
                  {s < step ? '✓' : s}
                </div>
                {s < 2 && (
                  <div className={`w-16 h-1 ${
                    s < step ? 'bg-theme-success' : 'bg-theme-surface-hover'
                  }`} />
                )}
              </React.Fragment>
            ))}
          </div>
          <div className="flex justify-center mt-2 text-sm text-theme-secondary">
            {step === 1 && 'Delegation Details'}
            {step === 2 && 'Roles & Permissions'}
          </div>
        </div>

        <form onSubmit={handleSubmit} className="p-6 overflow-y-auto max-h-[calc(90vh-200px)]">
          {/* Step 1: Delegation Details */}
          {step === 1 && (
            <div className="space-y-6">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  User Email
                </label>
                <input
                  type="email"
                  value={formData.delegated_user_email}
                  onChange={(e) => setFormData({ ...formData, delegated_user_email: e.target.value })}
                  className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary"
                  placeholder="Enter the email address of the user to delegate to"
                  required
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Expiration Date (Optional)
                </label>
                <input
                  type="datetime-local"
                  value={formData.expires_at}
                  onChange={(e) => setFormData({ ...formData, expires_at: e.target.value })}
                  className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary"
                />
                <p className="text-xs text-theme-secondary mt-1">
                  Leave empty for no expiration
                </p>
              </div>

              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Notes (Optional)
                </label>
                <textarea
                  value={formData.notes}
                  onChange={(e) => setFormData({ ...formData, notes: e.target.value })}
                  className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary"
                  rows={3}
                  placeholder="Add any notes about this delegation..."
                />
              </div>
            </div>
          )}

          {/* Step 2: Roles & Permissions */}
          {step === 2 && (
            <div className="space-y-6">
              <div>
                <h3 className="text-lg font-medium text-theme-primary mb-4">Roles & Permissions</h3>
                <p className="text-sm text-theme-secondary mb-6">
                  Select a role or specific permissions to delegate to the user
                </p>
                
                <PermissionSelector
                  selectedRoleId={formData.role_id}
                  selectedPermissionIds={formData.permission_ids}
                  onRoleChange={handleRoleChange}
                  onPermissionChange={handlePermissionChange}
                  availableRoles={availableRoles}
                  availablePermissions={availablePermissions}
                  loading={loading}
                  mode="both"
                />
              </div>
            </div>
          )}
        </form>

        <div className="p-6 border-t border-theme bg-theme-background">
          <div className="flex justify-between">
            <button
              type="button"
              onClick={() => step > 1 ? setStep(step - 1) : onClose()}
              className="px-4 py-2 text-theme-secondary border border-theme rounded-lg hover:bg-theme-surface-hover transition-colors"
            >
              {step === 1 ? 'Cancel' : 'Back'}
            </button>
            <button
              type="button"
              onClick={() => {
                if (step < 2 && isStepValid()) {
                  setStep(step + 1);
                } else if (step === 2 && isStepValid()) {
                  onCreate(formData);
                }
              }}
              disabled={!isStepValid() || loading}
              className="px-4 py-2 bg-theme-interactive-primary text-white rounded-lg hover:bg-theme-interactive-primary-hover disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              {loading ? 'Loading...' : step === 2 ? 'Create Delegation' : 'Next'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};