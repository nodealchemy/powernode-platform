import React, { useState } from 'react';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { maintenanceApi } from '@/shared/services/admin/maintenanceApi';
import { SettingsCard, ToggleSwitch } from '@/features/admin/components/settings/SettingsComponents';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { MaintenanceModeTabProps } from './types';

export const MaintenanceModeTab: React.FC<MaintenanceModeTabProps> = ({ status, onUpdate }) => {
  const { showNotification } = useNotifications();
  const { confirm, ConfirmationDialog } = useConfirmation();
  const [submitting, setSubmitting] = useState(false);
  const [message, setMessage] = useState(status.message || '');
  const [estimatedCompletion, setEstimatedCompletion] = useState(status.estimated_completion || '');
  // Comma/newline-separated in the UI; the API takes an array. Prefilled from
  // the store's current list so re-saving the message doesn't drop it.
  const [bypassIpsText, setBypassIpsText] = useState((status.bypass_ips || []).join(', '));

  // Undefined (older server, or a status shape a test doesn't set) is treated
  // as supported — only an explicit `false` (Admin::MaintenanceMode's
  // trusted_proxies_configured? returning false) disables the field.
  const bypassSupported = status.bypass_ips_supported !== false;

  const parseBypassIps = () =>
    bypassIpsText
      .split(/[,\s]+/)
      .map((entry) => entry.trim())
      .filter(Boolean);

  const reportError = (error: unknown, fallback: string) => {
    // Surface the SERVER's own message (e.g. Admin::MaintenanceMode's
    // InvalidBypassIp 422 explaining a rejected bypass-IP write) rather than
    // a generic string — an admin editing the bypass list needs to know WHY
    // the write was rejected, not just that it was.
    const errorMessage = error instanceof Error && error.message ? error.message : fallback;
    showNotification(errorMessage, 'error');
  };

  const handleToggleMode = async () => {
    // Confirm only on the OFF -> ON transition: enabling maintenance mode is
    // disruptive (blocks every non-exempt, non-bypassed user immediately);
    // disabling it is not, so it needs no confirmation. Uses the shared
    // ConfirmationModal (not window.confirm) for a consistent, themeable,
    // accessible dialog.
    if (!status.mode) {
      confirm({
        title: 'Enable Maintenance Mode',
        message: 'This will block access for all non-admin users immediately.',
        confirmLabel: 'Enable',
        variant: 'warning',
        onConfirm: () => toggle(true)
      });
      return;
    }

    await toggle(false);
  };

  const toggle = async (enabled: boolean) => {
    setSubmitting(true);
    try {
      await maintenanceApi.setMaintenanceMode(enabled, message, estimatedCompletion || undefined, parseBypassIps());
      showNotification(enabled ? 'Maintenance mode enabled' : 'Maintenance mode disabled', 'success');
      onUpdate();
    } catch (error) {
      reportError(error, 'Failed to update maintenance mode');
    } finally {
      setSubmitting(false);
    }
  };

  // Saves message/ETA/bypass IPs WITHOUT flipping `mode` — lets an admin
  // update the maintenance message or bypass list while maintenance is
  // already on, or stage them before turning it on, without a disable +
  // re-enable round trip. Routes to PATCH /admin/maintenance/mode
  // (Admin::MaintenanceMode.update_fields!), NOT the POST toggle endpoint:
  // the toggle's enable!/disable! either wipe these fields (when off) or
  // reset enabled_at (when on) as a side effect of toggling `enabled`, which
  // Save must never do since it isn't toggling anything.
  const handleSave = async () => {
    setSubmitting(true);
    try {
      await maintenanceApi.updateMaintenanceSettings(message, estimatedCompletion || undefined, parseBypassIps());
      showNotification('Maintenance settings saved', 'success');
      onUpdate();
    } catch (error) {
      reportError(error, 'Failed to save maintenance settings');
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
              disabled={submitting || !bypassSupported}
              className="input-theme w-full"
            />
            {bypassSupported ? (
              <p className="text-xs text-theme-secondary mt-1">
                Comma-separated IPs or CIDR ranges exempt from the maintenance gate.
              </p>
            ) : (
              <p className="text-xs text-theme-warning-fg mt-1">
                Bypass IPs are unavailable until the server sets TRUSTED_PROXY_CIDRS
                (see docs/operations/trusted-proxy-cidrs.md) — without it, a bypass
                IP can never be trusted.
              </p>
            )}
          </div>

          <div className="flex justify-end">
            <button
              type="button"
              onClick={handleSave}
              disabled={submitting}
              className="btn-theme btn-theme-secondary"
            >
              Save
            </button>
          </div>
        </div>
      </SettingsCard>
      {ConfirmationDialog}
    </div>
  );
};
