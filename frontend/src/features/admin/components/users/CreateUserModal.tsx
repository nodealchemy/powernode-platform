import React, { useState, useEffect } from 'react';
import { usersApi, UserFormData, AdminAccount } from '@/features/users/services/usersApi';

interface CreateUserModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
  accounts: AdminAccount[];
}

export const CreateUserModal: React.FC<CreateUserModalProps> = ({
  isOpen,
  onClose,
  onSuccess,
  accounts
}) => {
  const [formData, setFormData] = useState<UserFormData & { account_id: string }>({
    name: '',
    email: '',
    phone: '',
    roles: ['account.member'],
    account_id: ''
  });
  
  const [loading, setLoading] = useState(false);
  const [errors, setErrors] = useState<string[]>([]);
  const [availableRoles, setAvailableRoles] = useState<Array<{ value: string; label: string; description: string }>>([]);
  const [rolesLoading, setRolesLoading] = useState(true);

  // Load available roles
  useEffect(() => {
    const loadRoles = async () => {
      if (isOpen) {
        try {
          setRolesLoading(true);
          const roles = await usersApi.getAvailableRoles();
          setAvailableRoles(roles);
        } catch (error) {
          setAvailableRoles([]);
        } finally {
          setRolesLoading(false);
        }
      }
    };
    loadRoles();
  }, [isOpen]);

  const handleInputChange = (field: keyof typeof formData, value: string) => {
    setFormData(prev => ({
      ...prev,
      [field]: value
    }));
    setErrors([]);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    
    // Validate form data
    const validationErrors = usersApi.validateUserData(formData);
    if (!formData.account_id) {
      validationErrors.push('Account selection is required');
    }
    
    if (validationErrors.length > 0) {
      setErrors(validationErrors);
      return;
    }

    try {
      setLoading(true);
      setErrors([]);
      
      await usersApi.createAdminUser(formData);
      
      // Reset form
      setFormData({
        name: '',
        email: '',
        phone: '',
        roles: ['account.member'],
        account_id: ''
      });
      
      onSuccess();
      onClose();
    } catch (error: any) {
      const errorMessage = error.response?.data?.error || error.message || 'Failed to create user';
      const validationErrors = error.response?.data?.validation_errors || [];
      setErrors([errorMessage, ...validationErrors]);
    } finally {
      setLoading(false);
    }
  };

  const handleCancel = () => {
    setFormData({
      name: '',
      email: '',
      phone: '',
      roles: ['account.member'],
      account_id: ''
    });
    setErrors([]);
    onClose();
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-theme-surface rounded-lg p-6 w-full max-w-2xl max-h-[90vh] overflow-y-auto">
        <div className="flex justify-between items-center mb-6">
          <h3 className="text-lg font-semibold text-theme-primary">Create New User</h3>
          <button
            onClick={handleCancel}
            className="text-theme-secondary hover:text-theme-primary"
            disabled={loading}
          >
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {errors.length > 0 && (
          <div className="bg-theme-error bg-opacity-10 border border-theme-error border-opacity-30 rounded-lg p-4 mb-6">
            <h4 className="font-medium text-theme-error mb-2">Please correct the following errors:</h4>
            <ul className="list-disc list-inside space-y-1">
              {errors.map((error, index) => (
                <li key={index} className="text-theme-error text-sm">{error}</li>
              ))}
            </ul>
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-6">
          {/* Account Selection */}
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Account <span className="text-theme-error">*</span>
            </label>
            <select
              value={formData.account_id}
              onChange={(e) => handleInputChange('account_id', e.target.value)}
              className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
              required
              disabled={loading}
            >
              <option value="">Select an account...</option>
              {accounts.map(account => (
                <option key={account.id} value={account.id}>
                  {account.name} ({account.status})
                </option>
              ))}
            </select>
          </div>

          {/* Personal Information */}
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Full Name <span className="text-theme-error">*</span>
            </label>
            <input
              type="text"
              value={formData.name}
              onChange={(e) => handleInputChange('name', e.target.value)}
              placeholder="Enter full name"
              className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
              required
              disabled={loading}
            />
          </div>

          {/* Email */}
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Email Address <span className="text-theme-error">*</span>
            </label>
            <input
              type="email"
              value={formData.email}
              onChange={(e) => handleInputChange('email', e.target.value)}
              className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
              required
              disabled={loading}
            />
          </div>

          {/* Phone */}
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Phone Number
            </label>
            <input
              type="tel"
              value={formData.phone}
              onChange={(e) => handleInputChange('phone', e.target.value)}
              className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
              disabled={loading}
            />
          </div>

          {/* Role Selection */}
          <div>
            <label className="block text-sm font-medium text-theme-primary mb-2">
              Role <span className="text-theme-error">*</span>
            </label>
            <select
              value={formData.roles[0] || ''}
              onChange={(e) => setFormData(prev => ({ ...prev, roles: [e.target.value] }))}
              className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent"
              required
              disabled={loading || rolesLoading}
            >
              {rolesLoading ? (
                <option value="">Loading roles...</option>
              ) : availableRoles.length === 0 ? (
                <option value="">No roles available</option>
              ) : (
                availableRoles.map(role => (
                  <option key={role.value} value={role.value}>
                    {role.label}
                  </option>
                ))
              )}
            </select>
            <p className="text-sm text-theme-secondary mt-1">
              {rolesLoading ? 'Loading...' : availableRoles.find(r => r.value === formData.roles[0])?.description || 'Select a role to see description'}
            </p>
          </div>

          {/* Information Note */}
          <div className="bg-theme-info bg-opacity-10 border border-theme-info border-opacity-30 rounded-lg p-4">
            <div className="flex items-start space-x-3">
              <span className="text-theme-info text-xl">ℹ️</span>
              <div>
                <h4 className="font-medium text-theme-info mb-1">Account Setup</h4>
                <p className="text-theme-info opacity-80 text-sm">
                  A temporary password will be generated and sent to the user's email address. 
                  They will be prompted to change it on first login.
                </p>
              </div>
            </div>
          </div>

          {/* Form Actions */}
          <div className="flex justify-end space-x-3 pt-6 border-t border-theme">
            <button
              type="button"
              onClick={handleCancel}
              className="btn-theme btn-theme-secondary"
              disabled={loading}
            >
              Cancel
            </button>
            <button
              type="submit"
              className="btn-theme btn-theme-primary"
              disabled={loading}
            >
              {loading ? (
                <span className="flex items-center space-x-2">
                  <svg className="animate-spin -ml-1 mr-2 h-4 w-4" fill="none" viewBox="0 0 24 24">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                  Creating...
                </span>
              ) : (
                'Create User'
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

