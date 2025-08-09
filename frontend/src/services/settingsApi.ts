import { apiClient } from './api';

// Types for settings data
export interface UserPreferences {
  theme: 'light' | 'dark';
  language: string;
  timezone: string;
  date_format: string;
  currency_display: string;
  dashboard_layout: 'grid' | 'list';
  analytics_default_period: string;
  items_per_page: number;
  auto_refresh_interval: number;
  keyboard_shortcuts_enabled: boolean;
}

export interface AccountSettings {
  name: string;
  subdomain?: string;
  billing_email?: string;
  tax_id?: string;
  company_size?: string;
  industry?: string;
  website?: string;
  phone?: string;
  address?: string;
  logo_url?: string;
}

export interface NotificationPreferences {
  email_notifications: boolean;
  invoice_notifications: boolean;
  security_alerts: boolean;
  marketing_emails: boolean;
  account_updates: boolean;
  system_maintenance: boolean;
  new_features: boolean;
  usage_reports: boolean;
  payment_reminders: boolean;
}

export interface SecuritySettings {
  email_verified: boolean;
  password_last_changed: string;
  two_factor_enabled: boolean;
  login_history: Array<{
    timestamp: string;
    ip_address: string;
    user_agent: string;
  }>;
  failed_attempts: number;
  account_locked: boolean;
}

export interface SettingsData {
  user_preferences: UserPreferences;
  account_settings: AccountSettings;
  notification_preferences: NotificationPreferences;
  security_settings: SecuritySettings;
}

export interface SettingsUpdateRequest {
  user_preferences?: Partial<UserPreferences>;
  account_settings?: Partial<AccountSettings>;
  notification_preferences?: Partial<NotificationPreferences>;
  security_settings?: {
    password?: string;
    current_password?: string;
    password_confirmation?: string;
    email?: string;
  };
}

class SettingsApiService {
  // Get all settings
  async getSettings(): Promise<SettingsData> {
    const response = await apiClient.get('/settings');
    return response.data.data || response.data;
  }

  // Update all settings
  async updateSettings(settings: SettingsUpdateRequest): Promise<SettingsData> {
    const response = await apiClient.put('/settings', { settings });
    return response.data.data || response.data;
  }

  // Get user preferences only
  async getPreferences(): Promise<UserPreferences> {
    const response = await apiClient.get('/settings/preferences');
    return response.data.data || response.data;
  }

  // Update user preferences
  async updatePreferences(preferences: Partial<UserPreferences>): Promise<UserPreferences> {
    try {
      console.log('Updating preferences:', preferences);
      const response = await apiClient.put('/settings/preferences', { preferences });
      console.log('Preferences update response:', response.data);
      return response.data.data || response.data;
    } catch (error) {
      console.error('Failed to update preferences:', error);
      throw error;
    }
  }

  // Get notification preferences only
  async getNotifications(): Promise<NotificationPreferences> {
    const response = await apiClient.get('/settings/notifications');
    return response.data.data || response.data;
  }

  // Update notification preferences
  async updateNotifications(notifications: Partial<NotificationPreferences>): Promise<NotificationPreferences> {
    try {
      console.log('Updating notifications:', notifications);
      const response = await apiClient.put('/settings/notifications', { notifications });
      console.log('Notifications update response:', response.data);
      return response.data.data || response.data;
    } catch (error) {
      console.error('Failed to update notifications:', error);
      throw error;
    }
  }

  // Update user profile (name, email, etc.)
  async updateProfile(userData: {
    first_name?: string;
    last_name?: string;
    email?: string;
    current_password?: string;
    password?: string;
    password_confirmation?: string;
  }): Promise<any> {
    // Use the settings endpoint for profile updates
    const response = await apiClient.put('/settings', { 
      settings: {
        security_settings: userData
      }
    });
    return response.data.data || response.data;
  }

  // Update account settings
  async updateAccount(accountData: Partial<AccountSettings>): Promise<any> {
    // Use the settings endpoint for account updates
    const response = await apiClient.put('/settings', { 
      settings: {
        account_settings: accountData
      }
    });
    return response.data.data || response.data;
  }

  // Change password specifically
  async changePassword(data: {
    current_password: string;
    password: string;
    password_confirmation: string;
  }): Promise<any> {
    const response = await apiClient.put('/auth/change-password', data);
    return response.data;
  }
}

export const settingsApi = new SettingsApiService();