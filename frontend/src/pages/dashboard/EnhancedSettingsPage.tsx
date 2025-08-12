import React, { useState, useEffect, useCallback } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store';
import { settingsApi, UserSettings, NotificationPreferences } from '../../services/settingsApi';
import { useTheme } from '../../contexts/ThemeContext';
import { useSettingsWebSocket } from '../../hooks/useSettingsWebSocket';
import { WebSocketStatusIndicator } from '../../components/common/WebSocketStatusIndicator';

export const EnhancedSettingsPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const { theme, setTheme } = useTheme();
  const [settings, setSettings] = useState<UserSettings | null>(null);
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

  const [, setAccountForm] = useState({
    name: '',
    billing_email: '',
    company_size: '',
    industry: '',
    website: '',
    phone: ''
  });

  const [preferences, setPreferences] = useState<Partial<UserSettings>>({});
  const [notifications, setNotifications] = useState<Partial<UserSettings>>({});
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const [isReceivingUpdate, setIsReceivingUpdate] = useState(false);

  // Real-time settings update handlers
  const handleSettingsUpdate = useCallback((updatedData: Partial<UserSettings>) => {
    setIsReceivingUpdate(true);
    
    if (updatedData.user_preferences) {
      setPreferences(prev => ({ ...prev, ...updatedData.user_preferences }));
      setSuccessMessage('Settings updated from another session');
    }
    
    if (updatedData.notification_preferences) {
      setNotifications(prev => ({ ...prev, ...updatedData.notification_preferences }));
      setSuccessMessage('Notifications updated from another session');
    }

    setLastUpdated(new Date());
    setIsReceivingUpdate(false);

    // Clear success message after 3 seconds
    setTimeout(() => setSuccessMessage(''), 3000);
  }, []);

  const handlePreferencesUpdate = useCallback((updatedPreferences: Partial<UserSettings>) => {
    setPreferences(prev => ({ ...prev, ...updatedPreferences }));
    
    // Update theme context if theme preference changed
    if (updatedPreferences.user_preferences?.theme && updatedPreferences.user_preferences.theme !== theme) {
      setTheme(updatedPreferences.user_preferences.theme);
    }
    
    setLastUpdated(new Date());
    setSuccessMessage('Preferences synced from another session');
    setTimeout(() => setSuccessMessage(''), 3000);
  }, [theme, setTheme]);

  const handleNotificationsUpdate = useCallback((updatedNotifications: Partial<UserSettings>) => {
    setNotifications(prev => ({ ...prev, ...updatedNotifications }));
    setLastUpdated(new Date());
    setSuccessMessage('Notification settings synced from another session');
    setTimeout(() => setSuccessMessage(''), 3000);
  }, []);

  // Initialize WebSocket for real-time updates
  const { isConnected, broadcastSettingsUpdate } = useSettingsWebSocket({
    onSettingsUpdate: handleSettingsUpdate,
    onPreferencesUpdate: handlePreferencesUpdate,
    onNotificationsUpdate: handleNotificationsUpdate,
    enabled: true
  });

  const loadSettings = useCallback(async () => {
    try {
      setLoading(true);
      const response = await settingsApi.getUserSettings();
      if (!response.success) {
        throw new Error(response.error || 'Failed to load settings');
      }
      const settingsData = response.data;
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

      setPreferences({ user_preferences: settingsData.user_preferences });
      setNotifications({ notification_preferences: settingsData.notification_preferences });
    } catch (error) {
      console.error('Failed to load settings:', error);
    } finally {
      setLoading(false);
    }
  }, [user]);

  useEffect(() => {
    loadSettings();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []); // Only run once on mount

  const showSuccess = (message: string) => {
    setSuccessMessage(message);
    setTimeout(() => setSuccessMessage(''), 3000);
  };

  const showError = (field: string, message: string) => {
    setErrors({ ...errors, [field]: message });
    setTimeout(() => setErrors({}), 5000);
  };

  const handleUpdatePreferences = async (updatedPrefs: Partial<UserSettings>) => {
    try {
      setSaving(true);
      
      // Handle theme updates through the theme context
      if (updatedPrefs.user_preferences?.theme && updatedPrefs.user_preferences.theme !== theme) {
        await setTheme(updatedPrefs.user_preferences.theme);
      }
      
      // Update other preferences normally
      const otherPrefs = { ...updatedPrefs };
      if (otherPrefs.user_preferences?.theme) {
        delete otherPrefs.user_preferences.theme; // Theme is handled by context
      }
      
      if (Object.keys(otherPrefs).length > 0) {
        await settingsApi.updateUserSettings(otherPrefs);
      }
      
      setPreferences({ ...preferences, ...updatedPrefs });
      
      // Broadcast the update to other sessions in real-time
      broadcastSettingsUpdate('preferences_updated', updatedPrefs);
      
      showSuccess('Preferences updated successfully');
    } catch (error: any) {
      console.error('Preferences update error:', error);
      const errorMessage = error.response?.data?.error || error.message || 'Failed to update preferences';
      showError('preferences', errorMessage);
    } finally {
      setSaving(false);
    }
  };

  const handleUpdateNotifications = async (updatedNotifs: Partial<UserSettings>) => {
    try {
      setSaving(true);
      await settingsApi.updateUserSettings(updatedNotifs);
      setNotifications({ ...notifications, ...updatedNotifs });
      
      // Broadcast the update to other sessions in real-time
      broadcastSettingsUpdate('notifications_updated', updatedNotifs);
      
      showSuccess('Notification preferences updated');
    } catch (error: any) {
      console.error('Notifications update error:', error);
      const errorMessage = error.response?.data?.error || error.message || 'Failed to update notifications';
      showError('notifications', errorMessage);
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
        <div className="text-theme-secondary">Loading settings...</div>
      </div>
    );
  }

  const tabs = [
    { id: 'profile', name: 'Profile', icon: '👤' },
    { id: 'account', name: 'Account', icon: '🏢' },
    { id: 'preferences', name: 'Preferences', icon: '⚙️' },
    { id: 'notifications', name: 'Notifications', icon: '🔔' },
    { id: 'security', name: 'Security', icon: '🔒' },
  ];

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-start">
        <div>
          <h1 className="text-2xl font-bold text-theme-primary">Settings</h1>
          <p className="text-theme-secondary">
            Manage your account settings and preferences.
          </p>
          {lastUpdated && (
            <p className="text-sm text-theme-tertiary mt-1">
              Last synced: {lastUpdated.toLocaleTimeString()}
            </p>
          )}
        </div>
        
        {/* Real-time status indicator */}
        <div className="flex items-center space-x-3">
          <WebSocketStatusIndicator showDetails={false} />
          {isReceivingUpdate && (
            <div className="flex items-center space-x-2 px-3 py-1 bg-theme-info text-theme-info rounded-md">
              <div className="animate-pulse w-2 h-2 bg-theme-info rounded-full"></div>
              <span className="text-sm">Syncing...</span>
            </div>
          )}
          {isConnected && (
            <div className="flex items-center space-x-2 px-3 py-1 bg-theme-success text-theme-success rounded-md">
              <div className="w-2 h-2 bg-theme-success rounded-full"></div>
              <span className="text-sm">Live</span>
            </div>
          )}
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

      {/* Profile Tab */}
      {activeTab === 'profile' && (
        <div className="card-theme rounded-lg">
          <div className="px-6 py-4 border-b border-theme">
            <h3 className="text-lg font-medium text-theme-primary">Profile Information</h3>
          </div>
          <div className="p-6">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  First Name
                </label>
                <input
                  type="text"
                  value={profileForm.firstName}
                  onChange={(e) => setProfileForm({ ...profileForm, firstName: e.target.value })}
                  className="input-theme"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Last Name
                </label>
                <input
                  type="text"
                  value={profileForm.lastName}
                  onChange={(e) => setProfileForm({ ...profileForm, lastName: e.target.value })}
                  className="input-theme"
                />
              </div>
              <div className="md:col-span-2">
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Email Address
                </label>
                <input
                  type="email"
                  value={profileForm.email}
                  onChange={(e) => setProfileForm({ ...profileForm, email: e.target.value })}
                  className="input-theme"
                />
              </div>
            </div>
            <div className="mt-6">
              <button
                disabled={saving}
                className="btn-theme btn-theme-primary"
              >
                {saving ? 'Saving...' : 'Save Changes'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Preferences Tab */}
      {activeTab === 'preferences' && preferences && (
        <div className="card-theme rounded-lg">
          <div className="px-6 py-4 border-b border-theme">
            <h3 className="text-lg font-medium text-theme-primary">User Preferences</h3>
          </div>
          <div className="p-6 space-y-6">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Theme
                </label>
                <select
                  value={theme}
                  onChange={(e) => handleUpdatePreferences({ user_preferences: { theme: e.target.value as 'light' | 'dark' } })}
                  disabled={saving}
                  className="input-theme"
                >
                  <option value="light">Light</option>
                  <option value="dark">Dark</option>
                </select>
              </div>
              <div>
                <label className="label-theme">
                  Language
                </label>
                <select
                  value={preferences.user_preferences?.language}
                  onChange={(e) => handleUpdatePreferences({ user_preferences: { language: e.target.value } })}
                  disabled={saving}
                  className="select-theme"
                >
                  <option value="en">English</option>
                  <option value="es">Spanish</option>
                  <option value="fr">French</option>
                </select>
              </div>
              <div>
                <label className="label-theme">
                  Items per Page
                </label>
                <select
                  value={preferences.user_preferences?.items_per_page}
                  onChange={(e) => handleUpdatePreferences({ user_preferences: { items_per_page: parseInt(e.target.value) } })}
                  disabled={saving}
                  className="select-theme"
                >
                  <option value={10}>10</option>
                  <option value={25}>25</option>
                  <option value={50}>50</option>
                  <option value={100}>100</option>
                </select>
              </div>
              <div>
                <label className="label-theme">
                  Dashboard Layout
                </label>
                <select
                  value={preferences.user_preferences?.dashboard_layout}
                  onChange={(e) => handleUpdatePreferences({ user_preferences: { dashboard_layout: e.target.value as 'grid' | 'list' } })}
                  disabled={saving}
                  className="select-theme"
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
        <div className="card-theme">
          <div className="px-6 py-4 border-b border-theme">
            <h3 className="text-lg font-medium text-theme-primary">Notification Preferences</h3>
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
                  <h4 className="text-sm font-medium text-theme-primary">{label}</h4>
                  <p className="text-sm text-theme-secondary">{description}</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input
                    type="checkbox"
                    className="sr-only peer"
                    checked={(notifications.notification_preferences?.[key as keyof NotificationPreferences] as boolean) || false}
                    onChange={(e) => handleUpdateNotifications({ notification_preferences: { [key]: e.target.checked } })}
                    disabled={saving}
                  />
                  <div className="toggle-theme"></div>
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
          <div className="card-theme">
            <div className="px-6 py-4 border-b border-theme">
              <h3 className="text-lg font-medium text-theme-primary">Change Password</h3>
            </div>
            <div className="p-6">
              <form onSubmit={handlePasswordChange} className="space-y-4">
                <div>
                  <label className="label-theme">
                    Current Password
                  </label>
                  <input
                    type="password"
                    value={passwordForm.current_password}
                    onChange={(e) => setPasswordForm({ ...passwordForm, current_password: e.target.value })}
                    className="input-theme"
                    required
                  />
                </div>
                <div>
                  <label className="label-theme">
                    New Password
                  </label>
                  <input
                    type="password"
                    value={passwordForm.password}
                    onChange={(e) => setPasswordForm({ ...passwordForm, password: e.target.value })}
                    className="input-theme"
                    required
                  />
                </div>
                <div>
                  <label className="label-theme">
                    Confirm New Password
                  </label>
                  <input
                    type="password"
                    value={passwordForm.password_confirmation}
                    onChange={(e) => setPasswordForm({ ...passwordForm, password_confirmation: e.target.value })}
                    className="input-theme"
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
                    className="btn-theme btn-theme-primary"
                  >
                    {saving ? 'Changing...' : 'Change Password'}
                  </button>
                </div>
              </form>
            </div>
          </div>

          {/* Security Status */}
          {settings && (
            <div className="card-theme">
              <div className="px-6 py-4 border-b border-theme">
                <h3 className="text-lg font-medium text-theme-primary">Security Status</h3>
              </div>
              <div className="p-6 space-y-4">
                <div className="flex justify-between items-center">
                  <span className="text-sm font-medium text-theme-primary">Email Verification</span>
                  <span className={`px-2 py-1 rounded-full text-xs font-medium ${
                    settings.security_settings?.email_verified 
                      ? 'bg-theme-success text-theme-success' 
                      : 'bg-theme-error text-theme-error'
                  }`}>
                    {settings.security_settings?.email_verified ? 'Verified' : 'Not Verified'}
                  </span>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-sm font-medium text-theme-primary">Password Last Changed</span>
                  <span className="text-sm text-theme-secondary">
                    {settings.security_settings?.password_last_changed ? new Date(settings.security_settings.password_last_changed).toLocaleDateString() : 'Not available'}
                  </span>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-sm font-medium text-theme-primary">Failed Login Attempts</span>
                  <span className="text-sm text-theme-secondary">
                    {settings.security_settings?.failed_attempts || 0}
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