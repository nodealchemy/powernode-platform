import React, { useEffect, useState, useCallback } from 'react';
import { adminSettingsApi, DevelopmentInfo } from '@/features/admin/services/adminSettingsApi';

/**
 * Generic extensions development panel — lists every loaded extension and lets an
 * admin enable/disable each for development testing. Extension-agnostic: core
 * names no specific extension; per-extension detail comes from the registry.
 */
export const AdminSettingsDevelopmentTabPage: React.FC = () => {
  const [info, setInfo] = useState<DevelopmentInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [togglingSlug, setTogglingSlug] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const fetchInfo = useCallback(async () => {
    try {
      setError(null);
      const response = await adminSettingsApi.getDevelopmentInfo();
      if (response.success && response.data) {
        setInfo(response.data);
      } else {
        setError(response.error || 'Failed to load development info');
      }
    } catch {
      setError('Failed to load development info');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchInfo();
  }, [fetchInfo]);

  const handleToggle = async (slug: string, current: boolean) => {
    setTogglingSlug(slug);
    try {
      const response = await adminSettingsApi.updateExtensionEnabled(slug, !current);
      if (response.success && response.data) {
        const newEnabled = response.data.enabled;
        setInfo(prev =>
          prev
            ? { extensions: prev.extensions.map(e => (e.slug === slug ? { ...e, enabled: newEnabled } : e)) }
            : prev,
        );
      }
    } catch {
      setError(`Failed to toggle ${slug}`);
    } finally {
      setTogglingSlug(null);
    }
  };

  if (loading) {
    return (
      <div className="animate-pulse space-y-4">
        <div className="h-24 bg-theme-surface rounded-lg" />
        <div className="h-48 bg-theme-surface rounded-lg" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="space-y-4">
        <div className="rounded-lg border border-theme-error-border/30 bg-theme-error-fg/5 p-4">
          <p className="text-theme-error-fg text-sm">{error}</p>
        </div>
        <button
          onClick={() => { setLoading(true); fetchInfo(); }}
          className="text-sm text-theme-interactive-primary hover:underline"
        >
          Retry
        </button>
      </div>
    );
  }

  const extensions = info?.extensions ?? [];

  return (
    <div className="space-y-6">
      <div className="rounded-lg border border-theme bg-theme-surface p-6">
        <h3 className="text-lg font-medium text-theme-primary">Extensions</h3>
        <p className="mt-1 text-sm text-theme-secondary">
          Enable or disable loaded extensions for development testing. When an extension
          is disabled, the platform behaves as if it were not installed.
        </p>

        {extensions.length === 0 ? (
          <p className="mt-4 text-sm text-theme-secondary">
            No extensions loaded — running in core mode.
          </p>
        ) : (
          <div className="mt-4 space-y-3">
            {extensions.map(ext => (
              <div
                key={ext.slug}
                className="flex items-center justify-between py-2 border-b border-theme last:border-0"
              >
                <div>
                  <span className="text-sm font-medium text-theme-primary capitalize">
                    {ext.slug.replace(/-/g, ' ')}
                  </span>
                  {ext.version && (
                    <span className="ml-2 text-xs text-theme-tertiary">v{ext.version}</span>
                  )}
                </div>
                <div className="flex items-center gap-3">
                  <span
                    className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ${
                      ext.enabled
                        ? 'bg-theme-success-fg/10 text-theme-success-fg'
                        : 'bg-theme-background-secondary/30 text-theme-secondary'
                    }`}
                  >
                    {ext.enabled ? 'Enabled' : 'Disabled'}
                  </span>
                  <button
                    onClick={() => handleToggle(ext.slug, ext.enabled)}
                    disabled={togglingSlug === ext.slug}
                    className={`relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:ring-offset-2 ${
                      ext.enabled ? 'bg-theme-interactive-primary' : 'bg-theme-background-secondary'
                    } ${togglingSlug === ext.slug ? 'opacity-50 cursor-wait' : ''}`}
                    role="switch"
                    aria-checked={ext.enabled}
                    data-testid={`extension-toggle-${ext.slug}`}
                  >
                    <span
                      className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-theme-surface shadow ring-0 transition duration-200 ease-in-out ${
                        ext.enabled ? 'translate-x-5' : 'translate-x-0'
                      }`}
                    />
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};

export default AdminSettingsDevelopmentTabPage;
