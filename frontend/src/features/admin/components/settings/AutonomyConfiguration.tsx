import React, { useState, useEffect, useCallback } from 'react';
import { Bot } from 'lucide-react';
import { useSelector } from 'react-redux';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { siteSettingsApi, SiteSetting } from '@/features/admin/settings/services/siteSettingsApi';
import { RootState } from '@/shared/services';

// D3 — the AI autonomy closure driver's cadence flag.
//
// It is a SiteSetting, not an AdminSetting. Those are different tables, and the
// gate that reads it (Ai::Autonomy::ClosureDriverService.enabled?) reads
// SiteSetting — a control wired to the other one would render, save and notify
// success while actuating nothing.
export const CLOSURE_DRIVER_SETTING_KEY = 'ai.autonomy.closure_driver_enabled';
// The permission the write endpoint itself names.
export const CLOSURE_DRIVER_PERMISSION = 'settings.manage';

const CLOSURE_DRIVER_DESCRIPTION =
  'Run the AI autonomy closure driver on its cron cadence. OFF means the scheduled OODA cycle ' +
  'never runs; every other autonomy gate still applies when it is ON.';

type LoadState = 'loading' | 'loaded' | 'unknown';

export const AutonomyConfiguration: React.FC = () => {
  // Permissions, never roles.
  const { user } = useSelector((state: RootState) => state.auth);
  const permissions = user?.permissions;
  const canManage = Array.isArray(permissions) && permissions.includes(CLOSURE_DRIVER_PERMISSION);

  const [enabled, setEnabled] = useState(false);
  const [row, setRow] = useState<SiteSetting | null>(null);
  const [loadState, setLoadState] = useState<LoadState>('loading');
  const [saving, setSaving] = useState(false);

  const { showNotification } = useNotifications();

  const load = useCallback(async () => {
    try {
      const response = await siteSettingsApi.getSiteSettings();
      const found = response.data?.settings?.find(s => s.key === CLOSURE_DRIVER_SETTING_KEY) ?? null;
      setRow(found);
      // An absent row is a real, expected state — seeds do not re-run after
      // first boot, so an install older than the seed line has none — and it
      // means OFF, matching the server-side cast. That is NOT the same as a
      // failed load, which is handled below.
      setEnabled(found?.value === 'true');
      setLoadState('loaded');
    } catch (_error) {
      // Do not render a confident OFF for a control whose state we could not
      // read. An autonomy switch showing OFF when it may be ON is a misreport,
      // so the control says unknown and refuses to act until a load succeeds.
      setRow(null);
      setLoadState('unknown');
      showNotification('Could not load the autonomy closure driver setting', 'error');
    }
  }, [showNotification]);

  useEffect(() => {
    load();
  }, [load]);

  const unknown = loadState === 'unknown';

  const handleToggle = async (next: boolean) => {
    // The real guard. `disabled` is presentation — jsdom (and any synthetic
    // click) still delivers a change event to a disabled input, so a control
    // that gates only on the attribute would still call the write endpoint.
    if (!canManage || unknown) return;

    setSaving(true);
    try {
      if (row) {
        const response = await siteSettingsApi.updateSiteSetting(row.id, { value: next ? 'true' : 'false' });
        setRow(response.data.setting);
      } else {
        const response = await siteSettingsApi.createSiteSetting({
          key: CLOSURE_DRIVER_SETTING_KEY,
          value: next ? 'true' : 'false',
          description: CLOSURE_DRIVER_DESCRIPTION,
          setting_type: 'boolean',
          is_public: false
        });
        setRow(response.data.setting);
      }
      setEnabled(next);
      showNotification(
        next ? 'Autonomy closure driver enabled' : 'Autonomy closure driver disabled',
        'success'
      );
    } catch (_error) {
      // The stored value did not change, so the control must not claim it did.
      showNotification('Failed to update the autonomy closure driver setting', 'error');
    } finally {
      setSaving(false);
    }
  };

  if (loadState === 'loading') {
    return (
      <div className="flex items-center justify-center py-8">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  const disabled = saving || unknown || !canManage;

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-3">
        <div className="p-2 bg-theme-interactive-primary/10 rounded-lg">
          <Bot className="w-5 h-5 text-theme-interactive-primary" />
        </div>
        <div>
          <h2 className="text-xl font-semibold text-theme-primary">Autonomy</h2>
          <p className="text-sm text-theme-secondary">Platform-wide switches for autonomous agent cadences</p>
        </div>
      </div>

      <div className="bg-theme-surface rounded-lg border border-theme p-6 space-y-4">
        <div className="flex items-center justify-between">
          <div>
            <label htmlFor="closure_driver_enabled" className="text-sm font-medium text-theme-primary">
              Closure Driver
            </label>
            <p className="text-xs text-theme-secondary">
              Run the scheduled autonomy closure cycle. Off by default; saved immediately.
            </p>
            {unknown && (
              <p className="text-xs text-theme-warning-fg mt-1" data-testid="closure-driver-unknown">
                Current state unknown — the setting could not be loaded.
              </p>
            )}
            {!unknown && !canManage && (
              <p className="text-xs text-theme-secondary mt-1" data-testid="closure-driver-readonly">
                Read-only: changing this requires the {CLOSURE_DRIVER_PERMISSION} permission.
              </p>
            )}
          </div>
          <input
            id="closure_driver_enabled"
            type="checkbox"
            role="switch"
            aria-label="Closure Driver"
            checked={enabled && !unknown}
            disabled={disabled}
            onChange={(e) => handleToggle(e.target.checked)}
            className="h-4 w-4 text-theme-interactive-primary border-theme rounded focus:ring-theme-interactive-primary disabled:opacity-50"
          />
        </div>
      </div>
    </div>
  );
};

export default AutonomyConfiguration;
