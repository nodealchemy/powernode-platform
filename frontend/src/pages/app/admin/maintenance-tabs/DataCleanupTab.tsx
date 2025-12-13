import React, { useEffect } from 'react';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { maintenanceApi } from '@/shared/services/maintenanceApi';
import { DataCleanupManager } from '@/features/admin/components/system/MaintenanceComponents';
import { DataCleanupTabProps } from './types';

export const DataCleanupTab: React.FC<DataCleanupTabProps> = ({
  stats,
  onRefresh,
  onRegisterActions
}) => {
  const { showNotification } = useNotifications();

  const handleRunCleanup = async () => {
    try {
      const result = await maintenanceApi.runCleanup({
        old_logs: true,
        expired_sessions: true,
        temporary_files: true,
        cache_entries: true
      });
      showNotification(`Cleanup completed. ${result.cleaned_items} items cleaned`, 'success');
      onRefresh();
    } catch (_error: unknown) {
      showNotification('Failed to run cleanup', 'error');
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
