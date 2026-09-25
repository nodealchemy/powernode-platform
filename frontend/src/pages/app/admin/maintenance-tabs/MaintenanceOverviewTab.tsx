import React from 'react';
import { Link } from 'react-router-dom';
import { maintenanceApi } from '@/shared/services/admin/maintenanceApi';
import { SettingsCard } from '@/features/admin/components/settings/SettingsComponents';
import { MaintenanceOverviewTabProps, MaintenanceTab } from './types';

export const MaintenanceOverviewTab: React.FC<MaintenanceOverviewTabProps> = ({
  maintenanceStatus,
  backups,
  cleanupStats,
  schedules,
  onNavigateToTab
}) => {
  // Get total cleanup items
  const getTotalCleanupItems = () => {
    if (!cleanupStats) return 0;
    return (cleanupStats.old_logs || 0) +
           (cleanupStats.expired_sessions || 0) +
           (cleanupStats.temporary_files || 0) +
           (cleanupStats.orphaned_uploads || 0);
  };

  const latestBackup = backups[0];
  const activeSchedules = schedules.filter(s => s.enabled).length;

  return (
    <div className="space-y-6">
      {/* Maintenance mode banner. Platform health (services, host
          resources) is on /app/status, not here (fc-47). */}
      <div className={`rounded-lg border border-theme p-6 ${maintenanceStatus.mode ? 'bg-theme-warning-bg' : 'bg-theme-surface'}`}>
        <div className="flex items-center justify-between">
          <div className="flex items-center space-x-4">
            <span className="text-4xl">{maintenanceStatus.mode ? '🔧' : '✅'}</span>
            <div>
              <h3 className="text-xl font-semibold text-theme-primary">
                {maintenanceStatus.mode ? 'Maintenance Mode Active' : 'Maintenance mode is off'}
              </h3>
              <p className="text-theme-secondary">
                {maintenanceStatus.mode ? (
                  <span className="text-theme-warning-fg font-medium">Maintenance mode is currently active</span>
                ) : (
                  'Users can reach the platform'
                )}
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* Quick Stats Grid */}
      <QuickStatsGrid
        backups={backups}
        cleanupStats={cleanupStats}
        schedules={schedules}
        onNavigateToTab={onNavigateToTab}
        getTotalCleanupItems={getTotalCleanupItems}
        latestBackup={latestBackup}
        activeSchedules={activeSchedules}
      />

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
  backups: MaintenanceOverviewTabProps['backups'];
  cleanupStats: MaintenanceOverviewTabProps['cleanupStats'];
  schedules: MaintenanceOverviewTabProps['schedules'];
  onNavigateToTab: (tab: MaintenanceTab) => void;
  getTotalCleanupItems: () => number;
  latestBackup: MaintenanceOverviewTabProps['backups'][0] | undefined;
  activeSchedules: number;
}

const QuickStatsGrid: React.FC<QuickStatsGridProps> = ({
  backups,
  cleanupStats,
  onNavigateToTab,
  getTotalCleanupItems,
  latestBackup,
  activeSchedules
}) => (
  <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
    {/* Platform health is on /app/status (fc-47): a link, no verdict of its own. */}
    <Link
      to="/app/status"
      className="bg-theme-surface rounded-lg border border-theme p-4 hover:border-theme-interactive-primary transition-colors text-left"
    >
      <div className="flex items-center justify-between mb-3">
        <span className="text-2xl">💚</span>
      </div>
      <h4 className="font-medium text-theme-primary">Platform status →</h4>
      <p className="text-sm text-theme-secondary mt-1">Services, dependencies and incidents</p>
    </Link>

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
                backup.status === 'completed' ? 'bg-theme-success-bg' :
                backup.status === 'in_progress' ? 'bg-theme-warning-bg' : 'bg-theme-error-bg'
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
              backup.status === 'completed' ? 'bg-theme-success-bg text-theme-success-fg' :
              backup.status === 'in_progress' ? 'bg-theme-warning-bg text-theme-warning-fg' :
              'bg-theme-error-bg text-theme-error-fg'
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
            <span className="px-2 py-1 rounded text-xs font-medium bg-theme-success-bg text-theme-success-fg">
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
