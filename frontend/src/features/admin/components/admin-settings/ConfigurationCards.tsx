import React from 'react';

interface SettingsSummary {
  password_min_length?: number;
  session_timeout_minutes?: number;
  require_email_verification?: boolean;
  rate_limiting?: { enabled?: boolean };
  trial_period_days?: number;
  payment_retry_attempts?: number;
  webhook_timeout_seconds?: number;
  allow_account_deletion?: boolean;
  system_email?: string;
  support_email?: string;
  smtp_settings?: { host?: string };
  system_name?: string;
}

interface ConfigurationCardsProps {
  settingsSummary: SettingsSummary | null | undefined;
}

const ConfigBadge: React.FC<{ value: boolean; trueLabel?: string; falseLabel?: string }> = ({
  value,
  trueLabel = 'Enabled',
  falseLabel = 'Disabled'
}) => (
  <span className={`text-xs px-2 py-1 rounded font-medium ${
    value
      ? 'bg-theme-success-background text-theme-success'
      : 'bg-theme-warning-background text-theme-warning'
  }`}>
    {value ? trueLabel : falseLabel}
  </span>
);

export const SecurityConfigCard: React.FC<ConfigurationCardsProps> = ({ settingsSummary }) => (
  <div className="bg-theme-surface rounded-xl p-6 border border-theme">
    <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
      <span>🔒</span>
      <span>Security</span>
    </h3>
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <span className="text-sm text-theme-secondary">Password Min Length</span>
        <span className="text-sm font-medium text-theme-primary">{settingsSummary?.password_min_length || 12} chars</span>
      </div>
      <div className="flex items-center justify-between">
        <span className="text-sm text-theme-secondary">Session Timeout</span>
        <span className="text-sm font-medium text-theme-primary">{settingsSummary?.session_timeout_minutes || 60} min</span>
      </div>
      <div className="flex items-center justify-between">
        <span className="text-sm text-theme-secondary">Email Verification</span>
        <ConfigBadge value={!!settingsSummary?.require_email_verification} trueLabel="Required" falseLabel="Optional" />
      </div>
      <div className="flex items-center justify-between">
        <span className="text-sm text-theme-secondary">Rate Limiting</span>
        <ConfigBadge value={settingsSummary?.rate_limiting?.enabled !== false} trueLabel="Active" falseLabel="Disabled" />
      </div>
    </div>
  </div>
);

export const BusinessConfigCard: React.FC<ConfigurationCardsProps> = ({ settingsSummary }) => (
  <div className="bg-theme-surface rounded-xl p-6 border border-theme">
    <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
      <span>💼</span>
      <span>Business</span>
    </h3>
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <span className="text-sm text-theme-secondary">Trial Period</span>
        <span className="text-sm font-medium text-theme-primary">{settingsSummary?.trial_period_days || 14} days</span>
      </div>
      <div className="flex items-center justify-between">
        <span className="text-sm text-theme-secondary">Payment Retries</span>
        <span className="text-sm font-medium text-theme-primary">{settingsSummary?.payment_retry_attempts || 3} attempts</span>
      </div>
      <div className="flex items-center justify-between">
        <span className="text-sm text-theme-secondary">Webhook Timeout</span>
        <span className="text-sm font-medium text-theme-primary">{settingsSummary?.webhook_timeout_seconds || 30}s</span>
      </div>
      <div className="flex items-center justify-between">
        <span className="text-sm text-theme-secondary">Account Deletion</span>
        <span className={`text-xs px-2 py-1 rounded font-medium ${
          settingsSummary?.allow_account_deletion
            ? 'bg-theme-warning-background text-theme-warning'
            : 'bg-theme-success-background text-theme-success'
        }`}>
          {settingsSummary?.allow_account_deletion ? 'Allowed' : 'Protected'}
        </span>
      </div>
    </div>
  </div>
);

export const CommunicationConfigCard: React.FC<ConfigurationCardsProps> = ({ settingsSummary }) => (
  <div className="bg-theme-surface rounded-xl p-6 border border-theme">
    <h3 className="text-lg font-semibold text-theme-primary mb-4 flex items-center gap-2">
      <span>📧</span>
      <span>Communication</span>
    </h3>
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <span className="text-sm text-theme-secondary">System Email</span>
        <span className="text-xs font-medium text-theme-primary truncate max-w-24" title={settingsSummary?.system_email || 'Not set'}>
          {settingsSummary?.system_email ? '✓ Set' : '⚠ Not set'}
        </span>
      </div>
      <div className="flex items-center justify-between">
        <span className="text-sm text-theme-secondary">Support Email</span>
        <span className="text-xs font-medium text-theme-primary truncate max-w-24" title={settingsSummary?.support_email || 'Not set'}>
          {settingsSummary?.support_email ? '✓ Set' : '⚠ Not set'}
        </span>
      </div>
      <div className="flex items-center justify-between">
        <span className="text-sm text-theme-secondary">SMTP Host</span>
        <span className={`text-xs px-2 py-1 rounded font-medium ${
          settingsSummary?.smtp_settings?.host
            ? 'bg-theme-success-background text-theme-success'
            : 'bg-theme-error-background text-theme-error'
        }`}>
          {settingsSummary?.smtp_settings?.host ? 'Configured' : 'Missing'}
        </span>
      </div>
      <div className="flex items-center justify-between">
        <span className="text-sm text-theme-secondary">System Name</span>
        <span className="text-sm font-medium text-theme-primary truncate max-w-24" title={settingsSummary?.system_name || 'Powernode'}>
          {settingsSummary?.system_name || 'Powernode'}
        </span>
      </div>
    </div>
  </div>
);
