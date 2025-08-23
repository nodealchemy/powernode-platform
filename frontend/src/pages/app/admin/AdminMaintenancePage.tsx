import React, { useState, useEffect } from 'react';
import { useNavigate, useLocation } from 'react-router-dom';
import { useNotification } from '@/shared/hooks/useNotification';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { 
  MaintenanceModeControl, 
  SystemHealthMonitor, 
  DatabaseBackupManager, 
  DataCleanupManager 
} from '@/features/admin/components/system/MaintenanceComponents';
import { 
  maintenanceApi, 
  MaintenanceStatus, 
  BackupInfo, 
  SystemHealth, 
  CleanupStats,
  MaintenanceSystemMetrics,
  MaintenanceSchedule
} from '@/shared/services/maintenanceApi';
import { SettingsCard, ToggleSwitch, Input, Select, SectionHeader, StatsCard } from '@/features/admin/components/SettingsComponents';
import { FormField } from '@/shared/components/ui/FormField';
import { RefreshCw, Plus, Play, Pause, RotateCcw, Database, HardDrive, Activity, Settings, Clock, Trash2 } from 'lucide-react';

type MaintenanceTab = 'mode' | 'health' | 'backups' | 'cleanup' | 'operations' | 'schedules';

interface MaintenancePageActions {
  refreshData?: () => void;
  createBackup?: () => void;
  runCleanup?: () => void;
  createSchedule?: () => void;
}

export const AdminMaintenancePage: React.FC = () => {
  const navigate = useNavigate();
  const location = useLocation();
  const { showNotification } = useNotification();
  
  // Get active tab from URL path
  const getActiveTabFromPath = (): MaintenanceTab => {
    const pathSegments = location.pathname.split('/');
    const lastSegment = pathSegments[pathSegments.length - 1];
    if (['mode', 'health', 'backups', 'cleanup', 'operations', 'schedules'].includes(lastSegment)) {
      return lastSegment as MaintenanceTab;
    }
    return 'mode';
  };

  const [activeTab, setActiveTab] = useState<MaintenanceTab>(getActiveTabFromPath());
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [actions, setActions] = useState<MaintenancePageActions>({});
  
  // State for maintenance data
  const [maintenanceStatus, setMaintenanceStatus] = useState<MaintenanceStatus>({
    mode: false,
    message: ''
  });
  const [systemHealth, setSystemHealth] = useState<SystemHealth | null>(null);
  const [systemMetrics, setSystemMetrics] = useState<MaintenanceSystemMetrics | null>(null);
  const [backups, setBackups] = useState<BackupInfo[]>([]);
  const [cleanupStats, setCleanupStats] = useState<CleanupStats | null>(null);
  const [schedules, setSchedules] = useState<MaintenanceSchedule[]>([]);
  const [showScheduleModal, setShowScheduleModal] = useState(false);

  // Tab definitions
  const tabs = [
    { id: 'mode', label: 'Maintenance Mode', icon: '🔧', path: '/mode' },
    { id: 'health', label: 'System Health', icon: '💚', path: '/health' },
    { id: 'backups', label: 'Database Backups', icon: '💾', path: '/backups' },
    { id: 'cleanup', label: 'Data Cleanup', icon: '🗑️', path: '/cleanup' },
    { id: 'operations', label: 'System Operations', icon: '⚙️', path: '/operations' },
    { id: 'schedules', label: 'Scheduled Tasks', icon: '📅', path: '/schedules' }
  ] as const;

  const loadMaintenanceData = async () => {
    try {
      setLoading(true);
      setError(null);

      const [status, health, metrics, backupList, cleanup, scheduleList] = await Promise.all([
        maintenanceApi.getMaintenanceStatus(),
        maintenanceApi.getSystemHealth(),
        maintenanceApi.getSystemMetrics(),
        maintenanceApi.getBackups(),
        maintenanceApi.getCleanupStats(),
        maintenanceApi.getMaintenanceSchedules()
      ]);

      setMaintenanceStatus(status);
      setSystemHealth(health);
      setSystemMetrics(metrics);
      setBackups(backupList);
      setCleanupStats(cleanup);
      setSchedules(scheduleList);
    } catch (err: any) {
      console.error('Failed to load maintenance data:', err);
      setError(err.message || 'Failed to load maintenance data');
      showNotification('Failed to load maintenance data', 'error');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadMaintenanceData();
  }, []);

  useEffect(() => {
    setActiveTab(getActiveTabFromPath());
  }, [location.pathname]);

  const handleTabChange = (tabId: MaintenanceTab) => {
    const tab = tabs.find(t => t.id === tabId);
    if (tab) {
      const targetPath = tabId === 'mode' ? '/app/admin/maintenance' : `/app/admin/maintenance${tab.path}`;
      navigate(targetPath);
    }
  };

  const getBreadcrumbs = () => [
    { label: 'Dashboard', href: '/app', icon: '🏠' },
    { label: 'Admin', href: '/app/admin', icon: '👥' },
    { label: 'Maintenance', icon: '🔧' }
  ];

  const getPageActions = (): PageAction[] => {
    const baseActions: PageAction[] = [
      { 
        id: 'refresh', 
        label: 'Refresh', 
        onClick: () => { (actions.refreshData && actions.refreshData()) || loadMaintenanceData(); }, 
        variant: 'secondary', 
        icon: RefreshCw 
      }
    ];

    switch (activeTab) {
      case 'backups':
        baseActions.push({
          id: 'create-backup',
          label: 'Create Backup',
          onClick: () => { actions.createBackup && actions.createBackup(); },
          variant: 'primary',
          icon: Plus
        });
        break;
      case 'cleanup':
        baseActions.push({
          id: 'run-cleanup',
          label: 'Run Cleanup',
          onClick: () => { actions.runCleanup && actions.runCleanup(); },
          variant: 'primary',
          icon: Trash2
        });
        break;
      case 'schedules':
        baseActions.push({
          id: 'create-schedule',
          label: 'New Schedule',
          onClick: () => { actions.createSchedule && actions.createSchedule(); },
          variant: 'primary',
          icon: Plus
        });
        break;
    }

    return baseActions;
  };

  if (loading) {
    return (
      <PageContainer title="System Maintenance" breadcrumbs={getBreadcrumbs()} actions={getPageActions()}>
        <div className="flex items-center justify-center py-12">
          <LoadingSpinner size="lg" message="Loading maintenance data..." />
        </div>
      </PageContainer>
    );
  }

  if (error) {
    return (
      <PageContainer title="System Maintenance" breadcrumbs={getBreadcrumbs()} actions={getPageActions()}>
        <div className="bg-theme-surface rounded-lg border border-theme p-6">
          <div className="text-center">
            <div className="text-6xl mb-4">⚠️</div>
            <h3 className="text-lg font-medium text-theme-primary mb-2">Error Loading Maintenance Data</h3>
            <p className="text-theme-secondary mb-4">{error}</p>
            <button 
              onClick={loadMaintenanceData}
              className="btn-theme btn-theme-primary"
            >
              Try Again
            </button>
          </div>
        </div>
      </PageContainer>
    );
  }

  const renderTabContent = () => {
    switch (activeTab) {
      case 'mode':
        return <MaintenanceModeTab status={maintenanceStatus} onUpdate={loadMaintenanceData} />;
      case 'health':
        return <SystemHealthTab health={systemHealth} metrics={systemMetrics} onRefresh={loadMaintenanceData} />;
      case 'backups':
        return <DatabaseBackupsTab backups={backups} onRefresh={loadMaintenanceData} onRegisterActions={setActions} />;
      case 'cleanup':
        return <DataCleanupTab stats={cleanupStats} onRefresh={loadMaintenanceData} onRegisterActions={setActions} />;
      case 'operations':
        return <SystemOperationsTab health={systemHealth} onRefresh={loadMaintenanceData} />;
      case 'schedules':
        return <ScheduledTasksTab schedules={schedules} onRefresh={loadMaintenanceData} onRegisterActions={setActions} />;
      default:
        return <div>Tab not found</div>;
    }
  };

  return (
    <PageContainer title="System Maintenance" breadcrumbs={getBreadcrumbs()} actions={getPageActions()}>
      {/* Tab Navigation */}
      <div className="border-b border-theme mb-6">
        <div className="flex space-x-8 -mb-px overflow-x-auto">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => handleTabChange(tab.id as MaintenanceTab)}
              className={`flex items-center space-x-2 py-2 px-1 border-b-2 font-medium text-sm whitespace-nowrap ${
                activeTab === tab.id
                  ? 'border-theme-link text-theme-link'
                  : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme-tertiary'
              }`}
            >
              <span className="text-base">{tab.icon}</span>
              <span>{tab.label}</span>
            </button>
          ))}
        </div>
      </div>

      {/* Tab Content */}
      <div className="space-y-6">
        {renderTabContent()}
      </div>
    </PageContainer>
  );
};

// Maintenance Mode Tab
const MaintenanceModeTab: React.FC<{
  status: MaintenanceStatus;
  onUpdate: () => void;
}> = ({ status, onUpdate }) => {
  const { showNotification } = useNotification();
  const [submitting, setSubmitting] = useState(false);
  const [scheduledMode, setScheduledMode] = useState({
    enabled: false,
    startTime: '',
    endTime: '',
    message: ''
  });

  const handleToggleMode = async () => {
    setSubmitting(true);
    try {
      await maintenanceApi.setMaintenanceMode(!status.mode, status.message);
      showNotification(
        status.mode ? 'Maintenance mode disabled' : 'Maintenance mode enabled',
        'success'
      );
      onUpdate();
    } catch (error: any) {
      showNotification('Failed to update maintenance mode', 'error');
    } finally {
      setSubmitting(false);
    }
  };

  const handleScheduleMode = async () => {
    setSubmitting(true);
    try {
      await maintenanceApi.scheduleMaintenanceMode(
        scheduledMode.startTime,
        scheduledMode.endTime,
        scheduledMode.message
      );
      showNotification('Maintenance mode scheduled successfully', 'success');
      onUpdate();
    } catch (error: any) {
      showNotification('Failed to schedule maintenance mode', 'error');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="space-y-6">
      {/* Current Status */}
      <SettingsCard
        title="Maintenance Mode Status"
        description="Control system-wide maintenance mode"
        icon="🔧"
      >
        <div className="space-y-4">
          <div className="flex items-center justify-between p-4 rounded-lg border border-theme bg-theme-background-secondary">
            <div>
              <h4 className="text-sm font-medium text-theme-primary">
                Maintenance Mode
              </h4>
              <p className="text-sm text-theme-secondary">
                {status.mode ? 'System is currently in maintenance mode' : 'System is operational'}
              </p>
            </div>
            <ToggleSwitch
              checked={status.mode}
              onChange={handleToggleMode}
              disabled={submitting}
              variant={status.mode ? 'warning' : 'success'}
            />
          </div>

          {status.mode && status.message && (
            <div className="p-4 rounded-lg bg-theme-warning-background border border-theme-warning-border">
              <p className="text-sm text-theme-warning font-medium">Current Message:</p>
              <p className="text-sm text-theme-primary mt-1">{status.message}</p>
            </div>
          )}
        </div>
      </SettingsCard>

      {/* Schedule Maintenance */}
      <SettingsCard
        title="Schedule Maintenance Mode"
        description="Schedule maintenance mode for future activation"
        icon="📅"
      >
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <FormField 
            label="Start Time"
            type="datetime-local"
            value={scheduledMode.startTime}
            onChange={(value) => setScheduledMode(prev => ({ ...prev, startTime: value }))}
          />
          <FormField 
            label="End Time"
            type="datetime-local"
            value={scheduledMode.endTime}
            onChange={(value) => setScheduledMode(prev => ({ ...prev, endTime: value }))}
          />
          <div className="md:col-span-2">
            <FormField 
              label="Maintenance Message"
              type="text"
              placeholder="System maintenance in progress..."
              value={scheduledMode.message}
              onChange={(value) => setScheduledMode(prev => ({ ...prev, message: value }))}
            />
          </div>
          <div className="md:col-span-2">
            <button
              onClick={handleScheduleMode}
              disabled={submitting || !scheduledMode.startTime || !scheduledMode.endTime}
              className="btn-theme btn-theme-primary"
            >
              {submitting ? 'Scheduling...' : 'Schedule Maintenance'}
            </button>
          </div>
        </div>
      </SettingsCard>
    </div>
  );
};

// System Health Tab
const SystemHealthTab: React.FC<{
  health: SystemHealth | null;
  metrics: MaintenanceSystemMetrics | null;
  onRefresh: () => void;
}> = ({ health, metrics, onRefresh }) => {
  if (!health || !metrics) {
    return (
      <div className="text-center py-8">
        <p className="text-theme-secondary">System health data not available</p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Overall Status */}
      <SettingsCard
        title="System Overview"
        description="Overall system health status"
        icon="💚"
      >
        <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
          <StatsCard
            icon="🖥️"
            title="CPU Usage"
            value={`${metrics.cpu_usage}%`}
            valueColor={metrics.cpu_usage > 80 ? 'error' : metrics.cpu_usage > 60 ? 'warning' : 'success'}
          />
          <StatsCard
            icon="🧠"
            title="Memory Usage"
            value={`${metrics.memory_usage}%`}
            valueColor={metrics.memory_usage > 80 ? 'error' : metrics.memory_usage > 60 ? 'warning' : 'success'}
          />
          <StatsCard
            icon="💾"
            title="Disk Usage"
            value={`${metrics.disk_usage}%`}
            valueColor={metrics.disk_usage > 90 ? 'error' : metrics.disk_usage > 75 ? 'warning' : 'success'}
          />
          <StatsCard
            icon="👥"
            title="Active Users"
            value={metrics.active_users}
            valueColor="info"
          />
        </div>
      </SettingsCard>

      {/* Service Health */}
      <SettingsCard
        title="Service Health"
        description="Individual service status monitoring"
        icon="⚙️"
      >
        <div className="space-y-3">
          {health.services && health.services.length > 0 ? health.services.map((service, index) => (
            <div key={index} className="flex items-center justify-between p-3 rounded border border-theme">
              <div className="flex items-center space-x-3">
                <div className={`w-3 h-3 rounded-full ${
                  service.status === 'healthy' ? 'bg-theme-success' :
                  service.status === 'warning' ? 'bg-theme-warning' : 'bg-theme-error'
                }`} />
                <div>
                  <p className="font-medium text-theme-primary">{service.name}</p>
                  <p className="text-sm text-theme-secondary">
                    Uptime: {maintenanceApi.formatUptime(service.uptime)} | 
                    Memory: {maintenanceApi.formatBytes(service.memory_usage)}
                  </p>
                </div>
              </div>
              <span className={`text-sm font-medium ${maintenanceApi.getStatusColor(service.status)}`}>
                {service.status}
              </span>
            </div>
          )) : (
            <div className="text-center py-4">
              <p className="text-theme-secondary">No services data available</p>
            </div>
          )}
        </div>
      </SettingsCard>
    </div>
  );
};

// Database Backups Tab
const DatabaseBackupsTab: React.FC<{
  backups: BackupInfo[];
  onRefresh: () => void;
  onRegisterActions: (actions: MaintenancePageActions) => void;
}> = ({ backups, onRefresh, onRegisterActions }) => {
  const { showNotification } = useNotification();
  const [creating, setCreating] = useState(false);

  const handleCreateBackup = async () => {
    setCreating(true);
    try {
      await maintenanceApi.createBackup();
      showNotification('Backup created successfully', 'success');
      onRefresh();
    } catch (error: any) {
      showNotification('Failed to create backup', 'error');
    } finally {
      setCreating(false);
    }
  };

  useEffect(() => {
    onRegisterActions({ createBackup: handleCreateBackup });
  }, [onRegisterActions]);

  return (
    <div className="space-y-6">
      <DatabaseBackupManager backups={backups} onRefresh={onRefresh} />
    </div>
  );
};

// Data Cleanup Tab
const DataCleanupTab: React.FC<{
  stats: CleanupStats | null;
  onRefresh: () => void;
  onRegisterActions: (actions: MaintenancePageActions) => void;
}> = ({ stats, onRefresh, onRegisterActions }) => {
  const { showNotification } = useNotification();
  const [running, setRunning] = useState(false);

  const handleRunCleanup = async () => {
    setRunning(true);
    try {
      const result = await maintenanceApi.runCleanup({
        old_logs: true,
        expired_sessions: true,
        temporary_files: true,
        cache_entries: true
      });
      showNotification(`Cleanup completed. ${result.cleaned_items} items cleaned`, 'success');
      onRefresh();
    } catch (error: any) {
      showNotification('Failed to run cleanup', 'error');
    } finally {
      setRunning(false);
    }
  };

  useEffect(() => {
    onRegisterActions({ runCleanup: handleRunCleanup });
  }, [onRegisterActions]);

  if (!stats) {
    return (
      <div className="text-center py-8">
        <p className="text-theme-secondary">Cleanup statistics not available</p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <DataCleanupManager stats={stats} onRefresh={onRefresh} />
    </div>
  );
};

// System Operations Tab
const SystemOperationsTab: React.FC<{
  health: SystemHealth | null;
  onRefresh: () => void;
}> = ({ health, onRefresh }) => {
  const { showNotification } = useNotification();
  const [operations, setOperations] = useState({
    flushingCache: false,
    optimizingDb: false,
    restartingService: false
  });

  const handleFlushCache = async () => {
    setOperations(prev => ({ ...prev, flushingCache: true }));
    try {
      await maintenanceApi.flushCache();
      showNotification('Cache flushed successfully', 'success');
      onRefresh();
    } catch (error: any) {
      showNotification('Failed to flush cache', 'error');
    } finally {
      setOperations(prev => ({ ...prev, flushingCache: false }));
    }
  };

  const handleOptimizeDatabase = async () => {
    setOperations(prev => ({ ...prev, optimizingDb: true }));
    try {
      const result = await maintenanceApi.optimizeDatabase();
      showNotification(`Database optimized. ${result.tables_optimized} tables optimized`, 'success');
      onRefresh();
    } catch (error: any) {
      showNotification('Failed to optimize database', 'error');
    } finally {
      setOperations(prev => ({ ...prev, optimizingDb: false }));
    }
  };

  const handleRestartService = async (serviceName: string) => {
    setOperations(prev => ({ ...prev, restartingService: true }));
    try {
      await maintenanceApi.restartService(serviceName);
      showNotification(`${serviceName} service restarted successfully`, 'success');
      onRefresh();
    } catch (error: any) {
      showNotification(`Failed to restart ${serviceName} service`, 'error');
    } finally {
      setOperations(prev => ({ ...prev, restartingService: false }));
    }
  };

  return (
    <div className="space-y-6">
      {/* Cache Operations */}
      <SettingsCard
        title="Cache Management"
        description="Manage application cache"
        icon="🗄️"
      >
        <div className="space-y-4">
          <button
            onClick={handleFlushCache}
            disabled={operations.flushingCache}
            className="btn-theme btn-theme-warning"
          >
            {operations.flushingCache ? 'Flushing Cache...' : 'Flush All Cache'}
          </button>
          <p className="text-sm text-theme-secondary">
            This will clear all cached data and may temporarily impact performance.
          </p>
        </div>
      </SettingsCard>

      {/* Database Operations */}
      <SettingsCard
        title="Database Optimization"
        description="Optimize database performance"
        icon="🗃️"
      >
        <div className="space-y-4">
          <button
            onClick={handleOptimizeDatabase}
            disabled={operations.optimizingDb}
            className="btn-theme btn-theme-primary"
          >
            {operations.optimizingDb ? 'Optimizing...' : 'Optimize Database'}
          </button>
          <p className="text-sm text-theme-secondary">
            This will optimize database tables and may take several minutes.
          </p>
        </div>
      </SettingsCard>

      {/* Service Management */}
      <SettingsCard
        title="Service Management"
        description="Restart individual services"
        icon="⚙️"
      >
        <div className="space-y-3">
          {health?.services && health.services.length > 0 ? health.services.map((service, index) => (
            <div key={index} className="flex items-center justify-between p-3 rounded border border-theme">
              <div className="flex items-center space-x-3">
                <div className={`w-3 h-3 rounded-full ${
                  service.status === 'healthy' ? 'bg-theme-success' :
                  service.status === 'warning' ? 'bg-theme-warning' : 'bg-theme-error'
                }`} />
                <div>
                  <p className="font-medium text-theme-primary">{service.name}</p>
                  <p className="text-sm text-theme-secondary">
                    Status: {service.status} | Uptime: {maintenanceApi.formatUptime(service.uptime)}
                  </p>
                </div>
              </div>
              <button
                onClick={() => handleRestartService(service.name)}
                disabled={operations.restartingService}
                className="btn-theme btn-theme-secondary btn-sm"
              >
                {operations.restartingService ? 'Restarting...' : 'Restart'}
              </button>
            </div>
          )) : (
            <div className="text-center py-4">
              <p className="text-theme-secondary">No services data available</p>
            </div>
          )}
        </div>
      </SettingsCard>
    </div>
  );
};

// Scheduled Tasks Tab
const ScheduledTasksTab: React.FC<{
  schedules: MaintenanceSchedule[];
  onRefresh: () => void;
  onRegisterActions: (actions: MaintenancePageActions) => void;
}> = ({ schedules, onRefresh, onRegisterActions }) => {
  const { showNotification } = useNotification();
  const [showModal, setShowModal] = useState(false);

  const handleCreateSchedule = () => {
    setShowModal(true);
  };

  useEffect(() => {
    onRegisterActions({ createSchedule: handleCreateSchedule });
  }, [onRegisterActions]);

  const handleRunSchedule = async (scheduleId: string) => {
    try {
      await maintenanceApi.runScheduledTask(scheduleId);
      showNotification('Scheduled task executed successfully', 'success');
      onRefresh();
    } catch (error: any) {
      showNotification('Failed to execute scheduled task', 'error');
    }
  };

  return (
    <div className="space-y-6">
      <SettingsCard
        title="Scheduled Maintenance Tasks"
        description="Automated maintenance operations"
        icon="📅"
      >
        <div className="space-y-3">
          {schedules.length === 0 ? (
            <div className="text-center py-8">
              <div className="text-4xl mb-2">📅</div>
              <p className="text-theme-secondary">No scheduled tasks configured</p>
              <button
                onClick={handleCreateSchedule}
                className="btn-theme btn-theme-primary mt-4"
              >
                Create First Schedule
              </button>
            </div>
          ) : (
            schedules.map((schedule) => (
              <div key={schedule.id} className="flex items-center justify-between p-4 rounded border border-theme">
                <div>
                  <h4 className="font-medium text-theme-primary">{schedule.description}</h4>
                  <p className="text-sm text-theme-secondary">
                    Type: {schedule.type} | Frequency: {schedule.frequency} | 
                    Next run: {new Date(schedule.next_run).toLocaleString()}
                  </p>
                  {schedule.last_run && (
                    <p className="text-xs text-theme-tertiary">
                      Last run: {new Date(schedule.last_run).toLocaleString()}
                    </p>
                  )}
                </div>
                <div className="flex items-center space-x-2">
                  <ToggleSwitch
                    checked={schedule.enabled}
                    onChange={(enabled) => {
                      maintenanceApi.updateMaintenanceSchedule(schedule.id, { enabled })
                        .then(() => {
                          showNotification(`Schedule ${enabled ? 'enabled' : 'disabled'}`, 'success');
                          onRefresh();
                        })
                        .catch(() => showNotification('Failed to update schedule', 'error'));
                    }}
                    size="sm"
                  />
                  <button
                    onClick={() => handleRunSchedule(schedule.id)}
                    className="btn-theme btn-theme-secondary btn-sm"
                  >
                    Run Now
                  </button>
                </div>
              </div>
            ))
          )}
        </div>
      </SettingsCard>
    </div>
  );
};

export default AdminMaintenancePage;