import React, { useState, useEffect } from 'react';
import { useSelector } from 'react-redux';
import { Navigate } from 'react-router-dom';
import { RootState } from '../../store';
import { 
  adminApi, 
  AdminSettingsData, 
  SystemSettings
} from '../../services/adminApi';
import { AdminSettingsOverviewPage } from './AdminSettingsOverviewPage';
import { hasAdminAccess } from '../../utils/permissionUtils';
import { PlatformConfiguration } from '../../components/admin/PlatformConfiguration';
import {
  SettingsCard,
  ToggleSettingItem,
  FormField,
  Input,
  Select,
  StatsCard
} from '../../components/admin/SettingsComponents';
import {
  MaintenanceModeControl,
  SystemHealthMonitor,
  DatabaseBackupManager,
  DataCleanupManager
} from '../../components/admin/MaintenanceComponents';
import {
  maintenanceApi,
  MaintenanceStatus,
  SystemHealth,
  BackupInfo,
  CleanupStats,
  SystemMetrics
} from '../../services/maintenanceApi';

export const AdminSettingsPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const [settings, setSettings] = useState<AdminSettingsData | null>(null);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState('overview');
  const [saving, setSaving] = useState(false);
  const [successMessage, setSuccessMessage] = useState('');
  const [systemSettings, setSystemSettings] = useState<Partial<SystemSettings>>({});
  
  // Maintenance functionality state
  const [maintenanceStatus, setMaintenanceStatus] = useState<MaintenanceStatus | null>(null);
  const [systemHealth, setSystemHealth] = useState<SystemHealth | null>(null);
  const [systemMetrics, setSystemMetrics] = useState<SystemMetrics | null>(null);
  const [backups, setBackups] = useState<BackupInfo[]>([]);
  const [cleanupStats, setCleanupStats] = useState<CleanupStats | null>(null);
  const [maintenanceLoading, setMaintenanceLoading] = useState(false);

  // Check if user has admin access
  const isAdmin = hasAdminAccess(user);

  useEffect(() => {
    if (isAdmin) {
      loadAdminData();
    }
  }, [isAdmin]);

  useEffect(() => {
    if (isAdmin && activeTab === 'maintenance') {
      loadMaintenanceData();
    }
  }, [isAdmin, activeTab]);
  
  // Redirect non-admins to dashboard after hooks
  if (!isAdmin) {
    return <Navigate to="/dashboard" replace />;
  }

  const loadAdminData = async () => {
    try {
      setLoading(true);
      const settingsData = await adminApi.getAdminSettings();

      setSettings(settingsData);
      setSystemSettings(settingsData?.system_settings || {});
    } catch (error) {
      console.error('Failed to load admin data:', error);
    } finally {
      setLoading(false);
    }
  };

  const loadMaintenanceData = async () => {
    try {
      setMaintenanceLoading(true);
      const [status, health, metrics, backupList, stats] = await Promise.all([
        maintenanceApi.getMaintenanceStatus(),
        maintenanceApi.getSystemHealth(),
        maintenanceApi.getSystemMetrics(),
        maintenanceApi.getBackups(),
        maintenanceApi.getCleanupStats()
      ]);

      setMaintenanceStatus(status);
      setSystemHealth(health);
      setSystemMetrics(metrics);
      setBackups(backupList);
      setCleanupStats(stats);
    } catch (error) {
      console.error('Failed to load maintenance data:', error);
    } finally {
      setMaintenanceLoading(false);
    }
  };

  const showSuccess = (message: string) => {
    setSuccessMessage(message);
    setTimeout(() => setSuccessMessage(''), 3000);
  };

  const handleUpdateSettings = async (updatedSettings: Partial<SystemSettings>) => {
    try {
      setSaving(true);
      await adminApi.updateAdminSettings(updatedSettings);
      setSystemSettings({ ...systemSettings, ...updatedSettings });
      showSuccess('Admin settings updated successfully');
    } catch (error) {
      console.error('Failed to update settings:', error);
    } finally {
      setSaving(false);
    }
  };

  // TODO: Implement account suspension/activation UI
  // const handleSuspendAccount = async (accountId: string, reason: string) => {
  //   try {
  //     await adminApi.suspendAccount(accountId, reason);
  //     await loadAdminData(); // Reload data
  //     showSuccess('Account suspended successfully');
  //   } catch (error) {
  //     console.error('Failed to suspend account:', error);
  //   }
  // };

  // const handleActivateAccount = async (accountId: string, reason: string) => {
  //   try {
  //     await adminApi.activateAccount(accountId, reason);
  //     await loadAdminData(); // Reload data
  //     showSuccess('Account activated successfully');
  //   } catch (error) {
  //     console.error('Failed to activate account:', error);
  //   }
  // };


  if (!isAdmin) {
    return (
      <div className="text-center py-12">
        <div className="text-theme-error text-lg font-medium">
          🚫 Access Denied
        </div>
        <p className="text-theme-secondary mt-2">
          You need administrator privileges to access this page.
        </p>
      </div>
    );
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-theme-secondary">Loading admin settings...</div>
      </div>
    );
  }

  const tabs = [
    { id: 'overview', name: 'Overview', icon: '📊' },
    { id: 'system', name: 'Settings', icon: '⚙️' },
    { id: 'platform', name: 'Platform Config', icon: '🏗️' },
    { id: 'security', name: 'Security', icon: '🔒' },
    { id: 'notifications', name: 'Notifications', icon: '🔔' },
    { id: 'maintenance', name: 'Maintenance', icon: '🔧' }
  ];

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-3xl font-bold text-theme-primary">Admin Settings</h1>
          <p className="text-theme-secondary mt-2">
            System administration and platform management.
          </p>
        </div>
        <div className="bg-theme-error text-theme-error px-3 py-1 rounded-full text-sm font-medium">
          🔧 Admin Mode
        </div>
      </div>

      {successMessage && (
        <div className="alert-theme alert-theme-success">
          {successMessage}
        </div>
      )}

      {/* Tab Navigation */}
      <div className="border-b border-theme">
        <nav className="-mb-px flex space-x-8">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`py-2 px-1 border-b-2 font-medium text-sm ${
                activeTab === tab.id
                  ? 'border-theme-focus text-theme-link'
                  : 'border-transparent text-theme-secondary hover:text-theme-primary hover:border-theme'
              }`}
            >
              <span className="mr-2">{tab.icon}</span>
              {tab.name}
            </button>
          ))}
        </nav>
      </div>

      {/* Overview Tab */}
      {activeTab === 'overview' && (
        <AdminSettingsOverviewPage />
      )}

      {/* System Settings Tab */}
      {activeTab === 'system' && (
        <div className="space-y-6">
          {/* User Registration & Access */}
          <SettingsCard
            title="User Registration & Access"
            description="Control how users can register and access the platform"
            icon="👥"
          >
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
              <ToggleSettingItem
                title="User Registration"
                description="Allow new users to create accounts"
                checked={systemSettings?.registration_enabled || false}
                onChange={(checked) => handleUpdateSettings({ registration_enabled: checked })}
                disabled={saving}
                variant="success"
              />

              <ToggleSettingItem
                title="Email Verification"
                description="Require email verification for new users"
                checked={systemSettings?.email_verification_required || false}
                onChange={(checked) => handleUpdateSettings({ email_verification_required: checked })}
                disabled={saving}
                variant="success"
              />

              <ToggleSettingItem
                title="Account Deletion"
                description="Allow users to delete their accounts"
                checked={systemSettings?.allow_account_deletion || false}
                onChange={(checked) => handleUpdateSettings({ allow_account_deletion: checked })}
                disabled={saving}
                variant="warning"
              />

              <ToggleSettingItem
                title="Maintenance Mode"
                description="Prevent user access during updates"
                checked={systemSettings?.maintenance_mode || false}
                onChange={(checked) => handleUpdateSettings({ maintenance_mode: checked })}
                disabled={saving}
                variant="error"
              />
            </div>
          </SettingsCard>

          {/* Security Settings */}
          <SettingsCard
            title="Security Settings"
            description="Password policies and session management"
            icon="🔐"
          >
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
              <FormField label="Password Complexity Level">
                <Select
                  value={systemSettings?.password_complexity_level || 'high'}
                  onChange={(e) => handleUpdateSettings({ password_complexity_level: e.target.value as any })}
                  disabled={saving}
                >
                  <option value="low">Low - 8+ characters</option>
                  <option value="medium">Medium - 10+ chars, mixed case</option>
                  <option value="high">High - 12+ chars, mixed case, numbers, symbols</option>
                </Select>
              </FormField>

              <FormField
                label="Session Timeout (minutes)"
                helpText="Auto-logout after inactivity"
              >
                <Input
                  type="number"
                  min="5"
                  max="480"
                  value={systemSettings?.session_timeout_minutes || 60}
                  onChange={(e) => handleUpdateSettings({ session_timeout_minutes: parseInt(e.target.value) })}
                  disabled={saving}
                />
              </FormField>

              <FormField
                label="Max Failed Login Attempts"
                helpText="Lock account after failed attempts"
              >
                <Input
                  type="number"
                  min="3"
                  max="10"
                  value={systemSettings?.max_failed_login_attempts || 5}
                  onChange={(e) => handleUpdateSettings({ max_failed_login_attempts: parseInt(e.target.value) })}
                  disabled={saving}
                />
              </FormField>

              <FormField
                label="Account Lockout Duration (minutes)"
                helpText="How long accounts stay locked"
              >
                <Input
                  type="number"
                  min="5"
                  max="1440"
                  value={systemSettings?.account_lockout_duration || 30}
                  onChange={(e) => handleUpdateSettings({ account_lockout_duration: parseInt(e.target.value) })}
                  disabled={saving}
                />
              </FormField>
            </div>
          </SettingsCard>

          {/* Business Settings */}
          <SettingsCard
            title="Business Settings"
            description="Trial periods, billing, and subscription settings"
            icon="💼"
          >
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
              <FormField
                label="Default Trial Period (days)"
                helpText="Default trial length for new accounts"
              >
                <Input
                  type="number"
                  min="0"
                  max="365"
                  value={systemSettings?.trial_period_days || 14}
                  onChange={(e) => handleUpdateSettings({ trial_period_days: parseInt(e.target.value) })}
                  disabled={saving}
                />
              </FormField>

              <FormField
                label="Payment Retry Attempts"
                helpText="Retry failed payments automatically"
              >
                <Input
                  type="number"
                  min="1"
                  max="5"
                  value={systemSettings?.payment_retry_attempts || 3}
                  onChange={(e) => handleUpdateSettings({ payment_retry_attempts: parseInt(e.target.value) })}
                  disabled={saving}
                />
              </FormField>

              <FormField
                label="Webhook Timeout (seconds)"
                helpText="Timeout for payment webhook processing"
              >
                <Input
                  type="number"
                  min="5"
                  max="60"
                  value={systemSettings?.webhook_timeout_seconds || 30}
                  onChange={(e) => handleUpdateSettings({ webhook_timeout_seconds: parseInt(e.target.value) })}
                  disabled={saving}
                />
              </FormField>
            </div>
          </SettingsCard>

          {/* Save Button */}
          <div className="flex justify-end">
            <button
              onClick={() => handleUpdateSettings(systemSettings)}
              disabled={saving}
              className="btn-theme btn-theme-primary px-6 py-2"
            >
              {saving ? 'Saving...' : 'Save All Settings'}
            </button>
          </div>
        </div>
      )}

      {/* Platform Configuration Tab */}
      {activeTab === 'platform' && (
        <PlatformConfiguration />
      )}

      {/* Security Tab */}
      {activeTab === 'security' && (
        <div className="space-y-6">
          {/* Security Overview */}
          <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
            <StatsCard
              icon="🔐"
              title="Failed Logins"
              value={settings?.security_settings?.failed_login_attempts_today || 0}
              valueColor="error"
            />
            <StatsCard
              icon="🔒"
              title="Locked Accounts"
              value={settings?.security_settings?.locked_accounts || 0}
              valueColor="warning"
            />
            <StatsCard
              icon="⚠️"
              title="Security Events"
              value={settings?.security_settings?.recent_security_events || 0}
              valueColor="info"
            />
            <StatsCard
              icon="🛡️"
              title="Security Level"
              value="High"
              valueColor="success"
            />
          </div>

          {/* Security Alerts */}
          <div className="card-theme">
            <div className="px-6 py-4 border-b border-theme">
              <h3 className="text-lg font-semibold text-theme-primary flex items-center">
                <span className="mr-2">🚨</span>
                Security Alerts
              </h3>
              <p className="text-sm text-theme-secondary mt-1">Recent security events and alerts</p>
            </div>
            <div className="p-6">
              <div className="space-y-4">
                <div className="flex items-start gap-4 p-4 rounded-lg bg-theme-background-secondary">
                  <div className="text-2xl">🟢</div>
                  <div className="flex-1">
                    <h4 className="font-medium text-theme-primary">System Security: Normal</h4>
                    <p className="text-sm text-theme-secondary mt-1">No critical security events detected in the last 24 hours</p>
                    <p className="text-xs text-theme-tertiary mt-2">Last checked: {new Date().toLocaleString()}</p>
                  </div>
                </div>
                
                <div className="flex items-start gap-4 p-4 rounded-lg border border-theme-warning bg-theme-warning">
                  <div className="text-2xl">🟡</div>
                  <div className="flex-1">
                    <h4 className="font-medium text-theme-primary">Rate Limiting Active</h4>
                    <p className="text-sm text-theme-secondary mt-1">3 IP addresses currently rate-limited due to excessive requests</p>
                    <p className="text-xs text-theme-tertiary mt-2">Auto-resolved in 15 minutes</p>
                  </div>
                </div>
              </div>
            </div>
          </div>

          {/* IP Blocking */}
          <div className="card-theme">
            <div className="px-6 py-4 border-b border-theme">
              <h3 className="text-lg font-semibold text-theme-primary flex items-center">
                <span className="mr-2">🚫</span>
                IP Blocking & Monitoring
              </h3>
              <p className="text-sm text-theme-secondary mt-1">Monitor and block suspicious IP addresses</p>
            </div>
            <div className="p-6 space-y-4">
              <div className="flex items-center justify-between">
                <div>
                  <h4 className="font-medium text-theme-primary">Auto IP Blocking</h4>
                  <p className="text-sm text-theme-secondary">Automatically block IPs with suspicious activity</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input type="checkbox" className="sr-only peer" checked disabled={saving} />
                  <div className="toggle-theme peer-checked:bg-theme-success"></div>
                </label>
              </div>
              
              <div className="overflow-x-auto">
                <table className="min-w-full divide-y divide-theme">
                  <thead className="bg-theme-background-secondary">
                    <tr>
                      <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                        IP Address
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                        Reason
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                        Blocked At
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                        Actions
                      </th>
                    </tr>
                  </thead>
                  <tbody className="card-theme divide-y divide-theme">
                    <tr>
                      <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-theme-primary">
                        192.168.1.100
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-secondary">
                        Excessive login attempts
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-secondary">
                        2 hours ago
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap text-sm font-medium">
                        <button className="text-theme-link hover:text-theme-link-hover mr-3">Unblock</button>
                        <button className="text-theme-error hover:text-theme-error-hover">Permanent Block</button>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>
      )}


      {/* Payment Gateways section removed - available in main navigation */}

      {/* Notifications Tab */}
      {activeTab === 'notifications' && (
        <div className="space-y-6">
          <div className="card-theme">
            <div className="px-6 py-4 border-b border-theme">
              <h3 className="text-lg font-semibold text-theme-primary flex items-center">
                <span className="mr-2">🔔</span>
                Notification Settings
              </h3>
              <p className="text-sm text-theme-secondary mt-1">Configure email notifications and alerts</p>
            </div>
            <div className="p-6 space-y-6">
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <div className="flex items-center justify-between p-4 rounded-lg border border-theme bg-theme-background-secondary">
                  <div>
                    <h4 className="text-sm font-medium text-theme-primary">Payment Notifications</h4>
                    <p className="text-sm text-theme-secondary">Email alerts for payment events</p>
                  </div>
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input type="checkbox" className="sr-only peer" checked disabled={saving} />
                    <div className="toggle-theme peer-checked:bg-theme-success"></div>
                  </label>
                </div>

                <div className="flex items-center justify-between p-4 rounded-lg border border-theme bg-theme-background-secondary">
                  <div>
                    <h4 className="text-sm font-medium text-theme-primary">Security Alerts</h4>
                    <p className="text-sm text-theme-secondary">Notifications for security events</p>
                  </div>
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input type="checkbox" className="sr-only peer" checked disabled={saving} />
                    <div className="toggle-theme peer-checked:bg-theme-success"></div>
                  </label>
                </div>

                <div className="flex items-center justify-between p-4 rounded-lg border border-theme bg-theme-background-secondary">
                  <div>
                    <h4 className="text-sm font-medium text-theme-primary">System Maintenance</h4>
                    <p className="text-sm text-theme-secondary">Alerts for system maintenance</p>
                  </div>
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input type="checkbox" className="sr-only peer" checked disabled={saving} />
                    <div className="toggle-theme peer-checked:bg-theme-success"></div>
                  </label>
                </div>

                <div className="flex items-center justify-between p-4 rounded-lg border border-theme bg-theme-background-secondary">
                  <div>
                    <h4 className="text-sm font-medium text-theme-primary">User Activity</h4>
                    <p className="text-sm text-theme-secondary">Notifications for user registrations</p>
                  </div>
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input type="checkbox" className="sr-only peer" disabled={saving} />
                    <div className="toggle-theme peer-checked:bg-theme-success"></div>
                  </label>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Maintenance Tab */}
      {activeTab === 'maintenance' && (
        <div className="space-y-6">
          {maintenanceLoading ? (
            <div className="flex items-center justify-center py-12">
              <div className="text-theme-secondary">Loading maintenance data...</div>
            </div>
          ) : (
            <>
              {/* Maintenance Mode Control */}
              {maintenanceStatus && (
                <MaintenanceModeControl
                  status={maintenanceStatus}
                  onUpdate={loadMaintenanceData}
                />
              )}

              {/* System Health Monitor */}
              {systemHealth && systemMetrics && (
                <SystemHealthMonitor
                  health={systemHealth}
                  metrics={systemMetrics}
                  onRefresh={loadMaintenanceData}
                />
              )}

              {/* Database Backup Manager */}
              <DatabaseBackupManager
                backups={backups}
                onRefresh={loadMaintenanceData}
              />

              {/* Data Cleanup Manager */}
              {cleanupStats && (
                <DataCleanupManager
                  stats={cleanupStats}
                  onRefresh={loadMaintenanceData}
                />
              )}
            </>
          )}
        </div>
      )}

      {/* System Logs Tab */}
      {/* System Logs section removed - similar functionality available in Reports */}
    </div>
  );
};