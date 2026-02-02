import { api } from '@/shared/services/api';
import { isErrorWithResponse } from '@/shared/utils/errorHandling';

export interface EmailSettings {
  email_provider: 'smtp' | 'sendgrid' | 'ses' | 'mailgun';
  smtp_enabled: boolean;
  smtp_host: string;
  smtp_port: number;
  smtp_username: string;
  smtp_password: string;
  smtp_encryption: 'none' | 'tls' | 'ssl';
  smtp_authentication: boolean;
  smtp_from_address: string;
  smtp_from_name: string;
  smtp_domain: string;
  sendgrid_api_key: string;
  ses_access_key: string;
  ses_secret_key: string;
  ses_region: string;
  mailgun_api_key: string;
  mailgun_domain: string;
  email_verification_expiry_hours: number;
  password_reset_expiry_hours: number;
  max_email_retries: number;
  email_retry_delay_seconds: number;
}

export const emailSettingsApi = {
  async getSettings(): Promise<EmailSettings> {
    const response = await api.get('/email_settings');
    return response.data.data;
  },

  async updateSettings(settings: Partial<EmailSettings>): Promise<{
    message: string;
    status: string;
  }> {
    const response = await api.put('/email_settings', {
      email_settings: settings
    });
    // Handle standardized API response format: {success: true, data: {...}}
    return response.data.data || { message: 'Settings updated successfully', status: 'success' };
  },

  async testEmail(email: string): Promise<{
    message: string;
    status: string;
  }> {
    try {
      const response = await api.post('/email_settings/test', { email });
      
      // Handle standardized API response format: {success: true, data: {...}}
      if (response.data.success && response.data.data) {
        return {
          message: response.data.data.message || 'Test email queued successfully',
          status: 'success'
        };
      }
      
      // Fallback for backward compatibility
      return response.data.data || response.data || { message: 'Test email queued successfully', status: 'success' };
    } catch {
      // Re-throw with structured error information
      if (isErrorWithResponse(error) && error.response?.data) {
        const errorData = error.response.data;
        throw new Error(errorData.error || errorData.message || 'Failed to send test email');
      }
      throw error;
    }
  }
};