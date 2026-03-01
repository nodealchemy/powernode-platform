import React, { useState } from 'react';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { maintenanceApi } from '@/shared/services/admin/maintenanceApi';
import { SettingsCard, ToggleSwitch } from '@/features/admin/components/settings/SettingsComponents';
import { MaintenanceModeTabProps } from './types';

export const MaintenanceModeTab: React.FC<MaintenanceModeTabProps> = ({ status, onUpdate }) => {
  const { showNotification } = useNotifications();
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
    } catch (_error) {
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
    } catch (_error) {
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
          <div>
            <label className="block text-sm font-semibold text-theme-primary mb-2">Start Time</label>
            <input
              type="datetime-local"
              value={scheduledMode.startTime}
              onChange={(e) => setScheduledMode(prev => ({ ...prev, startTime: e.target.value }))}
              className="input-theme w-full"
            />
          </div>
          <div>
            <label className="block text-sm font-semibold text-theme-primary mb-2">End Time</label>
            <input
              type="datetime-local"
              value={scheduledMode.endTime}
              onChange={(e) => setScheduledMode(prev => ({ ...prev, endTime: e.target.value }))}
              className="input-theme w-full"
            />
          </div>
          <div className="md:col-span-2">
            <label className="block text-sm font-semibold text-theme-primary mb-2">Maintenance Message</label>
            <input
              type="text"
              placeholder="System maintenance in progress..."
              value={scheduledMode.message}
              onChange={(e) => setScheduledMode(prev => ({ ...prev, message: e.target.value }))}
              className="input-theme w-full"
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
