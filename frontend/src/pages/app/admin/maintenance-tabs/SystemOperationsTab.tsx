import React, { useState } from 'react';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { maintenanceApi } from '@/shared/services/maintenanceApi';
import { SettingsCard } from '@/features/admin/components/settings/SettingsComponents';
import { SystemOperationsTabProps } from './types';

export const SystemOperationsTab: React.FC<SystemOperationsTabProps> = ({ health, onRefresh }) => {
  const { showNotification } = useNotifications();
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
    } catch (_error: unknown) {
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
    } catch (_error: unknown) {
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
    } catch (_error: unknown) {
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
