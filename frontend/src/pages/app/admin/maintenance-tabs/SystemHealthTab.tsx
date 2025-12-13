import React from 'react';
import { maintenanceApi } from '@/shared/services/maintenanceApi';
import { SettingsCard, StatsCard } from '@/features/admin/components/settings/SettingsComponents';
import { SystemHealthTabProps } from './types';

export const SystemHealthTab: React.FC<SystemHealthTabProps> = ({ health, metrics }) => {
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
