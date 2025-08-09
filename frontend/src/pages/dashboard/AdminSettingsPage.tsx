import React, { useState, useEffect } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store';
import { 
  adminApi, 
  AdminSettingsData, 
  AdminUser, 
  AdminAccount, 
  AdminLog,
  SystemSettings
} from '../../services/adminApi';

export const AdminSettingsPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const [settings, setSettings] = useState<AdminSettingsData | null>(null);
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [accounts, setAccounts] = useState<AdminAccount[]>([]);
  const [logs, setLogs] = useState<AdminLog[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState('overview');
  const [saving, setSaving] = useState(false);
  const [successMessage, setSuccessMessage] = useState('');
  const [systemSettings, setSystemSettings] = useState<Partial<SystemSettings>>({});

  // Check if user has admin access
  const hasAdminAccess = user?.role === 'owner' || user?.role === 'admin';

  useEffect(() => {
    if (hasAdminAccess) {
      loadAdminData();
    }
  }, [hasAdminAccess]);

  const loadAdminData = async () => {
    try {
      setLoading(true);
      const [settingsData, usersData, accountsData, logsData] = await Promise.all([
        adminApi.getAdminSettings(),
        adminApi.getUsers(),
        adminApi.getAccounts(),
        adminApi.getSystemLogs()
      ]);

      setSettings(settingsData);
      setUsers(usersData.users);
      setAccounts(accountsData.accounts);
      setLogs(logsData.logs);
      setSystemSettings(settingsData.system_settings);
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

  const handleSuspendAccount = async (accountId: string, reason: string) => {
    try {
      await adminApi.suspendAccount(accountId, reason);
      await loadAdminData(); // Reload data
      showSuccess('Account suspended successfully');
    } catch (error) {
      console.error('Failed to suspend account:', error);
    }
  };

  const handleActivateAccount = async (accountId: string, reason: string) => {
    try {
      await adminApi.activateAccount(accountId, reason);
      await loadAdminData(); // Reload data
      showSuccess('Account activated successfully');
    } catch (error) {
      console.error('Failed to activate account:', error);
    }
  };

  if (!hasAdminAccess) {
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
    { id: 'users', name: 'User Management', icon: '👥' },
    { id: 'accounts', name: 'Account Management', icon: '🏢' },
    { id: 'security', name: 'Security', icon: '🔒' },
    { id: 'logs', name: 'System Logs', icon: '📋' }
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
      {activeTab === 'overview' && settings && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
          {/* Platform Statistics */}
          <div className="card-theme p-6">
            <div className="flex items-center">
              <div className="text-2xl">👥</div>
              <div className="ml-4">
                <p className="text-sm font-medium text-theme-secondary">Total Users</p>
                <p className="text-2xl font-semibold text-theme-primary">{settings.platform_stats.total_users}</p>
              </div>
            </div>
          </div>

          <div className="card-theme p-6">
            <div className="flex items-center">
              <div className="text-2xl">🏢</div>
              <div className="ml-4">
                <p className="text-sm font-medium text-theme-secondary">Active Accounts</p>
                <p className="text-2xl font-semibold text-theme-primary">{settings.platform_stats.active_accounts}</p>
              </div>
            </div>
          </div>

          <div className="card-theme p-6">
            <div className="flex items-center">
              <div className="text-2xl">💳</div>
              <div className="ml-4">
                <p className="text-sm font-medium text-theme-secondary">Subscriptions</p>
                <p className="text-2xl font-semibold text-theme-primary">{settings.platform_stats.active_subscriptions}</p>
              </div>
            </div>
          </div>

          <div className="card-theme p-6">
            <div className="flex items-center">
              <div className="text-2xl">💰</div>
              <div className="ml-4">
                <p className="text-sm font-medium text-theme-secondary">Revenue</p>
                <p className="text-2xl font-semibold text-theme-primary">${settings.platform_stats.total_revenue.toLocaleString()}</p>
              </div>
            </div>
          </div>

          {/* System Status */}
          <div className="md:col-span-2 card-theme">
            <div className="px-6 py-4 border-b border-theme">
              <h3 className="text-lg font-medium text-theme-primary">System Status</h3>
            </div>
            <div className="p-6 space-y-4">
              <div className="flex justify-between">
                <span className="text-sm text-theme-secondary">Platform Version</span>
                <span className="text-sm font-medium text-theme-primary">{settings.system_settings.platform_version}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-theme-secondary">Registration</span>
                <span className={`text-sm font-medium ${settings.system_settings.registration_enabled ? 'text-theme-success' : 'text-theme-error'}`}>
                  {settings.system_settings.registration_enabled ? 'Enabled' : 'Disabled'}
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-theme-secondary">Maintenance Mode</span>
                <span className={`text-sm font-medium ${settings.system_settings.maintenance_mode ? 'text-theme-error' : 'text-theme-success'}`}>
                  {settings.system_settings.maintenance_mode ? 'Active' : 'Inactive'}
                </span>
              </div>
            </div>
          </div>

          {/* Security Overview */}
          <div className="md:col-span-2 card-theme">
            <div className="px-6 py-4 border-b border-theme">
              <h3 className="text-lg font-medium text-theme-primary">Security Overview</h3>
            </div>
            <div className="p-6 space-y-4">
              <div className="flex justify-between">
                <span className="text-sm text-theme-secondary">Failed Logins Today</span>
                <span className="text-sm font-medium text-theme-primary">{settings.security_settings.failed_login_attempts_today}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-theme-secondary">Locked Accounts</span>
                <span className="text-sm font-medium text-theme-error">{settings.security_settings.locked_accounts}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-theme-secondary">Recent Security Events</span>
                <span className="text-sm font-medium text-theme-primary">{settings.security_settings.recent_security_events}</span>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* System Settings Tab */}
      {activeTab === 'system' && (
        <div className="card-theme">
          <div className="px-6 py-4 border-b border-theme">
            <h3 className="text-lg font-medium text-theme-primary">System Configuration</h3>
          </div>
          <div className="p-6 space-y-6">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div className="flex items-center justify-between">
                <div>
                  <h4 className="text-sm font-medium text-theme-primary">Maintenance Mode</h4>
                  <p className="text-sm text-theme-secondary">Enable to prevent user access during updates</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input
                    type="checkbox"
                    className="sr-only peer"
                    checked={systemSettings.maintenance_mode || false}
                    onChange={(e) => handleUpdateSettings({ maintenance_mode: e.target.checked })}
                    disabled={saving}
                  />
                  <div className="toggle-theme peer-checked:bg-red-600"></div>
                </label>
              </div>

              <div className="flex items-center justify-between">
                <div>
                  <h4 className="text-sm font-medium text-theme-primary">User Registration</h4>
                  <p className="text-sm text-theme-secondary">Allow new users to register</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input
                    type="checkbox"
                    className="sr-only peer"
                    checked={systemSettings.registration_enabled || false}
                    onChange={(e) => handleUpdateSettings({ registration_enabled: e.target.checked })}
                    disabled={saving}
                  />
                  <div className="toggle-theme peer-checked:bg-blue-600"></div>
                </label>
              </div>

              <div className="flex items-center justify-between">
                <div>
                  <h4 className="text-sm font-medium text-theme-primary">Email Verification</h4>
                  <p className="text-sm text-theme-secondary">Require email verification for new users</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input
                    type="checkbox"
                    className="sr-only peer"
                    checked={systemSettings.email_verification_required || false}
                    onChange={(e) => handleUpdateSettings({ email_verification_required: e.target.checked })}
                    disabled={saving}
                  />
                  <div className="toggle-theme peer-checked:bg-blue-600"></div>
                </label>
              </div>

              <div>
                <label className="label-theme">
                  Password Complexity Level
                </label>
                <select
                  value={systemSettings.password_complexity_level || 'high'}
                  onChange={(e) => handleUpdateSettings({ password_complexity_level: e.target.value as any })}
                  disabled={saving}
                  className="select-theme"
                >
                  <option value="low">Low</option>
                  <option value="medium">Medium</option>
                  <option value="high">High</option>
                </select>
              </div>

              <div>
                <label className="label-theme">
                  Session Timeout (minutes)
                </label>
                <input
                  type="number"
                  min="5"
                  max="480"
                  value={systemSettings.session_timeout_minutes || 60}
                  onChange={(e) => handleUpdateSettings({ session_timeout_minutes: parseInt(e.target.value) })}
                  disabled={saving}
                  className="input-theme"
                />
              </div>

              <div>
                <label className="label-theme">
                  Max Failed Login Attempts
                </label>
                <input
                  type="number"
                  min="3"
                  max="10"
                  value={systemSettings.max_failed_login_attempts || 5}
                  onChange={(e) => handleUpdateSettings({ max_failed_login_attempts: parseInt(e.target.value) })}
                  disabled={saving}
                  className="input-theme"
                />
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Users Tab */}
      {activeTab === 'users' && (
        <div className="card-theme">
          <div className="px-6 py-4 border-b border-theme">
            <h3 className="text-lg font-medium text-theme-primary">User Management</h3>
            <p className="text-sm text-theme-secondary mt-1">{users.length} total users</p>
          </div>
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-theme">
              <thead className="bg-theme-background-secondary">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    User
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Account
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Role
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Status
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Last Login
                  </th>
                </tr>
              </thead>
              <tbody className="card-theme divide-y divide-theme">
                {users.slice(0, 10).map((user) => (
                  <tr key={user.id}>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div>
                        <div className="text-sm font-medium text-theme-primary">{user.full_name}</div>
                        <div className="text-sm text-theme-secondary">{user.email}</div>
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="text-sm text-theme-primary">{user.account.name}</div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className="inline-flex px-2 py-1 text-xs font-semibold rounded-full bg-theme-info text-theme-info">
                        {user.roles.join(', ')}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${
                        user.status === 'active' ? 'bg-theme-success text-theme-success' :
                        user.status === 'suspended' ? 'bg-theme-error text-theme-error' :
                        'bg-theme-background-tertiary text-theme-secondary'
                      }`}>
                        {user.status}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-secondary">
                      {user.last_login_at ? new Date(user.last_login_at).toLocaleDateString() : 'Never'}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Accounts Tab */}
      {activeTab === 'accounts' && (
        <div className="card-theme">
          <div className="px-6 py-4 border-b border-theme">
            <h3 className="text-lg font-medium text-theme-primary">Account Management</h3>
            <p className="text-sm text-theme-secondary mt-1">{accounts.length} total accounts</p>
          </div>
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-theme">
              <thead className="bg-theme-background-secondary">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Account
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Users
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Plan
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Status
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody className="card-theme divide-y divide-theme">
                {accounts.slice(0, 10).map((account) => (
                  <tr key={account.id}>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div>
                        <div className="text-sm font-medium text-theme-primary">{account.name}</div>
                        <div className="text-sm text-theme-secondary">{account.subdomain || 'No subdomain'}</div>
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-primary">
                      {account.users_count}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-primary">
                      {account.subscription?.plan_name || 'No subscription'}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${
                        account.status === 'active' ? 'bg-theme-success text-theme-success' :
                        account.status === 'suspended' ? 'bg-theme-error text-theme-error' :
                        'bg-theme-background-tertiary text-theme-secondary'
                      }`}>
                        {account.status}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium space-x-2">
                      {account.status === 'active' ? (
                        <button
                          onClick={() => handleSuspendAccount(account.id, 'Admin action')}
                          className="text-theme-error hover:text-theme-error-hover"
                        >
                          Suspend
                        </button>
                      ) : (
                        <button
                          onClick={() => handleActivateAccount(account.id, 'Admin action')}
                          className="text-theme-success hover:text-theme-success-hover"
                        >
                          Activate
                        </button>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* System Logs Tab */}
      {activeTab === 'logs' && (
        <div className="card-theme">
          <div className="px-6 py-4 border-b border-theme">
            <h3 className="text-lg font-medium text-theme-primary">Recent System Logs</h3>
            <p className="text-sm text-theme-secondary mt-1">Last 100 system events</p>
          </div>
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-theme">
              <thead className="bg-theme-background-secondary">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Timestamp
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    Action
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    User
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-theme-secondary uppercase tracking-wider">
                    IP Address
                  </th>
                </tr>
              </thead>
              <tbody className="card-theme divide-y divide-theme">
                {logs.slice(0, 20).map((log) => (
                  <tr key={log.id}>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-secondary">
                      {new Date(log.created_at).toLocaleString()}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className="text-sm font-medium text-theme-primary">{log.action}</span>
                      <div className="text-sm text-theme-secondary">{log.resource_type}</div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-primary">
                      {log.user ? `${log.user.full_name} (${log.user.email})` : 'System'}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-theme-secondary">
                      {log.ip_address}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
};