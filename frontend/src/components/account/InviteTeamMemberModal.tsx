import React, { useState } from 'react';
import { Modal } from '../ui/Modal';
import { FormField } from '../ui/FormField';
import { invitationsApi, InviteUserRequest } from '../../services/invitationsApi';

interface InviteTeamMemberModalProps {
  isOpen: boolean;
  onClose: () => void;
  onInviteSent: () => void;
  accountId?: string;
}

export const InviteTeamMemberModal: React.FC<InviteTeamMemberModalProps> = ({
  isOpen,
  onClose,
  onInviteSent,
  accountId
}) => {
  const [loading, setLoading] = useState(false);
  const [formData, setFormData] = useState<InviteUserRequest>({
    email: '',
    role: 'member',
    message: ''
  });
  const [errors, setErrors] = useState<Record<string, string>>({});

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setErrors({});

    try {
      // Validate form
      const newErrors: Record<string, string> = {};
      
      if (!formData.email.trim()) {
        newErrors.email = 'Email is required';
      } else if (!/\S+@\S+\.\S+/.test(formData.email)) {
        newErrors.email = 'Please enter a valid email address';
      }
      
      if (!formData.role) {
        newErrors.role = 'Role is required';
      }

      if (Object.keys(newErrors).length > 0) {
        setErrors(newErrors);
        return;
      }

      // Send invitation
      const response = await invitationsApi.inviteUser(formData, accountId);
      
      if (response.success) {
        // Reset form
        setFormData({ email: '', role: 'member', message: '' });
        onInviteSent();
        onClose();
      } else {
        setErrors({ general: response.message || 'Failed to send invitation' });
      }
    } catch (error) {
      setErrors({ general: 'An unexpected error occurred' });
    } finally {
      setLoading(false);
    }
  };

  const handleInputChange = (field: keyof InviteUserRequest, value: string) => {
    setFormData(prev => ({ ...prev, [field]: value }));
    if (errors[field as keyof typeof errors]) {
      setErrors(prev => ({ ...prev, [field]: '' }));
    }
  };

  const roleOptions = [
    { value: 'admin', label: 'Admin', description: 'Full account management access' },
    { value: 'manager', label: 'Manager', description: 'Can manage team and billing' },
    { value: 'member', label: 'Member', description: 'Standard access to resources' },
    { value: 'viewer', label: 'Viewer', description: 'Read-only access' }
  ];

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Invite Team Member"
      maxWidth="md"
    >
      <form onSubmit={handleSubmit} className="space-y-6">
        {errors.general && (
          <div className="bg-theme-error bg-opacity-10 border border-theme-error text-theme-error p-4 rounded-lg">
            {errors.general}
          </div>
        )}

        <FormField
          label="Email Address"
          type="email"
          value={formData.email}
          onChange={(value) => handleInputChange('email', value)}
          error={errors.email}
          placeholder="colleague@example.com"
          required
        />

        <div>
          <label className="block text-sm font-medium text-theme-primary mb-3">
            Role *
          </label>
          <div className="space-y-3">
            {roleOptions.map((option) => (
              <label
                key={option.value}
                className={`flex items-start space-x-3 p-3 rounded-lg border cursor-pointer transition-all ${
                  formData.role === option.value
                    ? 'border-theme-interactive-primary bg-theme-interactive-primary bg-opacity-5'
                    : 'border-theme hover:border-theme-interactive-primary hover:bg-theme-surface-hover'
                }`}
              >
                <input
                  type="radio"
                  name="role"
                  value={option.value}
                  checked={formData.role === option.value}
                  onChange={(e) => handleInputChange('role', e.target.value)}
                  className="mt-1 h-4 w-4 text-theme-interactive-primary border-theme focus:ring-theme-interactive-primary"
                />
                <div className="flex-1">
                  <div className="font-medium text-theme-primary">{option.label}</div>
                  <div className="text-sm text-theme-secondary">{option.description}</div>
                </div>
              </label>
            ))}
          </div>
          {errors.role && (
            <p className="mt-2 text-sm text-theme-error">{errors.role}</p>
          )}
        </div>

        <FormField
          label="Personal Message (Optional)"
          type="textarea"
          value={formData.message || ''}
          onChange={(value) => handleInputChange('message', value)}
          placeholder="Add a personal message to the invitation email..."
          rows={3}
        />

        <div className="bg-theme-surface p-4 rounded-lg">
          <h4 className="font-medium text-theme-primary mb-2">What happens next?</h4>
          <ul className="text-sm text-theme-secondary space-y-1">
            <li>• The invitee will receive an email with an invitation link</li>
            <li>• They'll need to create an account or sign in if they already have one</li>
            <li>• Once accepted, they'll have {roleOptions.find(r => r.value === formData.role)?.label.toLowerCase()} access</li>
            <li>• Invitations expire after 7 days</li>
          </ul>
        </div>

        <div className="flex justify-end space-x-3 pt-4">
          <button
            type="button"
            onClick={onClose}
            disabled={loading}
            className="btn-theme btn-theme-secondary"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={loading}
            className="btn-theme btn-theme-primary"
          >
            {loading ? (
              <>
                <div className="animate-spin h-4 w-4 border-2 border-white border-t-transparent rounded-full mr-2"></div>
                Sending Invitation...
              </>
            ) : (
              'Send Invitation'
            )}
          </button>
        </div>
      </form>
    </Modal>
  );
};

export default InviteTeamMemberModal;