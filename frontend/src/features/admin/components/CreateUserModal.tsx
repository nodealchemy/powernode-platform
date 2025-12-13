import React, { useState, useEffect } from 'react';
import { usersApi, UserFormData, AdminAccount } from '@/features/users/services/usersApi';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
// Removed unused FormField import
import { useForm, FormValidationRules } from '@/shared/hooks/useForm';
import { UserPlus, Save } from 'lucide-react';

interface CreateUserModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => Promise<void>;
  accounts: AdminAccount[];
}

interface CreateUserFormData extends UserFormData {
  account_id: string;
}

export const CreateUserModal: React.FC<CreateUserModalProps> = ({
  isOpen,
  onClose,
  onSuccess,
  accounts
}) => {
  const [availableRoles, setAvailableRoles] = useState<Array<{ value: string; label: string; description: string }>>([]);
  const [rolesLoading, setRolesLoading] = useState(true);

  const defaultValues: CreateUserFormData = {
    name: '',
    email: '',
    phone: '',
    roles: ['account.member'],
    account_id: ''
  };

  const validationRules: FormValidationRules = {
    name: {
      required: true,
      minLength: 2,
      maxLength: 100,
    },
    email: {
      required: true,
      pattern: /^[^\s@]+@[^\s@]+\.[^\s@]+$/,
    },
    phone: {
      maxLength: 20,
    },
    account_id: {
      required: true,
    },
    roles: {
      custom: (value: unknown) => {
        const roles = value as string[];
        if (!roles || roles.length === 0) {
          return 'At least one role must be selected';
        }
        return null;
      }
    }
  };

  const handleCreateUser = async (formData: CreateUserFormData) => {
    await usersApi.createAdminUser(formData);
    await onSuccess();
    onClose();
  };

  const form = useForm<CreateUserFormData>({
    initialValues: defaultValues,
    validationRules,
    onSubmit: handleCreateUser,
    enableRealTimeValidation: true,
    showSuccessNotification: true,
    successMessage: 'User created successfully',
    resetAfterSubmit: true,
  });

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

  // Reset form when modal opens
  useEffect(() => {
    if (isOpen) {
      form.reset();
    }
  }, [isOpen, form]);
  const handleCancel = () => {
    form.reset();
    onClose();
  };

  const modalFooter = (
    <div className="flex justify-end space-x-3">
      <Button
        variant="secondary"
        onClick={handleCancel}
        disabled={form.isSubmitting}
      >
        Cancel
      </Button>
      <Button
        variant="primary"
        type="submit"
        form="create-user-form"
        loading={form.isSubmitting}
      >
        {!form.isSubmitting && <Save className="w-4 h-4 mr-2" />}
        {form.isSubmitting ? 'Creating...' : 'Create User'}
      </Button>
    </div>
  );

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleCancel}
      title="Create New User"
      subtitle="Add a new user to the system"
      icon={<UserPlus />}
      maxWidth="2xl"
      footer={modalFooter}
      closeOnBackdrop={!form.isSubmitting}
      closeOnEscape={!form.isSubmitting}
    >
      <form id="create-user-form" onSubmit={form.handleSubmit} className="space-y-6">
        {/* Account Selection */}
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-2">
            Account <span className="text-theme-error">*</span>
          </label>
          <select
            {...form.getFieldProps('account_id')}
            className={`w-full px-3 py-2 border rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent ${
              form.errors.account_id ? 'border-theme-error' : 'border-theme'
            }`}
            required
            disabled={form.isSubmitting}
          >
            <option value="">Select an account...</option>
            {accounts.map(account => (
              <option key={account.id} value={account.id}>
                {account.name} ({account.status})
              </option>
            ))}
          </select>
          {form.errors.account_id && (
            <p className="text-theme-error text-sm mt-1">{form.errors.account_id}</p>
          )}
        </div>

        {/* Personal Information */}
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-2">
            Full Name <span className="text-theme-error">*</span>
          </label>
          <input
            type="text"
            {...form.getFieldProps('name')}
            required
            disabled={form.isSubmitting}
            placeholder="John Doe"
            className={`w-full px-3 py-2 border rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent ${form.errors.name ? 'border-theme-error' : 'border-theme'}`}
          />
          {form.errors.name && (
            <p className="text-theme-error text-sm mt-1">{form.errors.name}</p>
          )}
        </div>

        {/* Email */}
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-2">
            Email Address <span className="text-theme-error">*</span>
          </label>
          <input type="email" {...form.getFieldProps('email')} required disabled={form.isSubmitting} className={`w-full px-3 py-2 border rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent ${form.errors.email ? 'border-theme-error' : 'border-theme'}`} />
          {form.errors.email && (
            <p className="text-theme-error text-sm mt-1">{form.errors.email}</p>
          )}
        </div>

        {/* Phone */}
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-2">
            Phone Number
          </label>
          <input type="tel" {...form.getFieldProps('phone')} disabled={form.isSubmitting} className={`w-full px-3 py-2 border rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent ${form.errors.phone ? 'border-theme-error' : 'border-theme'}`} />
          {form.errors.phone && (
            <p className="text-theme-error text-sm mt-1">{form.errors.phone}</p>
          )}
        </div>

        {/* Role Selection */}
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-2">
            Role <span className="text-theme-error">*</span>
          </label>
          <select
            value={form.values.roles[0] || ''}
            onChange={(e) => form.setValue('roles', [e.target.value])}
            onBlur={form.handleBlur}
            name="roles"
            className={`w-full px-3 py-2 border rounded-lg bg-theme-background text-theme-primary focus:ring-2 focus:ring-theme-interactive-primary focus:border-transparent ${
              form.errors.roles ? 'border-theme-error' : 'border-theme'
            }`}
            required
            disabled={form.isSubmitting || rolesLoading}
          >
            <option value="">Select a role...</option>
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
            {rolesLoading ? 'Loading...' : availableRoles.find(r => r.value === form.values.roles[0])?.description || 'Select a role to see description'}
          </p>
          {form.errors.roles && (
            <p className="text-theme-error text-sm mt-1">{form.errors.roles}</p>
          )}
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
      </form>
    </Modal>
  );
};

