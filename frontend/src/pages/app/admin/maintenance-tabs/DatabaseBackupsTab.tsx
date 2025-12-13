import React, { useEffect } from 'react';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { maintenanceApi } from '@/shared/services/maintenanceApi';
import { DatabaseBackupManager } from '@/features/admin/components/system/MaintenanceComponents';
import { DatabaseBackupsTabProps } from './types';

export const DatabaseBackupsTab: React.FC<DatabaseBackupsTabProps> = ({
  backups,
  onRefresh,
  onRegisterActions
}) => {
  const { showNotification } = useNotifications();

  const handleCreateBackup = async () => {
    try {
      await maintenanceApi.createBackup();
      showNotification('Backup created successfully', 'success');
      onRefresh();
    } catch (_error: unknown) {
      showNotification('Failed to create backup', 'error');
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
