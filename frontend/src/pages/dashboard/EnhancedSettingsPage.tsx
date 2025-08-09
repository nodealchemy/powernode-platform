import React, { useState, useEffect } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store';
import { settingsApi, SettingsData, UserPreferences, NotificationPreferences } from '../../services/settingsApi';

export const EnhancedSettingsPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const [settings, setSettings] = useState<SettingsData | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [activeTab, setActiveTab] = useState('profile');
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [successMessage, setSuccessMessage] = useState('');

  // Form states
  const [profileForm, setProfileForm] = useState({
    firstName: '',
    lastName: '',
    email: ''
  });

  const [passwordForm, setPasswordForm] = useState({
    current_password: '',
    password: '',
    password_confirmation: ''
  });

  const [accountForm, setAccountForm] = useState({
    name: '',
    billing_email: '',
    company_size: '',
    industry: '',
    website: '',
    phone: ''
  });

  const [preferences, setPreferences] = useState<Partial<UserPreferences>>({});
  const [notifications, setNotifications] = useState<Partial<NotificationPreferences>>({});

  useEffect(() => {
    loadSettings();
  }, []);

  const loadSettings = async () => {
    try {
      setLoading(true);
      const settingsData = await settingsApi.getSettings();
      setSettings(settingsData);
      
      // Initialize form states
      setProfileForm({
        firstName: user?.firstName || '',
        lastName: user?.lastName || '',
        email: user?.email || ''
      });

      setAccountForm({
        name: settingsData.account_settings.name || '',
        billing_email: settingsData.account_settings.billing_email || '',
        company_size: settingsData.account_settings.company_size || '',
        industry: settingsData.account_settings.industry || '',
        website: settingsData.account_settings.website || '',
        phone: settingsData.account_settings.phone || ''
      });

      setPreferences(settingsData.user_preferences);
      setNotifications(settingsData.notification_preferences);
    } catch (error) {
      console.error('Failed to load settings:', error);
    } finally {
      setLoading(false);
    }
  };

  const showSuccess = (message: string) => {
    setSuccessMessage(message);
    setTimeout(() => setSuccessMessage(''), 3000);
  };

  const showError = (field: string, message: string) => {
    setErrors({ ...errors, [field]: message });
    setTimeout(() => setErrors({}), 5000);
  };

  const handleUpdatePreferences = async (updatedPrefs: Partial<UserPreferences>) => {
    try {
      setSaving(true);
      await settingsApi.updatePreferences(updatedPrefs);
      setPreferences({ ...preferences, ...updatedPrefs });
      showSuccess('Preferences updated successfully');
    } catch (error) {
      showError('preferences', 'Failed to update preferences');
    } finally {
      setSaving(false);
    }
  };

  const handleUpdateNotifications = async (updatedNotifs: Partial<NotificationPreferences>) => {
    try {
      setSaving(true);
      await settingsApi.updateNotifications(updatedNotifs);
      setNotifications({ ...notifications, ...updatedNotifs });
      showSuccess('Notification preferences updated');
    } catch (error) {
      showError('notifications', 'Failed to update notifications');
    } finally {
      setSaving(false);
    }
  };

  const handlePasswordChange = async (e: React.FormEvent) => {
    e.preventDefault();
    if (passwordForm.password !== passwordForm.password_confirmation) {
      showError('password', 'Passwords do not match');
      return;
    }

    try {
      setSaving(true);
      await settingsApi.changePassword(passwordForm);
      setPasswordForm({ current_password: '', password: '', password_confirmation: '' });
      showSuccess('Password changed successfully');
    } catch (error) {
      showError('password', 'Failed to change password');
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-600">Loading settings...</div>
      </div>
    );
  }

  const tabs = [
    { id: 'profile', name: 'Profile', icon: '👤' },
    { id: 'account', name: 'Account', icon: '🏢' },
    { id: 'preferences', name: 'Preferences', icon: '⚙️' },
    { id: 'notifications', name: 'Notifications', icon: '🔔' },
    { id: 'security', name: 'Security', icon: '🔒' }
  ];

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Settings</h1>
        <p className="text-gray-600">
          Manage your account settings and preferences.
        </p>
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
                  ? 'border-blue-500 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              <span className="mr-2">{tab.icon}</span>
              {tab.name}
            </button>
          ))}
        </nav>
      </div>

      {/* Profile Tab */}
      {activeTab === 'profile' && (
        <div className="bg-white shadow rounded-lg">
          <div className="px-6 py-4 border-b border-gray-200">
            <h3 className="text-lg font-medium text-gray-900">Profile Information</h3>
          </div>
          <div className="p-6">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  First Name
                </label>
                <input
                  type="text"
                  value={profileForm.firstName}
                  onChange={(e) => setProfileForm({ ...profileForm, firstName: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Last Name
                </label>
                <input
                  type="text"
                  value={profileForm.lastName}
                  onChange={(e) => setProfileForm({ ...profileForm, lastName: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                />
              </div>
              <div className="md:col-span-2">
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Email Address
                </label>
                <input
                  type="email"
                  value={profileForm.email}
                  onChange={(e) => setProfileForm({ ...profileForm, email: e.target.value })}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                />
              </div>
            </div>
            <div className="mt-6">
              <button
                disabled={saving}
                className="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition-colors disabled:opacity-50"
              >
                {saving ? 'Saving...' : 'Save Changes'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Preferences Tab */}
      {activeTab === 'preferences' && preferences && (
        <div className="bg-white shadow rounded-lg">
          <div className="px-6 py-4 border-b border-gray-200">
            <h3 className="text-lg font-medium text-gray-900">User Preferences</h3>
          </div>
          <div className="p-6 space-y-6">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Theme
                </label>
                <select
                  value={preferences.theme}
                  onChange={(e) => handleUpdatePreferences({ theme: e.target.value as 'light' | 'dark' })}
                  disabled={saving}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                >
                  <option value="light">Light</option>
                  <option value="dark">Dark</option>
                </select>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Language
                </label>
                <select
                  value={preferences.language}
                  onChange={(e) => handleUpdatePreferences({ language: e.target.value })}
                  disabled={saving}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                >
                  <option value="en">English</option>
                  <option value="es">Spanish</option>
                  <option value="fr">French</option>
                </select>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Items per Page
                </label>
                <select
                  value={preferences.items_per_page}
                  onChange={(e) => handleUpdatePreferences({ items_per_page: parseInt(e.target.value) })}
                  disabled={saving}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                >
                  <option value={10}>10</option>
                  <option value={25}>25</option>
                  <option value={50}>50</option>
                  <option value={100}>100</option>
                </select>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Dashboard Layout
                </label>
                <select
                  value={preferences.dashboard_layout}
                  onChange={(e) => handleUpdatePreferences({ dashboard_layout: e.target.value as 'grid' | 'list' })}
                  disabled={saving}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                >
                  <option value="grid">Grid</option>
                  <option value="list">List</option>
                </select>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Notifications Tab */}
      {activeTab === 'notifications' && notifications && (
        <div className="bg-white shadow rounded-lg">
          <div className="px-6 py-4 border-b border-gray-200">
            <h3 className="text-lg font-medium text-gray-900">Notification Preferences</h3>
          </div>
          <div className="p-6 space-y-4">
            {[
              { key: 'email_notifications', label: 'Email Notifications', description: 'Receive notifications via email' },
              { key: 'invoice_notifications', label: 'Invoice Notifications', description: 'Receive invoice and payment notifications' },
              { key: 'security_alerts', label: 'Security Alerts', description: 'Receive security-related notifications' },
              { key: 'marketing_emails', label: 'Marketing Emails', description: 'Receive product updates and marketing content' },
              { key: 'system_maintenance', label: 'System Maintenance', description: 'Receive notifications about system maintenance' }
            ].map(({ key, label, description }) => (
              <div key={key} className="flex items-center justify-between">
                <div>
                  <h4 className="text-sm font-medium text-gray-900">{label}</h4>
                  <p className="text-sm text-gray-600">{description}</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input
                    type="checkbox"
                    className="sr-only peer"
                    checked={notifications[key as keyof NotificationPreferences] as boolean}
                    onChange={(e) => handleUpdateNotifications({ [key]: e.target.checked })}
                    disabled={saving}
                  />
                  <div className="w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-blue-300 rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-blue-600"></div>
                </label>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Security Tab */}
      {activeTab === 'security' && (
        <div className="space-y-6">
          {/* Change Password */}
          <div className="bg-white shadow rounded-lg">
            <div className="px-6 py-4 border-b border-gray-200">
              <h3 className="text-lg font-medium text-gray-900">Change Password</h3>
            </div>
            <div className="p-6">
              <form onSubmit={handlePasswordChange} className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    Current Password
                  </label>
                  <input
                    type="password"
                    value={passwordForm.current_password}
                    onChange={(e) => setPasswordForm({ ...passwordForm, current_password: e.target.value })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                    required
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    New Password
                  </label>
                  <input
                    type="password"
                    value={passwordForm.password}
                    onChange={(e) => setPasswordForm({ ...passwordForm, password: e.target.value })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                    required
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    Confirm New Password
                  </label>
                  <input
                    type="password"
                    value={passwordForm.password_confirmation}
                    onChange={(e) => setPasswordForm({ ...passwordForm, password_confirmation: e.target.value })}
                    className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                    required
                  />
                </div>
                {errors.password && (
                  <div className="text-red-600 text-sm">{errors.password}</div>
                )}
                <div>
                  <button
                    type="submit"
                    disabled={saving}
                    className="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 transition-colors disabled:opacity-50"
                  >
                    {saving ? 'Changing...' : 'Change Password'}
                  </button>
                </div>
              </form>
            </div>
          </div>

          {/* Security Status */}
          {settings && (
            <div className="bg-white shadow rounded-lg">
              <div className="px-6 py-4 border-b border-gray-200">
                <h3 className="text-lg font-medium text-gray-900">Security Status</h3>
              </div>
              <div className="p-6 space-y-4">
                <div className="flex justify-between items-center">
                  <span className="text-sm font-medium text-gray-700">Email Verification</span>
                  <span className={`px-2 py-1 rounded-full text-xs font-medium ${
                    settings.security_settings.email_verified 
                      ? 'bg-green-100 text-green-800' 
                      : 'bg-red-100 text-red-800'
                  }`}>
                    {settings.security_settings.email_verified ? 'Verified' : 'Not Verified'}
                  </span>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-sm font-medium text-gray-700">Password Last Changed</span>
                  <span className="text-sm text-gray-600">
                    {new Date(settings.security_settings.password_last_changed).toLocaleDateString()}
                  </span>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-sm font-medium text-gray-700">Failed Login Attempts</span>
                  <span className="text-sm text-gray-600">
                    {settings.security_settings.failed_attempts}
                  </span>
                </div>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
};