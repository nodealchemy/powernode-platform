import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { useSelector, useDispatch } from 'react-redux';
import { useLocation } from 'react-router-dom';
import { RootState, AppDispatch } from '@/shared/services';
import { addNotification } from '@/shared/services/slices/uiSlice';
import { settingsApi, UserSettings, NotificationPreferences } from '@/shared/services/settingsApi';
import { useSettingsWebSocket } from '@/shared/hooks/useSettingsWebSocket';
import { WebSocketStatusIndicator } from '@/shared/components/ui/WebSocketStatusIndicator';
import { useTheme } from '@/shared/hooks/ThemeContext';
import { PageContainer, PageAction } from '@/shared/components/layout/PageContainer';
import { TabContainer, TabPanel } from '@/shared/components/layout/TabContainer';
import { Save, RefreshCw } from 'lucide-react';

export const SettingsPage: React.FC = () => {
SettingsPage.displayName = 'SettingsPage';
  const dispatch = useDispatch<AppDispatch>();
  const location = useLocation();
  const { user } = useSelector((state: RootState) => state.auth);
  const { theme, setTheme } = useTheme();
  const [settings, setSettings] = useState<UserSettings | null>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  
  // Get active tab from URL path
  const getActiveTabFromPath = useCallback(() => {
    const path = location.pathname;
    
    // Check for exact matches first to avoid conflicts
    if (path === '/app/profile') return 'profile';
    if (path === '/app/profile/account') return 'account';
    if (path === '/app/profile/preferences') return 'preferences';
    if (path === '/app/profile/notifications') return 'notifications';
    if (path === '/app/profile/security') return 'security';
    
    // Default to profile for base settings path or any other case
    return 'profile';
  }, [location.pathname]);
  
  const [activeTab, setActiveTab] = useState(() => {
    const path = location.pathname;
    // Use exact matches like in getActiveTabFromPath
    if (path === '/app/profile') return 'profile';
    if (path === '/app/profile/account') return 'account';
    if (path === '/app/profile/preferences') return 'preferences';
    if (path === '/app/profile/notifications') return 'notifications';
    if (path === '/app/profile/security') return 'security';
    return 'profile';
  });

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

  const [preferences, setPreferences] = useState<Partial<UserSettings>>({});
  const [notifications, setNotifications] = useState<Partial<UserSettings>>({});
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const [isReceivingUpdate, setIsReceivingUpdate] = useState(false);

  // Real-time settings update handlers
  const handleSettingsUpdate = useCallback((updatedData: Partial<UserSettings>) => {
    setIsReceivingUpdate(true);
    
    if (updatedData.user_preferences) {
      setPreferences(prev => ({ ...prev, ...updatedData.user_preferences }));
      
      // If theme was updated from another session, apply it locally
      if (updatedData.user_preferences.theme && updatedData.user_preferences.theme !== theme) {
        setTheme(updatedData.user_preferences.theme);
      }
      
      dispatch(addNotification({
        type: 'success',
        message: 'Settings updated from another session'
      }));
    }
    
    if (updatedData.notification_preferences) {
      setNotifications(prev => ({ ...prev, ...updatedData.notification_preferences }));
      dispatch(addNotification({
        type: 'success',
        message: 'Notifications updated from another session'
      }));
    }
    
    if (updatedData.account_settings) {
      setSettings(prev => prev ? { ...prev, account_settings: updatedData.account_settings! } : null);
      dispatch(addNotification({
        type: 'success',
        message: 'Account settings updated from another session'
      }));
    }

    setLastUpdated(new Date());
    setIsReceivingUpdate(false);
  }, [theme, setTheme, dispatch]);

  const handlePreferencesUpdate = useCallback((updatedPreferences: Partial<UserSettings>) => {
    setPreferences(prev => ({ ...prev, ...updatedPreferences }));
    
    // If theme was updated from another session, apply it locally
    if (updatedPreferences.user_preferences?.theme && updatedPreferences.user_preferences.theme !== theme) {
      setTheme(updatedPreferences.user_preferences.theme);
    }
    
    setLastUpdated(new Date());
    dispatch(addNotification({
      type: 'success',
      message: 'Preferences synced from another session'
    }));
  }, [theme, setTheme, dispatch]);

  const handleNotificationsUpdate = useCallback((updatedNotifications: Partial<UserSettings>) => {
    setNotifications(prev => ({ ...prev, ...updatedNotifications }));
    setLastUpdated(new Date());
    dispatch(addNotification({
      type: 'success',
      message: 'Notification settings synced from another session'
    }));
  }, [dispatch]);

  // Initialize WebSocket for real-time updates
  const { isConnected, requestSettingsSync } = useSettingsWebSocket({
    onSettingsUpdate: handleSettingsUpdate,
    onPreferencesUpdate: handlePreferencesUpdate,
    onNotificationsUpdate: handleNotificationsUpdate,
    onProfileUpdate: (data) => {
      // Handle profile updates if needed
    },
    onError: (error) => {
      console.error('Settings WebSocket error:', error);
    }
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
        firstName: user?.first_name || '',
        lastName: user?.last_name || '',
        email: user?.email || ''
      });

      setPreferences({ user_preferences: settingsData.user_preferences || {} });
      setNotifications({ notification_preferences: settingsData.notification_preferences || {} });
    } catch (error) {
      console.error('Failed to load settings:', error);
      dispatch(addNotification({
        type: 'error',
        message: 'Failed to load settings'
      }));
    } finally {
      setLoading(false);
    }
  }, [user, dispatch]);

  useEffect(() => {
    loadSettings();
  }, [loadSettings]);

  const showSuccess = (message: string) => {
    dispatch(addNotification({
      type: 'success',
      message
    }));
  };

  const showError = (message: string) => {
    dispatch(addNotification({
      type: 'error',
      message
    }));
  };

  const handleUpdatePreferences = async (updatedPrefs: Partial<UserSettings>) => {
    try {
      setSaving(true);
      await settingsApi.updateUserSettings(updatedPrefs);
      setPreferences({ ...preferences, ...updatedPrefs });
      
      // Sync settings to other sessions
      requestSettingsSync();
      
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
      setPreferences({ ...preferences, user_preferences: { ...preferences.user_preferences, theme: newTheme } });
      
      // Sync settings to other sessions
      requestSettingsSync();
      
      showSuccess('Theme updated successfully');
    } catch (error) {
      showError('Failed to update theme');
    } finally {
      setSaving(false);
    }
  };

  const handleUpdateNotifications = async (updatedNotifs: Partial<UserSettings>) => {
    try {
      setSaving(true);
      await settingsApi.updateUserSettings(updatedNotifs);
      setNotifications({ ...notifications, ...updatedNotifs });
      
      // Sync settings to other sessions
      requestSettingsSync();
      
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

  const pageActions: PageAction[] = [
    {
      id: 'save',
      label: 'Save Changes',
      onClick: () => {
        // Handle save action based on active tab
        if (activeTab === 'profile') {
          document.getElementById('profile-form')?.dispatchEvent(new Event('submit', { bubbles: true }));
        }
      },
      variant: 'primary',
      icon: Save,
      disabled: saving
    },
    {
      id: 'refresh',
      label: 'Refresh',
      onClick: loadSettings,
      variant: 'secondary',
      icon: RefreshCw,
      disabled: loading
    }
  ];

  const tabs = useMemo(() => [
    { id: 'profile', label: 'Profile', icon: '👤', path: '/' },
    { id: 'account', label: 'Account', icon: '🏢', path: '/account' },
    { id: 'preferences', label: 'Preferences', icon: '⚙️', path: '/preferences' },
    { id: 'notifications', label: 'Notifications', icon: '🔔', path: '/notifications' },
    { id: 'security', label: 'Security', icon: '🔒', path: '/security' }
  ], []);

  const breadcrumbs = useMemo(() => {
    const baseBreadcrumbs = [
      { label: 'Dashboard', href: '/app', icon: '🏠' },
      { label: 'Profile', icon: '👤' }
    ];
    
    // Add active tab to breadcrumbs
    const activeTabInfo = tabs.find(tab => tab.id === activeTab);
    if (activeTabInfo && activeTab !== 'profile') {
      baseBreadcrumbs.push({
        label: activeTabInfo.label,
        icon: activeTabInfo.icon
      });
    }
    
    return baseBreadcrumbs;
  }, [activeTab, tabs]);

  
  // Update active tab when URL changes
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => {
    const newActiveTab = getActiveTabFromPath();
    if (newActiveTab !== activeTab) {
      setActiveTab(newActiveTab);
    }
  }, [location.pathname]); // Remove getActiveTabFromPath and activeTab dependencies

  const getPageDescription = () => {
    if (loading) return "Loading profile...";
    return `Manage your profile settings and preferences${lastUpdated ? ` - Last synced: ${lastUpdated.toLocaleTimeString()}` : ''}`;
  };

  return (
    <PageContainer
      title="My Profile"
      description={getPageDescription()}
      breadcrumbs={breadcrumbs}
      actions={loading ? [] : pageActions}
    >
      {loading ? (
        <div className="flex items-center justify-center h-64">
          <div className="text-theme-secondary">Loading profile...</div>
        </div>
      ) : (
        <div>
          {/* Real-time status indicator */}
          <div className="flex justify-end items-center space-x-3 mb-6">
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

          {/* Tab Navigation */}
          <TabContainer
            tabs={tabs}
            activeTab={activeTab}
            onTabChange={setActiveTab}
            basePath="/app/profile"
            variant="underline"
            className="mb-6"
          >

            {/* Tab Panels */}
            <TabPanel tabId="profile" activeTab={activeTab}>
              <div className="card-theme">
                <div className="px-6 py-4 border-b border-theme">
                  <h3 className="text-lg font-medium text-theme-primary">Profile Information</h3>
                  <p className="text-sm text-theme-secondary mt-1">Update your personal information</p>
                </div>
                <div className="p-6">
                  <form id="profile-form" onSubmit={handleProfileUpdate}>
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
            </TabPanel>

            <TabPanel tabId="account" activeTab={activeTab}>
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
            </TabPanel>

            <TabPanel tabId="preferences" activeTab={activeTab}>
              {preferences && (
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
                          value={preferences.user_preferences?.language || 'en'}
                          onChange={(e) => handleUpdatePreferences({ user_preferences: { language: e.target.value } })}
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
                          value={preferences.user_preferences?.items_per_page || 25}
                          onChange={(e) => handleUpdatePreferences({ user_preferences: { items_per_page: parseInt(e.target.value) } })}
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
                          value={preferences.user_preferences?.dashboard_layout || 'grid'}
                          onChange={(e) => handleUpdatePreferences({ user_preferences: { dashboard_layout: e.target.value as 'grid' | 'list' } })}
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
            </TabPanel>

        <TabPanel tabId="security" activeTab={activeTab}>
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
                      settings.security_settings?.email_verified || user?.email_verified
                        ? 'bg-theme-success text-theme-success' 
                        : 'bg-theme-error text-theme-error'
                    }`}>
                      {(settings.security_settings?.email_verified || user?.email_verified) ? 'Verified' : 'Not Verified'}
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
        </TabPanel>

        <TabPanel tabId="notifications" activeTab={activeTab}>
          {notifications && (
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
                      checked={(notifications.notification_preferences?.[key as keyof NotificationPreferences] as boolean) || false}
                      onChange={(e) => handleUpdateNotifications({ notification_preferences: { [key]: e.target.checked } })}
                      disabled={saving}
                    />
                  </div>
                ))}
              </div>
            </div>
          )}
        </TabPanel>
      </TabContainer>
      </div>
      )}
    </PageContainer>
  );
};