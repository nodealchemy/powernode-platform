import { settingsApi, UserPreferences, NotificationPreferences } from '../services/settingsApi';

// Debug utility for testing settings updates
export const debugSettings = {
  async testPreferencesUpdate() {
    try {
      console.log('=== Testing Preferences Update ===');
      
      // First get current preferences
      const currentPrefs = await settingsApi.getPreferences();
      console.log('Current preferences:', currentPrefs);
      
      // Test update with a simple change
      const testUpdate: Partial<UserPreferences> = {
        theme: currentPrefs.theme === 'light' ? 'dark' : 'light',
        items_per_page: 20
      };
      
      console.log('Updating preferences with:', testUpdate);
      const updated = await settingsApi.updatePreferences(testUpdate);
      console.log('Update result:', updated);
      
      // Verify the update
      const verifyPrefs = await settingsApi.getPreferences();
      console.log('Verified preferences:', verifyPrefs);
      
      return {
        success: true,
        message: 'Preferences update test completed',
        before: currentPrefs,
        update: testUpdate,
        after: verifyPrefs
      };
      
    } catch (error) {
      console.error('Preferences update test failed:', error);
      return {
        success: false,
        error: error
      };
    }
  },
  
  async testNotificationsUpdate() {
    try {
      console.log('=== Testing Notifications Update ===');
      
      // First get current notifications
      const currentNotifs = await settingsApi.getNotifications();
      console.log('Current notifications:', currentNotifs);
      
      // Test update with a simple change
      const testUpdate: Partial<NotificationPreferences> = {
        email_notifications: !currentNotifs.email_notifications,
        marketing_emails: !currentNotifs.marketing_emails
      };
      
      console.log('Updating notifications with:', testUpdate);
      const updated = await settingsApi.updateNotifications(testUpdate);
      console.log('Update result:', updated);
      
      // Verify the update
      const verifyNotifs = await settingsApi.getNotifications();
      console.log('Verified notifications:', verifyNotifs);
      
      return {
        success: true,
        message: 'Notifications update test completed',
        before: currentNotifs,
        update: testUpdate,
        after: verifyNotifs
      };
      
    } catch (error) {
      console.error('Notifications update test failed:', error);
      return {
        success: false,
        error: error
      };
    }
  },
  
  async testAllSettings() {
    try {
      console.log('=== Testing All Settings ===');
      
      const settings = await settingsApi.getSettings();
      console.log('All settings:', settings);
      
      return {
        success: true,
        settings: settings
      };
      
    } catch (error) {
      console.error('Get all settings test failed:', error);
      return {
        success: false,
        error: error
      };
    }
  }
};

// Make it available globally for debugging
if (typeof window !== 'undefined') {
  (window as any).debugSettings = debugSettings;
}