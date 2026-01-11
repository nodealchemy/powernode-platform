import React from 'react';
import { Settings } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { FormField } from '@/shared/components/ui/FormField';
import { Modal } from '@/shared/components/ui/Modal';
import { CreateTeamMemberModalProps, EditTeamMemberModalProps, DeleteTeamMemberModalProps } from './types';

export const CreateTeamMemberModal: React.FC<CreateTeamMemberModalProps> = ({
  isOpen,
  formData,
  formErrors,
  actionLoading,
  onClose,
  onFormChange,
  onSubmit
}) => (
  <Modal
    isOpen={isOpen}
    onClose={onClose}
    title="Create New User"
    maxWidth="md"
  >
    <div className="space-y-4">
      {formErrors.length > 0 && (
        <div className="bg-theme-error-background border border-theme-error-border text-theme-error px-4 py-3 rounded">
          <ul className="list-disc list-inside">
            {formErrors.map((error, index) => (
              <li key={index}>{error}</li>
            ))}
          </ul>
        </div>
      )}

      <FormField
        label="Full Name"
        type="text"
        value={formData.name}
        onChange={(value) => onFormChange('name', value)}
        placeholder="Enter full name"
        required
      />

      <FormField
        label="Email"
        type="email"
        value={formData.email}
        onChange={(value) => onFormChange('email', value)}
        required
      />

      <FormField
        label="Phone (Optional)"
        type="tel"
        value={formData.phone}
        onChange={(value: string) => onFormChange('phone', value)}
      />

      <div className="bg-theme-info-background border border-theme-info-border rounded-lg p-4">
        <div className="flex items-center space-x-3">
          <Settings className="h-5 w-5 text-theme-info flex-shrink-0" />
          <div>
            <h4 className="font-medium text-theme-info">Default Role Assignment</h4>
            <p className="text-sm text-theme-info mt-1">
              New users will be assigned the default "Account Member" role. You can manage additional roles after creation using the "Manage Roles" button.
            </p>
          </div>
        </div>
      </div>

      <FormField
        label="Password"
        type="password"
        value={formData.password}
        onChange={(value) => onFormChange('password', value)}
        required
      />

      <FormField
        label="Confirm Password"
        type="password"
        value={formData.password_confirmation}
        onChange={(value) => onFormChange('password_confirmation', value)}
        required
      />

      <div className="flex justify-end space-x-3 mt-6">
        <Button variant="secondary" onClick={onClose}>
          Cancel
        </Button>
        <Button onClick={onSubmit} disabled={actionLoading}>
          {actionLoading ? 'Creating...' : 'Create User'}
        </Button>
      </div>
    </div>
  </Modal>
);

export const EditTeamMemberModal: React.FC<EditTeamMemberModalProps> = ({
  isOpen,
  formData,
  formErrors,
  actionLoading,
  onClose,
  onFormChange,
  onSubmit
}) => (
  <Modal
    isOpen={isOpen}
    onClose={onClose}
    title="Edit User"
    maxWidth="md"
  >
    <div className="space-y-4">
      {formErrors.length > 0 && (
        <div className="bg-theme-error-background border border-theme-error-border text-theme-error px-4 py-3 rounded">
          <ul className="list-disc list-inside">
            {formErrors.map((error, index) => (
              <li key={index}>{error}</li>
            ))}
          </ul>
        </div>
      )}

      <FormField
        label="Full Name"
        type="text"
        value={formData.name}
        onChange={(value) => onFormChange('name', value)}
        placeholder="Enter full name"
        required
      />

      <FormField
        label="Email"
        type="email"
        value={formData.email}
        onChange={(value) => onFormChange('email', value)}
        required
      />

      <FormField
        label="Phone (Optional)"
        type="tel"
        value={formData.phone}
        onChange={(value: string) => onFormChange('phone', value)}
      />

      <div className="bg-theme-warning-background border border-theme-warning-border rounded-lg p-4">
        <div className="flex items-center space-x-3">
          <Settings className="h-5 w-5 text-theme-warning flex-shrink-0" />
          <div>
            <h4 className="font-medium text-theme-warning">Role Management</h4>
            <p className="text-sm text-theme-warning mt-1">
              Use the "Manage Roles" button in the user table to modify role assignments for this user.
            </p>
          </div>
        </div>
      </div>

      <div className="flex justify-end space-x-3 mt-6">
        <Button variant="secondary" onClick={onClose}>
          Cancel
        </Button>
        <Button onClick={onSubmit} disabled={actionLoading}>
          {actionLoading ? 'Updating...' : 'Update User'}
        </Button>
      </div>
    </div>
  </Modal>
);

export const DeleteTeamMemberModal: React.FC<DeleteTeamMemberModalProps> = ({
  isOpen,
  userName,
  actionLoading,
  onClose,
  onConfirm
}) => (
  <Modal
    isOpen={isOpen}
    onClose={onClose}
    title="Delete User"
    maxWidth="sm"
  >
    <div className="text-theme-primary">
      Are you sure you want to delete <strong>{userName}</strong>?
      This action cannot be undone.
    </div>
    <div className="flex justify-end space-x-3 mt-6">
      <Button variant="secondary" onClick={onClose}>
        Cancel
      </Button>
      <Button
        variant="danger"
        onClick={onConfirm}
        disabled={actionLoading}
      >
        {actionLoading ? 'Deleting...' : 'Delete User'}
      </Button>
    </div>
  </Modal>
);
