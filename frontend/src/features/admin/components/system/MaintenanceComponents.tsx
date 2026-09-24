import React, { useState } from 'react';
import {
  Download,
  Trash2,
  RefreshCw
} from 'lucide-react';
import {
  maintenanceApi,
  BackupInfo,
  CleanupStats
} from '@/shared/services/admin/maintenanceApi';
import { SettingsCard } from '../settings/SettingsComponents';
import { useConfirmation } from '@/shared/components/ui/ConfirmationModal';
import { useNotifications } from '@/shared/hooks/useNotifications';

// Database Backup Component
interface DatabaseBackupProps {
  backups: BackupInfo[];
  onRefresh: () => void;
}

export const DatabaseBackupManager: React.FC<DatabaseBackupProps> = ({ backups, onRefresh }) => {
  const [loading, setLoading] = useState(false);
  const [creatingBackup, setCreatingBackup] = useState(false);
  const { showNotification } = useNotifications();
  const { confirm, ConfirmationDialog } = useConfirmation();

  const handleCreateBackup = async () => {
    try {
      setCreatingBackup(true);
      await maintenanceApi.createBackup();
      showNotification('Backup created successfully', 'success');
      onRefresh();
    } catch (_error) {
      showNotification('Failed to create backup', 'error');
    } finally {
      setCreatingBackup(false);
    }
  };

  const handleDeleteBackup = async (backupId: string) => {
    confirm({
      title: 'Delete Backup',
      message: 'Are you sure you want to delete this backup? This action cannot be undone.',
      confirmLabel: 'Delete',
      variant: 'danger',
      onConfirm: async () => {
        try {
          setLoading(true);
          await maintenanceApi.deleteBackup(backupId);
          showNotification('Backup deleted successfully', 'success');
          onRefresh();
        } catch (_error) {
          showNotification('Failed to delete backup', 'error');
        } finally {
          setLoading(false);
        }
      }
    });
  };

  const handleDownloadBackup = async (backupId: string) => {
    try {
      const downloadUrl = await maintenanceApi.downloadBackup(backupId);
      window.open(downloadUrl, '_blank');
    } catch (_error) {
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
                latestBackup.status === 'completed' ? 'bg-theme-success-bg text-theme-success-fg' :
                latestBackup.status === 'in_progress' ? 'bg-theme-warning-bg text-theme-warning-fg' :
                'bg-theme-error-bg text-theme-error-fg'
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
          <button
            onClick={handleCreateBackup}
            disabled={creatingBackup}
            className="btn-theme btn-theme-primary flex-1"
          >
            {creatingBackup ? (
              <>
                <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                Creating Backup...
              </>
            ) : (
              'Create Backup Now'
            )}
          </button>
          <button
            onClick={onRefresh}
            disabled={loading}
            aria-label="Refresh"
            className="btn-theme btn-theme-secondary px-4"
          >
            <RefreshCw className="w-4 h-4" />
          </button>
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
                        backup.status === 'completed' ? 'bg-theme-success-bg text-theme-success-fg' :
                        backup.status === 'in_progress' ? 'bg-theme-warning-bg text-theme-warning-fg' :
                        'bg-theme-error-bg text-theme-error-fg'
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
                      <button
                        onClick={() => handleDownloadBackup(backup.id)}
                        className="p-2 text-theme-link hover:text-theme-link-hover"
                        title="Download backup"
                      >
                        <Download className="w-4 h-4" />
                      </button>
                    )}
                    <button
                      onClick={() => handleDeleteBackup(backup.id)}
                      disabled={loading}
                      className="p-2 text-theme-error-fg hover:text-theme-error-hover"
                      title="Delete backup"
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}
        {ConfirmationDialog}
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
  const { confirm, ConfirmationDialog } = useConfirmation();

  const handleRunCleanup = async () => {
    confirm({
      title: 'Run Cleanup',
      message: 'Are you sure you want to run the selected cleanup operations? This action cannot be undone.',
      confirmLabel: 'Run Cleanup',
      variant: 'warning',
      onConfirm: async () => {
        try {
          setLoading(true);
          const result = await maintenanceApi.runCleanup(selectedOptions);
          showNotification(
            `Cleanup completed: ${result.cleaned_items} items removed, ${maintenanceApi.formatBytes(result.freed_space)} freed`,
            'success'
          );
          onRefresh();
        } catch (_error) {
          showNotification('Cleanup failed', 'error');
        } finally {
          setLoading(false);
        }
      }
    });
  };

  const cleanupItems = [
    { key: 'old_logs', label: 'Old Log Files', count: stats.old_logs || 0, description: 'Remove log files older than 30 days' },
    { key: 'expired_sessions', label: 'Expired Sessions', count: stats.expired_sessions || 0, description: 'Clear expired user sessions' },
    { key: 'temporary_files', label: 'Temporary Files', count: stats.temporary_files || 0, description: 'Remove temporary uploaded files' },
    { key: 'audit_logs', label: 'Old Audit Logs', count: stats.audit_logs_older_than_90_days || 0, description: 'Archive audit logs older than 90 days' },
    { key: 'orphaned_uploads', label: 'Orphaned Uploads', count: stats.orphaned_uploads || 0, description: 'Remove uploaded files without references' },
    { key: 'cache_entries', label: 'Cache Entries', count: stats.cache_entries || 0, description: 'Clear application cache' },
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

        {/* Run Cleanup */}
        <button
          onClick={handleRunCleanup}
          disabled={loading || !Object.values(selectedOptions).some(Boolean)}
          className="btn-theme btn-theme-secondary w-full"
        >
          {loading ? (
            <>
              <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
              Running Cleanup...
            </>
          ) : (
            'Run Selected Cleanup Operations'
          )}
        </button>
        {ConfirmationDialog}
      </div>
    </SettingsCard>
  );
};