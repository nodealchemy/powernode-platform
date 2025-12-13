import React from 'react';
import { maintenanceApi } from '@/shared/services/maintenanceApi';
import { SettingsCard } from '@/features/admin/components/settings/SettingsComponents';
import { MaintenanceOverviewTabProps, MaintenanceTab } from './types';

// Helper functions
const getHealthColor = (status: string) => {
  switch (status) {
    case 'healthy': return 'text-theme-success';
    case 'warning': return 'text-theme-warning';
    case 'critical': return 'text-theme-error';
    default: return 'text-theme-secondary';
  }
};

const getHealthBgColor = (status: string) => {
  switch (status) {
    case 'healthy': return 'bg-theme-success-background';
    case 'warning': return 'bg-theme-warning-background';
    case 'critical': return 'bg-theme-error-background';
    default: return 'bg-theme-surface';
  }
};

export const MaintenanceOverviewTab: React.FC<MaintenanceOverviewTabProps> = ({
  maintenanceStatus,
  systemHealth,
  systemMetrics,
  backups,
  cleanupStats,
  schedules,
  onNavigateToTab
}) => {
  // Calculate overall system status
  const getOverallStatus = () => {
    if (!systemHealth) return { status: 'unknown', label: 'Unknown', icon: '❓' };
    const { overall_status } = systemHealth;

    if (overall_status === 'healthy') {
      return { status: 'healthy', label: 'All Systems Operational', icon: '✅' };
    }
    if (overall_status === 'critical') {
      return { status: 'critical', label: 'Critical Issues Detected', icon: '🚨' };
    }
    return { status: 'warning', label: 'Some Services Degraded', icon: '⚠️' };
  };

  // Count healthy services
  const getHealthyServiceCount = () => {
    if (!systemHealth) return 0;
    let count = 0;
    if (systemHealth.database?.status === 'healthy') count++;
    if (systemHealth.redis?.status === 'healthy') count++;
    if (systemHealth.storage?.status === 'healthy') count++;
    const healthyServices = systemHealth.services?.filter(s => s.status === 'healthy').length || 0;
    return count + healthyServices;
  };

  // Get total cleanup items
  const getTotalCleanupItems = () => {
    if (!cleanupStats) return 0;
    return (cleanupStats.old_logs || 0) +
           (cleanupStats.expired_sessions || 0) +
           (cleanupStats.temporary_files || 0) +
           (cleanupStats.orphaned_uploads || 0);
  };

  const overallStatus = getOverallStatus();
  const latestBackup = backups[0];
  const activeSchedules = schedules.filter(s => s.enabled).length;

  return (
    <div className="space-y-6">
      {/* System Status Banner */}
      <div className={`rounded-lg border border-theme p-6 ${getHealthBgColor(overallStatus.status)}`}>
        <div className="flex items-center justify-between">
          <div className="flex items-center space-x-4">
            <span className="text-4xl">{overallStatus.icon}</span>
            <div>
              <h3 className="text-xl font-semibold text-theme-primary">{overallStatus.label}</h3>
              <p className="text-theme-secondary">
                {maintenanceStatus.mode ? (
                  <span className="text-theme-warning font-medium">Maintenance mode is currently active</span>
                ) : (
                  'System is running normally'
                )}
              </p>
            </div>
          </div>
          {maintenanceStatus.mode && (
            <span className="px-3 py-1 rounded-full bg-theme-warning-background text-theme-warning text-sm font-medium">
              Maintenance Mode Active
            </span>
          )}
        </div>
      </div>

      {/* Quick Stats Grid */}
      <QuickStatsGrid
        systemHealth={systemHealth}
        backups={backups}
        cleanupStats={cleanupStats}
        schedules={schedules}
        onNavigateToTab={onNavigateToTab}
        getHealthColor={getHealthColor}
        getHealthyServiceCount={getHealthyServiceCount}
        getTotalCleanupItems={getTotalCleanupItems}
        latestBackup={latestBackup}
        activeSchedules={activeSchedules}
      />

      {/* Service Health Details */}
      <SettingsCard
        title="Service Health Overview"
        description="Current status of all system services"
        icon="🏥"
      >
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {/* Database */}
          <div className={`p-4 rounded-lg ${getHealthBgColor(systemHealth?.database?.status || 'unknown')}`}>
            <div className="flex items-center space-x-3">
              <span className="text-2xl">🗄️</span>
              <div>
                <h5 className="font-medium text-theme-primary">Database</h5>
                <p className={`text-sm font-medium ${getHealthColor(systemHealth?.database?.status || 'unknown')}`}>
                  {systemHealth?.database?.status || 'Unknown'}
                </p>
              </div>
            </div>
          </div>

          {/* Redis */}
          <div className={`p-4 rounded-lg ${getHealthBgColor(systemHealth?.redis?.status || 'unknown')}`}>
            <div className="flex items-center space-x-3">
              <span className="text-2xl">⚡</span>
              <div>
                <h5 className="font-medium text-theme-primary">Redis</h5>
                <p className={`text-sm font-medium ${getHealthColor(systemHealth?.redis?.status || 'unknown')}`}>
                  {systemHealth?.redis?.status || 'Unknown'}
                </p>
              </div>
            </div>
          </div>

          {/* Storage */}
          <div className={`p-4 rounded-lg ${getHealthBgColor(systemHealth?.storage?.status || 'unknown')}`}>
            <div className="flex items-center space-x-3">
              <span className="text-2xl">💿</span>
              <div>
                <h5 className="font-medium text-theme-primary">Storage</h5>
                <p className={`text-sm font-medium ${getHealthColor(systemHealth?.storage?.status || 'unknown')}`}>
                  {systemHealth?.storage?.status || 'Unknown'}
                </p>
              </div>
            </div>
          </div>

          {/* Dynamic Services */}
          {systemHealth?.services?.map((service, index) => (
            <div key={index} className={`p-4 rounded-lg ${getHealthBgColor(service.status)}`}>
              <div className="flex items-center space-x-3">
                <span className="text-2xl">⚙️</span>
                <div>
                  <h5 className="font-medium text-theme-primary">{service.name}</h5>
                  <p className={`text-sm font-medium ${getHealthColor(service.status)}`}>
                    {service.status}
                  </p>
                </div>
              </div>
            </div>
          ))}
        </div>
      </SettingsCard>

      {/* System Metrics */}
      {systemMetrics && (
        <SystemMetricsSection systemMetrics={systemMetrics} />
      )}

      {/* Recent Activity / Quick Actions */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <RecentBackupsSection backups={backups} onNavigateToTab={onNavigateToTab} />
        <ActiveSchedulesSection schedules={schedules} onNavigateToTab={onNavigateToTab} />
      </div>

      {/* Quick Actions */}
      <QuickActionsSection onNavigateToTab={onNavigateToTab} />
    </div>
  );
};

// Quick Stats Grid Sub-component
interface QuickStatsGridProps {
  systemHealth: MaintenanceOverviewTabProps['systemHealth'];
  backups: MaintenanceOverviewTabProps['backups'];
  cleanupStats: MaintenanceOverviewTabProps['cleanupStats'];
  schedules: MaintenanceOverviewTabProps['schedules'];
  onNavigateToTab: (tab: MaintenanceTab) => void;
  getHealthColor: (status: string) => string;
  getHealthyServiceCount: () => number;
  getTotalCleanupItems: () => number;
  latestBackup: MaintenanceOverviewTabProps['backups'][0] | undefined;
  activeSchedules: number;
}

const QuickStatsGrid: React.FC<QuickStatsGridProps> = ({
  systemHealth,
  backups,
  cleanupStats,
  onNavigateToTab,
  getHealthColor,
  getHealthyServiceCount,
  getTotalCleanupItems,
  latestBackup,
  activeSchedules
}) => (
  <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
    {/* Health Status Card */}
    <button
      onClick={() => onNavigateToTab('health')}
      className="bg-theme-surface rounded-lg border border-theme p-4 hover:border-theme-interactive-primary transition-colors text-left"
    >
      <div className="flex items-center justify-between mb-3">
        <span className="text-2xl">💚</span>
        <span className={`text-sm font-medium ${getHealthColor(systemHealth?.overall_status || 'unknown')}`}>
          {systemHealth?.overall_status || 'Unknown'}
        </span>
      </div>
      <h4 className="font-medium text-theme-primary">System Health</h4>
      <p className="text-sm text-theme-secondary mt-1">
        {systemHealth ? `${getHealthyServiceCount()} services healthy` : 'Loading...'}
      </p>
    </button>

    {/* Backups Card */}
    <button
      onClick={() => onNavigateToTab('backups')}
      className="bg-theme-surface rounded-lg border border-theme p-4 hover:border-theme-interactive-primary transition-colors text-left"
    >
      <div className="flex items-center justify-between mb-3">
        <span className="text-2xl">💾</span>
        <span className="text-sm font-medium text-theme-secondary">{backups.length} total</span>
      </div>
      <h4 className="font-medium text-theme-primary">Database Backups</h4>
      <p className="text-sm text-theme-secondary mt-1">
        {latestBackup ? `Last: ${new Date(latestBackup.created_at).toLocaleDateString()}` : 'No backups found'}
      </p>
    </button>

    {/* Cleanup Stats Card */}
    <button
      onClick={() => onNavigateToTab('cleanup')}
      className="bg-theme-surface rounded-lg border border-theme p-4 hover:border-theme-interactive-primary transition-colors text-left"
    >
      <div className="flex items-center justify-between mb-3">
        <span className="text-2xl">🗑️</span>
        <span className="text-sm font-medium text-theme-secondary">
          {getTotalCleanupItems()} items
        </span>
      </div>
      <h4 className="font-medium text-theme-primary">Data Cleanup</h4>
      <p className="text-sm text-theme-secondary mt-1">
        {cleanupStats?.orphaned_uploads || 0} orphaned uploads
      </p>
    </button>

    {/* Scheduled Tasks Card */}
    <button
      onClick={() => onNavigateToTab('schedules')}
      className="bg-theme-surface rounded-lg border border-theme p-4 hover:border-theme-interactive-primary transition-colors text-left"
    >
      <div className="flex items-center justify-between mb-3">
        <span className="text-2xl">📅</span>
        <span className="text-sm font-medium text-theme-secondary">{activeSchedules} active</span>
      </div>
      <h4 className="font-medium text-theme-primary">Scheduled Tasks</h4>
      <p className="text-sm text-theme-secondary mt-1">
        {backups.length} total schedules
      </p>
    </button>
  </div>
);

// System Metrics Section Sub-component
interface SystemMetricsSectionProps {
  systemMetrics: NonNullable<MaintenanceOverviewTabProps['systemMetrics']>;
}

const SystemMetricsSection: React.FC<SystemMetricsSectionProps> = ({ systemMetrics }) => (
  <SettingsCard
    title="System Metrics"
    description="Current resource utilization and performance metrics"
    icon="📈"
  >
    <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
      {/* CPU Usage */}
      <div>
        <div className="flex justify-between items-center mb-2">
          <span className="text-sm font-medium text-theme-primary">CPU Usage</span>
          <span className="text-sm text-theme-secondary">{systemMetrics.cpu_usage?.toFixed(1) || 0}%</span>
        </div>
        <div className="h-2 bg-theme-background rounded-full overflow-hidden">
          <div
            className={`h-full rounded-full transition-all ${
              (systemMetrics.cpu_usage || 0) > 80 ? 'bg-theme-error' :
              (systemMetrics.cpu_usage || 0) > 60 ? 'bg-theme-warning' : 'bg-theme-success'
            }`}
            style={{ width: `${Math.min(systemMetrics.cpu_usage || 0, 100)}%` }}
          />
        </div>
      </div>

      {/* Memory Usage */}
      <div>
        <div className="flex justify-between items-center mb-2">
          <span className="text-sm font-medium text-theme-primary">Memory Usage</span>
          <span className="text-sm text-theme-secondary">{systemMetrics.memory_usage?.toFixed(1) || 0}%</span>
        </div>
        <div className="h-2 bg-theme-background rounded-full overflow-hidden">
          <div
            className={`h-full rounded-full transition-all ${
              (systemMetrics.memory_usage || 0) > 80 ? 'bg-theme-error' :
              (systemMetrics.memory_usage || 0) > 60 ? 'bg-theme-warning' : 'bg-theme-success'
            }`}
            style={{ width: `${Math.min(systemMetrics.memory_usage || 0, 100)}%` }}
          />
        </div>
      </div>

      {/* Disk Usage */}
      <div>
        <div className="flex justify-between items-center mb-2">
          <span className="text-sm font-medium text-theme-primary">Disk Usage</span>
          <span className="text-sm text-theme-secondary">{systemMetrics.disk_usage?.toFixed(1) || 0}%</span>
        </div>
        <div className="h-2 bg-theme-background rounded-full overflow-hidden">
          <div
            className={`h-full rounded-full transition-all ${
              (systemMetrics.disk_usage || 0) > 80 ? 'bg-theme-error' :
              (systemMetrics.disk_usage || 0) > 60 ? 'bg-theme-warning' : 'bg-theme-success'
            }`}
            style={{ width: `${Math.min(systemMetrics.disk_usage || 0, 100)}%` }}
          />
        </div>
      </div>
    </div>

    {/* Additional Metrics */}
    <div className="grid grid-cols-2 md:grid-cols-4 gap-4 mt-6 pt-6 border-t border-theme">
      <div className="text-center">
        <p className="text-2xl font-semibold text-theme-primary">{systemMetrics.database_connections || 0}</p>
        <p className="text-sm text-theme-secondary">DB Connections</p>
      </div>
      <div className="text-center">
        <p className="text-2xl font-semibold text-theme-primary">{systemMetrics.queue_size || 0}</p>
        <p className="text-sm text-theme-secondary">Queue Size</p>
      </div>
      <div className="text-center">
        <p className="text-2xl font-semibold text-theme-primary">{systemMetrics.active_users || 0}</p>
        <p className="text-sm text-theme-secondary">Active Users</p>
      </div>
      <div className="text-center">
        <p className="text-2xl font-semibold text-theme-primary">{systemMetrics.response_time_avg || 0}ms</p>
        <p className="text-sm text-theme-secondary">Avg Response Time</p>
      </div>
    </div>
  </SettingsCard>
);

// Recent Backups Section Sub-component
interface RecentBackupsSectionProps {
  backups: MaintenanceOverviewTabProps['backups'];
  onNavigateToTab: (tab: MaintenanceTab) => void;
}

const RecentBackupsSection: React.FC<RecentBackupsSectionProps> = ({ backups, onNavigateToTab }) => (
  <SettingsCard
    title="Recent Backups"
    description="Latest database backup activity"
    icon="💾"
  >
    {backups.length === 0 ? (
      <div className="text-center py-6">
        <p className="text-theme-secondary">No backups available</p>
        <button
          onClick={() => onNavigateToTab('backups')}
          className="btn-theme btn-theme-primary mt-3"
        >
          Create First Backup
        </button>
      </div>
    ) : (
      <div className="space-y-3">
        {backups.slice(0, 3).map((backup) => (
          <div key={backup.id} className="flex items-center justify-between p-3 bg-theme-background rounded-lg">
            <div className="flex items-center space-x-3">
              <span className={`w-2 h-2 rounded-full ${
                backup.status === 'completed' ? 'bg-theme-success' :
                backup.status === 'in_progress' ? 'bg-theme-warning' : 'bg-theme-error'
              }`} />
              <div>
                <p className="text-sm font-medium text-theme-primary">
                  {new Date(backup.created_at).toLocaleString()}
                </p>
                <p className="text-xs text-theme-secondary">
                  {maintenanceApi.formatBytes(backup.size)}
                </p>
              </div>
            </div>
            <span className={`px-2 py-1 rounded text-xs font-medium ${
              backup.status === 'completed' ? 'bg-theme-success-background text-theme-success' :
              backup.status === 'in_progress' ? 'bg-theme-warning-background text-theme-warning' :
              'bg-theme-error-background text-theme-error'
            }`}>
              {backup.status}
            </span>
          </div>
        ))}
        {backups.length > 3 && (
          <button
            onClick={() => onNavigateToTab('backups')}
            className="w-full text-center text-sm text-theme-link hover:text-theme-link-hover py-2"
          >
            View all {backups.length} backups →
          </button>
        )}
      </div>
    )}
  </SettingsCard>
);

// Active Schedules Section Sub-component
interface ActiveSchedulesSectionProps {
  schedules: MaintenanceOverviewTabProps['schedules'];
  onNavigateToTab: (tab: MaintenanceTab) => void;
}

const ActiveSchedulesSection: React.FC<ActiveSchedulesSectionProps> = ({ schedules, onNavigateToTab }) => (
  <SettingsCard
    title="Active Schedules"
    description="Currently enabled maintenance schedules"
    icon="📅"
  >
    {schedules.length === 0 ? (
      <div className="text-center py-6">
        <p className="text-theme-secondary">No scheduled tasks configured</p>
        <button
          onClick={() => onNavigateToTab('schedules')}
          className="btn-theme btn-theme-primary mt-3"
        >
          Create Schedule
        </button>
      </div>
    ) : (
      <div className="space-y-3">
        {schedules.filter(s => s.enabled).slice(0, 3).map((schedule) => (
          <div key={schedule.id} className="flex items-center justify-between p-3 bg-theme-background rounded-lg">
            <div>
              <p className="text-sm font-medium text-theme-primary">{schedule.description}</p>
              <p className="text-xs text-theme-secondary">
                {schedule.frequency} • Next: {new Date(schedule.next_run).toLocaleString()}
              </p>
            </div>
            <span className="px-2 py-1 rounded text-xs font-medium bg-theme-success-background text-theme-success">
              Active
            </span>
          </div>
        ))}
        {schedules.length > 3 && (
          <button
            onClick={() => onNavigateToTab('schedules')}
            className="w-full text-center text-sm text-theme-link hover:text-theme-link-hover py-2"
          >
            View all {schedules.length} schedules →
          </button>
        )}
      </div>
    )}
  </SettingsCard>
);

// Quick Actions Section Sub-component
interface QuickActionsSectionProps {
  onNavigateToTab: (tab: MaintenanceTab) => void;
}

const QuickActionsSection: React.FC<QuickActionsSectionProps> = ({ onNavigateToTab }) => (
  <SettingsCard
    title="Quick Actions"
    description="Common maintenance operations"
    icon="⚡"
  >
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
      <button
        onClick={() => onNavigateToTab('mode')}
        className="flex items-center space-x-3 p-4 rounded-lg border border-theme hover:bg-theme-background transition-colors"
      >
        <span className="text-2xl">🔧</span>
        <div className="text-left">
          <p className="font-medium text-theme-primary">Maintenance Mode</p>
          <p className="text-xs text-theme-secondary">Enable/disable site access</p>
        </div>
      </button>

      <button
        onClick={() => onNavigateToTab('backups')}
        className="flex items-center space-x-3 p-4 rounded-lg border border-theme hover:bg-theme-background transition-colors"
      >
        <span className="text-2xl">💾</span>
        <div className="text-left">
          <p className="font-medium text-theme-primary">Create Backup</p>
          <p className="text-xs text-theme-secondary">Backup database now</p>
        </div>
      </button>

      <button
        onClick={() => onNavigateToTab('cleanup')}
        className="flex items-center space-x-3 p-4 rounded-lg border border-theme hover:bg-theme-background transition-colors"
      >
        <span className="text-2xl">🗑️</span>
        <div className="text-left">
          <p className="font-medium text-theme-primary">Run Cleanup</p>
          <p className="text-xs text-theme-secondary">Clean orphaned data</p>
        </div>
      </button>

      <button
        onClick={() => onNavigateToTab('operations')}
        className="flex items-center space-x-3 p-4 rounded-lg border border-theme hover:bg-theme-background transition-colors"
      >
        <span className="text-2xl">⚙️</span>
        <div className="text-left">
          <p className="font-medium text-theme-primary">System Operations</p>
          <p className="text-xs text-theme-secondary">Advanced operations</p>
        </div>
      </button>
    </div>
  </SettingsCard>
);
