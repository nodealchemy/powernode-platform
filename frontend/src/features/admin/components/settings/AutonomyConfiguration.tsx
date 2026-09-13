import React, { useState, useEffect, useCallback } from 'react';
import { Bot } from 'lucide-react';
import { useSelector } from 'react-redux';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { siteSettingsApi, SiteSetting } from '@/features/admin/settings/services/siteSettingsApi';
import { RootState } from '@/shared/services';

// Platform-wide autonomy switches. Every control here is a SiteSetting, not an
// AdminSetting. Those are different tables, and every gate these controls feed
// reads SiteSetting — a control wired to the other one would render, save and
// notify success while actuating nothing.

// D3 — the AI autonomy closure driver's cadence flag
// (Ai::Autonomy::ClosureDriverService.enabled?). Absent means OFF.
export const CLOSURE_DRIVER_SETTING_KEY = 'ai.autonomy.closure_driver_enabled';

// D5 — the LLM judge (Ai::Learning::EvaluationService). These replace the
// :agent_evaluation Flipper flag, which no UI and no API could reach. The
// judge is ON by default, so an ABSENT enabled row means ON — the opposite of
// the closure driver — and an absent cap means the server default.
export const EVALUATION_ENABLED_SETTING_KEY = 'ai.evaluation.enabled';
export const EVALUATION_DAILY_CAP_SETTING_KEY = 'ai.evaluation.daily_cap';
export const DEFAULT_EVALUATION_DAILY_CAP = 20;

// The permission the write endpoint itself names.
export const CLOSURE_DRIVER_PERMISSION = 'settings.manage';
export const AUTONOMY_SETTINGS_PERMISSION = CLOSURE_DRIVER_PERMISSION;

const DESCRIPTIONS: Record<string, string> = {
  [CLOSURE_DRIVER_SETTING_KEY]:
    'Run the AI autonomy closure driver on its cron cadence. OFF means the scheduled OODA cycle ' +
    'never runs; every other autonomy gate still applies when it is ON.',
  [EVALUATION_ENABLED_SETTING_KEY]:
    'Run the LLM judge on completed agent work. OFF means no evaluation is judged, persisted, ' +
    'or credited to trust or skill versions.',
  [EVALUATION_DAILY_CAP_SETTING_KEY]:
    'Maximum LLM-judge evaluations per account per rolling day. A missing, zero or non-numeric ' +
    'value falls back to the default.'
};

type LoadState = 'loading' | 'loaded' | 'unknown';
type Rows = Record<string, SiteSetting | null>;

const KEYS = [CLOSURE_DRIVER_SETTING_KEY, EVALUATION_ENABLED_SETTING_KEY, EVALUATION_DAILY_CAP_SETTING_KEY];

// Only a positive whole number is a cap. The server guards the same way
// (positive? or the default), but a control that accepted 0 would appear to
// switch the judge off while the server silently used 20.
export const parseDailyCap = (raw: string): number | null => {
  const trimmed = raw.trim();
  if (!/^\d+$/.test(trimmed)) return null;
  const value = Number(trimmed);
  return Number.isSafeInteger(value) && value > 0 ? value : null;
};

export const AutonomyConfiguration: React.FC = () => {
  // Permissions, never roles.
  const { user } = useSelector((state: RootState) => state.auth);
  const permissions = user?.permissions;
  const canManage = Array.isArray(permissions) && permissions.includes(AUTONOMY_SETTINGS_PERMISSION);

  const [rows, setRows] = useState<Rows>({});
  const [loadState, setLoadState] = useState<LoadState>('loading');
  const [saving, setSaving] = useState<string | null>(null);
  const [capDraft, setCapDraft] = useState('');

  const { showNotification } = useNotifications();

  const load = useCallback(async () => {
    try {
      const response = await siteSettingsApi.getSiteSettings();
      const settings = response.data?.settings ?? [];
      const found: Rows = {};
      KEYS.forEach(key => {
        found[key] = settings.find(s => s.key === key) ?? null;
      });
      // An absent row is a real, expected state — seeds do not re-run after
      // first boot, so an install older than a seed line has none — and each
      // control renders the server's meaning of absence. That is NOT the same
      // as a failed load, which is handled below.
      setRows(found);
      setCapDraft(found[EVALUATION_DAILY_CAP_SETTING_KEY]?.value ?? '');
      setLoadState('loaded');
    } catch (_error) {
      // Do not render a confident state for controls we could not read: they
      // say unknown and refuse to act until a load succeeds.
      setRows({});
      setLoadState('unknown');
      showNotification('Could not load the autonomy settings', 'error');
    }
  }, [showNotification]);

  useEffect(() => {
    load();
  }, [load]);

  const unknown = loadState === 'unknown';

  // One write path for every control: update the row when it exists, create it
  // with its declared type when it does not. Returns whether it stuck.
  const write = async (key: string, value: string, settingType: 'boolean' | 'integer'): Promise<boolean> => {
    // The real guard. `disabled` is presentation — jsdom (and any synthetic
    // event) still delivers a change to a disabled input, so a control that
    // gated only on the attribute would still call the write endpoint.
    if (!canManage || unknown) return false;

    setSaving(key);
    try {
      const row = rows[key];
      const response = row
        ? await siteSettingsApi.updateSiteSetting(row.id, { value })
        : await siteSettingsApi.createSiteSetting({
            key,
            value,
            description: DESCRIPTIONS[key],
            setting_type: settingType,
            is_public: false
          });
      setRows(prev => ({ ...prev, [key]: response.data.setting }));
      return true;
    } catch (_error) {
      // The stored value did not change, so the control must not claim it did.
      return false;
    } finally {
      setSaving(null);
    }
  };

  const closureEnabled = rows[CLOSURE_DRIVER_SETTING_KEY]?.value === 'true';
  // Absent means ON (the ruled default); only an explicit "true" is ON once a
  // row exists, so an unparseable stored value never reads as enabled.
  const judgeRow = rows[EVALUATION_ENABLED_SETTING_KEY];
  const judgeEnabled = judgeRow ? judgeRow.value === 'true' : true;
  const storedCap = rows[EVALUATION_DAILY_CAP_SETTING_KEY]?.value ?? null;
  const effectiveCap = (storedCap !== null && parseDailyCap(storedCap)) || DEFAULT_EVALUATION_DAILY_CAP;

  const toggleClosure = async (next: boolean) => {
    const ok = await write(CLOSURE_DRIVER_SETTING_KEY, next ? 'true' : 'false', 'boolean');
    if (ok) {
      showNotification(next ? 'Autonomy closure driver enabled' : 'Autonomy closure driver disabled', 'success');
    } else if (canManage && !unknown) {
      showNotification('Failed to update the autonomy closure driver setting', 'error');
    }
  };

  const toggleJudge = async (next: boolean) => {
    const ok = await write(EVALUATION_ENABLED_SETTING_KEY, next ? 'true' : 'false', 'boolean');
    if (ok) {
      showNotification(next ? 'LLM judge enabled' : 'LLM judge disabled', 'success');
    } else if (canManage && !unknown) {
      showNotification('Failed to update the LLM judge setting', 'error');
    }
  };

  const saveCap = async () => {
    if (!canManage || unknown) return;
    const cap = parseDailyCap(capDraft);
    if (cap === null) {
      showNotification('The daily cap must be a whole number greater than zero', 'error');
      return;
    }
    const ok = await write(EVALUATION_DAILY_CAP_SETTING_KEY, String(cap), 'integer');
    showNotification(
      ok ? `LLM judge daily cap set to ${cap}` : 'Failed to update the LLM judge daily cap',
      ok ? 'success' : 'error'
    );
  };

  if (loadState === 'loading') {
    return (
      <div className="flex items-center justify-center py-8">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  const disabledFor = (key: string) => saving === key || unknown || !canManage;

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

      {unknown && (
        <p className="text-xs text-theme-warning-fg" data-testid="closure-driver-unknown">
          Current state unknown — the autonomy settings could not be loaded.
        </p>
      )}
      {!unknown && !canManage && (
        <p className="text-xs text-theme-secondary" data-testid="closure-driver-readonly">
          Read-only: changing these requires the {AUTONOMY_SETTINGS_PERMISSION} permission.
        </p>
      )}

      <div className="bg-theme-surface rounded-lg border border-theme p-6 space-y-6">
        <div className="flex items-center justify-between">
          <div>
            <label htmlFor="closure_driver_enabled" className="text-sm font-medium text-theme-primary">
              Closure Driver
            </label>
            <p className="text-xs text-theme-secondary">
              Run the scheduled autonomy closure cycle. Off by default; saved immediately.
            </p>
          </div>
          <input
            id="closure_driver_enabled"
            type="checkbox"
            role="switch"
            aria-label="Closure Driver"
            checked={closureEnabled && !unknown}
            disabled={disabledFor(CLOSURE_DRIVER_SETTING_KEY)}
            onChange={(e) => toggleClosure(e.target.checked)}
            className="h-4 w-4 text-theme-interactive-primary border-theme rounded focus:ring-theme-interactive-primary disabled:opacity-50"
          />
        </div>

        <div className="flex items-center justify-between">
          <div>
            <label htmlFor="evaluation_enabled" className="text-sm font-medium text-theme-primary">
              LLM Judge
            </label>
            <p className="text-xs text-theme-secondary">
              Judge completed agent work and credit trust and skill versions. On by default; saved immediately.
            </p>
          </div>
          <input
            id="evaluation_enabled"
            type="checkbox"
            role="switch"
            aria-label="LLM Judge"
            checked={judgeEnabled && !unknown}
            disabled={disabledFor(EVALUATION_ENABLED_SETTING_KEY)}
            onChange={(e) => toggleJudge(e.target.checked)}
            className="h-4 w-4 text-theme-interactive-primary border-theme rounded focus:ring-theme-interactive-primary disabled:opacity-50"
          />
        </div>

        <div className="flex items-center justify-between gap-4">
          <div>
            <label htmlFor="evaluation_daily_cap" className="text-sm font-medium text-theme-primary">
              LLM Judge daily cap
            </label>
            <p className="text-xs text-theme-secondary" data-testid="evaluation-daily-cap-effective">
              Evaluations per account per rolling day. In effect: {unknown ? 'unknown' : effectiveCap}
              {!unknown && storedCap === null ? ' (default)' : ''}.
            </p>
          </div>
          <div className="flex items-center gap-2">
            <input
              id="evaluation_daily_cap"
              type="text"
              inputMode="numeric"
              aria-label="LLM Judge daily cap"
              placeholder={String(DEFAULT_EVALUATION_DAILY_CAP)}
              value={capDraft}
              disabled={disabledFor(EVALUATION_DAILY_CAP_SETTING_KEY)}
              onChange={(e) => setCapDraft(e.target.value)}
              className="w-24 px-2 py-1 text-sm bg-theme-background border border-theme rounded text-theme-primary disabled:opacity-50"
            />
            <button
              type="button"
              onClick={saveCap}
              disabled={disabledFor(EVALUATION_DAILY_CAP_SETTING_KEY)}
              className="px-3 py-1 text-sm rounded bg-theme-interactive-primary text-theme-on-primary disabled:opacity-50"
            >
              Save cap
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default AutonomyConfiguration;
