import React, { useState, useEffect } from 'react';
import { Info, Server, Monitor, GitBranch, Clock } from 'lucide-react';
import { versionApi, VersionInfo, FullVersionInfo, HealthInfo } from '@/shared/services/system/versionApi';

interface VersionDisplayProps {
  show?: 'simple' | 'detailed' | 'badge';
  showFrontend?: boolean;
  showBackend?: boolean;
  className?: string;
}

export const VersionDisplay: React.FC<VersionDisplayProps> = ({
  show = 'simple',
  showFrontend = true,
  showBackend = true,
  className = ''
}) => {
  const [backendVersion, setBackendVersion] = useState<VersionInfo | null>(null);
  const [fullVersion, setFullVersion] = useState<FullVersionInfo | null>(null);
  const [health, setHealth] = useState<HealthInfo | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const frontendVersion = versionApi.getFrontendVersion();

  useEffect(() => {
    const fetchVersionInfo = async () => {
      try {
        setLoading(true);
        setError(null);

        if (showBackend) {
          // Add timeout and retry logic
          const fetchWithTimeout = async <T,>(promise: Promise<T>, timeoutMs = 5000): Promise<T> => {
            const timeoutPromise = new Promise<never>((_, reject) =>
              setTimeout(() => reject(new Error('Request timeout')), timeoutMs)
            );
            return Promise.race([promise, timeoutPromise]);
          };

          try {
            const [versionResponse, fullResponse, healthResponse] = await Promise.allSettled([
              fetchWithTimeout(versionApi.getVersion()),
              show === 'detailed' ? fetchWithTimeout(versionApi.getFullVersion()) : Promise.resolve({ success: false, data: {} as FullVersionInfo }),
              show === 'detailed' ? fetchWithTimeout(versionApi.getHealth()) : Promise.resolve({ success: false, data: {} as HealthInfo })
            ]);

            if (versionResponse.status === 'fulfilled' && versionResponse.value.success) {
              setBackendVersion(versionResponse.value.data);
            }

            if (fullResponse.status === 'fulfilled' && fullResponse.value.success) {
              setFullVersion(fullResponse.value.data);
            }

            if (healthResponse.status === 'fulfilled' && healthResponse.value.success) {
              setHealth(healthResponse.value.data);
            }
          } catch (error) {
            // Silently fail version fetching - it's not critical to app functionality
          }
        }
      } catch (error) {
        // Only log warnings for version fetching failures
      } finally {
        setLoading(false);
      }
    };

    fetchVersionInfo();
  }, [showBackend, show]);

  if (loading && showBackend) {
    return (
      <div className={`text-xs text-theme-tertiary ${className}`}>
        Loading version...
      </div>
    );
  }

  if (error && showBackend) {
    return (
      <div className={`text-xs text-theme-error ${className}`}>
        Version unavailable
      </div>
    );
  }

  // Badge display
  if (show === 'badge') {
    return (
      <div className={`flex items-center gap-2 ${className}`}>
        {showFrontend && (
          <span className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-medium ${versionApi.getVersionBadgeColor(frontendVersion)}`}>
            <Monitor className="w-3 h-3 mr-1" />
            Frontend {versionApi.formatVersion(frontendVersion)}
          </span>
        )}
        {showBackend && backendVersion && (
          <span className={`inline-flex items-center px-2 py-1 rounded-full text-xs font-medium ${versionApi.getVersionBadgeColor(backendVersion.version)}`}>
            <Server className="w-3 h-3 mr-1" />
            Backend {versionApi.formatVersion(backendVersion.version)}
          </span>
        )}
      </div>
    );
  }

  // Simple display
  if (show === 'simple') {
    const versions = [];
    if (showFrontend) {
      versions.push(`Frontend ${versionApi.formatVersion(frontendVersion)}`);
    }
    if (showBackend && backendVersion) {
      versions.push(`Backend ${versionApi.formatVersion(backendVersion.version)}`);
    }

    return (
      <div className={`text-xs text-theme-tertiary ${className}`}>
        {versions.join(' • ')}
      </div>
    );
  }

  // Detailed display
  if (show === 'detailed') {
    return (
      <div className={`space-y-4 ${className}`}>
        <div className="flex items-center gap-2 text-sm font-medium text-theme-primary">
          <Info className="w-4 h-4" />
          System Version Information
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {/* Frontend Version */}
          {showFrontend && (
            <div className="space-y-2">
              <div className="flex items-center gap-2 text-sm font-medium text-theme-primary">
                <Monitor className="w-4 h-4" />
                Frontend
              </div>
              <div className="space-y-1 text-xs">
                <div className="flex justify-between">
                  <span className="text-theme-secondary">Version:</span>
                  <span className="text-theme-primary font-mono">{frontendVersion}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-theme-secondary">Environment:</span>
                  <span className="text-theme-primary">{process.env.NODE_ENV || 'development'}</span>
                </div>
              </div>
            </div>
          )}

          {/* Backend Version */}
          {showBackend && (backendVersion || fullVersion) && (
            <div className="space-y-2">
              <div className="flex items-center gap-2 text-sm font-medium text-theme-primary">
                <Server className="w-4 h-4" />
                Backend
              </div>
              <div className="space-y-1 text-xs">
                <div className="flex justify-between">
                  <span className="text-theme-secondary">Version:</span>
                  <span className="text-theme-primary font-mono">
                    {backendVersion?.version || fullVersion?.version}
                  </span>
                </div>
                {fullVersion && (
                  <>
                    <div className="flex justify-between">
                      <span className="text-theme-secondary">Environment:</span>
                      <span className="text-theme-primary">{fullVersion.environment}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-theme-secondary">Rails:</span>
                      <span className="text-theme-primary">{fullVersion.rails_version}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-theme-secondary">Ruby:</span>
                      <span className="text-theme-primary">{fullVersion.ruby_version}</span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-theme-secondary">Branch:</span>
                      <span className="text-theme-primary flex items-center gap-1">
                        <GitBranch className="w-3 h-3" />
                        {fullVersion.git_branch}
                      </span>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-theme-secondary">Commit:</span>
                      <span className="text-theme-primary font-mono">{fullVersion.git_commit}</span>
                    </div>
                  </>
                )}
                {backendVersion && (
                  <div className="flex justify-between">
                    <span className="text-theme-secondary">Build Date:</span>
                    <span className="text-theme-primary">
                      {new Date(backendVersion.build_date).toLocaleString()}
                    </span>
                  </div>
                )}
              </div>
            </div>
          )}
        </div>

        {/* Health Information */}
        {health && (
          <div className="border-t border-theme pt-4">
            <div className="flex items-center gap-2 text-sm font-medium text-theme-primary mb-2">
              <Clock className="w-4 h-4" />
              System Health
            </div>
            <div className="grid grid-cols-2 gap-4 text-xs">
              <div className="flex justify-between">
                <span className="text-theme-secondary">Status:</span>
                <span className={`${health.status === 'healthy' ? 'text-theme-success' : 'text-theme-error'}`}>
                  {health.status}
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-theme-secondary">Uptime:</span>
                <span className="text-theme-primary">{health.uptime.uptime_human}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-theme-secondary">Boot Time:</span>
                <span className="text-theme-primary">
                  {new Date(health.uptime.boot_time).toLocaleString()}
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-theme-secondary">Last Check:</span>
                <span className="text-theme-primary">
                  {new Date(health.timestamp).toLocaleTimeString()}
                </span>
              </div>
            </div>
          </div>
        )}
      </div>
    );
  }

  return null;
};

export default VersionDisplay;