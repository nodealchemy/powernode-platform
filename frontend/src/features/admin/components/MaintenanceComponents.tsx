import React, { useState } from 'react';
import { Button } from '@/shared/components/ui/Button';
import { 
  Download, 
  Trash2, 
  RefreshCw, 
  Calendar, 
  Database, 
  HardDrive, 
  Cpu, 
  MemoryStick,
  Activity,
  AlertTriangle,
  CheckCircle,
  Info
} from 'lucide-react';
import { 
  maintenanceApi, 
  BackupInfo, 
  SystemHealth, 
  CleanupStats, 
  MaintenanceSystemMetrics,
  MaintenanceStatus
} from '@/shared/services/maintenanceApi';
import { SettingsCard, ToggleSwitch } from './SettingsComponents';
import { FormField } from '@/shared/components/ui/FormField';
import { useNotifications } from '@/shared/hooks/useNotifications';

// Maintenance Mode Control Component
interface MaintenanceModeControlProps {
  status: MaintenanceStatus;
  onUpdate: () => void;
}

export const MaintenanceModeControl: React.FC<MaintenanceModeControlProps> = ({ status, onUpdate }) => {
  const [loading, setLoading] = useState(false);
  const [scheduled, setScheduled] = useState(false);
  const [scheduledStart, setScheduledStart] = useState('');
  const [scheduledEnd, setScheduledEnd] = useState('');
  const [message, setMessage] = useState(status.message || '');
  const { showNotification } = useNotifications();

  const handleToggleMaintenanceMode = async (enabled: boolean) => {
    try {
      setLoading(true);
      await maintenanceApi.setMaintenanceMode(enabled, message);
      showNotification(
        enabled ? 'Maintenance mode activated' : 'Maintenance mode deactivated',
        'success'
      );
      onUpdate();
    } catch (error) {
      showNotification('Failed to update maintenance mode', 'error');
    } finally {
      setLoading(false);
    }
  };

  const handleScheduleMaintenance = async () => {
    try {
      setLoading(true);
      await maintenanceApi.scheduleMaintenanceMode(scheduledStart, scheduledEnd, message);
      showNotification('Maintenance window scheduled successfully', 'success');
      setScheduled(false);
      onUpdate();
    } catch (error) {
      showNotification('Failed to schedule maintenance', 'error');
    } finally {
      setLoading(false);
    }
  };

  return (
    <SettingsCard
      title="Maintenance Mode"
      description="Control system access during maintenance operations"
      icon="🔧"
    >
      <div className="space-y-6">
        {/* Current Status */}
        <div className="flex items-center justify-between p-4 rounded-lg border border-theme bg-theme-background-secondary">
          <div>
            <h4 className="text-sm font-medium text-theme-primary">
              System Access Control
            </h4>
            <p className="text-sm text-theme-secondary">
              {status.mode ? 'System is in maintenance mode' : 'System is accessible to users'}
            </p>
          </div>
          <ToggleSwitch
            checked={status.mode}
            onChange={handleToggleMaintenanceMode}
            disabled={loading}
            variant="error"
          />
        </div>

        {/* Active Maintenance Alert */}
        {status.mode && (
          <div className="p-4 bg-theme-error-background border border-theme-error rounded-lg">
            <div className="flex items-center gap-2">
              <AlertTriangle className="w-5 h-5 text-theme-error" />
              <h4 className="font-medium text-theme-error">Maintenance Mode Active</h4>
            </div>
            <p className="text-sm text-theme-error mt-1">
              Users cannot access the application. Only administrators can use the system.
            </p>
          </div>
        )}

        {/* Scheduled Maintenance */}
        {(status.scheduled_start || scheduled) && (
          <div className="p-4 bg-theme-info-background border border-theme-info rounded-lg">
            <div className="flex items-center gap-2 mb-2">
              <Calendar className="w-5 h-5 text-theme-info" />
              <h4 className="font-medium text-theme-info">Scheduled Maintenance</h4>
            </div>
            {status.scheduled_start && (
              <p className="text-sm text-theme-info">
                Scheduled from {new Date(status.scheduled_start).toLocaleString()} 
                to {status.scheduled_end ? new Date(status.scheduled_end).toLocaleString() : 'TBD'}
              </p>
            )}
          </div>
        )}

        {/* Maintenance Message */}
        <FormField
          label="Maintenance Message"
          helpText="Message displayed to users during maintenance"
          type="text"
          value={message}
          onChange={setMessage}
          placeholder="System is under maintenance. Please try again later."
          disabled={loading}
        />

        {/* Schedule Maintenance */}
        <div className="pt-4 border-t border-theme">
          <div className="flex items-center justify-between mb-4">
            <h4 className="text-sm font-medium text-theme-primary">Schedule Maintenance Window</h4>
            <Button variant="outline" onClick={() => setScheduled(!scheduled)}
              className="text-sm text-theme-link hover:text-theme-link-hover"
            >
              {scheduled ? 'Cancel' : 'Schedule'}
            </Button>
          </div>

          {scheduled && (
            <div className="space-y-4">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                <FormField 
                  label="Start Time"
                  type="datetime-local"
                  value={scheduledStart}
                  onChange={setScheduledStart}
                  disabled={loading}
                />
                <FormField 
                  label="End Time"
                  type="datetime-local"
                  value={scheduledEnd}
                  onChange={setScheduledEnd}
                  disabled={loading}
                />
              </div>
              <Button onClick={handleScheduleMaintenance} disabled={loading || !scheduledStart || !scheduledEnd} variant="outline" fullWidth>
                Schedule Maintenance Window
              </Button>
            </div>
          )}
        </div>
      </div>
    </SettingsCard>
  );
};

// System Health Component
interface SystemHealthProps {
  health: SystemHealth;
  metrics: MaintenanceSystemMetrics;
  onRefresh: () => void;
}

export const SystemHealthMonitor: React.FC<SystemHealthProps> = ({ health, metrics, onRefresh }) => {
  const getStatusIcon = (status: string) => {
    switch (status) {
      case 'healthy': return <CheckCircle className="w-5 h-5 text-theme-success" />;
      case 'warning': return <AlertTriangle className="w-5 h-5 text-theme-warning" />;
      case 'critical': return <AlertTriangle className="w-5 h-5 text-theme-error" />;
      default: return <Info className="w-5 h-5 text-theme-secondary" />;
    }
  };

  return (
    <SettingsCard
      title="System Health"
      description="Monitor system performance and resource usage"
      icon="🏥"
    >
      <div className="space-y-6">
        {/* Overall Status */}
        <div className={`p-4 rounded-lg border ${maintenanceApi.getStatusBgColor(health.overall_status)}`}>
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              {getStatusIcon(health.overall_status)}
              <div>
                <h4 className="font-medium text-theme-primary">System Status</h4>
                <p className="text-sm text-theme-secondary capitalize">{health.overall_status}</p>
              </div>
            </div>
            <Button onClick={onRefresh} variant="outline">
              <RefreshCw className="w-4 h-4" />
            </Button>
          </div>
        </div>

        {/* System Metrics */}
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div className="text-center p-4 bg-theme-background rounded-lg border border-theme">
            <Cpu className="w-8 h-8 text-theme-interactive-primary mx-auto mb-2" />
            <div className="text-2xl font-bold text-theme-primary">{metrics.cpu_usage}%</div>
            <div className="text-sm text-theme-secondary">CPU Usage</div>
          </div>
          <div className="text-center p-4 bg-theme-background rounded-lg border border-theme">
            <MemoryStick className="w-8 h-8 text-theme-interactive-primary mx-auto mb-2" />
            <div className="text-2xl font-bold text-theme-primary">{metrics.memory_usage}%</div>
            <div className="text-sm text-theme-secondary">Memory</div>
          </div>
          <div className="text-center p-4 bg-theme-background rounded-lg border border-theme">
            <HardDrive className="w-8 h-8 text-theme-interactive-primary mx-auto mb-2" />
            <div className="text-2xl font-bold text-theme-primary">{metrics.disk_usage}%</div>
            <div className="text-sm text-theme-secondary">Disk Usage</div>
          </div>
          <div className="text-center p-4 bg-theme-background rounded-lg border border-theme">
            <Activity className="w-8 h-8 text-theme-interactive-primary mx-auto mb-2" />
            <div className="text-2xl font-bold text-theme-primary">{metrics.active_users}</div>
            <div className="text-sm text-theme-secondary">Active Users</div>
          </div>
        </div>

        {/* Component Status */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          <div className="p-4 bg-theme-background rounded-lg border border-theme">
            <div className="flex items-center justify-between mb-2">
              <div className="flex items-center gap-2">
                <Database className="w-5 h-5 text-theme-interactive-primary" />
                <span className="font-medium text-theme-primary">Database</span>
              </div>
              {getStatusIcon(health.database.status)}
            </div>
            <div className="space-y-1 text-sm text-theme-secondary">
              <div>Size: {maintenanceApi.formatBytes(health.database.size)}</div>
              <div>Response: {health.database.connection_time}ms</div>
            </div>
          </div>

          <div className="p-4 bg-theme-background rounded-lg border border-theme">
            <div className="flex items-center justify-between mb-2">
              <div className="flex items-center gap-2">
                <MemoryStick className="w-5 h-5 text-theme-interactive-primary" />
                <span className="font-medium text-theme-primary">Redis</span>
              </div>
              {getStatusIcon(health.redis.status)}
            </div>
            <div className="space-y-1 text-sm text-theme-secondary">
              <div>Memory: {maintenanceApi.formatBytes(health.redis.memory_usage)}</div>
              <div>Clients: {health.redis.connected_clients}</div>
            </div>
          </div>

          <div className="p-4 bg-theme-background rounded-lg border border-theme">
            <div className="flex items-center justify-between mb-2">
              <div className="flex items-center gap-2">
                <HardDrive className="w-5 h-5 text-theme-interactive-primary" />
                <span className="font-medium text-theme-primary">Storage</span>
              </div>
              {getStatusIcon(health.storage.status)}
            </div>
            <div className="space-y-1 text-sm text-theme-secondary">
              <div>Used: {maintenanceApi.formatBytes(health.storage.used_space)}</div>
              <div>Free: {maintenanceApi.formatBytes(health.storage.available_space)}</div>
            </div>
          </div>
        </div>

        {/* Services Status */}
        {health.services.length > 0 && (
          <div>
            <h5 className="font-medium text-theme-primary mb-3">Services</h5>
            <div className="space-y-2">
              {health.services.map((service, index) => (
                <div key={index} className="flex items-center justify-between p-3 bg-theme-background rounded border border-theme">
                  <div className="flex items-center gap-3">
                    {getStatusIcon(service.status)}
                    <div>
                      <div className="font-medium text-theme-primary">{service.name}</div>
                      <div className="text-sm text-theme-secondary">
                        Uptime: {maintenanceApi.formatUptime(service.uptime)} | 
                        Memory: {maintenanceApi.formatBytes(service.memory_usage)}
                      </div>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </SettingsCard>
  );
};

// Database Backup Component
interface DatabaseBackupProps {
  backups: BackupInfo[];
  onRefresh: () => void;
}

export const DatabaseBackupManager: React.FC<DatabaseBackupProps> = ({ backups, onRefresh }) => {
  const [loading, setLoading] = useState(false);
  const [creatingBackup, setCreatingBackup] = useState(false);
  const { showNotification } = useNotifications();

  const handleCreateBackup = async () => {
    try {
      setCreatingBackup(true);
      await maintenanceApi.createBackup();
      showNotification('Backup created successfully', 'success');
      onRefresh();
    } catch (error) {
      showNotification('Failed to create backup', 'error');
    } finally {
      setCreatingBackup(false);
    }
  };

  const handleDeleteBackup = async (backupId: string) => {
    if (!window.confirm('Are you sure you want to delete this backup? This action cannot be undone.')) {
      return;
    }

    try {
      setLoading(true);
      await maintenanceApi.deleteBackup(backupId);
      showNotification('Backup deleted successfully', 'success');
      onRefresh();
    } catch (error) {
      showNotification('Failed to delete backup', 'error');
    } finally {
      setLoading(false);
    }
  };

  const handleDownloadBackup = async (backupId: string) => {
    try {
      const downloadUrl = await maintenanceApi.downloadBackup(backupId);
      window.open(downloadUrl, '_blank');
    } catch (error) {
      showNotification('Failed to download backup', 'error');
    }
  };

  const latestBackup = backups[0];

  return (
    <SettingsCard
      title="Database Backups"
      description="Create, manage, and restore database backups"
      icon="💾"
    >
      <div className="space-y-6">
        {/* Latest Backup Info */}
        {latestBackup && (
          <div className="p-4 bg-theme-background rounded-lg border border-theme">
            <div className="flex items-center justify-between mb-3">
              <h4 className="font-medium text-theme-primary">Latest Backup</h4>
              <span className={`px-2 py-1 rounded text-xs font-medium ${
                latestBackup.status === 'completed' ? 'bg-theme-success-background text-theme-success' :
                latestBackup.status === 'in_progress' ? 'bg-theme-warning-background text-theme-warning' :
                'bg-theme-error-background text-theme-error'
              }`}>
                {latestBackup.status}
              </span>
            </div>
            <div className="grid grid-cols-2 gap-4 text-sm">
              <div>
                <span className="text-theme-secondary">Created:</span>
                <div className="font-medium text-theme-primary">
                  {new Date(latestBackup.created_at).toLocaleString()}
                </div>
              </div>
              <div>
                <span className="text-theme-secondary">Size:</span>
                <div className="font-medium text-theme-primary">
                  {maintenanceApi.formatBytes(latestBackup.size)}
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Create Backup */}
        <div className="flex gap-3">
          <Button onClick={handleCreateBackup} disabled={creatingBackup} variant="outline">
            {creatingBackup ? (
              <>
                <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                Creating Backup...
              </>
            ) : (
              'Create Backup Now'
            )}
          </Button>
          <Button onClick={onRefresh} disabled={loading} variant="outline">
            <RefreshCw className="w-4 h-4" />
          </Button>
        </div>

        {/* Backup List */}
        {backups.length > 0 && (
          <div>
            <h5 className="font-medium text-theme-primary mb-3">Backup History</h5>
            <div className="space-y-2">
              {backups.slice(0, 5).map((backup) => (
                <div key={backup.id} className="flex items-center justify-between p-3 bg-theme-background rounded border border-theme">
                  <div className="flex-1">
                    <div className="flex items-center gap-2">
                      <span className="font-medium text-theme-primary">{backup.filename}</span>
                      <span className={`px-2 py-1 rounded text-xs font-medium ${
                        backup.status === 'completed' ? 'bg-theme-success-background text-theme-success' :
                        backup.status === 'in_progress' ? 'bg-theme-warning-background text-theme-warning' :
                        'bg-theme-error-background text-theme-error'
                      }`}>
                        {backup.status}
                      </span>
                    </div>
                    <div className="text-sm text-theme-secondary">
                      {new Date(backup.created_at).toLocaleString()} • {maintenanceApi.formatBytes(backup.size)} • {backup.type}
                    </div>
                  </div>
                  <div className="flex items-center gap-2">
                    {backup.status === 'completed' && (
                      <Button variant="outline" onClick={() => handleDownloadBackup(backup.id)}
                        className="p-2 text-theme-link hover:text-theme-link-hover"
                        title="Download backup"
                      >
                        <Download className="w-4 h-4" />
                      </Button>
                    )}
                    <Button variant="outline" onClick={() => handleDeleteBackup(backup.id)}
                      disabled={loading}
                      className="p-2 text-theme-error hover:text-theme-error-hover"
                      title="Delete backup"
                    >
                      <Trash2 className="w-4 h-4" />
                    </Button>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </SettingsCard>
  );
};

// Data Cleanup Component
interface DataCleanupProps {
  stats: CleanupStats;
  onRefresh: () => void;
}

export const DataCleanupManager: React.FC<DataCleanupProps> = ({ stats, onRefresh }) => {
  const [loading, setLoading] = useState(false);
  const [selectedOptions, setSelectedOptions] = useState({
    old_logs: true,
    expired_sessions: true,
    temporary_files: true,
    audit_logs: false,
    orphaned_uploads: true,
    cache_entries: false,
  });
  const { showNotification } = useNotifications();

  const handleRunCleanup = async () => {
    if (!window.confirm('Are you sure you want to run the selected cleanup operations? This action cannot be undone.')) {
      return;
    }

    try {
      setLoading(true);
      const result = await maintenanceApi.runCleanup(selectedOptions);
      showNotification(
        `Cleanup completed: ${result.cleaned_items} items removed, ${maintenanceApi.formatBytes(result.freed_space)} freed`,
        'success'
      );
      onRefresh();
    } catch (error) {
      showNotification('Cleanup failed', 'error');
    } finally {
      setLoading(false);
    }
  };

  const cleanupItems = [
    { key: 'old_logs', label: 'Old Log Files', count: stats.old_logs, description: 'Remove log files older than 30 days' },
    { key: 'expired_sessions', label: 'Expired Sessions', count: stats.expired_sessions, description: 'Clear expired user sessions' },
    { key: 'temporary_files', label: 'Temporary Files', count: stats.temporary_files, description: 'Remove temporary uploaded files' },
    { key: 'audit_logs', label: 'Old Audit Logs', count: stats.audit_logs_older_than_90_days, description: 'Archive audit logs older than 90 days' },
    { key: 'orphaned_uploads', label: 'Orphaned Uploads', count: stats.orphaned_uploads, description: 'Remove uploaded files without references' },
    { key: 'cache_entries', label: 'Cache Entries', count: stats.cache_entries, description: 'Clear application cache' },
  ];

  return (
    <SettingsCard
      title="Data Cleanup"
      description="Remove unnecessary data and free up storage space"
      icon="🗑️"
    >
      <div className="space-y-6">
        {/* Cleanup Options */}
        <div className="space-y-3">
          {cleanupItems.map((item) => (
            <div key={item.key} className="flex items-center justify-between p-3 bg-theme-background rounded border border-theme">
              <div className="flex items-center gap-3">
                <input
                  type="checkbox"
                  id={item.key}
                  checked={selectedOptions[item.key as keyof typeof selectedOptions]}
                  onChange={(e) => setSelectedOptions(prev => ({ ...prev, [item.key]: e.target.checked }))}
                  className="rounded border-theme text-theme-interactive-primary focus:ring-theme-interactive-primary"
                />
                <label htmlFor={item.key} className="flex-1 cursor-pointer">
                  <div className="font-medium text-theme-primary">{item.label}</div>
                  <div className="text-sm text-theme-secondary">{item.description}</div>
                </label>
              </div>
              <div className="text-sm font-medium text-theme-primary">
                {item.count.toLocaleString()} items
              </div>
            </div>
          ))}
        </div>

        <Button onClick={handleRunCleanup} disabled={loading || !Object.values(selectedOptions).some(Boolean)} variant="outline" fullWidth>
          {loading ? (
            <>
              <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
              Running Cleanup...
            </>
          ) : (
            'Run Selected Cleanup Operations'
          )}
        </Button>
      </div>
    </SettingsCard>
  );
};