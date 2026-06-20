import React, { useEffect, useState } from 'react';
import { Loader2 } from 'lucide-react';
import { logger } from '@/shared/utils/logger';
import { setupApi, type SetupExtension } from '../services/setupApi';
import type { SetupStepComponentProps } from './types';

/**
 * Extension-selection step — lists the extensions present in this build and lets
 * the operator toggle each. Toggling is live (POST /setup/extensions/:slug) and
 * NON-DESTRUCTIVE: disabling gates the extension off but retains its data. The
 * wizard footer's "Continue" stamps the step complete.
 */
export const ExtensionSelectionStep: React.FC<SetupStepComponentProps> = () => {
  const [extensions, setExtensions] = useState<SetupExtension[] | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    setupApi
      .getExtensions()
      .then((list) => {
        if (!cancelled) setExtensions(list);
      })
      .catch((err) => {
        logger.error('ExtensionSelectionStep: list failed', err);
        if (!cancelled) setExtensions([]);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const toggle = async (ext: SetupExtension) => {
    setBusy(ext.slug);
    setError(null);
    try {
      const updated = await setupApi.setExtension(ext.slug, !ext.enabled);
      setExtensions((prev) =>
        prev?.map((e) => (e.slug === ext.slug ? { ...e, enabled: updated.enabled } : e)) ?? null
      );
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to toggle extension.');
    } finally {
      setBusy(null);
    }
  };

  if (extensions === null) {
    return (
      <div className="flex items-center gap-2 text-sm text-theme-secondary">
        <Loader2 className="h-4 w-4 animate-spin" /> Loading extensions…
      </div>
    );
  }

  if (extensions.length === 0) {
    return (
      <p className="text-sm text-theme-secondary" data-testid="setup-extensions-empty">
        No optional extensions are installed in this build.
      </p>
    );
  }

  return (
    <div className="space-y-2" data-testid="setup-extension-list">
      {extensions.map((ext) => (
        <div
          key={ext.slug}
          className="flex items-center justify-between rounded-md border border-theme bg-theme-surface px-3 py-2"
        >
          <div className="min-w-0">
            <p className="text-sm font-medium text-theme-primary">{ext.slug}</p>
            {ext.version && <p className="text-xs text-theme-secondary">v{ext.version}</p>}
          </div>
          <button
            type="button"
            onClick={() => void toggle(ext)}
            disabled={busy === ext.slug}
            aria-pressed={ext.enabled}
            data-testid={`setup-ext-toggle-${ext.slug}`}
            className={`rounded-md px-3 py-1 text-xs font-semibold ${
              ext.enabled
                ? 'bg-theme-interactive-primary text-white'
                : 'bg-theme-background-secondary text-theme-secondary'
            }`}
          >
            {busy === ext.slug ? '…' : ext.enabled ? 'Enabled' : 'Disabled'}
          </button>
        </div>
      ))}
      {error && (
        <p className="text-xs text-theme-danger-fg" data-testid="setup-ext-error">
          {error}
        </p>
      )}
    </div>
  );
};

export default ExtensionSelectionStep;
