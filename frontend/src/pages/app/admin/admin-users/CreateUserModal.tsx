import React from 'react';
import { Button } from '@/shared/components/ui/Button';
import { Modal } from '@/shared/components/ui/Modal';
import { CreateUserModalProps } from './types';

export const CreateUserModal: React.FC<CreateUserModalProps> = ({
  isOpen,
  formData,
  formErrors,
  actionLoading,
  availableRoles,
  rolesLoading,
  onClose,
  onFormChange,
  onRolesChange,
  onSubmit
}) => (
  <Modal
    isOpen={isOpen}
    onClose={onClose}
    title="Create New User"
    maxWidth="md"
  >
    <div className="space-y-6 p-1">
      {formErrors.length > 0 && (
        <div className="bg-theme-error-background border border-theme-error-border text-theme-error px-4 py-3 rounded">
          <ul className="list-disc list-inside">
            {formErrors.map((error, index) => (
              <li key={index}>{error}</li>
            ))}
          </ul>
        </div>
      )}

      <div className="bg-theme-background border border-theme rounded-xl p-6 space-y-5">
        <div className="space-y-2">
          <label className="block text-sm font-semibold text-theme-primary">
            Full Name <span className="text-theme-error">*</span>
          </label>
          <input
            type="text"
            value={formData.name}
            onChange={(e) => onFormChange('name', e.target.value)}
            className="w-full px-4 py-3 bg-theme-surface border-2 border-theme rounded-lg text-theme-primary placeholder-theme-tertiary focus:outline-none focus:border-theme-interactive-primary focus:bg-theme-background transition-all duration-200"
            placeholder="Enter full name"
            required
          />
        </div>

        <div className="space-y-2">
          <label className="block text-sm font-semibold text-theme-primary">
            Email Address <span className="text-theme-error">*</span>
          </label>
          <input
            type="email"
            value={formData.email}
            onChange={(e) => onFormChange('email', e.target.value)}
            className="w-full px-4 py-3 bg-theme-surface border-2 border-theme rounded-lg text-theme-primary placeholder-theme-tertiary focus:outline-none focus:border-theme-interactive-primary focus:bg-theme-background transition-all duration-200"
            placeholder="Enter email address"
            required
          />
        </div>

        <div className="space-y-2">
          <label className="block text-sm font-semibold text-theme-primary">
            Phone Number
          </label>
          <input
            type="tel"
            value={formData.phone || ''}
            onChange={(e) => onFormChange('phone', e.target.value)}
            className="w-full px-4 py-3 bg-theme-surface border-2 border-theme rounded-lg text-theme-primary placeholder-theme-tertiary focus:outline-none focus:border-theme-interactive-primary focus:bg-theme-background transition-all duration-200"
            placeholder="Enter phone number (optional)"
          />
        </div>

        <div className="space-y-2">
          <label className="block text-sm font-semibold text-theme-primary">
            Roles <span className="text-theme-error">*</span>
            {rolesLoading && <span className="text-xs text-theme-secondary ml-2">(Loading...)</span>}
          </label>
          {rolesLoading ? (
            <div className="w-full px-4 py-3 bg-theme-surface border-2 border-theme rounded-lg flex items-center justify-center text-theme-secondary">
              <svg className="animate-spin h-4 w-4 mr-2" fill="none" viewBox="0 0 24 24">
                <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
              </svg>
              Loading roles...
            </div>
          ) : (
            <select
              value={formData.roles?.[0] || (availableRoles[0]?.value || 'account.member')}
              onChange={(e) => onRolesChange([e.target.value])}
              className="w-full px-4 py-3 bg-theme-surface border-2 border-theme rounded-lg text-theme-primary focus:outline-none focus:border-theme-interactive-primary focus:bg-theme-background transition-all duration-200 appearance-none cursor-pointer"
              required
              disabled={availableRoles.length === 0}
            >
              {availableRoles.length === 0 ? (
                <option value="">No roles available</option>
              ) : (
                availableRoles.map(role => (
                  <option key={role.value} value={role.value}>
                    {role.label}
                  </option>
                ))
              )}
            </select>
          )}
        </div>

        <div className="grid grid-cols-2 gap-4">
          <div className="space-y-2">
            <label className="block text-sm font-semibold text-theme-primary">
              Password <span className="text-theme-error">*</span>
            </label>
            <input
              type="password"
              value={formData.password}
              onChange={(e) => onFormChange('password', e.target.value)}
              className="w-full px-4 py-3 bg-theme-surface border-2 border-theme rounded-lg text-theme-primary placeholder-theme-tertiary focus:outline-none focus:border-theme-interactive-primary focus:bg-theme-background transition-all duration-200"
              placeholder="Enter password"
              required
            />
          </div>
          <div className="space-y-2">
            <label className="block text-sm font-semibold text-theme-primary">
              Confirm Password <span className="text-theme-error">*</span>
            </label>
            <input
              type="password"
              value={formData.password_confirmation}
              onChange={(e) => onFormChange('password_confirmation', e.target.value)}
              className="w-full px-4 py-3 bg-theme-surface border-2 border-theme rounded-lg text-theme-primary placeholder-theme-tertiary focus:outline-none focus:border-theme-interactive-primary focus:bg-theme-background transition-all duration-200"
              placeholder="Confirm password"
              required
            />
          </div>
        </div>
      </div>

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
