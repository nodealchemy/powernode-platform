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
        <div className="text-red-600 text-lg font-medium">
          🚫 Access Denied
        </div>
        <p className="text-gray-600 mt-2">
          You need administrator privileges to access this page.
        </p>
      </div>
    );
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-600">Loading admin settings...</div>
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
          <h1 className="text-2xl font-bold text-gray-900">Admin Settings</h1>
          <p className="text-gray-600">
            System administration and platform management.
          </p>
        </div>
        <div className="bg-red-100 text-red-800 px-3 py-1 rounded-full text-sm font-medium">
          🔧 Admin Mode
        </div>
      </div>

      {successMessage && (
        <div className="bg-green-100 border border-green-400 text-green-700 px-4 py-3 rounded">
          {successMessage}
        </div>
      )}

      {/* Tab Navigation */}
      <div className="border-b border-gray-200">
        <nav className="-mb-px flex space-x-8">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`py-2 px-1 border-b-2 font-medium text-sm ${
                activeTab === tab.id
                  ? 'border-red-500 text-red-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
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
          <div className="bg-white shadow rounded-lg p-6">
            <div className="flex items-center">
              <div className="text-2xl">👥</div>
              <div className="ml-4">
                <p className="text-sm font-medium text-gray-600">Total Users</p>
                <p className="text-2xl font-semibold text-gray-900">{settings.platform_stats.total_users}</p>
              </div>
            </div>
          </div>

          <div className="bg-white shadow rounded-lg p-6">
            <div className="flex items-center">
              <div className="text-2xl">🏢</div>
              <div className="ml-4">
                <p className="text-sm font-medium text-gray-600">Active Accounts</p>
                <p className="text-2xl font-semibold text-gray-900">{settings.platform_stats.active_accounts}</p>
              </div>
            </div>
          </div>

          <div className="bg-white shadow rounded-lg p-6">
            <div className="flex items-center">
              <div className="text-2xl">💳</div>
              <div className="ml-4">
                <p className="text-sm font-medium text-gray-600">Subscriptions</p>
                <p className="text-2xl font-semibold text-gray-900">{settings.platform_stats.active_subscriptions}</p>
              </div>
            </div>
          </div>

          <div className="bg-white shadow rounded-lg p-6">
            <div className="flex items-center">
              <div className="text-2xl">💰</div>
              <div className="ml-4">
                <p className="text-sm font-medium text-gray-600">Revenue</p>
                <p className="text-2xl font-semibold text-gray-900">${settings.platform_stats.total_revenue.toLocaleString()}</p>
              </div>
            </div>
          </div>

          {/* System Status */}
          <div className="md:col-span-2 bg-white shadow rounded-lg">
            <div className="px-6 py-4 border-b border-gray-200">
              <h3 className="text-lg font-medium text-gray-900">System Status</h3>
            </div>
            <div className="p-6 space-y-4">
              <div className="flex justify-between">
                <span className="text-sm text-gray-600">Platform Version</span>
                <span className="text-sm font-medium">{settings.system_settings.platform_version}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-gray-600">Registration</span>
                <span className={`text-sm font-medium ${settings.system_settings.registration_enabled ? 'text-green-600' : 'text-red-600'}`}>
                  {settings.system_settings.registration_enabled ? 'Enabled' : 'Disabled'}
                </span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-gray-600">Maintenance Mode</span>
                <span className={`text-sm font-medium ${settings.system_settings.maintenance_mode ? 'text-red-600' : 'text-green-600'}`}>
                  {settings.system_settings.maintenance_mode ? 'Active' : 'Inactive'}
                </span>
              </div>
            </div>
          </div>

          {/* Security Overview */}
          <div className="md:col-span-2 bg-white shadow rounded-lg">
            <div className="px-6 py-4 border-b border-gray-200">
              <h3 className="text-lg font-medium text-gray-900">Security Overview</h3>
            </div>
            <div className="p-6 space-y-4">
              <div className="flex justify-between">
                <span className="text-sm text-gray-600">Failed Logins Today</span>
                <span className="text-sm font-medium">{settings.security_settings.failed_login_attempts_today}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-gray-600">Locked Accounts</span>
                <span className="text-sm font-medium text-red-600">{settings.security_settings.locked_accounts}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-sm text-gray-600">Recent Security Events</span>
                <span className="text-sm font-medium">{settings.security_settings.recent_security_events}</span>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* System Settings Tab */}
      {activeTab === 'system' && (
        <div className="bg-white shadow rounded-lg">
          <div className="px-6 py-4 border-b border-gray-200">
            <h3 className="text-lg font-medium text-gray-900">System Configuration</h3>
          </div>
          <div className="p-6 space-y-6">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div className="flex items-center justify-between">
                <div>
                  <h4 className="text-sm font-medium text-gray-900">Maintenance Mode</h4>
                  <p className="text-sm text-gray-600">Enable to prevent user access during updates</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input
                    type="checkbox"
                    className="sr-only peer"
                    checked={systemSettings.maintenance_mode || false}
                    onChange={(e) => handleUpdateSettings({ maintenance_mode: e.target.checked })}
                    disabled={saving}
                  />
                  <div className="w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-red-300 rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-red-600"></div>
                </label>
              </div>

              <div className="flex items-center justify-between">
                <div>
                  <h4 className="text-sm font-medium text-gray-900">User Registration</h4>
                  <p className="text-sm text-gray-600">Allow new users to register</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input
                    type="checkbox"
                    className="sr-only peer"
                    checked={systemSettings.registration_enabled || false}
                    onChange={(e) => handleUpdateSettings({ registration_enabled: e.target.checked })}
                    disabled={saving}
                  />
                  <div className="w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-blue-300 rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-blue-600"></div>
                </label>
              </div>

              <div className="flex items-center justify-between">
                <div>
                  <h4 className="text-sm font-medium text-gray-900">Email Verification</h4>
                  <p className="text-sm text-gray-600">Require email verification for new users</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input
                    type="checkbox"
                    className="sr-only peer"
                    checked={systemSettings.email_verification_required || false}
                    onChange={(e) => handleUpdateSettings({ email_verification_required: e.target.checked })}
                    disabled={saving}
                  />
                  <div className="w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-blue-300 rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-blue-600"></div>
                </label>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Password Complexity Level
                </label>
                <select
                  value={systemSettings.password_complexity_level || 'high'}
                  onChange={(e) => handleUpdateSettings({ password_complexity_level: e.target.value as any })}
                  disabled={saving}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                >
                  <option value="low">Low</option>
                  <option value="medium">Medium</option>
                  <option value="high">High</option>
                </select>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Session Timeout (minutes)
                </label>
                <input
                  type="number"
                  min="5"
                  max="480"
                  value={systemSettings.session_timeout_minutes || 60}
                  onChange={(e) => handleUpdateSettings({ session_timeout_minutes: parseInt(e.target.value) })}
                  disabled={saving}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Max Failed Login Attempts
                </label>
                <input
                  type="number"
                  min="3"
                  max="10"
                  value={systemSettings.max_failed_login_attempts || 5}
                  onChange={(e) => handleUpdateSettings({ max_failed_login_attempts: parseInt(e.target.value) })}
                  disabled={saving}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                />
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Users Tab */}
      {activeTab === 'users' && (
        <div className="bg-white shadow rounded-lg">
          <div className="px-6 py-4 border-b border-gray-200">
            <h3 className="text-lg font-medium text-gray-900">User Management</h3>
            <p className="text-sm text-gray-600 mt-1">{users.length} total users</p>
          </div>
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-200">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    User
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Account
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Role
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Status
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Last Login
                  </th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {users.slice(0, 10).map((user) => (
                  <tr key={user.id}>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div>
                        <div className="text-sm font-medium text-gray-900">{user.full_name}</div>
                        <div className="text-sm text-gray-500">{user.email}</div>
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="text-sm text-gray-900">{user.account.name}</div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className="inline-flex px-2 py-1 text-xs font-semibold rounded-full bg-blue-100 text-blue-800">
                        {user.roles.join(', ')}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${
                        user.status === 'active' ? 'bg-green-100 text-green-800' :
                        user.status === 'suspended' ? 'bg-red-100 text-red-800' :
                        'bg-gray-100 text-gray-800'
                      }`}>
                        {user.status}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
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
        <div className="bg-white shadow rounded-lg">
          <div className="px-6 py-4 border-b border-gray-200">
            <h3 className="text-lg font-medium text-gray-900">Account Management</h3>
            <p className="text-sm text-gray-600 mt-1">{accounts.length} total accounts</p>
          </div>
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-200">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Account
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Users
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Plan
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Status
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {accounts.slice(0, 10).map((account) => (
                  <tr key={account.id}>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div>
                        <div className="text-sm font-medium text-gray-900">{account.name}</div>
                        <div className="text-sm text-gray-500">{account.subdomain || 'No subdomain'}</div>
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      {account.users_count}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      {account.subscription?.plan_name || 'No subscription'}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${
                        account.status === 'active' ? 'bg-green-100 text-green-800' :
                        account.status === 'suspended' ? 'bg-red-100 text-red-800' :
                        'bg-gray-100 text-gray-800'
                      }`}>
                        {account.status}
                      </span>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm font-medium space-x-2">
                      {account.status === 'active' ? (
                        <button
                          onClick={() => handleSuspendAccount(account.id, 'Admin action')}
                          className="text-red-600 hover:text-red-900"
                        >
                          Suspend
                        </button>
                      ) : (
                        <button
                          onClick={() => handleActivateAccount(account.id, 'Admin action')}
                          className="text-green-600 hover:text-green-900"
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
        <div className="bg-white shadow rounded-lg">
          <div className="px-6 py-4 border-b border-gray-200">
            <h3 className="text-lg font-medium text-gray-900">Recent System Logs</h3>
            <p className="text-sm text-gray-600 mt-1">Last 100 system events</p>
          </div>
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-200">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Timestamp
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Action
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    User
                  </th>
                  <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    IP Address
                  </th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {logs.slice(0, 20).map((log) => (
                  <tr key={log.id}>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                      {new Date(log.created_at).toLocaleString()}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <span className="text-sm font-medium text-gray-900">{log.action}</span>
                      <div className="text-sm text-gray-500">{log.resource_type}</div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                      {log.user ? `${log.user.full_name} (${log.user.email})` : 'System'}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
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