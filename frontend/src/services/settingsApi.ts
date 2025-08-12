import { api } from './api';

export interface PublicSettings {
  system_name: string;
  copyright_text: string;
  maintenance_mode: boolean;
  registration_enabled: boolean;
  require_email_verification: boolean;
}

export interface UserPreferences {
  theme?: 'light' | 'dark';
  language?: string;
  timezone?: string;
  date_format?: string;
  currency_display?: string;
  dashboard_layout?: string;
  analytics_default_period?: string;
  items_per_page?: number;
  auto_refresh_interval?: number;
  keyboard_shortcuts_enabled?: boolean;
}

export interface AccountSettings {
  name?: string;
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
  email_notifications?: boolean;
  invoice_notifications?: boolean;
  security_alerts?: boolean;
  marketing_emails?: boolean;
  account_updates?: boolean;
  system_maintenance?: boolean;
  new_features?: boolean;
  usage_reports?: boolean;
  payment_reminders?: boolean;
}

export interface SecuritySettings {
  email_verified?: boolean;
  password_last_changed?: string;
  two_factor_enabled?: boolean;
  login_history?: any[];
  failed_attempts?: number;
  account_locked?: boolean;
}

export interface UserSettingsData {
  user_preferences: UserPreferences;
  account_settings: AccountSettings;
  notification_preferences: NotificationPreferences;
  security_settings: SecuritySettings;
}

export interface UserSettings {
  user_preferences?: UserPreferences;
  account_settings?: AccountSettings;
  notification_preferences?: NotificationPreferences;
  security_settings?: SecuritySettings;
}

export interface PublicSettingsResponse {
  success: boolean;
  data: PublicSettings;
  error?: string;
}

export interface UserSettingsResponse {
  success: boolean;
  data: UserSettingsData;
  error?: string;
  message?: string;
}

// API Service
export const settingsApi = {
  // Get public settings (no authentication required)
  async getPublicSettings(): Promise<PublicSettingsResponse> {
    try {
      const response = await api.get('/settings/public');
      return response.data;
    } catch (error: any) {
      return {
        success: false,
        data: {} as PublicSettings,
        error: error.response?.data?.error || 'Failed to fetch public settings'
      };
    }
  },

  // Get user settings (authentication required)
  async getUserSettings(): Promise<UserSettingsResponse> {
    try {
      const response = await api.get('/settings');
      return response.data;
    } catch (error: any) {
      return {
        success: false,
        data: {} as UserSettingsData,
        error: error.response?.data?.error || 'Failed to fetch user settings'
      };
    }
  },

  // Update user settings (authentication required)
  async updateUserSettings(settings: Partial<UserSettings>): Promise<UserSettingsResponse> {
    try {
      const response = await api.put('/settings', { settings });
      return response.data;
    } catch (error: any) {
      return {
        success: false,
        data: {} as UserSettingsData,
        error: error.response?.data?.error || 'Failed to update user settings',
        message: error.response?.data?.details?.join(', ')
      };
    }
  },

  // Get cached copyright text
  getCachedCopyright(): string {
    const cached = localStorage.getItem('powernode_copyright');
    if (cached) {
      try {
        const { text, timestamp } = JSON.parse(cached);
        // Cache for 1 hour
        if (Date.now() - timestamp < 3600000) {
          return text;
        }
      } catch (e) {
        // Invalid cache, remove it
        localStorage.removeItem('powernode_copyright');
      }
    }
    return `© ${new Date().getFullYear()} Powernode Platform. All rights reserved.`;
  },

  // Cache copyright text
  setCachedCopyright(text: string): void {
    const cacheData = {
      text,
      timestamp: Date.now()
    };
    localStorage.setItem('powernode_copyright', JSON.stringify(cacheData));
  },

  // Get copyright text with caching
  async getCopyright(): Promise<string> {
    try {
      const response = await this.getPublicSettings();
      if (response.success && response.data.copyright_text) {
        this.setCachedCopyright(response.data.copyright_text);
        return response.data.copyright_text;
      }
    } catch (error) {
      console.warn('Failed to fetch copyright from server, using cached version');
    }
    
    return this.getCachedCopyright();
  },

  // Format copyright text with year replacement
  formatCopyright(template: string): string {
    const currentYear = new Date().getFullYear();
    return template.replace('{year}', currentYear.toString());
  },

  // Change user password (authentication required)
  async changePassword(passwordData: { current_password: string; password: string; password_confirmation: string }): Promise<{ success: boolean; error?: string; message?: string }> {
    try {
      const response = await api.put('/auth/change-password', passwordData);
      return response.data;
    } catch (error: any) {
      return {
        success: false,
        error: error.response?.data?.error || 'Failed to change password',
        message: error.response?.data?.details?.join(', ')
      };
    }
  },

  // Update user profile (authentication required)
  async updateProfile(profileData: { first_name: string; last_name: string; email: string }): Promise<{ success: boolean; error?: string; message?: string }> {
    try {
      const response = await api.put('/users/profile', profileData);
      return response.data;
    } catch (error: any) {
      return {
        success: false,
        error: error.response?.data?.error || 'Failed to update profile',
        message: error.response?.data?.details?.join(', ')
      };
    }
  }
};

export default settingsApi;