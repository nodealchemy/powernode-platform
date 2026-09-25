import React, { useState, useEffect, useCallback } from 'react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { FormField } from '@/shared/components/ui/FormField';
import { invitationsApi, InviteUserRequest } from '@/shared/services/account/invitationsApi';
import { usersApi } from '@/features/account/users/services/usersApi';
import { useForm, FormValidationRules } from '@/shared/hooks/useForm';
import { Send, UserPlus } from 'lucide-react';

interface InviteTeamMemberModalProps {
  isOpen: boolean;
  onClose: () => void;
  onInviteSent: () => void;
}

// Mirrors the real InviteUserRequest exactly: the server's Invitation model
// validates first_name/last_name presence, and role_names is an array
// checked against Role.for_account (Api::V1::InvitationsController#
// authorize_role_conferral!) -- there is no `message` column or param
// anywhere in the contract, so this form does not collect one.
interface InviteFormValues {
  email: string;
  first_name: string;
  last_name: string;
  role_names: string[];
}

interface AssignableRole {
  value: string;
  label: string;
  description: string;
  canAssign?: boolean;
}

export const InviteTeamMemberModal: React.FC<InviteTeamMemberModalProps> = ({
  isOpen,
  onClose,
  onInviteSent
}) => {
  const [availableRoles, setAvailableRoles] = useState<AssignableRole[]>([]);
  const [rolesLoading, setRolesLoading] = useState(false);
  const [rolesError, setRolesError] = useState<string | null>(null);

  const defaultValues: InviteFormValues = {
    email: '',
    first_name: '',
    last_name: '',
    role_names: []
  };

  const validationRules: FormValidationRules = {
    email: {
      required: true,
      pattern: /^[^\s@]+@[^\s@]+\.[^\s@]+$/,
    },
    first_name: {
      required: true,
    },
    last_name: {
      required: true,
    },
    // `required` never fires for an array (`[] === ''` is false), so the
    // "at least one role" rule has to be a custom validator instead.
    role_names: {
      custom: (value) => (Array.isArray(value) && value.length === 0 ? 'Select at least one role' : null),
    },
  };

  const handleInvite = async (formData: InviteFormValues) => {
    const request: InviteUserRequest = {
      email: formData.email,
      first_name: formData.first_name,
      last_name: formData.last_name,
      role_names: formData.role_names,
    };
    const response = await invitationsApi.inviteUser(request);

    if (response.success) {
      onInviteSent();
      onClose();
    } else {
      throw new Error(response.message || 'Failed to send invitation');
    }
  };

  const form = useForm<InviteFormValues>({
    initialValues: defaultValues,
    validationRules,
    onSubmit: handleInvite,
    enableRealTimeValidation: true,
    showSuccessNotification: true,
    successMessage: 'Invitation sent successfully',
    resetAfterSubmit: true,
  });

  const loadAvailableRoles = useCallback(async () => {
    try {
      setRolesLoading(true);
      setRolesError(null);
      const roles = await usersApi.getAvailableRoles();
      setAvailableRoles((roles || []).filter((role) => role.canAssign !== false));
    } catch (_error) {
      setAvailableRoles([]);
      setRolesError('Failed to load assignable roles. Please close and try again.');
    } finally {
      setRolesLoading(false);
    }
  }, []);

  // Reset form and reload the assignable-roles catalog every time the modal opens --
  // the catalog can change (a role gets deleted, or the operator's own grantable set
  // shrinks) between one open and the next.
  useEffect(() => {
    if (isOpen) {
      form.reset();
      loadAvailableRoles();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isOpen, loadAvailableRoles]);

  const handleCancel = () => {
    form.reset();
    onClose();
  };

  const toggleRole = (roleValue: string) => {
    const current = form.values.role_names || [];
    const next = current.includes(roleValue)
      ? current.filter((name) => name !== roleValue)
      : [ ...current, roleValue ];
    form.setValue('role_names', next);
  };

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
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <FormField
            label="First Name"
            type="text"
            value={form.values.first_name}
            onChange={(value) => form.setValue('first_name', value)}
            error={form.errors.first_name}
            placeholder="Jane"
            required
            disabled={form.isSubmitting}
          />
          <FormField
            label="Last Name"
            type="text"
            value={form.values.last_name}
            onChange={(value) => form.setValue('last_name', value)}
            error={form.errors.last_name}
            placeholder="Doe"
            required
            disabled={form.isSubmitting}
          />
        </div>

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
            Roles *
          </label>

          {rolesError && (
            <p role="alert" className="text-sm text-theme-error-fg mb-3">
              {rolesError}
            </p>
          )}

          {rolesLoading ? (
            <p className="text-sm text-theme-secondary">Loading roles…</p>
          ) : availableRoles.length === 0 ? (
            !rolesError && (
              <p className="text-sm text-theme-secondary">No assignable roles are available.</p>
            )
          ) : (
            <div className="space-y-3">
              {availableRoles.map((role) => (
                <label
                  key={role.value}
                  className={`flex items-start space-x-3 p-3 rounded-lg border cursor-pointer transition-all ${
                    form.values.role_names.includes(role.value)
                      ? 'border-theme-interactive-primary bg-theme-interactive-primary/5'
                      : 'border-theme hover:border-theme-interactive-primary hover:bg-theme-surface-hover'
                  }`}
                >
                  <input
                    type="checkbox"
                    name="role_names"
                    value={role.value}
                    checked={form.values.role_names.includes(role.value)}
                    onChange={() => toggleRole(role.value)}
                    onBlur={form.handleBlur}
                    className="mt-1 h-4 w-4 text-theme-interactive-primary border-theme focus:ring-theme-interactive-primary"
                    disabled={form.isSubmitting}
                  />
                  <div className="flex-1">
                    <div className="font-medium text-theme-primary">{role.label}</div>
                    <div className="text-sm text-theme-secondary">{role.description}</div>
                  </div>
                </label>
              ))}
            </div>
          )}
          {form.errors.role_names && (
            <p className="mt-2 text-sm text-theme-error-fg">{form.errors.role_names}</p>
          )}
        </div>

        <div className="bg-theme-surface p-4 rounded-lg">
          <h4 className="font-medium text-theme-primary mb-2">What happens next?</h4>
          <ul className="text-sm text-theme-secondary space-y-1">
            <li>• The invitee will receive an email with an invitation link</li>
            <li>• They'll need to create an account or sign in if they already have one</li>
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
