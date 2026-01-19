import React, { useState, useEffect } from 'react';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { maintenanceApi, MaintenanceSchedule } from '@/shared/services/admin/maintenanceApi';
import { SettingsCard, ToggleSwitch } from '@/features/admin/components/settings/SettingsComponents';
import { RefreshCw, Plus } from 'lucide-react';
import { ScheduledTasksTabProps } from './types';

// Schedule Creation Modal
const CreateScheduleModal: React.FC<{
  isOpen: boolean;
  onClose: () => void;
  onSubmit: (schedule: Omit<MaintenanceSchedule, 'id' | 'next_run' | 'last_run'>) => Promise<void>;
}> = ({ isOpen, onClose, onSubmit }) => {
  const [formData, setFormData] = useState({
    type: 'backup' as MaintenanceSchedule['type'],
    scheduled_at: '',
    frequency: 'once' as MaintenanceSchedule['frequency'],
    enabled: true,
    description: ''
  });
  const [submitting, setSubmitting] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!formData.scheduled_at || !formData.description) return;

    setSubmitting(true);
    try {
      await onSubmit(formData);
      setFormData({
        type: 'backup',
        scheduled_at: '',
        frequency: 'once',
        enabled: true,
        description: ''
      });
      onClose();
    } finally {
      setSubmitting(false);
    }
  };

  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-theme-surface rounded-lg shadow-xl w-full max-w-md mx-4">
        <div className="p-6 border-b border-theme">
          <h2 className="text-lg font-semibold text-theme-primary">Create Maintenance Schedule</h2>
          <p className="text-sm text-theme-secondary mt-1">Set up a new automated maintenance task</p>
        </div>

        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div>
            <label className="block text-sm font-semibold text-theme-primary mb-2">
              Description<span className="text-theme-error ml-1">*</span>
            </label>
            <input
              type="text"
              value={formData.description}
              onChange={(e) => setFormData({ ...formData, description: e.target.value })}
              placeholder="e.g., Daily database backup"
              className="input-theme w-full"
              required
            />
          </div>

          <div>
            <label className="block text-sm font-semibold text-theme-primary mb-2">
              Task Type<span className="text-theme-error ml-1">*</span>
            </label>
            <select
              value={formData.type}
              onChange={(e) => setFormData({ ...formData, type: e.target.value as MaintenanceSchedule['type'] })}
              className="input-theme w-full"
            >
              <option value="backup">Database Backup</option>
              <option value="cleanup">Data Cleanup</option>
              <option value="restart">Service Restart</option>
              <option value="maintenance_mode">Maintenance Mode</option>
            </select>
          </div>

          <div>
            <label className="block text-sm font-semibold text-theme-primary mb-2">
              Scheduled Time<span className="text-theme-error ml-1">*</span>
            </label>
            <input
              type="datetime-local"
              value={formData.scheduled_at}
              onChange={(e) => setFormData({ ...formData, scheduled_at: e.target.value })}
              className="input-theme w-full"
              required
            />
          </div>

          <div>
            <label className="block text-sm font-semibold text-theme-primary mb-2">
              Frequency<span className="text-theme-error ml-1">*</span>
            </label>
            <select
              value={formData.frequency}
              onChange={(e) => setFormData({ ...formData, frequency: e.target.value as MaintenanceSchedule['frequency'] })}
              className="input-theme w-full"
            >
              <option value="once">Run Once</option>
              <option value="daily">Daily</option>
              <option value="weekly">Weekly</option>
              <option value="monthly">Monthly</option>
            </select>
          </div>

          <div className="flex items-center gap-2">
            <input
              type="checkbox"
              id="enabled"
              checked={formData.enabled}
              onChange={(e) => setFormData({ ...formData, enabled: e.target.checked })}
              className="rounded border-theme text-theme-interactive-primary focus:ring-theme-interactive-primary"
            />
            <label htmlFor="enabled" className="text-sm text-theme-primary">
              Enable schedule immediately
            </label>
          </div>

          <div className="flex justify-end gap-3 pt-4">
            <button
              type="button"
              onClick={onClose}
              className="btn-theme btn-theme-secondary"
              disabled={submitting}
            >
              Cancel
            </button>
            <button
              type="submit"
              className="btn-theme btn-theme-primary"
              disabled={submitting || !formData.description || !formData.scheduled_at}
            >
              {submitting ? (
                <>
                  <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                  Creating...
                </>
              ) : (
                <>
                  <Plus className="w-4 h-4 mr-2" />
                  Create Schedule
                </>
              )}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

export const ScheduledTasksTab: React.FC<ScheduledTasksTabProps> = ({
  schedules,
  onRefresh,
  onRegisterActions
}) => {
  const { showNotification } = useNotifications();
  const [showCreateModal, setShowCreateModal] = useState(false);

  const handleCreateSchedule = () => {
    setShowCreateModal(true);
  };

  const handleSubmitSchedule = async (schedule: Omit<MaintenanceSchedule, 'id' | 'next_run' | 'last_run'>) => {
    try {
      await maintenanceApi.createMaintenanceSchedule(schedule);
      showNotification('Maintenance schedule created successfully', 'success');
      onRefresh();
    } catch (error) {
      showNotification('Failed to create maintenance schedule', 'error');
      throw error;
    }
  };

  useEffect(() => {
    onRegisterActions({ createSchedule: handleCreateSchedule });
  }, [onRegisterActions]);

  const handleRunSchedule = async (scheduleId: string) => {
    try {
      await maintenanceApi.runScheduledTask(scheduleId);
      showNotification('Scheduled task executed successfully', 'success');
      onRefresh();
    } catch (_error: unknown) {
      showNotification('Failed to execute scheduled task', 'error');
    }
  };

  return (
    <div className="space-y-6">
      <CreateScheduleModal
        isOpen={showCreateModal}
        onClose={() => setShowCreateModal(false)}
        onSubmit={handleSubmitSchedule}
      />

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
