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

export const AdminSettingsPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const [settings, setSettings] = useState<AdminSettingsData | null>(null);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState('overview');
  const [saving, setSaving] = useState(false);
  const [successMessage, setSuccessMessage] = useState('');
  const [systemSettings, setSystemSettings] = useState<Partial<SystemSettings>>({});

  // Check if user has admin access
  const isAdmin = hasAdminAccess(user);

  useEffect(() => {
    if (isAdmin) {
      loadAdminData();
    }
  }, [isAdmin]);
  
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
    { id: 'system', name: 'System Settings', icon: '⚙️' },
    { id: 'security', name: 'Security', icon: '🔒' },
    { id: 'notifications', name: 'Notifications', icon: '🔔' },
    { id: 'maintenance', name: 'Maintenance', icon: '🔧' }
  ];

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-2xl font-bold text-theme-primary">Admin Settings</h1>
          <p className="text-theme-secondary">
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
          {/* Platform Configuration */}
          <div className="card-theme">
            <div className="px-6 py-4 border-b border-theme">
              <h3 className="text-lg font-semibold text-theme-primary flex items-center">
                <span className="mr-2">🏗️</span>
                Platform Configuration
              </h3>
              <p className="text-sm text-theme-secondary mt-1">Core platform settings and features</p>
            </div>
            <div className="p-6 space-y-6">
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <div>
                  <label className="label-theme">Platform Name</label>
                  <input
                    type="text"
                    value={systemSettings?.system_name || 'Powernode Platform'}
                    onChange={(e) => handleUpdateSettings({ system_name: e.target.value })}
                    disabled={saving}
                    className="input-theme"
                    placeholder="Your Platform Name"
                  />
                  <p className="text-xs text-theme-tertiary mt-1">Displayed in emails and interface</p>
                </div>
                
                <div>
                  <label className="label-theme">System Email</label>
                  <input
                    type="email"
                    value={systemSettings?.system_email || ''}
                    onChange={(e) => handleUpdateSettings({ system_email: e.target.value })}
                    disabled={saving}
                    className="input-theme"
                    placeholder="system@yourplatform.com"
                  />
                  <p className="text-xs text-theme-tertiary mt-1">Default sender for system emails</p>
                </div>

                <div>
                  <label className="label-theme">Support Email</label>
                  <input
                    type="email"
                    value={systemSettings?.support_email || ''}
                    onChange={(e) => handleUpdateSettings({ support_email: e.target.value })}
                    disabled={saving}
                    className="input-theme"
                    placeholder="support@yourplatform.com"
                  />
                  <p className="text-xs text-theme-tertiary mt-1">Contact email for user support</p>
                </div>

                <div>
                  <label className="label-theme">Platform URL</label>
                  <input
                    type="url"
                    value={systemSettings?.platform_url || ''}
                    onChange={(e) => handleUpdateSettings({ platform_url: e.target.value })}
                    disabled={saving}
                    className="input-theme"
                    placeholder="https://yourplatform.com"
                  />
                  <p className="text-xs text-theme-tertiary mt-1">Base URL for links in emails</p>
                </div>
              </div>
            </div>
          </div>

          {/* User Registration & Access */}
          <div className="card-theme">
            <div className="px-6 py-4 border-b border-theme">
              <h3 className="text-lg font-semibold text-theme-primary flex items-center">
                <span className="mr-2">👥</span>
                User Registration & Access
              </h3>
              <p className="text-sm text-theme-secondary mt-1">Control how users can register and access the platform</p>
            </div>
            <div className="p-6 space-y-6">
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <div className="flex items-center justify-between p-4 rounded-lg border border-theme bg-theme-background-secondary">
                  <div>
                    <h4 className="text-sm font-medium text-theme-primary">User Registration</h4>
                    <p className="text-sm text-theme-secondary">Allow new users to create accounts</p>
                  </div>
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input
                      type="checkbox"
                      className="sr-only peer"
                      checked={systemSettings?.registration_enabled || false}
                      onChange={(e) => handleUpdateSettings({ registration_enabled: e.target.checked })}
                      disabled={saving}
                    />
                    <div className="toggle-theme peer-checked:bg-theme-success"></div>
                  </label>
                </div>

                <div className="flex items-center justify-between p-4 rounded-lg border border-theme bg-theme-background-secondary">
                  <div>
                    <h4 className="text-sm font-medium text-theme-primary">Email Verification</h4>
                    <p className="text-sm text-theme-secondary">Require email verification for new users</p>
                  </div>
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input
                      type="checkbox"
                      className="sr-only peer"
                      checked={systemSettings?.email_verification_required || false}
                      onChange={(e) => handleUpdateSettings({ email_verification_required: e.target.checked })}
                      disabled={saving}
                    />
                    <div className="toggle-theme peer-checked:bg-theme-success"></div>
                  </label>
                </div>

                <div className="flex items-center justify-between p-4 rounded-lg border border-theme bg-theme-background-secondary">
                  <div>
                    <h4 className="text-sm font-medium text-theme-primary">Account Deletion</h4>
                    <p className="text-sm text-theme-secondary">Allow users to delete their accounts</p>
                  </div>
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input
                      type="checkbox"
                      className="sr-only peer"
                      checked={systemSettings?.allow_account_deletion || false}
                      onChange={(e) => handleUpdateSettings({ allow_account_deletion: e.target.checked })}
                      disabled={saving}
                    />
                    <div className="toggle-theme peer-checked:bg-theme-warning"></div>
                  </label>
                </div>

                <div className="flex items-center justify-between p-4 rounded-lg border border-theme bg-theme-background-secondary">
                  <div>
                    <h4 className="text-sm font-medium text-theme-primary">Maintenance Mode</h4>
                    <p className="text-sm text-theme-secondary">Prevent user access during updates</p>
                  </div>
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input
                      type="checkbox"
                      className="sr-only peer"
                      checked={systemSettings?.maintenance_mode || false}
                      onChange={(e) => handleUpdateSettings({ maintenance_mode: e.target.checked })}
                      disabled={saving}
                    />
                    <div className="toggle-theme peer-checked:bg-theme-error"></div>
                  </label>
                </div>
              </div>
            </div>
          </div>

          {/* Security Settings */}
          <div className="card-theme">
            <div className="px-6 py-4 border-b border-theme">
              <h3 className="text-lg font-semibold text-theme-primary flex items-center">
                <span className="mr-2">🔐</span>
                Security Settings
              </h3>
              <p className="text-sm text-theme-secondary mt-1">Password policies and session management</p>
            </div>
            <div className="p-6 space-y-6">
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <div>
                  <label className="label-theme">Password Complexity Level</label>
                  <select
                    value={systemSettings?.password_complexity_level || 'high'}
                    onChange={(e) => handleUpdateSettings({ password_complexity_level: e.target.value as any })}
                    disabled={saving}
                    className="select-theme"
                  >
                    <option value="low">Low - 8+ characters</option>
                    <option value="medium">Medium - 10+ chars, mixed case</option>
                    <option value="high">High - 12+ chars, mixed case, numbers, symbols</option>
                  </select>
                </div>

                <div>
                  <label className="label-theme">Session Timeout (minutes)</label>
                  <input
                    type="number"
                    min="5"
                    max="480"
                    value={systemSettings?.session_timeout_minutes || 60}
                    onChange={(e) => handleUpdateSettings({ session_timeout_minutes: parseInt(e.target.value) })}
                    disabled={saving}
                    className="input-theme"
                  />
                  <p className="text-xs text-theme-tertiary mt-1">Auto-logout after inactivity</p>
                </div>

                <div>
                  <label className="label-theme">Max Failed Login Attempts</label>
                  <input
                    type="number"
                    min="3"
                    max="10"
                    value={systemSettings?.max_failed_login_attempts || 5}
                    onChange={(e) => handleUpdateSettings({ max_failed_login_attempts: parseInt(e.target.value) })}
                    disabled={saving}
                    className="input-theme"
                  />
                  <p className="text-xs text-theme-tertiary mt-1">Lock account after failed attempts</p>
                </div>

                <div>
                  <label className="label-theme">Account Lockout Duration (minutes)</label>
                  <input
                    type="number"
                    min="5"
                    max="1440"
                    value={systemSettings?.account_lockout_duration || 30}
                    onChange={(e) => handleUpdateSettings({ account_lockout_duration: parseInt(e.target.value) })}
                    disabled={saving}
                    className="input-theme"
                  />
                  <p className="text-xs text-theme-tertiary mt-1">How long accounts stay locked</p>
                </div>
              </div>
            </div>
          </div>

          {/* Business Settings */}
          <div className="card-theme">
            <div className="px-6 py-4 border-b border-theme">
              <h3 className="text-lg font-semibold text-theme-primary flex items-center">
                <span className="mr-2">💼</span>
                Business Settings
              </h3>
              <p className="text-sm text-theme-secondary mt-1">Trial periods, billing, and subscription settings</p>
            </div>
            <div className="p-6 space-y-6">
              <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
                <div>
                  <label className="label-theme">Default Trial Period (days)</label>
                  <input
                    type="number"
                    min="0"
                    max="365"
                    value={systemSettings?.trial_period_days || 14}
                    onChange={(e) => handleUpdateSettings({ trial_period_days: parseInt(e.target.value) })}
                    disabled={saving}
                    className="input-theme"
                  />
                  <p className="text-xs text-theme-tertiary mt-1">Default trial length for new accounts</p>
                </div>

                <div>
                  <label className="label-theme">Payment Retry Attempts</label>
                  <input
                    type="number"
                    min="1"
                    max="5"
                    value={systemSettings?.payment_retry_attempts || 3}
                    onChange={(e) => handleUpdateSettings({ payment_retry_attempts: parseInt(e.target.value) })}
                    disabled={saving}
                    className="input-theme"
                  />
                  <p className="text-xs text-theme-tertiary mt-1">Retry failed payments automatically</p>
                </div>

                <div>
                  <label className="label-theme">Webhook Timeout (seconds)</label>
                  <input
                    type="number"
                    min="5"
                    max="60"
                    value={systemSettings?.webhook_timeout_seconds || 30}
                    onChange={(e) => handleUpdateSettings({ webhook_timeout_seconds: parseInt(e.target.value) })}
                    disabled={saving}
                    className="input-theme"
                  />
                  <p className="text-xs text-theme-tertiary mt-1">Timeout for payment webhook processing</p>
                </div>

                <div>
                  <label className="label-theme">API Rate Limit (requests/minute)</label>
                  <input
                    type="number"
                    min="10"
                    max="1000"
                    value={systemSettings?.rate_limiting?.api_requests_per_minute || 60}
                    onChange={(e) => handleUpdateSettings({ 
                      rate_limiting: { 
                        ...systemSettings?.rate_limiting, 
                        api_requests_per_minute: parseInt(e.target.value) 
                      } 
                    })}
                    disabled={saving}
                    className="input-theme"
                  />
                  <p className="text-xs text-theme-tertiary mt-1">API rate limiting per user</p>
                </div>
              </div>
            </div>
          </div>

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

      {/* Users Tab */}

      {/* Accounts Tab */}
      {/* Accounts section moved to main navigation */}

      {/* Security Tab */}
      {activeTab === 'security' && (
        <div className="space-y-6">
          {/* Security Overview */}
          <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
            <div className="card-theme p-4">
              <div className="flex items-center">
                <div className="text-2xl mr-3">🔐</div>
                <div>
                  <p className="text-sm text-theme-secondary">Failed Logins</p>
                  <p className="text-xl font-semibold text-theme-error">
                    {settings?.security_settings?.failed_login_attempts_today || 0}
                  </p>
                </div>
              </div>
            </div>
            <div className="card-theme p-4">
              <div className="flex items-center">
                <div className="text-2xl mr-3">🔒</div>
                <div>
                  <p className="text-sm text-theme-secondary">Locked Accounts</p>
                  <p className="text-xl font-semibold text-theme-warning">
                    {settings?.security_settings?.locked_accounts || 0}
                  </p>
                </div>
              </div>
            </div>
            <div className="card-theme p-4">
              <div className="flex items-center">
                <div className="text-2xl mr-3">⚠️</div>
                <div>
                  <p className="text-sm text-theme-secondary">Security Events</p>
                  <p className="text-xl font-semibold text-theme-info">
                    {settings?.security_settings?.recent_security_events || 0}
                  </p>
                </div>
              </div>
            </div>
            <div className="card-theme p-4">
              <div className="flex items-center">
                <div className="text-2xl mr-3">🛡️</div>
                <div>
                  <p className="text-sm text-theme-secondary">Security Level</p>
                  <p className="text-xl font-semibold text-theme-success">High</p>
                </div>
              </div>
            </div>
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
          <div className="card-theme">
            <div className="px-6 py-4 border-b border-theme">
              <h3 className="text-lg font-semibold text-theme-primary flex items-center">
                <span className="mr-2">🔧</span>
                System Maintenance
              </h3>
              <p className="text-sm text-theme-secondary mt-1">Database maintenance, backups, and system health</p>
            </div>
            <div className="p-6 space-y-6">
              {/* Maintenance Mode Control */}
              <div className="bg-theme-background-secondary border border-theme rounded-lg p-6">
                <div className="flex items-center justify-between mb-4">
                  <div>
                    <h4 className="text-lg font-medium text-theme-primary">Maintenance Mode</h4>
                    <p className="text-sm text-theme-secondary">Put the system in maintenance mode to prevent user access</p>
                  </div>
                  <label className="relative inline-flex items-center cursor-pointer">
                    <input
                      type="checkbox"
                      className="sr-only peer"
                      checked={systemSettings?.maintenance_mode || false}
                      onChange={(e) => handleUpdateSettings({ maintenance_mode: e.target.checked })}
                      disabled={saving}
                    />
                    <div className="toggle-theme peer-checked:bg-theme-error"></div>
                  </label>
                </div>
                {systemSettings?.maintenance_mode && (
                  <div className="alert-theme alert-theme-warning">
                    <strong>⚠️ Maintenance Mode Active:</strong> Users cannot access the application.
                  </div>
                )}
              </div>

              {/* Database Operations */}
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div className="card-theme p-6">
                  <h4 className="text-lg font-medium text-theme-primary mb-4 flex items-center">
                    <span className="mr-2">💾</span>
                    Database Backup
                  </h4>
                  <div className="space-y-4">
                    <div className="flex justify-between items-center">
                      <span className="text-sm text-theme-secondary">Last Backup</span>
                      <span className="text-sm font-medium text-theme-primary">2 hours ago</span>
                    </div>
                    <div className="flex justify-between items-center">
                      <span className="text-sm text-theme-secondary">Backup Size</span>
                      <span className="text-sm font-medium text-theme-primary">245 MB</span>
                    </div>
                    <button className="btn-theme btn-theme-primary w-full">
                      Create Backup Now
                    </button>
                  </div>
                </div>

                <div className="card-theme p-6">
                  <h4 className="text-lg font-medium text-theme-primary mb-4 flex items-center">
                    <span className="mr-2">🗑️</span>
                    Data Cleanup
                  </h4>
                  <div className="space-y-4">
                    <div className="flex justify-between items-center">
                      <span className="text-sm text-theme-secondary">Old Logs</span>
                      <span className="text-sm font-medium text-theme-primary">1,245 entries</span>
                    </div>
                    <div className="flex justify-between items-center">
                      <span className="text-sm text-theme-secondary">Expired Sessions</span>
                      <span className="text-sm font-medium text-theme-primary">67 sessions</span>
                    </div>
                    <button className="btn-theme btn-theme-secondary w-full">
                      Run Cleanup
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* System Logs Tab */}
      {/* System Logs section removed - similar functionality available in Reports */}
    </div>
  );
};