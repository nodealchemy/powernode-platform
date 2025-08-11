import React, { useState, useEffect, useCallback } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store';
import { settingsApi, SettingsData, UserPreferences, NotificationPreferences } from '../../services/settingsApi';
import { useSettingsWebSocket } from '../../hooks/useSettingsWebSocket';
import { WebSocketStatusIndicator } from '../../components/common/WebSocketStatusIndicator';
import { useTheme } from '../../contexts/ThemeContext';

export const SettingsPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const { theme, setTheme } = useTheme();
  const [settings, setSettings] = useState<SettingsData | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [activeTab, setActiveTab] = useState('profile');
  const [successMessage, setSuccessMessage] = useState('');
  const [errorMessage, setErrorMessage] = useState('');

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

  const [preferences, setPreferences] = useState<Partial<UserPreferences>>({});
  const [notifications, setNotifications] = useState<Partial<NotificationPreferences>>({});
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const [isReceivingUpdate, setIsReceivingUpdate] = useState(false);

  // Real-time settings update handlers
  const handleSettingsUpdate = useCallback((updatedData: Partial<SettingsData>) => {
    setIsReceivingUpdate(true);
    
    if (updatedData.user_preferences) {
      setPreferences(prev => ({ ...prev, ...updatedData.user_preferences }));
      
      // If theme was updated from another session, apply it locally
      if (updatedData.user_preferences.theme && updatedData.user_preferences.theme !== theme) {
        setTheme(updatedData.user_preferences.theme);
      }
      
      setSuccessMessage('Settings updated from another session');
    }
    
    if (updatedData.notification_preferences) {
      setNotifications(prev => ({ ...prev, ...updatedData.notification_preferences }));
      setSuccessMessage('Notifications updated from another session');
    }
    
    if (updatedData.account_settings) {
      setSettings(prev => prev ? { ...prev, account_settings: updatedData.account_settings! } : null);
      setSuccessMessage('Account settings updated from another session');
    }

    setLastUpdated(new Date());
    setIsReceivingUpdate(false);

    // Clear success message after 3 seconds
    setTimeout(() => setSuccessMessage(''), 3000);
  }, [theme, setTheme]);

  const handlePreferencesUpdate = useCallback((updatedPreferences: Partial<UserPreferences>) => {
    setPreferences(prev => ({ ...prev, ...updatedPreferences }));
    
    // If theme was updated from another session, apply it locally
    if (updatedPreferences.theme && updatedPreferences.theme !== theme) {
      setTheme(updatedPreferences.theme);
    }
    
    setLastUpdated(new Date());
    setSuccessMessage('Preferences synced from another session');
    setTimeout(() => setSuccessMessage(''), 3000);
  }, [theme, setTheme]);

  const handleNotificationsUpdate = useCallback((updatedNotifications: Partial<NotificationPreferences>) => {
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
      const settingsData = await settingsApi.getSettings();
      setSettings(settingsData);
      
      // Initialize form states
      setProfileForm({
        firstName: user?.firstName || '',
        lastName: user?.lastName || '',
        email: user?.email || ''
      });

      setPreferences(settingsData.user_preferences || {});
      setNotifications(settingsData.notification_preferences || {});
    } catch (error) {
      console.error('Failed to load settings:', error);
      setErrorMessage('Failed to load settings');
    } finally {
      setLoading(false);
    }
  }, [user]);

  useEffect(() => {
    loadSettings();
  }, [loadSettings]);

  const showSuccess = (message: string) => {
    setSuccessMessage(message);
    setErrorMessage('');
    setTimeout(() => setSuccessMessage(''), 3000);
  };

  const showError = (message: string) => {
    setErrorMessage(message);
    setSuccessMessage('');
    setTimeout(() => setErrorMessage(''), 5000);
  };

  const handleUpdatePreferences = async (updatedPrefs: Partial<UserPreferences>) => {
    try {
      setSaving(true);
      await settingsApi.updatePreferences(updatedPrefs);
      setPreferences({ ...preferences, ...updatedPrefs });
      
      // Broadcast the update to other sessions in real-time
      broadcastSettingsUpdate('preferences_updated', updatedPrefs);
      
      showSuccess('Preferences updated successfully');
    } catch (error) {
      showError('Failed to update preferences');
    } finally {
      setSaving(false);
    }
  };

  const handleThemeChange = async (newTheme: 'light' | 'dark') => {
    try {
      setSaving(true);
      // Use the theme context which automatically applies theme and saves to API
      await setTheme(newTheme);
      setPreferences({ ...preferences, theme: newTheme });
      
      // Broadcast the theme update to other sessions
      broadcastSettingsUpdate('preferences_updated', { theme: newTheme });
      
      showSuccess('Theme updated successfully');
    } catch (error) {
      showError('Failed to update theme');
    } finally {
      setSaving(false);
    }
  };

  const handleUpdateNotifications = async (updatedNotifs: Partial<NotificationPreferences>) => {
    try {
      setSaving(true);
      await settingsApi.updateNotifications(updatedNotifs);
      setNotifications({ ...notifications, ...updatedNotifs });
      
      // Broadcast the update to other sessions in real-time
      broadcastSettingsUpdate('notifications_updated', updatedNotifs);
      
      showSuccess('Notification preferences updated');
    } catch (error) {
      showError('Failed to update notifications');
    } finally {
      setSaving(false);
    }
  };

  const handleProfileUpdate = async (e: React.FormEvent) => {
    e.preventDefault();
    
    // Basic validation
    if (!profileForm.firstName.trim() || !profileForm.lastName.trim()) {
      showError('First name and last name are required');
      return;
    }
    
    if (!profileForm.email.trim() || !isValidEmail(profileForm.email)) {
      showError('Please enter a valid email address');
      return;
    }

    try {
      setSaving(true);
      await settingsApi.updateProfile({
        first_name: profileForm.firstName,
        last_name: profileForm.lastName,
        email: profileForm.email
      });
      showSuccess('Profile updated successfully');
    } catch (error: any) {
      const errorMsg = error?.response?.data?.error || error?.message || 'Failed to update profile';
      showError(errorMsg);
    } finally {
      setSaving(false);
    }
  };

  const handlePasswordChange = async (e: React.FormEvent) => {
    e.preventDefault();
    
    // Validation
    if (!passwordForm.current_password.trim()) {
      showError('Current password is required');
      return;
    }
    
    if (!passwordForm.password.trim()) {
      showError('New password is required');
      return;
    }
    
    if (passwordForm.password.length < 12) {
      showError('Password must be at least 12 characters long');
      return;
    }
    
    if (!isStrongPassword(passwordForm.password)) {
      showError('Password must contain uppercase, lowercase, numbers, and special characters');
      return;
    }
    
    if (passwordForm.password !== passwordForm.password_confirmation) {
      showError('Passwords do not match');
      return;
    }

    try {
      setSaving(true);
      await settingsApi.changePassword(passwordForm);
      setPasswordForm({ current_password: '', password: '', password_confirmation: '' });
      showSuccess('Password changed successfully');
    } catch (error: any) {
      const errorMsg = error?.response?.data?.error || error?.message || 'Failed to change password';
      showError(errorMsg);
    } finally {
      setSaving(false);
    }
  };

  // Helper functions for validation
  const isValidEmail = (email: string): boolean => {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
  };

  const isStrongPassword = (password: string): boolean => {
    const hasUpperCase = /[A-Z]/.test(password);
    const hasLowerCase = /[a-z]/.test(password);
    const hasNumbers = /\d/.test(password);
    const hasSpecialChar = /[!@#$%^&*(),.?":{}|<>]/.test(password);
    return hasUpperCase && hasLowerCase && hasNumbers && hasSpecialChar;
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
    { id: 'security', name: 'Security', icon: '🔒' }
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

      {errorMessage && (
        <div className="alert-theme alert-theme-error">
          {errorMessage}
        </div>
      )}

      {/* Tab Navigation */}
      <div className="border-b border-theme">
        <nav className="-mb-px flex space-x-8">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`py-2 px-1 border-b-2 font-medium text-sm transition-colors duration-150 ${
                activeTab === tab.id
                  ? 'border-theme-focus text-theme-link'
                  : 'border-transparent text-theme-tertiary hover:text-theme-primary hover:border-theme'
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
        <div className="card-theme">
          <div className="px-6 py-4 border-b border-theme">
            <h3 className="text-lg font-medium text-theme-primary">Profile Information</h3>
            <p className="text-sm text-theme-secondary mt-1">Update your personal information</p>
          </div>
          <div className="p-6">
            <form onSubmit={handleProfileUpdate}>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div>
                  <label className="label-theme">
                    First Name *
                  </label>
                  <input
                    type="text"
                    value={profileForm.firstName}
                    onChange={(e) => setProfileForm({ ...profileForm, firstName: e.target.value })}
                    className={`input-theme w-full ${
                      !profileForm.firstName.trim() ? 'border-theme-error' : ''
                    }`}
                    placeholder="Enter your first name"
                    required
                  />
                  {!profileForm.firstName.trim() && (
                    <p className="form-error">First name is required</p>
                  )}
                </div>
                <div>
                  <label className="label-theme">
                    Last Name *
                  </label>
                  <input
                    type="text"
                    value={profileForm.lastName}
                    onChange={(e) => setProfileForm({ ...profileForm, lastName: e.target.value })}
                    className={`input-theme w-full ${
                      !profileForm.lastName.trim() ? 'border-theme-error' : ''
                    }`}
                    placeholder="Enter your last name"
                    required
                  />
                  {!profileForm.lastName.trim() && (
                    <p className="form-error">Last name is required</p>
                  )}
                </div>
                <div className="md:col-span-2">
                  <label className="label-theme">
                    Email Address *
                  </label>
                  <input
                    type="email"
                    value={profileForm.email}
                    onChange={(e) => setProfileForm({ ...profileForm, email: e.target.value })}
                    className={`input-theme w-full ${
                      profileForm.email.trim() && !isValidEmail(profileForm.email) ? 'border-theme-error' : ''
                    }`}
                    placeholder="Enter your email address"
                    required
                  />
                  {profileForm.email.trim() && !isValidEmail(profileForm.email) && (
                    <p className="form-error-theme">Please enter a valid email address</p>
                  )}
                </div>
              </div>
              <div className="mt-6 flex items-center justify-between">
                <div className="flex items-center space-x-4">
                  <button
                    type="submit"
                    disabled={saving || !profileForm.firstName.trim() || !profileForm.lastName.trim() || !isValidEmail(profileForm.email)}
                    className="btn-theme btn-theme-primary"
                  >
{saving ? 'Saving...' : 'Save Changes'}
                  </button>
                </div>
                <p className="form-help-theme">
                  * Required fields
                </p>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Account Tab */}
      {activeTab === 'account' && (
        <div className="card-theme">
          <div className="px-6 py-4 border-b border-theme">
            <h3 className="text-lg font-medium text-theme-primary">Account Information</h3>
            <p className="text-sm text-theme-secondary mt-1">View your account details and current status</p>
          </div>
          <div className="p-6">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div className="space-y-4">
                <div>
                  <h4 className="text-sm font-medium text-theme-primary">Account Name</h4>
                  <p className="text-sm text-theme-secondary mt-1">
                    {user?.account?.name || 'No account name'}
                  </p>
                </div>
                <div>
                  <h4 className="text-sm font-medium text-theme-primary">Account Role</h4>
                  <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-theme-info text-theme-info capitalize">
                    {user?.role || 'No role assigned'}
                  </span>
                </div>
              </div>
              <div className="space-y-4">
                <div>
                  <h4 className="text-sm font-medium text-theme-primary">Account Status</h4>
                  <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-theme-success text-theme-success">
                    {user?.status || 'Active'}
                  </span>
                </div>
                <div>
                  <h4 className="text-sm font-medium text-theme-primary">Account ID</h4>
                  <p className="text-sm text-theme-secondary mt-1 font-mono text-xs">
                    {user?.account?.id || 'Unknown'}
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Preferences Tab */}
      {activeTab === 'preferences' && preferences && (
        <div className="card-theme">
          <div className="px-6 py-4 border-b border-theme">
            <h3 className="text-lg font-medium text-theme-primary">User Preferences</h3>
            <p className="text-sm text-theme-secondary mt-1">Customize your application experience</p>
          </div>
          <div className="p-6 space-y-6">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <label className="label-theme">
                  Theme
                  <span className="ml-1 text-theme-tertiary" title="Choose your preferred color scheme">ℹ️</span>
                </label>
                <select
                  value={theme}
                  onChange={(e) => handleThemeChange(e.target.value as 'light' | 'dark')}
                  disabled={saving}
                  className="select-theme"
                >
                  <option value="light">Light</option>
                  <option value="dark">Dark</option>
                </select>
                <div className="form-help-theme">Choose your preferred color scheme for the interface</div>
              </div>
              <div>
                <label className="label-theme">
                  Language
                  <span className="ml-1 text-theme-tertiary" title="Select your preferred language">🌐</span>
                </label>
                <select
                  value={preferences.language || 'en'}
                  onChange={(e) => handleUpdatePreferences({ language: e.target.value })}
                  disabled={saving}
                  className="select-theme"
                >
                  <option value="en">English</option>
                  <option value="es">Spanish</option>
                  <option value="fr">French</option>
                </select>
                <div className="form-help-theme">Select your preferred language for the interface</div>
              </div>
              <div>
                <label className="label-theme">
                  Items per Page
                  <span className="ml-1 text-theme-tertiary" title="Number of items to display per page in lists">📄</span>
                </label>
                <select
                  value={preferences.items_per_page || 25}
                  onChange={(e) => handleUpdatePreferences({ items_per_page: parseInt(e.target.value) })}
                  disabled={saving}
                  className="select-theme"
                >
                  <option value={10}>10 items</option>
                  <option value={25}>25 items</option>
                  <option value={50}>50 items</option>
                  <option value={100}>100 items</option>
                </select>
                <div className="form-help-theme">How many items to show per page in lists and tables</div>
              </div>
              <div>
                <label className="label-theme">
                  Dashboard Layout
                  <span className="ml-1 text-theme-tertiary" title="Choose how data is displayed on your dashboard">📊</span>
                </label>
                <select
                  value={preferences.dashboard_layout || 'grid'}
                  onChange={(e) => handleUpdatePreferences({ dashboard_layout: e.target.value as 'grid' | 'list' })}
                  disabled={saving}
                  className="select-theme"
                >
                  <option value="grid">Grid View</option>
                  <option value="list">List View</option>
                </select>
                <div className="form-help-theme">Choose how information is displayed on your dashboard</div>
              </div>
            </div>
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
              <p className="text-sm text-theme-secondary mt-1">Update your password to keep your account secure</p>
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
                    placeholder="Enter your current password"
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
                    className={`input-theme ${
                      passwordForm.password && isStrongPassword(passwordForm.password) ? 'success' : 
                      passwordForm.password ? 'error' : ''
                    }`}
                    placeholder="Enter your new password"
                    required
                  />
                  <div className="mt-2">
                    <p className="text-xs text-theme-tertiary mb-2">Password must contain:</p>
                    <div className="grid grid-cols-2 gap-2 text-xs">
                      <div className={`flex items-center ${
                        passwordForm.password.length >= 12 ? 'text-theme-success' : 'text-theme-quaternary'
                      }`}>
                        <span className="mr-1">{passwordForm.password.length >= 12 ? '✓' : '○'}</span>
                        At least 12 characters
                      </div>
                      <div className={`flex items-center ${
                        /[A-Z]/.test(passwordForm.password) ? 'text-theme-success' : 'text-theme-quaternary'
                      }`}>
                        <span className="mr-1">{/[A-Z]/.test(passwordForm.password) ? '✓' : '○'}</span>
                        Uppercase letter
                      </div>
                      <div className={`flex items-center ${
                        /[a-z]/.test(passwordForm.password) ? 'text-theme-success' : 'text-theme-quaternary'
                      }`}>
                        <span className="mr-1">{/[a-z]/.test(passwordForm.password) ? '✓' : '○'}</span>
                        Lowercase letter
                      </div>
                      <div className={`flex items-center ${
                        /\d/.test(passwordForm.password) ? 'text-theme-success' : 'text-theme-quaternary'
                      }`}>
                        <span className="mr-1">{/\d/.test(passwordForm.password) ? '✓' : '○'}</span>
                        Number
                      </div>
                      <div className={`flex items-center ${
                        /[!@#$%^&*(),.?":{}|<>]/.test(passwordForm.password) ? 'text-theme-success' : 'text-theme-quaternary'
                      }`}>
                        <span className="mr-1">{/[!@#$%^&*(),.?":{}|<>]/.test(passwordForm.password) ? '✓' : '○'}</span>
                        Special character
                      </div>
                    </div>
                  </div>
                </div>
                <div>
                  <label className="label-theme">
                    Confirm New Password
                  </label>
                  <input
                    type="password"
                    value={passwordForm.password_confirmation}
                    onChange={(e) => setPasswordForm({ ...passwordForm, password_confirmation: e.target.value })}
                    className={`input-theme ${
                      passwordForm.password_confirmation && passwordForm.password === passwordForm.password_confirmation ? 'success' : 
                      passwordForm.password_confirmation ? 'error' : ''
                    }`}
                    placeholder="Confirm your new password"
                    required
                  />
                  {passwordForm.password_confirmation && passwordForm.password !== passwordForm.password_confirmation && (
                    <p className="form-error-theme">Passwords do not match</p>
                  )}
                  {passwordForm.password_confirmation && passwordForm.password === passwordForm.password_confirmation && (
                    <p className="form-success-theme">
                      Passwords match
                    </p>
                  )}
                </div>
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
                <p className="text-sm text-theme-secondary mt-1">Monitor your account security</p>
              </div>
              <div className="p-6 space-y-4">
                <div className="flex justify-between items-center p-3 bg-theme-background-secondary rounded-lg">
                  <span className="text-sm font-medium text-theme-primary">Email Verification</span>
                  <span className={`px-2 py-1 rounded-full text-xs font-medium ${
                    settings.security_settings?.email_verified || user?.emailVerified
                      ? 'bg-theme-success text-theme-success' 
                      : 'bg-theme-error text-theme-error'
                  }`}>
                    {(settings.security_settings?.email_verified || user?.emailVerified) ? 'Verified' : 'Not Verified'}
                  </span>
                </div>
                {settings.security_settings?.password_last_changed && (
                  <div className="flex justify-between items-center p-3 bg-theme-background-secondary rounded-lg">
                    <span className="text-sm font-medium text-theme-primary">Password Last Changed</span>
                    <span className="text-sm text-theme-secondary">
                      {new Date(settings.security_settings.password_last_changed).toLocaleDateString()}
                    </span>
                  </div>
                )}
                {settings.security_settings?.failed_attempts !== undefined && (
                  <div className="flex justify-between items-center p-3 bg-theme-background-secondary rounded-lg">
                    <span className="text-sm font-medium text-theme-primary">Recent Failed Login Attempts</span>
                    <span className="text-sm text-theme-secondary">
                      {settings.security_settings.failed_attempts}
                    </span>
                  </div>
                )}
              </div>
            </div>
          )}
        </div>
      )}

      {/* Notifications Tab */}
      {activeTab === 'notifications' && notifications && (
        <div className="card-theme">
          <div className="px-6 py-4 border-b border-theme">
            <h3 className="text-lg font-medium text-theme-primary">Notification Preferences</h3>
            <p className="text-sm text-theme-secondary mt-1">Control how and when you receive notifications</p>
          </div>
          <div className="p-6 space-y-4">
            {[
              { key: 'email_notifications', label: 'Email Notifications', description: 'Receive general notifications via email' },
              { key: 'invoice_notifications', label: 'Invoice Notifications', description: 'Receive invoice and payment notifications' },
              { key: 'security_alerts', label: 'Security Alerts', description: 'Receive security-related notifications' },
              { key: 'marketing_emails', label: 'Marketing Emails', description: 'Receive product updates and marketing content' },
              { key: 'system_maintenance', label: 'System Maintenance', description: 'Receive notifications about system maintenance' }
            ].map(({ key, label, description }) => (
              <div key={key} className="flex items-center justify-between p-3 bg-theme-background-secondary rounded-lg hover:bg-theme-surface-hover transition-colors duration-150">
                <div className="flex-1">
                  <h4 className="text-sm font-medium text-theme-primary">{label}</h4>
                  <p className="text-sm text-theme-secondary mt-1">{description}</p>
                </div>
                <input
                  type="checkbox"
                  className="toggle-theme"
                  checked={notifications[key as keyof NotificationPreferences] as boolean || false}
                  onChange={(e) => handleUpdateNotifications({ [key]: e.target.checked })}
                  disabled={saving}
                />
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
};