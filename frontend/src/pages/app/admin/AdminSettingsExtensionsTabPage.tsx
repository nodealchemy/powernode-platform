import React, { useEffect, useState, useCallback } from 'react';
import {
  Building2, Puzzle, Package, ExternalLink,
  CheckCircle2, XCircle, Loader2
} from 'lucide-react';
import { adminSettingsApi, ExtensionInfo } from '@/features/admin/services/adminSettingsApi';

const ICON_MAP: Record<string, React.ComponentType<React.SVGProps<SVGSVGElement>>> = {
  'building-2': Building2,
  'puzzle': Puzzle,
  'package': Package,
};

export const AdminSettingsExtensionsTabPage: React.FC = () => {
  const [extensions, setExtensions] = useState<ExtensionInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [togglingSlug, setTogglingSlug] = useState<string | null>(null);

  const fetchExtensions = useCallback(async () => {
    try {
      setError(null);
      const response = await adminSettingsApi.getExtensions();
      if (response.success && response.data) {
        setExtensions(response.data.extensions);
      } else {
        setError(response.error || 'Failed to load extensions');
      }
    } catch {
      setError('Failed to load extensions');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchExtensions();
  }, [fetchExtensions]);

  const handleToggle = async (ext: ExtensionInfo) => {
    if (!ext.installed) return;
    setTogglingSlug(ext.slug);
    try {
      const response = await adminSettingsApi.toggleExtension(ext.slug, !ext.enabled);
      if (response.success && response.data) {
        setExtensions(prev =>
          prev.map(e => e.slug === ext.slug ? { ...e, enabled: response.data!.enabled } : e)
        );
      } else {
        setError(response.error || 'Failed to toggle extension');
      }
    } catch {
      setError('Failed to toggle extension');
    } finally {
      setTogglingSlug(null);
    }
  };

  if (loading) {
    return (
      <div className="animate-pulse space-y-4">
        <div className="h-32 bg-theme-surface rounded-lg" />
        <div className="h-32 bg-theme-surface rounded-lg" />
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
          onClick={() => { setLoading(true); fetchExtensions(); }}
          className="text-sm text-theme-interactive-primary hover:underline"
        >
          Retry
        </button>
      </div>
    );
  }

  if (extensions.length === 0) {
    return (
      <div className="rounded-lg border border-theme bg-theme-surface p-8 text-center">
        <Puzzle className="w-12 h-12 text-theme-tertiary mx-auto mb-3" />
        <h3 className="text-lg font-medium text-theme-primary">No Extensions Found</h3>
        <p className="mt-2 text-sm text-theme-secondary">
          Place extensions in the <code className="text-xs bg-theme-tertiary/20 px-1.5 py-0.5 rounded">extensions/</code> directory with an <code className="text-xs bg-theme-tertiary/20 px-1.5 py-0.5 rounded">extension.json</code> manifest.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {extensions.map((ext) => {
        const IconComponent = ICON_MAP[ext.icon] || Puzzle;
        const isToggling = togglingSlug === ext.slug;

        return (
          <div key={ext.slug} className="rounded-lg border border-theme bg-theme-surface p-6">
            <div className="flex items-start justify-between gap-4">
              {/* Left: icon + info */}
              <div className="flex items-start gap-4 min-w-0">
                <div className="flex-shrink-0 p-2.5 bg-theme-interactive-primary/10 rounded-lg">
                  <IconComponent className="w-6 h-6 text-theme-interactive-primary" />
                </div>
                <div className="min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <h3 className="text-lg font-medium text-theme-primary">{ext.name}</h3>
                    <span className="text-xs text-theme-secondary font-mono">v{ext.version}</span>
                  </div>
                  {ext.description && (
                    <p className="mt-1 text-sm text-theme-secondary">{ext.description}</p>
                  )}
                  {ext.author && (
                    <p className="mt-1 text-xs text-theme-tertiary">
                      By {ext.homepage ? (
                        <a href={ext.homepage} target="_blank" rel="noopener noreferrer" className="text-theme-interactive-primary hover:underline inline-flex items-center gap-1">
                          {ext.author} <ExternalLink className="w-3 h-3" />
                        </a>
                      ) : ext.author}
                    </p>
                  )}
                </div>
              </div>

              {/* Right: badges + toggle */}
              <div className="flex flex-col items-end gap-3 flex-shrink-0">
                {/* Status badges */}
                <div className="flex items-center gap-2">
                  <span className={`inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-xs font-medium ${
                    ext.installed
                      ? 'bg-theme-success/10 text-theme-success'
                      : 'bg-theme-tertiary/30 text-theme-secondary'
                  }`}>
                    {ext.installed ? <CheckCircle2 className="w-3 h-3" /> : <XCircle className="w-3 h-3" />}
                    {ext.installed ? 'Installed' : 'Not loaded'}
                  </span>
                  <span className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium ${
                    ext.enabled
                      ? 'bg-theme-interactive-primary/10 text-theme-interactive-primary'
                      : 'bg-theme-tertiary/30 text-theme-secondary'
                  }`}>
                    {ext.enabled ? 'Enabled' : 'Disabled'}
                  </span>
                </div>

                {/* Toggle */}
                <button
                  onClick={() => handleToggle(ext)}
                  disabled={!ext.installed || isToggling}
                  className={`relative inline-flex h-6 w-11 flex-shrink-0 rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary focus:ring-offset-2 ${
                    ext.enabled
                      ? 'bg-theme-interactive-primary'
                      : 'bg-theme-tertiary'
                  } ${!ext.installed ? 'opacity-40 cursor-not-allowed' : isToggling ? 'opacity-50 cursor-wait' : 'cursor-pointer'}`}
                  role="switch"
                  aria-checked={ext.enabled}
                  aria-label={`Toggle ${ext.name}`}
                  title={!ext.installed ? 'Engine not loaded — restart the backend to install' : `${ext.enabled ? 'Disable' : 'Enable'} ${ext.name}`}
                  data-testid={`extension-toggle-${ext.slug}`}
                >
                  {isToggling ? (
                    <span className="flex items-center justify-center h-5 w-5 transform rounded-full bg-white shadow">
                      <Loader2 className="w-3 h-3 animate-spin text-theme-tertiary" />
                    </span>
                  ) : (
                    <span
                      className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out ${
                        ext.enabled ? 'translate-x-5' : 'translate-x-0'
                      }`}
                    />
                  )}
                </button>
              </div>
            </div>

            {/* Capabilities */}
            {ext.capabilities.length > 0 && (
              <div className="mt-4 flex flex-wrap gap-2">
                {ext.capabilities.map((cap) => (
                  <span
                    key={cap}
                    className="inline-flex items-center rounded-md bg-theme-tertiary/15 px-2 py-1 text-xs text-theme-secondary"
                  >
                    {cap}
                  </span>
                ))}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
};

export default AdminSettingsExtensionsTabPage;
