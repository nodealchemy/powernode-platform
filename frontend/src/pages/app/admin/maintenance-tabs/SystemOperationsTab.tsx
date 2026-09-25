import React, { useState } from 'react';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { maintenanceApi } from '@/shared/services/admin/maintenanceApi';
import { SettingsCard } from '@/features/admin/components/settings/SettingsComponents';
import { SystemOperationsTabProps } from './types';

export const SystemOperationsTab: React.FC<SystemOperationsTabProps> = ({ onRefresh }) => {
  const { showNotification } = useNotifications();
  const [operations, setOperations] = useState({
    flushingCache: false,
    optimizingDb: false
  });

  const handleFlushCache = async () => {
    setOperations(prev => ({ ...prev, flushingCache: true }));
    try {
      await maintenanceApi.flushCache();
      showNotification('Cache flushed successfully', 'success');
      onRefresh();
    } catch (_error) {
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
    } catch (_error) {
      showNotification('Failed to optimize database', 'error');
    } finally {
      setOperations(prev => ({ ...prev, optimizingDb: false }));
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

    </div>
  );
};
