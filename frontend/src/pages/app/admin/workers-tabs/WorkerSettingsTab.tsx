import React, { useState } from 'react';
import { Card } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { FlexBetween } from '@/shared/components/ui/FlexContainer';
import { RefreshCw } from 'lucide-react';
import type { WorkerSettingsTabProps } from './types';

export const WorkerSettingsTab: React.FC<WorkerSettingsTabProps> = ({
  workers,
  canManageWorkers,
  onRefresh
}) => {
  const [settings, setSettings] = useState({
    autoCleanupEnabled: true,
    cleanupAfterDays: 30,
    tokenExpiryDays: 90,
    healthCheckInterval: 300, // 5 minutes
    enableActivityLogging: true,
    maxFailedAttempts: 5
  });

  return (
    <div className="space-y-6">
      {/* Global Settings */}
      <Card className="p-6">
        <FlexBetween className="mb-4">
          <div>
            <h3 className="text-lg font-medium text-theme-primary">Worker Configuration</h3>
            <p className="text-sm text-theme-secondary">
              Configure global worker system settings
            </p>
          </div>
          <Button onClick={onRefresh} variant="secondary" size="sm">
            <RefreshCw className="w-4 h-4 mr-2" />
            Refresh
          </Button>
        </FlexBetween>

        <div className="space-y-6">
          {/* Security Settings */}
          <div>
            <h4 className="text-md font-medium text-theme-primary mb-3">Security Settings</h4>
            <div className="space-y-4">
              <FlexBetween>
                <div>
                  <label className="block text-sm font-medium text-theme-primary">
                    Token Expiry Period
                  </label>
                  <p className="text-sm text-theme-secondary">
                    How long worker tokens remain valid
                  </p>
                </div>
                <div className="flex items-center space-x-2">
                  <input
                    type="number"
                    value={settings.tokenExpiryDays}
                    onChange={(e) => setSettings(prev => ({ ...prev, tokenExpiryDays: parseInt(e.target.value) }))}
                    className="w-20 p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary text-sm"
                    min="1"
                    max="365"
                    disabled={!canManageWorkers}
                  />
                  <span className="text-sm text-theme-secondary">days</span>
                </div>
              </FlexBetween>

              <FlexBetween>
                <div>
                  <label className="block text-sm font-medium text-theme-primary">
                    Max Failed Attempts
                  </label>
                  <p className="text-sm text-theme-secondary">
                    Worker is suspended after this many failed requests
                  </p>
                </div>
                <input
                  type="number"
                  value={settings.maxFailedAttempts}
                  onChange={(e) => setSettings(prev => ({ ...prev, maxFailedAttempts: parseInt(e.target.value) }))}
                  className="w-20 p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary text-sm"
                  min="1"
                  max="100"
                  disabled={!canManageWorkers}
                />
              </FlexBetween>
            </div>
          </div>

          {/* Monitoring Settings */}
          <div className="pt-4 border-t border-theme">
            <h4 className="text-md font-medium text-theme-primary mb-3">Monitoring Settings</h4>
            <div className="space-y-4">
              <FlexBetween>
                <div>
                  <label className="block text-sm font-medium text-theme-primary">
                    Health Check Interval
                  </label>
                  <p className="text-sm text-theme-secondary">
                    How often to check worker health status
                  </p>
                </div>
                <div className="flex items-center space-x-2">
                  <input
                    type="number"
                    value={settings.healthCheckInterval}
                    onChange={(e) => setSettings(prev => ({ ...prev, healthCheckInterval: parseInt(e.target.value) }))}
                    className="w-20 p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary text-sm"
                    min="60"
                    max="3600"
                    disabled={!canManageWorkers}
                  />
                  <span className="text-sm text-theme-secondary">seconds</span>
                </div>
              </FlexBetween>

              <FlexBetween>
                <div>
                  <label className="block text-sm font-medium text-theme-primary">
                    Enable Activity Logging
                  </label>
                  <p className="text-sm text-theme-secondary">
                    Log all worker activities and requests
                  </p>
                </div>
                <Button
                  onClick={() => setSettings(prev => ({ ...prev, enableActivityLogging: !prev.enableActivityLogging }))}
                  variant={settings.enableActivityLogging ? 'success' : 'secondary'}
                  size="sm"
                  disabled={!canManageWorkers}
                >
                  {settings.enableActivityLogging ? 'Enabled' : 'Disabled'}
                </Button>
              </FlexBetween>
            </div>
          </div>

          {/* Cleanup Settings */}
          <div className="pt-4 border-t border-theme">
            <h4 className="text-md font-medium text-theme-primary mb-3">Cleanup Settings</h4>
            <div className="space-y-4">
              <FlexBetween>
                <div>
                  <label className="block text-sm font-medium text-theme-primary">
                    Auto Cleanup Activities
                  </label>
                  <p className="text-sm text-theme-secondary">
                    Automatically remove old activity logs
                  </p>
                </div>
                <Button
                  onClick={() => setSettings(prev => ({ ...prev, autoCleanupEnabled: !prev.autoCleanupEnabled }))}
                  variant={settings.autoCleanupEnabled ? 'success' : 'secondary'}
                  size="sm"
                  disabled={!canManageWorkers}
                >
                  {settings.autoCleanupEnabled ? 'Enabled' : 'Disabled'}
                </Button>
              </FlexBetween>

              {settings.autoCleanupEnabled && (
                <FlexBetween>
                  <div>
                    <label className="block text-sm font-medium text-theme-primary">
                      Cleanup After
                    </label>
                    <p className="text-sm text-theme-secondary">
                      Remove activity logs older than this period
                    </p>
                  </div>
                  <div className="flex items-center space-x-2">
                    <input
                      type="number"
                      value={settings.cleanupAfterDays}
                      onChange={(e) => setSettings(prev => ({ ...prev, cleanupAfterDays: parseInt(e.target.value) }))}
                      className="w-20 p-2 border border-theme rounded-lg bg-theme-surface text-theme-primary text-sm"
                      min="1"
                      max="365"
                      disabled={!canManageWorkers}
                    />
                    <span className="text-sm text-theme-secondary">days</span>
                  </div>
                </FlexBetween>
              )}
            </div>
          </div>

          {/* Save Button */}
          {canManageWorkers && (
            <div className="pt-4 border-t border-theme">
              <FlexBetween>
                <p className="text-sm text-theme-secondary">
                  Changes will be applied to all workers immediately
                </p>
                <Button variant="primary">
                  Save Settings
                </Button>
              </FlexBetween>
            </div>
          )}
        </div>
      </Card>

      {/* System Information */}
      <Card className="p-6">
        <h3 className="text-lg font-medium text-theme-primary mb-4">System Information</h3>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
          <div>
            <h4 className="text-sm font-medium text-theme-primary mb-2">Worker System Status</h4>
            <div className="space-y-2 text-sm">
              <FlexBetween>
                <span className="text-theme-secondary">Total Workers:</span>
                <span className="text-theme-primary">{workers.length}</span>
              </FlexBetween>
              <FlexBetween>
                <span className="text-theme-secondary">Active Workers:</span>
                <span className="text-theme-success">{workers.filter(w => w.status === 'active').length}</span>
              </FlexBetween>
              <FlexBetween>
                <span className="text-theme-secondary">System Workers:</span>
                <span className="text-theme-info">{workers.filter(w => w.account_name === 'System').length}</span>
              </FlexBetween>
              <FlexBetween>
                <span className="text-theme-secondary">Account Workers:</span>
                <span className="text-theme-warning">{workers.filter(w => w.account_name !== 'System').length}</span>
              </FlexBetween>
            </div>
          </div>
          <div>
            <h4 className="text-sm font-medium text-theme-primary mb-2">Performance Metrics</h4>
            <div className="space-y-2 text-sm">
              <FlexBetween>
                <span className="text-theme-secondary">Total Requests:</span>
                <span className="text-theme-primary">
                  {workers.reduce((sum, w) => sum + w.request_count, 0).toLocaleString()}
                </span>
              </FlexBetween>
              <FlexBetween>
                <span className="text-theme-secondary">Average Requests/Worker:</span>
                <span className="text-theme-primary">
                  {Math.round(workers.reduce((sum, w) => sum + w.request_count, 0) / workers.length) || 0}
                </span>
              </FlexBetween>
              <FlexBetween>
                <span className="text-theme-secondary">Recently Active:</span>
                <span className="text-theme-success">{workers.filter(w => w.active_recently).length}</span>
              </FlexBetween>
              <FlexBetween>
                <span className="text-theme-secondary">System Uptime:</span>
                <span className="text-theme-success">99.8%</span>
              </FlexBetween>
            </div>
          </div>
        </div>
      </Card>
    </div>
  );
};
