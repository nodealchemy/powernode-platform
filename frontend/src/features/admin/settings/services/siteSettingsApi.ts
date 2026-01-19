import { api } from '@/shared/services/api';

// Types for site settings
export interface FooterData {
  site_name: string;
  copyright_text: string;
  copyright_year: string;
  footer_description: string;
  contact_email: string;
  contact_phone: string;
  company_address: string;
  social_facebook: string;
  social_twitter: string;
  social_linkedin: string;
  social_instagram: string;
  social_youtube: string;
}

export interface SiteSetting {
  id: string;
  key: string;
  value: string;
  parsed_value: string | number | boolean | object;
  description: string;
  setting_type: 'string' | 'text' | 'boolean' | 'integer' | 'json';
  is_public: boolean;
  created_at: string;
  updated_at: string;
}

export interface FooterResponse {
  success: boolean;
  data: {
    footer: FooterData;
  };
}

export interface SiteSettingsListResponse {
  success: boolean;
  data: {
    settings: SiteSetting[];
    total_count: number;
  };
}

export interface SiteSettingResponse {
  success: boolean;
  data: {
    setting: SiteSetting;
  };
}

export interface SiteSettingCreateResponse {
  success: boolean;
  data: {
    setting: SiteSetting;
    message: string;
  };
}

export interface SiteSettingUpdateResponse {
  success: boolean;
  data: {
    setting: SiteSetting;
    message: string;
  };
}

export interface BulkUpdateResponse {
  success: boolean;
  data: {
    settings: Record<string, SiteSetting>;
    message: string;
  };
}

export interface SiteSettingFormData {
  key: string;
  value: string;
  description: string;
  setting_type: 'string' | 'text' | 'boolean' | 'integer' | 'json';
  is_public: boolean;
}

class SiteSettingsApiService {
  // Get public footer data (no auth required)
  async getPublicFooter(): Promise<FooterResponse> {
    const response = await api.get('/public/footer');
    return response.data;
  }

  // Get all site settings (admin only)
  async getSiteSettings(): Promise<SiteSettingsListResponse> {
    const response = await api.get('/site_settings');
    return response.data;
  }

  // Get footer settings for admin management
  async getFooterSettings(): Promise<SiteSettingsListResponse> {
    const response = await api.get('/site_settings/footer');
    return response.data;
  }

  // Get a specific site setting
  async getSiteSetting(settingId: string): Promise<SiteSettingResponse> {
    const response = await api.get(`/site_settings/${settingId}`);
    return response.data;
  }

  // Create a new site setting
  async createSiteSetting(settingData: SiteSettingFormData): Promise<SiteSettingCreateResponse> {
    const response = await api.post('/site_settings', {
      site_setting: settingData
    });
    return response.data;
  }

  // Update an existing site setting
  async updateSiteSetting(settingId: string, settingData: Partial<SiteSettingFormData>): Promise<SiteSettingUpdateResponse> {
    const response = await api.put(`/site_settings/${settingId}`, {
      site_setting: settingData
    });
    return response.data;
  }

  // Delete a site setting
  async deleteSiteSetting(settingId: string): Promise<{ success: boolean; message: string }> {
    const response = await api.delete(`/site_settings/${settingId}`);
    return response.data;
  }

  // Bulk update multiple settings
  async bulkUpdateSettings(settings: Record<string, { value: string; description?: string; setting_type?: string; is_public?: boolean }>): Promise<BulkUpdateResponse> {
    const response = await api.put('/site_settings/bulk_update', {
      settings
    });
    return response.data;
  }

  // Helper methods for form management
  getSettingTypes(): Array<{ value: string; label: string }> {
    return [
      { value: 'string', label: 'String' },
      { value: 'text', label: 'Text' },
      { value: 'boolean', label: 'Boolean' },
      { value: 'integer', label: 'Integer' },
      { value: 'json', label: 'JSON' }
    ];
  }

  // Validate setting data
  validateSettingData(settingData: Partial<SiteSettingFormData>): string[] {
    const errors: string[] = [];

    if (!settingData.key || settingData.key.trim().length < 2) {
      errors.push('Setting key must be at least 2 characters long');
    }

    if (!settingData.value && settingData.setting_type !== 'boolean') {
      errors.push('Setting value is required');
    }

    if (!settingData.setting_type) {
      errors.push('Setting type is required');
    }

    if (!['string', 'text', 'boolean', 'integer', 'json'].includes(settingData.setting_type || '')) {
      errors.push('Invalid setting type');
    }

    return errors;
  }

  // Format setting value for display
  formatSettingValue(setting: SiteSetting): string {
    switch (setting.setting_type) {
      case 'boolean':
        return setting.parsed_value ? 'Yes' : 'No';
      case 'json':
        return JSON.stringify(setting.parsed_value, null, 2);
      case 'text':
        return setting.value.length > 100 ? `${setting.value.substring(0, 100)}...` : setting.value;
      default:
        return setting.value || '';
    }
  }

  // Get setting type color for badges
  getSettingTypeColor(settingType: string): string {
    switch (settingType) {
      case 'string':
        return 'bg-theme-primary/20 text-theme-primary border-theme-primary/30';
      case 'text':
        return 'bg-theme-secondary/20 text-theme-secondary border-theme-secondary/30';
      case 'boolean':
        return 'bg-theme-success/20 text-theme-success border-theme-success/30';
      case 'integer':
        return 'bg-theme-info/20 text-theme-info border-theme-info/30';
      case 'json':
        return 'bg-theme-warning/20 text-theme-warning border-theme-warning/30';
      default:
        return 'bg-theme-background-secondary text-theme-secondary border-theme';
    }
  }
}

export const siteSettingsApi = new SiteSettingsApiService();