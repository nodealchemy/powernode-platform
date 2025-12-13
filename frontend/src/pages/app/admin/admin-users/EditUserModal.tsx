import React from 'react';
import { Button } from '@/shared/components/ui/Button';
import { Modal } from '@/shared/components/ui/Modal';
import { EditUserModalProps } from './types';

export const EditUserModal: React.FC<EditUserModalProps> = ({
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
    title="Edit User Profile"
    maxWidth="4xl"
    variant="centered"
  >
    <div className="space-y-8 p-2">
      {formErrors.length > 0 && (
        <div className="bg-theme-error-background border border-theme-error-border text-theme-error px-4 py-3 rounded">
          <ul className="list-disc list-inside">
            {formErrors.map((error, index) => (
              <li key={index}>{error}</li>
            ))}
          </ul>
        </div>
      )}

      <div className="space-y-8">
        {/* Personal Information Section */}
        <div className="bg-theme-background border-2 border-theme rounded-2xl p-8">
          <div className="flex items-center space-x-3 mb-6">
            <div className="relative">
              <div className="absolute inset-0 bg-gradient-to-br from-theme-interactive-primary/15 to-theme-interactive-primary/5 rounded-xl blur-md"></div>
              <div className="relative w-10 h-10 bg-theme-surface/50 backdrop-blur-sm rounded-xl flex items-center justify-center">
                <svg className="w-5 h-5 text-theme-interactive-primary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
                </svg>
              </div>
            </div>
            <div>
              <h3 className="text-lg font-semibold text-theme-primary">Personal Information</h3>
              <p className="text-sm text-theme-secondary">Update the user's basic profile information</p>
            </div>
          </div>

          <div className="space-y-6">
            <div className="space-y-3">
              <label className="block text-sm font-semibold text-theme-primary">
                Full Name <span className="text-theme-error">*</span>
              </label>
              <input
                type="text"
                value={formData.name}
                onChange={(e) => onFormChange('name', e.target.value)}
                className="w-full px-4 py-4 bg-theme-surface border-2 border-theme rounded-xl text-theme-primary placeholder-theme-tertiary focus:outline-none focus:border-theme-interactive-primary focus:bg-theme-background focus:shadow-lg transition-all duration-300"
                placeholder="Enter full name"
                required
              />
            </div>

            <div className="space-y-3">
              <label className="block text-sm font-semibold text-theme-primary">
                Email Address <span className="text-theme-error">*</span>
              </label>
              <div className="relative">
                <input
                  type="email"
                  value={formData.email}
                  onChange={(e) => onFormChange('email', e.target.value)}
                  className="w-full pl-12 pr-4 py-4 bg-theme-surface border-2 border-theme rounded-xl text-theme-primary placeholder-theme-tertiary focus:outline-none focus:border-theme-interactive-primary focus:bg-theme-background focus:shadow-lg transition-all duration-300"
                  placeholder="Enter email address"
                  required
                />
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none">
                  <svg className="h-5 w-5 text-theme-tertiary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M16 12a4 4 0 10-8 0 4 4 0 008 0zm0 0v1.5a2.5 2.5 0 005 0V12a9 9 0 10-9 9m4.5-1.206a8.959 8.959 0 01-4.5 1.207" />
                  </svg>
                </div>
              </div>
            </div>

            <div className="space-y-3">
              <label className="block text-sm font-semibold text-theme-primary">
                Phone Number
              </label>
              <div className="relative">
                <input
                  type="tel"
                  value={formData.phone || ''}
                  onChange={(e) => onFormChange('phone', e.target.value)}
                  className="w-full pl-12 pr-4 py-4 bg-theme-surface border-2 border-theme rounded-xl text-theme-primary placeholder-theme-tertiary focus:outline-none focus:border-theme-interactive-primary focus:bg-theme-background focus:shadow-lg transition-all duration-300"
                  placeholder="Enter phone number (optional)"
                />
                <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none">
                  <svg className="h-5 w-5 text-theme-tertiary" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z" />
                  </svg>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Footer Actions */}
      <div className="flex items-center justify-between pt-8 mt-8 border-t-2 border-theme">
        <div className="text-sm text-theme-secondary">
          Make sure all information is accurate before updating the user profile.
        </div>
        <div className="flex space-x-4">
          <Button
            variant="secondary"
            size="lg"
            onClick={onClose}
            className="px-8"
          >
            Cancel
          </Button>
          <Button
            variant="primary"
            size="lg"
            onClick={onSubmit}
            disabled={actionLoading}
            className="px-8"
          >
            {actionLoading ? (
              <div className="flex items-center space-x-2">
                <svg className="animate-spin -ml-1 mr-2 h-4 w-4 text-white" fill="none" viewBox="0 0 24 24">
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
                <span>Updating...</span>
              </div>
            ) : (
              <div className="flex items-center space-x-2">
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                </svg>
                <span>Update User</span>
              </div>
            )}
          </Button>
        </div>
      </div>
    </div>
  </Modal>
);
