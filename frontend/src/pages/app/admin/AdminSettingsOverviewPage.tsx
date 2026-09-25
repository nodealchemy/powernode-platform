import React, { useState, useEffect, useCallback, useMemo, Suspense } from 'react';
import { useNavigate } from 'react-router-dom';
import { useSelector } from 'react-redux';
import { RootState } from '@/shared/services';
import { adminSettingsApi, AdminOverviewData } from '@/features/admin/services/adminSettingsApi';
import { MetricCard as StandardMetricCard } from '@/shared/components/ui/Card';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { SystemStatusCard } from '@/features/admin/components/admin-settings';
import { featureRegistry } from '@/shared/services/featureRegistry';
import { hasPermissions } from '@/shared/utils/permissionUtils';

// Extension metric cards mount through this generic component-slot prefix:
// featureRegistry.registerComponentSlots({ 'admin.settings.overview.<id>':
// Card }), optionally gated by registerSlotMeta permissions. Core names no
// extension and renders no extension data of its own.
const OVERVIEW_SLOT_PREFIX = 'admin.settings.overview.';

// The registered overview cards the viewer may see, re-read whenever an
// extension registers one.
const useOverviewSlotCards = (): Array<{ id: string; Card: React.ComponentType }> => {
  const { user } = useSelector((state: RootState) => state.auth);
  const [registryVersion, setRegistryVersion] = useState(() => featureRegistry.getVersion());
  useEffect(
    () => featureRegistry.subscribe(() => setRegistryVersion(featureRegistry.getVersion())),
    []
  );

  return useMemo(
    () =>
      featureRegistry.getComponentSlotIds(OVERVIEW_SLOT_PREFIX).flatMap((id) => {
        const Card = featureRegistry.getComponentSlot(id) as React.ComponentType | undefined;
        const permissions = featureRegistry.getSlotMeta(id)?.permissions ?? [];
        if (!Card || !hasPermissions(user, permissions)) return [];
        return [{ id, Card }];
      }),
    // eslint-disable-next-line react-hooks/exhaustive-deps -- registryVersion is the real dependency; the registry is a stable singleton.
    [registryVersion, user]
  );
};

export const AdminSettingsOverviewPage: React.FC = () => {
  const navigate = useNavigate();
  const slotCards = useOverviewSlotCards();
  const [data, setData] = useState<AdminOverviewData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const { showNotification } = useNotifications();

  const loadOverviewData = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);

      const overviewData = await adminSettingsApi.getOverview();

      setData(overviewData.data || null);
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to load admin overview data';
      console.error('Admin overview load error:', error);
      setError(errorMessage);
      showNotification('Failed to load admin overview data', 'error');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadOverviewData();
  }, [loadOverviewData]);


  if (loading && !data) {
    return (
      <LoadingSpinner size="lg" className="h-64" message="Loading system overview..." />
    );
  }

  if (error) {
    return (
      <div className="bg-theme-error-bg border border-theme-error-border rounded-xl p-6">
        <div className="flex items-center gap-3 mb-4">
          <span className="text-theme-error-fg text-2xl">⚠️</span>
          <div>
            <h3 className="text-lg font-semibold text-theme-error-fg">Unable to Load System Data</h3>
            <p className="text-theme-error-fg">{error}</p>
          </div>
        </div>
        <button
          onClick={loadOverviewData}
          className="btn-theme btn-theme-danger"
        >
          Retry Loading
        </button>
      </div>
    );
  }

  if (!data) return null;

  const { metrics, settings_summary } = data;

  // Determine overall system status
  const getSystemStatus = () => {
    if (settings_summary?.maintenance_mode) return { status: 'maintenance' as const, message: 'System in maintenance mode' };
    if (metrics.system_health === 'error') return { status: 'error' as const, message: 'System experiencing errors' };
    if (metrics.system_health === 'warning') return { status: 'warning' as const, message: 'System has warnings' };

    return { status: 'healthy' as const, message: 'All systems operational' };
  };

  const systemStatus = getSystemStatus();

  return (
    <div className="space-y-6">
      {/* System Status Indicator */}
      <div className="flex items-center gap-4 p-4 bg-theme-surface rounded-lg border border-theme">
        <span className="text-theme-secondary">System Status:</span>
        <div className="flex items-center gap-2">
          <div className={`w-2 h-2 rounded-full ${
            systemStatus.status === 'healthy' ? 'bg-theme-success-bg' :
            systemStatus.status === 'warning' ? 'bg-theme-warning-bg' :
            systemStatus.status === 'error' ? 'bg-theme-error-bg' :
            'bg-theme-warning-bg'
          }`} />
          <span className={`text-sm font-medium ${
            systemStatus.status === 'healthy' ? 'text-theme-success-fg' :
            systemStatus.status === 'warning' ? 'text-theme-warning-fg' :
            systemStatus.status === 'error' ? 'text-theme-error-fg' :
            'text-theme-warning-fg'
          }`}>
            {systemStatus.message}
          </span>
        </div>
      </div>

      {/* System Status Alert */}
      {systemStatus.status !== 'healthy' && (
        <div className={`p-4 rounded-xl border ${
          systemStatus.status === 'maintenance' ? 'bg-theme-warning-bg border-theme-warning-border' :
          systemStatus.status === 'warning' ? 'bg-theme-warning-bg border-theme-warning-border' :
          'bg-theme-error-bg border-theme-error-border'
        }`}>
          <div className="flex items-center gap-3">
            <span className="text-2xl">
              {systemStatus.status === 'maintenance' ? '🔧' :
               systemStatus.status === 'warning' ? '⚠️' : '❌'}
            </span>
            <div>
              <h3 className={`font-semibold ${
                systemStatus.status === 'maintenance' ? 'text-theme-warning-fg' :
                systemStatus.status === 'warning' ? 'text-theme-warning-fg' :
                'text-theme-error-fg'
              }`}>
                System Status Alert
              </h3>
              <p className={`text-sm ${
                systemStatus.status === 'maintenance' ? 'text-theme-warning-fg' :
                systemStatus.status === 'warning' ? 'text-theme-warning-fg' :
                'text-theme-error-fg'
              }`}>
                {systemStatus.message}. Please review system settings and logs for details.
              </p>
            </div>
          </div>
        </div>
      )}

      {/* System Status Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <SystemStatusCard
          title="System Health"
          status={metrics.system_health}
          value={metrics.system_health === 'healthy' ? 'Operational' : 
                 metrics.system_health === 'warning' ? 'Warnings' : 'Critical'}
          description={`Uptime: ${adminSettingsApi.formatUptime(metrics.uptime)}`}
        />

        <SystemStatusCard
          title="Maintenance Mode"
          status={settings_summary?.maintenance_mode ? 'maintenance' : 'healthy'}
          value={settings_summary?.maintenance_mode ? 'ACTIVE' : 'Disabled'}
          description={settings_summary?.maintenance_mode ? 'Users cannot access system' : 'System fully accessible'}
          action={{
            // One control for maintenance mode: this badge links to the
            // Maintenance tab, which is the only place that writes it
            // (Api::V1::Admin::Maintenance::MaintenanceController#update_mode).
            label: settings_summary?.maintenance_mode ? 'Manage Maintenance Mode' : 'Enable Maintenance Mode',
            onClick: () => navigate('/app/admin/maintenance/mode')
          }}
        />

        <SystemStatusCard
          title="Registration"
          status={settings_summary?.registration_enabled ? 'healthy' : 'warning'}
          value={settings_summary?.registration_enabled ? 'Open' : 'Closed'}
          description={settings_summary?.registration_enabled ? 'New users can register' : 'Registration disabled'}
        />
      </div>

      {/* Key Metrics */}
      <div>
        <h2 className="text-xl font-semibold text-theme-primary mb-6 flex items-center gap-2">
          <span>📊</span>
          <span>Key Metrics</span>
        </h2>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
          <StandardMetricCard
            title="Total Users"
            value={adminSettingsApi.formatNumber(metrics.total_users)}
            icon="👥"
            description="Platform users"
          />
          <StandardMetricCard
            title="Active Accounts"
            value={`${metrics.active_accounts}/${metrics.total_accounts}`}
            icon="🏢"
            description="Business accounts"
          />
          {slotCards.map(({ id, Card }) => (
            <Suspense key={id} fallback={<LoadingSpinner size="sm" />}>
              <Card />
            </Suspense>
          ))}
        </div>
      </div>

      {/* Footer */}
      <div className="bg-theme-background-secondary rounded-xl p-4 border border-theme">
        <div className="flex items-center justify-between text-sm text-theme-secondary">
          <div className="flex items-center gap-4">
            <span>Last updated: {settings_summary?.updated_at ? adminSettingsApi.formatRelativeTime(settings_summary.updated_at) : 'Never'}</span>
            <span>•</span>
            <span>Data refreshed: {new Date().toLocaleTimeString()}</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-2 h-2 bg-theme-success-bg rounded-full animate-pulse"></div>
            <span>Live Data</span>
          </div>
        </div>
      </div>
    </div>
  );
};