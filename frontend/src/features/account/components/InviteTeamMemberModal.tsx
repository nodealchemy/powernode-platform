import React from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { FormField } from '@/shared/components/ui/FormField';
import { invitationsApi, InviteUserRequest } from '@/shared/services/invitationsApi';
import { useForm, FormValidationRules } from '@/shared/hooks/useForm';
import { Send, UserPlus } from 'lucide-react';

interface InviteTeamMemberModalProps {
  isOpen: boolean;
  onClose: () => void;
  onInviteSent: () => void;
  accountId?: string;
}

export const InviteTeamMemberModal: React.FC<InviteTeamMemberModalProps> = ({
InviteTeamMemberModal.displayName = 'InviteTeamMemberModal';
  isOpen,
  onClose,
  onInviteSent,
  accountId
}) => {
  const defaultValues: InviteUserRequest = {
    email: '',
    role: 'account.member',
    message: ''
  };

  const validationRules: FormValidationRules = {
    email: {
      required: true,
      pattern: /^[^\s@]+@[^\s@]+\.[^\s@]+$/,
    },
    role: {
      required: true,
    },
    message: {
      maxLength: 500,
    }
  };

  const handleInvite = async (formData: InviteUserRequest) => {
    const response = await invitationsApi.inviteUser(formData, accountId);
    
    if (response.success) {
      onInviteSent();
      onClose();
    } else {
      throw new Error(response.message || 'Failed to send invitation');
    }
  };

  const form = useForm<InviteUserRequest>({
    initialValues: defaultValues,
    validationRules,
    onSubmit: handleInvite,
    enableRealTimeValidation: true,
    showSuccessNotification: true,
    successMessage: 'Invitation sent successfully',
    resetAfterSubmit: true,
  });

  // Reset form when modal opens
  React.useEffect(() => {
    if (isOpen) {
      form.reset();
    }
  }, [isOpen, form]);

  const handleCancel = () => {
    form.reset();
    onClose();
  };

  const roleOptions = [
    { value: 'account.manager', label: 'Account Manager', description: 'Full account management access' },
    { value: 'billing.manager', label: 'Billing Manager', description: 'Can manage billing and payments' },
    { value: 'account.member', label: 'Account Member', description: 'Standard access to resources' }
  ];

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleCancel}
      title="Invite Team Member"
      subtitle="Send an invitation to join your team"
      icon={<UserPlus />}
      maxWidth="md"
    >
      <form onSubmit={form.handleSubmit} className="space-y-6">
        <FormField
          label="Email Address"
          type="email"
          value={form.values.email}
          onChange={(value) => form.setValue('email', value)}
          error={form.errors.email}
          placeholder="colleague@example.com"
          required
          disabled={form.isSubmitting}
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
                  form.values.role === option.value
                    ? 'border-theme-interactive-primary bg-theme-interactive-primary bg-opacity-5'
                    : 'border-theme hover:border-theme-interactive-primary hover:bg-theme-surface-hover'
                }`}
              >
                <input
                  type="radio"
                  name="role"
                  value={option.value}
                  checked={form.values.role === option.value}
                  onChange={(e) => form.setValue('role', e.target.value)}
                  onBlur={form.handleBlur}
                  className="mt-1 h-4 w-4 text-theme-interactive-primary border-theme focus:ring-theme-interactive-primary"
                  disabled={form.isSubmitting}
                />
                <div className="flex-1">
                  <div className="font-medium text-theme-primary">{option.label}</div>
                  <div className="text-sm text-theme-secondary">{option.description}</div>
                </div>
              </label>
            ))}
          </div>
          {form.errors.role && (
            <p className="mt-2 text-sm text-theme-error">{form.errors.role}</p>
          )}
        </div>

        <FormField
          label="Personal Message (Optional)"
          type="textarea"
          value={form.values.message || ''}
          onChange={(value) => form.setValue('message', value)}
          error={form.errors.message}
          placeholder="Add a personal message to the invitation email..."
          rows={3}
          disabled={form.isSubmitting}
        />

        <div className="bg-theme-surface p-4 rounded-lg">
          <h4 className="font-medium text-theme-primary mb-2">What happens next?</h4>
          <ul className="text-sm text-theme-secondary space-y-1">
            <li>• The invitee will receive an email with an invitation link</li>
            <li>• They'll need to create an account or sign in if they already have one</li>
            <li>• Once accepted, they'll have {roleOptions.find(r => r.value === form.values.role)?.label.toLowerCase()} access</li>
            <li>• Invitations expire after 7 days</li>
          </ul>
        </div>

        <div className="flex justify-end space-x-3 pt-4">
          <Button
            type="button"
            onClick={handleCancel}
            disabled={form.isSubmitting}
            variant="secondary"
          >
            Cancel
          </Button>
          <Button
            type="submit"
            loading={form.isSubmitting}
            variant="primary"
            disabled={form.isSubmitting || !form.isValid}
          >
            {!form.isSubmitting && <Send className="w-4 h-4 mr-2" />}
            {form.isSubmitting ? 'Sending Invitation...' : 'Send Invitation'}
          </Button>
        </div>
      </form>
    </Modal>
  );
};

export default InviteTeamMemberModal;