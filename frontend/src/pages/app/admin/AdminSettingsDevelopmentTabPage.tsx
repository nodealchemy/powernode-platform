import React, { useEffect, useState, useCallback } from 'react';
import { adminSettingsApi, DevelopmentInfo } from '@/features/admin/services/adminSettingsApi';

export const AdminSettingsDevelopmentTabPage: React.FC = () => {
  const [info, setInfo] = useState<DevelopmentInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [toggling, setToggling] = useState(false);
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

  const handleToggle = async () => {
    if (!info) return;
    setToggling(true);
    try {
      const response = await adminSettingsApi.updateDevelopmentSettings(!info.business_enabled);
      if (response.success && response.data) {
        setInfo(prev => prev ? { ...prev, business_enabled: response.data.business_enabled } : prev);
      }
    } catch {
      setError('Failed to toggle business mode');
    } finally {
      setToggling(false);
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
        <div className="rounded-lg border border-theme-error/30 bg-theme-error/5 p-4">
          <p className="text-theme-error text-sm">{error}</p>
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

  if (!info) {
    return (
      <div className="rounded-lg border border-theme bg-theme-surface p-6">
        <p className="text-sm text-theme-secondary">
          Unable to load business development settings. Ensure the backend is running and business engine is loaded.
        </p>
      </div>
    );
  }

  if (!info.business_installed) {
    return (
      <div className="rounded-lg border border-theme bg-theme-surface p-6">
        <h3 className="text-lg font-medium text-theme-primary">Business Not Loaded</h3>
        <p className="mt-2 text-sm text-theme-secondary">
          The business submodule is present but the engine is not loaded on the backend.
          Restart the backend service to load the business engine.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Business Mode Toggle */}
      <div className="rounded-lg border border-theme bg-theme-surface p-6">
        <div className="flex items-center justify-between">
          <div>
            <h3 className="text-lg font-medium text-theme-primary">Business Mode</h3>
            <p className="mt-1 text-sm text-theme-secondary">
              Toggle business features on or off for development testing.
              When disabled, the platform behaves as the open-core edition.
            </p>
          </div>
          <button
            onClick={handleToggle}
            disabled={toggling}
            className={`relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:ring-offset-2 ${
              info.business_enabled
                ? 'bg-theme-interactive-primary'
                : 'bg-theme-tertiary'
            } ${toggling ? 'opacity-50 cursor-wait' : ''}`}
            role="switch"
            aria-checked={info.business_enabled}
            data-testid="business-mode-toggle"
          >
            <span
              className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out ${
                info.business_enabled ? 'translate-x-5' : 'translate-x-0'
              }`}
            />
          </button>
        </div>

        <div className="mt-4 flex items-center gap-2">
          <span className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ${
            info.business_enabled
              ? 'bg-theme-success/10 text-theme-success'
              : 'bg-theme-tertiary/30 text-theme-secondary'
          }`}>
            {info.business_enabled ? 'Enabled' : 'Disabled'}
          </span>
        </div>
      </div>

      {/* Business Info */}
      <div className="rounded-lg border border-theme bg-theme-surface p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-4">Business Details</h3>
        <dl className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          {info.engine_version && (
            <div>
              <dt className="text-sm font-medium text-theme-secondary">Engine Version</dt>
              <dd className="mt-1 text-sm text-theme-primary">{info.engine_version}</dd>
            </div>
          )}
          <div>
            <dt className="text-sm font-medium text-theme-secondary">License Status</dt>
            <dd className="mt-1">
              <span className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ${
                info.license_valid
                  ? 'bg-theme-success/10 text-theme-success'
                  : 'bg-theme-warning/10 text-theme-warning'
              }`}>
                {info.license_valid ? 'Valid' : 'Not configured'}
              </span>
            </dd>
          </div>
          {info.license_edition && (
            <div>
              <dt className="text-sm font-medium text-theme-secondary">License Edition</dt>
              <dd className="mt-1 text-sm text-theme-primary capitalize">{info.license_edition}</dd>
            </div>
          )}
        </dl>
      </div>

      {/* Feature Flags */}
      {info.feature_flags && info.feature_flags.length > 0 && (
        <div className="rounded-lg border border-theme bg-theme-surface p-6">
          <h3 className="text-lg font-medium text-theme-primary mb-4">Business Feature Flags</h3>
          <div className="space-y-3">
            {info.feature_flags.map((flag) => (
              <div key={flag.name} className="flex items-center justify-between py-2 border-b border-theme last:border-0">
                <span className="text-sm text-theme-primary font-mono">
                  {flag.name.replace(/^business_/, '').replace(/_/g, ' ')}
                </span>
                <span className={`inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ${
                  flag.enabled
                    ? 'bg-theme-success/10 text-theme-success'
                    : 'bg-theme-tertiary/30 text-theme-secondary'
                }`}>
                  {flag.enabled ? 'on' : 'off'}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
};

export default AdminSettingsDevelopmentTabPage;
