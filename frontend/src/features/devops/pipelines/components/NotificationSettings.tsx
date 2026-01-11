import React, { useState } from 'react';
import { Mail, Plus, Trash2, User, Bell, BellOff } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';

export interface NotificationRecipient {
  type: 'email' | 'user_id';
  value: string;
  display_name?: string;
}

export interface NotificationSettingsConfig {
  on_approval_required: boolean;
  on_completion: boolean;
  on_failure: boolean;
}

interface NotificationSettingsProps {
  recipients: NotificationRecipient[];
  settings: NotificationSettingsConfig;
  availableUsers?: Array<{ id: string; email: string; name?: string }>;
  onChange: (recipients: NotificationRecipient[], settings: NotificationSettingsConfig) => void;
  disabled?: boolean;
}

export const NotificationSettings: React.FC<NotificationSettingsProps> = ({
  recipients,
  settings,
  availableUsers = [],
  onChange,
  disabled = false,
}) => {
  const [newEmail, setNewEmail] = useState('');
  const [addType, setAddType] = useState<'email' | 'user'>('email');
  const [selectedUserId, setSelectedUserId] = useState('');

  const handleAddRecipient = () => {
    if (addType === 'email') {
      if (!newEmail || !newEmail.includes('@')) return;

      const exists = recipients.some(
        (r) => r.type === 'email' && r.value === newEmail
      );
      if (exists) return;

      onChange(
        [...recipients, { type: 'email', value: newEmail }],
        settings
      );
      setNewEmail('');
    } else {
      if (!selectedUserId) return;

      const exists = recipients.some(
        (r) => r.type === 'user_id' && r.value === selectedUserId
      );
      if (exists) return;

      const user = availableUsers.find((u) => u.id === selectedUserId);
      onChange(
        [
          ...recipients,
          {
            type: 'user_id',
            value: selectedUserId,
            display_name: user?.name || user?.email,
          },
        ],
        settings
      );
      setSelectedUserId('');
    }
  };

  const handleRemoveRecipient = (index: number) => {
    const updated = [...recipients];
    updated.splice(index, 1);
    onChange(updated, settings);
  };

  const handleSettingChange = (key: keyof NotificationSettingsConfig, value: boolean) => {
    onChange(recipients, { ...settings, [key]: value });
  };

  return (
    <div className="space-y-6">
      <div>
        <h3 className="text-sm font-medium text-theme-primary mb-3 flex items-center gap-2">
          <Bell className="w-4 h-4" />
          Notification Events
        </h3>
        <div className="space-y-2">
          <label className="flex items-center gap-3">
            <input
              type="checkbox"
              checked={settings.on_approval_required}
              onChange={(e) => handleSettingChange('on_approval_required', e.target.checked)}
              disabled={disabled}
              className="rounded border-theme text-theme-primary focus:ring-theme-primary"
            />
            <span className="text-sm text-theme-secondary">
              Send notification when approval is required
            </span>
          </label>
          <label className="flex items-center gap-3">
            <input
              type="checkbox"
              checked={settings.on_failure}
              onChange={(e) => handleSettingChange('on_failure', e.target.checked)}
              disabled={disabled}
              className="rounded border-theme text-theme-primary focus:ring-theme-primary"
            />
            <span className="text-sm text-theme-secondary">
              Send notification on pipeline failure
            </span>
          </label>
          <label className="flex items-center gap-3">
            <input
              type="checkbox"
              checked={settings.on_completion}
              onChange={(e) => handleSettingChange('on_completion', e.target.checked)}
              disabled={disabled}
              className="rounded border-theme text-theme-primary focus:ring-theme-primary"
            />
            <span className="text-sm text-theme-secondary">
              Send notification on pipeline completion
            </span>
          </label>
        </div>
      </div>

      <div>
        <h3 className="text-sm font-medium text-theme-primary mb-3 flex items-center gap-2">
          <Mail className="w-4 h-4" />
          Notification Recipients
        </h3>

        {/* Current recipients list */}
        {recipients.length > 0 && (
          <div className="mb-4 space-y-2">
            {recipients.map((recipient, index) => (
              <div
                key={`${recipient.type}-${recipient.value}`}
                className="flex items-center justify-between bg-theme-surface-elevated rounded-lg px-3 py-2 border border-theme"
              >
                <div className="flex items-center gap-2">
                  {recipient.type === 'user_id' ? (
                    <User className="w-4 h-4 text-theme-secondary" />
                  ) : (
                    <Mail className="w-4 h-4 text-theme-secondary" />
                  )}
                  <span className="text-sm text-theme-primary">
                    {recipient.display_name || recipient.value}
                  </span>
                  <span className="text-xs text-theme-tertiary capitalize">
                    ({recipient.type === 'user_id' ? 'Team Member' : 'Email'})
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
            className="px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary text-sm focus:outline-none focus:ring-2 focus:ring-theme-primary"
          >
            <option value="email">Email Address</option>
            {availableUsers.length > 0 && <option value="user">Team Member</option>}
          </select>

          {addType === 'email' ? (
            <input
              type="email"
              value={newEmail}
              onChange={(e) => setNewEmail(e.target.value)}
              placeholder="recipient@example.com"
              disabled={disabled}
              className="flex-1 px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary text-sm focus:outline-none focus:ring-2 focus:ring-theme-primary"
            />
          ) : (
            <select
              value={selectedUserId}
              onChange={(e) => setSelectedUserId(e.target.value)}
              disabled={disabled}
              className="flex-1 px-3 py-2 bg-theme-surface border border-theme rounded-lg text-theme-primary text-sm focus:outline-none focus:ring-2 focus:ring-theme-primary"
            >
              <option value="">Select team member...</option>
              {availableUsers
                .filter((u) => !recipients.some((r) => r.type === 'user_id' && r.value === u.id))
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
            disabled={disabled || (addType === 'email' ? !newEmail : !selectedUserId)}
          >
            <Plus className="w-4 h-4 mr-1" />
            Add
          </Button>
        </div>

        {recipients.length === 0 && (
          <p className="mt-3 text-xs text-theme-tertiary flex items-center gap-1">
            <BellOff className="w-3 h-3" />
            No recipients configured. Add recipients to receive pipeline notifications.
          </p>
        )}
      </div>
    </div>
  );
};

export default NotificationSettings;
