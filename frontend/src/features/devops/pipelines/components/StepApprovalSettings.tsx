import React from 'react';
import { Shield, Clock, MessageSquare, Users, Mail, Plus, Trash2 } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';

export interface ApprovalSettings {
  timeout_hours: number;
  require_comment: boolean;
  notification_recipients: Array<{
    type: 'email' | 'user_id';
    value: string;
    display_name?: string;
  }>;
}

interface StepApprovalSettingsProps {
  requiresApproval: boolean;
  settings: ApprovalSettings;
  availableUsers?: Array<{ id: string; email: string; name?: string }>;
  onApprovalToggle: (requires: boolean) => void;
  onSettingsChange: (settings: ApprovalSettings) => void;
  disabled?: boolean;
}

export const StepApprovalSettings: React.FC<StepApprovalSettingsProps> = ({
  requiresApproval,
  settings,
  availableUsers = [],
  onApprovalToggle,
  onSettingsChange,
  disabled = false,
}) => {
  const [newRecipientEmail, setNewRecipientEmail] = React.useState('');
  const [selectedUserId, setSelectedUserId] = React.useState('');
  const [addType, setAddType] = React.useState<'email' | 'user'>('email');

  const handleAddRecipient = () => {
    if (addType === 'email') {
      if (!newRecipientEmail || !newRecipientEmail.includes('@')) return;

      const exists = settings.notification_recipients.some(
        (r) => r.type === 'email' && r.value === newRecipientEmail
      );
      if (exists) return;

      onSettingsChange({
        ...settings,
        notification_recipients: [
          ...settings.notification_recipients,
          { type: 'email', value: newRecipientEmail },
        ],
      });
      setNewRecipientEmail('');
    } else {
      if (!selectedUserId) return;

      const exists = settings.notification_recipients.some(
        (r) => r.type === 'user_id' && r.value === selectedUserId
      );
      if (exists) return;

      const user = availableUsers.find((u) => u.id === selectedUserId);
      onSettingsChange({
        ...settings,
        notification_recipients: [
          ...settings.notification_recipients,
          {
            type: 'user_id',
            value: selectedUserId,
            display_name: user?.name || user?.email,
          },
        ],
      });
      setSelectedUserId('');
    }
  };

  const handleRemoveRecipient = (index: number) => {
    const updated = [...settings.notification_recipients];
    updated.splice(index, 1);
    onSettingsChange({ ...settings, notification_recipients: updated });
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Shield className="w-5 h-5 text-theme-secondary" />
          <h3 className="text-sm font-medium text-theme-primary">
            Require Approval
          </h3>
        </div>
        <label className="relative inline-flex items-center cursor-pointer">
          <input
            type="checkbox"
            checked={requiresApproval}
            onChange={(e) => onApprovalToggle(e.target.checked)}
            disabled={disabled}
            className="sr-only peer"
          />
          <div className="w-11 h-6 bg-theme-secondary/30 peer-focus:outline-none peer-focus:ring-2 peer-focus:ring-theme-primary rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-theme-primary after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-theme-surface after:border-theme after:border after:rounded-full after:h-5 after:w-5 after:transition-all after:shadow-sm peer-checked:bg-theme-primary peer-checked:after:bg-theme-surface"></div>
        </label>
      </div>

      {requiresApproval && (
        <div className="pl-7 space-y-4 border-l-2 border-theme ml-2">
          <p className="text-xs text-theme-tertiary">
            This step will pause and send email notifications when reached.
            The pipeline will continue only after approval.
          </p>

          {/* Timeout Setting */}
          <div>
            <label className="flex items-center gap-2 text-sm font-medium text-theme-secondary mb-2">
              <Clock className="w-4 h-4" />
              Approval Timeout
            </label>
            <div className="flex items-center gap-2">
              <input
                type="number"
                value={settings.timeout_hours}
                onChange={(e) =>
                  onSettingsChange({
                    ...settings,
                    timeout_hours: Math.max(1, parseInt(e.target.value) || 24),
                  })
                }
                disabled={disabled}
                min={1}
                max={168}
                className="w-20 px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary text-sm focus:outline-none focus:ring-2 focus:ring-theme-primary"
              />
              <span className="text-sm text-theme-secondary">hours</span>
            </div>
            <p className="mt-1 text-xs text-theme-tertiary">
              The approval request will expire after this time (1-168 hours)
            </p>
          </div>

          {/* Require Comment */}
          <div>
            <label className="flex items-center gap-3">
              <MessageSquare className="w-4 h-4 text-theme-secondary" />
              <input
                type="checkbox"
                checked={settings.require_comment}
                onChange={(e) =>
                  onSettingsChange({ ...settings, require_comment: e.target.checked })
                }
                disabled={disabled}
                className="rounded border-theme text-theme-primary focus:ring-theme-primary"
              />
              <span className="text-sm text-theme-secondary">
                Require comment when approving or rejecting
              </span>
            </label>
          </div>

          {/* Step-Level Recipients Override */}
          <div>
            <label className="flex items-center gap-2 text-sm font-medium text-theme-secondary mb-2">
              <Users className="w-4 h-4" />
              Override Recipients (optional)
            </label>
            <p className="text-xs text-theme-tertiary mb-2">
              Leave empty to use pipeline-level notification recipients
            </p>

            {/* Current recipients list */}
            {settings.notification_recipients.length > 0 && (
              <div className="mb-3 space-y-2">
                {settings.notification_recipients.map((recipient, index) => (
                  <div
                    key={`${recipient.type}-${recipient.value}`}
                    className="flex items-center justify-between bg-theme-surface-elevated rounded px-3 py-2 border border-theme"
                  >
                    <div className="flex items-center gap-2">
                      <Mail className="w-4 h-4 text-theme-secondary" />
                      <span className="text-sm text-theme-primary">
                        {recipient.display_name || recipient.value}
                      </span>
                    </div>
                    <Button
                      onClick={() => handleRemoveRecipient(index)}
                      variant="ghost"
                      size="sm"
                      disabled={disabled}
                    >
                      <Trash2 className="w-4 h-4 text-theme-error" />
                    </Button>
                  </div>
                ))}
              </div>
            )}

            {/* Add recipient form */}
            <div className="flex flex-col sm:flex-row gap-2">
              <select
                value={addType}
                onChange={(e) => setAddType(e.target.value as 'email' | 'user')}
                disabled={disabled}
                className="px-3 py-1.5 bg-theme-surface border border-theme rounded text-theme-primary text-sm focus:outline-none focus:ring-2 focus:ring-theme-primary"
              >
                <option value="email">Email</option>
                {availableUsers.length > 0 && <option value="user">Team</option>}
              </select>

              {addType === 'email' ? (
                <input
                  type="email"
                  value={newRecipientEmail}
                  onChange={(e) => setNewRecipientEmail(e.target.value)}
                  placeholder="email@example.com"
                  disabled={disabled}
                  className="flex-1 px-3 py-1.5 bg-theme-surface border border-theme rounded text-theme-primary text-sm focus:outline-none focus:ring-2 focus:ring-theme-primary"
                />
              ) : (
                <select
                  value={selectedUserId}
                  onChange={(e) => setSelectedUserId(e.target.value)}
                  disabled={disabled}
                  className="flex-1 px-3 py-1.5 bg-theme-surface border border-theme rounded text-theme-primary text-sm focus:outline-none focus:ring-2 focus:ring-theme-primary"
                >
                  <option value="">Select...</option>
                  {availableUsers
                    .filter(
                      (u) =>
                        !settings.notification_recipients.some(
                          (r) => r.type === 'user_id' && r.value === u.id
                        )
                    )
                    .map((user) => (
                      <option key={user.id} value={user.id}>
                        {user.name || user.email}
                      </option>
                    ))}
                </select>
              )}

              <Button
                onClick={handleAddRecipient}
                variant="secondary"
                size="sm"
                disabled={disabled || (addType === 'email' ? !newRecipientEmail : !selectedUserId)}
              >
                <Plus className="w-4 h-4" />
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default StepApprovalSettings;
