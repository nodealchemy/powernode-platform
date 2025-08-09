import React, { useState, useEffect } from 'react';
import { useSelector } from 'react-redux';
import { RootState } from '../../store';
import { settingsApi, SettingsData, UserPreferences, NotificationPreferences } from '../../services/settingsApi';

export const SettingsPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
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

      setPreferences(settingsData.user_preferences || {});
      setNotifications(settingsData.notification_preferences || {});
    } catch (error) {
      console.error('Failed to load settings:', error);
      setErrorMessage('Failed to load settings');
    } finally {
      setLoading(false);
    }
  };

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
      showSuccess('Preferences updated successfully');
    } catch (error) {
      showError('Failed to update preferences');
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

      {errorMessage && (
        <div className="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded">
          {errorMessage}
        </div>
      )}

      {/* Tab Navigation */}
      <div className="border-b border-gray-200">
        <nav className="-mb-px flex space-x-8">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`py-2 px-1 border-b-2 font-medium text-sm transition-colors duration-150 ${
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
            <p className="text-sm text-gray-500 mt-1">Update your personal information</p>
          </div>
          <div className="p-6">
            <form onSubmit={handleProfileUpdate}>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    First Name *
                  </label>
                  <input
                    type="text"
                    value={profileForm.firstName}
                    onChange={(e) => setProfileForm({ ...profileForm, firstName: e.target.value })}
                    className={`w-full px-3 py-2 border rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-colors duration-150 ${
                      profileForm.firstName.trim() ? 'border-gray-300' : 'border-red-300'
                    }`}
                    placeholder="Enter your first name"
                    required
                  />
                  {!profileForm.firstName.trim() && (
                    <p className="text-sm text-red-600 mt-1">First name is required</p>
                  )}
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    Last Name *
                  </label>
                  <input
                    type="text"
                    value={profileForm.lastName}
                    onChange={(e) => setProfileForm({ ...profileForm, lastName: e.target.value })}
                    className={`w-full px-3 py-2 border rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-colors duration-150 ${
                      profileForm.lastName.trim() ? 'border-gray-300' : 'border-red-300'
                    }`}
                    placeholder="Enter your last name"
                    required
                  />
                  {!profileForm.lastName.trim() && (
                    <p className="text-sm text-red-600 mt-1">Last name is required</p>
                  )}
                </div>
                <div className="md:col-span-2">
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    Email Address *
                  </label>
                  <input
                    type="email"
                    value={profileForm.email}
                    onChange={(e) => setProfileForm({ ...profileForm, email: e.target.value })}
                    className={`w-full px-3 py-2 border rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-colors duration-150 ${
                      profileForm.email.trim() && isValidEmail(profileForm.email) ? 'border-gray-300' : 'border-red-300'
                    }`}
                    placeholder="Enter your email address"
                    required
                  />
                  {profileForm.email.trim() && !isValidEmail(profileForm.email) && (
                    <p className="text-sm text-red-600 mt-1">Please enter a valid email address</p>
                  )}
                </div>
              </div>
              <div className="mt-6 flex items-center justify-between">
                <div className="flex items-center space-x-4">
                  <button
                    type="submit"
                    disabled={saving || !profileForm.firstName.trim() || !profileForm.lastName.trim() || !isValidEmail(profileForm.email)}
                    className="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors duration-150"
                  >
                    {saving ? (
                      <span className="flex items-center">
                        <svg className="animate-spin -ml-1 mr-3 h-4 w-4 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                          <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                          <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                        </svg>
                        Saving...
                      </span>
                    ) : 'Save Changes'}
                  </button>
                </div>
                <p className="text-sm text-gray-500">
                  * Required fields
                </p>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* Account Tab */}
      {activeTab === 'account' && (
        <div className="bg-white shadow rounded-lg">
          <div className="px-6 py-4 border-b border-gray-200">
            <h3 className="text-lg font-medium text-gray-900">Account Information</h3>
            <p className="text-sm text-gray-500 mt-1">View your account details and current status</p>
          </div>
          <div className="p-6">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div className="space-y-4">
                <div>
                  <h4 className="text-sm font-medium text-gray-900">Account Name</h4>
                  <p className="text-sm text-gray-600 mt-1">
                    {user?.account?.name || 'No account name'}
                  </p>
                </div>
                <div>
                  <h4 className="text-sm font-medium text-gray-900">Account Role</h4>
                  <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800 capitalize">
                    {user?.role || 'No role assigned'}
                  </span>
                </div>
              </div>
              <div className="space-y-4">
                <div>
                  <h4 className="text-sm font-medium text-gray-900">Account Status</h4>
                  <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
                    {user?.status || 'Active'}
                  </span>
                </div>
                <div>
                  <h4 className="text-sm font-medium text-gray-900">Account ID</h4>
                  <p className="text-sm text-gray-600 mt-1 font-mono text-xs">
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
        <div className="bg-white shadow rounded-lg">
          <div className="px-6 py-4 border-b border-gray-200">
            <h3 className="text-lg font-medium text-gray-900">User Preferences</h3>
            <p className="text-sm text-gray-500 mt-1">Customize your application experience</p>
          </div>
          <div className="p-6 space-y-6">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Theme
                  <span className="ml-1 text-gray-400" title="Choose your preferred color scheme">ℹ️</span>
                </label>
                <select
                  value={preferences.theme || 'light'}
                  onChange={(e) => handleUpdatePreferences({ theme: e.target.value as 'light' | 'dark' })}
                  disabled={saving}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500 disabled:opacity-50 transition-colors duration-150"
                >
                  <option value="light">Light</option>
                  <option value="dark">Dark</option>
                </select>
                <p className="text-xs text-gray-500 mt-1">Choose your preferred color scheme for the interface</p>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Language
                  <span className="ml-1 text-gray-400" title="Select your preferred language">🌐</span>
                </label>
                <select
                  value={preferences.language || 'en'}
                  onChange={(e) => handleUpdatePreferences({ language: e.target.value })}
                  disabled={saving}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500 disabled:opacity-50 transition-colors duration-150"
                >
                  <option value="en">English</option>
                  <option value="es">Spanish</option>
                  <option value="fr">French</option>
                </select>
                <p className="text-xs text-gray-500 mt-1">Select your preferred language for the interface</p>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Items per Page
                  <span className="ml-1 text-gray-400" title="Number of items to display per page in lists">📄</span>
                </label>
                <select
                  value={preferences.items_per_page || 25}
                  onChange={(e) => handleUpdatePreferences({ items_per_page: parseInt(e.target.value) })}
                  disabled={saving}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500 disabled:opacity-50 transition-colors duration-150"
                >
                  <option value={10}>10 items</option>
                  <option value={25}>25 items</option>
                  <option value={50}>50 items</option>
                  <option value={100}>100 items</option>
                </select>
                <p className="text-xs text-gray-500 mt-1">How many items to show per page in lists and tables</p>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Dashboard Layout
                  <span className="ml-1 text-gray-400" title="Choose how data is displayed on your dashboard">📊</span>
                </label>
                <select
                  value={preferences.dashboard_layout || 'grid'}
                  onChange={(e) => handleUpdatePreferences({ dashboard_layout: e.target.value as 'grid' | 'list' })}
                  disabled={saving}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500 disabled:opacity-50 transition-colors duration-150"
                >
                  <option value="grid">Grid View</option>
                  <option value="list">List View</option>
                </select>
                <p className="text-xs text-gray-500 mt-1">Choose how information is displayed on your dashboard</p>
              </div>
            </div>
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
              <p className="text-sm text-gray-500 mt-1">Update your password to keep your account secure</p>
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
                    className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-colors duration-150"
                    placeholder="Enter your current password"
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
                    className={`w-full px-3 py-2 border rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-colors duration-150 ${
                      passwordForm.password && isStrongPassword(passwordForm.password) ? 'border-green-300' : 
                      passwordForm.password ? 'border-red-300' : 'border-gray-300'
                    }`}
                    placeholder="Enter your new password"
                    required
                  />
                  <div className="mt-2">
                    <p className="text-xs text-gray-600 mb-2">Password must contain:</p>
                    <div className="grid grid-cols-2 gap-2 text-xs">
                      <div className={`flex items-center ${
                        passwordForm.password.length >= 12 ? 'text-green-600' : 'text-gray-400'
                      }`}>
                        <span className="mr-1">{passwordForm.password.length >= 12 ? '✓' : '○'}</span>
                        At least 12 characters
                      </div>
                      <div className={`flex items-center ${
                        /[A-Z]/.test(passwordForm.password) ? 'text-green-600' : 'text-gray-400'
                      }`}>
                        <span className="mr-1">{/[A-Z]/.test(passwordForm.password) ? '✓' : '○'}</span>
                        Uppercase letter
                      </div>
                      <div className={`flex items-center ${
                        /[a-z]/.test(passwordForm.password) ? 'text-green-600' : 'text-gray-400'
                      }`}>
                        <span className="mr-1">{/[a-z]/.test(passwordForm.password) ? '✓' : '○'}</span>
                        Lowercase letter
                      </div>
                      <div className={`flex items-center ${
                        /\d/.test(passwordForm.password) ? 'text-green-600' : 'text-gray-400'
                      }`}>
                        <span className="mr-1">{/\d/.test(passwordForm.password) ? '✓' : '○'}</span>
                        Number
                      </div>
                      <div className={`flex items-center ${
                        /[!@#$%^&*(),.?":{}|<>]/.test(passwordForm.password) ? 'text-green-600' : 'text-gray-400'
                      }`}>
                        <span className="mr-1">{/[!@#$%^&*(),.?":{}|<>]/.test(passwordForm.password) ? '✓' : '○'}</span>
                        Special character
                      </div>
                    </div>
                  </div>
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">
                    Confirm New Password
                  </label>
                  <input
                    type="password"
                    value={passwordForm.password_confirmation}
                    onChange={(e) => setPasswordForm({ ...passwordForm, password_confirmation: e.target.value })}
                    className={`w-full px-3 py-2 border rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500 transition-colors duration-150 ${
                      passwordForm.password_confirmation && passwordForm.password === passwordForm.password_confirmation ? 'border-green-300' : 
                      passwordForm.password_confirmation ? 'border-red-300' : 'border-gray-300'
                    }`}
                    placeholder="Confirm your new password"
                    required
                  />
                  {passwordForm.password_confirmation && passwordForm.password !== passwordForm.password_confirmation && (
                    <p className="text-sm text-red-600 mt-1">Passwords do not match</p>
                  )}
                  {passwordForm.password_confirmation && passwordForm.password === passwordForm.password_confirmation && (
                    <p className="text-sm text-green-600 mt-1 flex items-center">
                      <span className="mr-1">✓</span>
                      Passwords match
                    </p>
                  )}
                </div>
                <div>
                  <button
                    type="submit"
                    disabled={saving}
                    className="bg-blue-600 text-white px-4 py-2 rounded-md hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors duration-150"
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
                <p className="text-sm text-gray-500 mt-1">Monitor your account security</p>
              </div>
              <div className="p-6 space-y-4">
                <div className="flex justify-between items-center p-3 bg-gray-50 rounded-lg">
                  <span className="text-sm font-medium text-gray-700">Email Verification</span>
                  <span className={`px-2 py-1 rounded-full text-xs font-medium ${
                    settings.security_settings?.email_verified || user?.emailVerified
                      ? 'bg-green-100 text-green-800' 
                      : 'bg-red-100 text-red-800'
                  }`}>
                    {(settings.security_settings?.email_verified || user?.emailVerified) ? 'Verified' : 'Not Verified'}
                  </span>
                </div>
                {settings.security_settings?.password_last_changed && (
                  <div className="flex justify-between items-center p-3 bg-gray-50 rounded-lg">
                    <span className="text-sm font-medium text-gray-700">Password Last Changed</span>
                    <span className="text-sm text-gray-600">
                      {new Date(settings.security_settings.password_last_changed).toLocaleDateString()}
                    </span>
                  </div>
                )}
                {settings.security_settings?.failed_attempts !== undefined && (
                  <div className="flex justify-between items-center p-3 bg-gray-50 rounded-lg">
                    <span className="text-sm font-medium text-gray-700">Recent Failed Login Attempts</span>
                    <span className="text-sm text-gray-600">
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
        <div className="bg-white shadow rounded-lg">
          <div className="px-6 py-4 border-b border-gray-200">
            <h3 className="text-lg font-medium text-gray-900">Notification Preferences</h3>
            <p className="text-sm text-gray-500 mt-1">Control how and when you receive notifications</p>
          </div>
          <div className="p-6 space-y-4">
            {[
              { key: 'email_notifications', label: 'Email Notifications', description: 'Receive general notifications via email' },
              { key: 'invoice_notifications', label: 'Invoice Notifications', description: 'Receive invoice and payment notifications' },
              { key: 'security_alerts', label: 'Security Alerts', description: 'Receive security-related notifications' },
              { key: 'marketing_emails', label: 'Marketing Emails', description: 'Receive product updates and marketing content' },
              { key: 'system_maintenance', label: 'System Maintenance', description: 'Receive notifications about system maintenance' }
            ].map(({ key, label, description }) => (
              <div key={key} className="flex items-center justify-between p-3 bg-gray-50 rounded-lg hover:bg-gray-100 transition-colors duration-150">
                <div className="flex-1">
                  <h4 className="text-sm font-medium text-gray-900">{label}</h4>
                  <p className="text-sm text-gray-600 mt-1">{description}</p>
                </div>
                <label className="relative inline-flex items-center cursor-pointer ml-4">
                  <input
                    type="checkbox"
                    className="sr-only peer"
                    checked={notifications[key as keyof NotificationPreferences] as boolean || false}
                    onChange={(e) => handleUpdateNotifications({ [key]: e.target.checked })}
                    disabled={saving}
                  />
                  <div className="w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-blue-300 rounded-full peer peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-blue-600 disabled:opacity-50"></div>
                </label>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
};