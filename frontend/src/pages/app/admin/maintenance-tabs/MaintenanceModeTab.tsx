import React, { useState } from 'react';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { maintenanceApi } from '@/shared/services/admin/maintenanceApi';
import { SettingsCard, ToggleSwitch } from '@/features/admin/components/settings/SettingsComponents';
import { MaintenanceModeTabProps } from './types';

export const MaintenanceModeTab: React.FC<MaintenanceModeTabProps> = ({ status, onUpdate }) => {
  const { showNotification } = useNotifications();
  const [submitting, setSubmitting] = useState(false);
  const [message, setMessage] = useState(status.message || '');
  const [estimatedCompletion, setEstimatedCompletion] = useState(status.estimated_completion || '');
  // Comma/newline-separated in the UI; the API takes an array. Prefilled from
  // the store's current list so re-saving the message doesn't drop it.
  const [bypassIpsText, setBypassIpsText] = useState((status.bypass_ips || []).join(', '));

  const parseBypassIps = () =>
    bypassIpsText
      .split(/[,\s]+/)
      .map((entry) => entry.trim())
      .filter(Boolean);

  const handleToggleMode = async () => {
    setSubmitting(true);
    try {
      await maintenanceApi.setMaintenanceMode(!status.mode, message, estimatedCompletion || undefined, parseBypassIps());
      showNotification(
        status.mode ? 'Maintenance mode disabled' : 'Maintenance mode enabled',
        'success'
      );
      onUpdate();
    } catch (_error) {
      showNotification('Failed to update maintenance mode', 'error');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="space-y-6">
      {/* Current Status */}
      <SettingsCard
        title="Maintenance Mode Status"
        description="Control system-wide maintenance mode"
        icon="🔧"
      >
        <div className="space-y-4">
          <div className="flex items-center justify-between p-4 rounded-lg border border-theme bg-theme-background-secondary">
            <div>
              <h4 className="text-sm font-medium text-theme-primary">
                Maintenance Mode
              </h4>
              <p className="text-sm text-theme-secondary">
                {status.mode ? 'System is currently in maintenance mode' : 'System is operational'}
              </p>
            </div>
            <ToggleSwitch
              checked={status.mode}
              onChange={handleToggleMode}
              disabled={submitting}
              variant={status.mode ? 'warning' : 'success'}
            />
          </div>

          {status.mode && status.message && (
            <div className="p-4 rounded-lg bg-theme-warning-bg border border-theme-warning-border">
              <p className="text-sm text-theme-warning-fg font-medium">Current Message:</p>
              <p className="text-sm text-theme-primary mt-1">{status.message}</p>
            </div>
          )}

          <div>
            <label htmlFor="maintenance-message" className="block text-sm font-semibold text-theme-primary mb-2">
              Maintenance Message
            </label>
            <input
              id="maintenance-message"
              type="text"
              placeholder="System maintenance in progress..."
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              disabled={submitting}
              className="input-theme w-full"
            />
          </div>

          <div>
            <label htmlFor="maintenance-estimated-completion" className="block text-sm font-semibold text-theme-primary mb-2">
              Estimated Completion
            </label>
            <input
              id="maintenance-estimated-completion"
              type="text"
              placeholder="e.g. 2026-01-01T12:00:00Z or '30 minutes'"
              value={estimatedCompletion}
              onChange={(e) => setEstimatedCompletion(e.target.value)}
              disabled={submitting}
              className="input-theme w-full"
            />
          </div>

          <div>
            <label htmlFor="maintenance-bypass-ips" className="block text-sm font-semibold text-theme-primary mb-2">
              Bypass IPs
            </label>
            <input
              id="maintenance-bypass-ips"
              type="text"
              placeholder="203.0.113.5, 198.51.100.0/24"
              value={bypassIpsText}
              onChange={(e) => setBypassIpsText(e.target.value)}
              disabled={submitting}
              className="input-theme w-full"
            />
            <p className="text-xs text-theme-secondary mt-1">
              Comma-separated IPs or CIDR ranges exempt from the maintenance gate.
            </p>
          </div>
        </div>
      </SettingsCard>
    </div>
  );
};
