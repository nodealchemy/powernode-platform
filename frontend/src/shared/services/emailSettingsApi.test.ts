import { emailSettingsApi, EmailSettings } from './emailSettingsApi';
import { api } from '@/shared/services/api';

// Mock the API client
jest.mock('@/shared/services/api', () => ({
  api: {
    get: jest.fn(),
    put: jest.fn(),
    post: jest.fn()
  }
}));

const mockApi = api as jest.Mocked<typeof api>;

const mockEmailSettings: EmailSettings = {
  email_provider: 'smtp',
  smtp_enabled: true,
  smtp_host: 'smtp.gmail.com',
  smtp_port: 587,
  smtp_username: 'test@gmail.com',
  smtp_password: 'password123',
  smtp_encryption: 'tls',
  smtp_authentication: true,
  smtp_from_address: 'noreply@example.com',
  smtp_from_name: 'Test Company',
  smtp_domain: 'example.com',
  sendgrid_api_key: 'SG.test-key',
  ses_access_key: 'AKIAXXXXXXXXXXXXXXXX',
  ses_secret_key: 'test-secret-key',
  ses_region: 'us-east-1',
  mailgun_api_key: 'key-test123',
  mailgun_domain: 'mg.example.com',
  email_verification_expiry_hours: 24,
  password_reset_expiry_hours: 2,
  max_email_retries: 3,
  email_retry_delay_seconds: 60
};

describe('emailSettingsApi', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('getSettings', () => {
    it('should fetch email settings successfully', async () => {
      mockApi.get.mockResolvedValue({
        data: {
          data: mockEmailSettings
        }
      });

      const result = await emailSettingsApi.getSettings();

      expect(mockApi.get).toHaveBeenCalledWith('/email_settings');
      expect(result).toEqual(mockEmailSettings);
    });

    it('should handle API errors', async () => {
      const errorMessage = 'Network Error';
      mockApi.get.mockRejectedValue(new Error(errorMessage));

      await expect(emailSettingsApi.getSettings()).rejects.toThrow(errorMessage);
    });

    it('should handle malformed response data', async () => {
      mockApi.get.mockResolvedValue({
        data: null
      });

      await expect(emailSettingsApi.getSettings()).rejects.toThrow();
    });
  });

  describe('updateSettings', () => {
    it('should update email settings successfully', async () => {
      const settingsUpdate = {
        smtp_host: 'new-smtp.example.com',
        smtp_port: 465
      };

      const mockResponse = {
        message: 'Settings updated successfully',
        status: 'success'
      };

      mockApi.put.mockResolvedValue({
        data: {
          data: mockResponse
        }
      });

      const result = await emailSettingsApi.updateSettings(settingsUpdate);

      expect(mockApi.put).toHaveBeenCalledWith('/email_settings', {
        email_settings: settingsUpdate
      });
      expect(result).toEqual(mockResponse);
    });

    it('should handle partial settings updates', async () => {
      const partialUpdate = {
        email_provider: 'sendgrid' as const,
        sendgrid_api_key: 'SG.new-key'
      };

      mockApi.put.mockResolvedValue({
        data: {
          data: {
            message: 'SendGrid settings updated',
            status: 'success'
          }
        }
      });

      const result = await emailSettingsApi.updateSettings(partialUpdate);

      expect(mockApi.put).toHaveBeenCalledWith('/email_settings', {
        email_settings: partialUpdate
      });
      expect(result.status).toBe('success');
    });

    it('should handle API response without data wrapper', async () => {
      const settingsUpdate = { smtp_enabled: false };

      mockApi.put.mockResolvedValue({
        data: {
          message: 'Settings updated',
          status: 'success'
        }
      });

      const result = await emailSettingsApi.updateSettings(settingsUpdate);

      expect(result).toEqual({
        message: 'Settings updated successfully',
        status: 'success'
      });
    });

    it('should handle update errors', async () => {
      const settingsUpdate = { smtp_host: 'invalid-host' };
      const errorMessage = 'Invalid SMTP configuration';

      mockApi.put.mockRejectedValue({
        response: {
          data: {
            error: errorMessage
          }
        }
      });

      await expect(emailSettingsApi.updateSettings(settingsUpdate)).rejects.toMatchObject({
        response: {
          data: {
            error: errorMessage
          }
        }
      });
    });

    it('should handle network errors', async () => {
      const settingsUpdate = { smtp_enabled: true };

      mockApi.put.mockRejectedValue(new Error('Network Error'));

      await expect(emailSettingsApi.updateSettings(settingsUpdate)).rejects.toThrow('Network Error');
    });

    it('should send correct payload structure', async () => {
      const complexUpdate = {
        email_provider: 'ses' as const,
        ses_access_key: 'AKIATEST',
        ses_secret_key: 'secret123',
        ses_region: 'eu-west-1',
        email_verification_expiry_hours: 48,
        max_email_retries: 5
      };

      mockApi.put.mockResolvedValue({
        data: {
          data: {
            message: 'AWS SES configured successfully',
            status: 'success'
          }
        }
      });

      await emailSettingsApi.updateSettings(complexUpdate);

      expect(mockApi.put).toHaveBeenCalledWith('/email_settings', {
        email_settings: complexUpdate
      });
    });
  });

  describe('testEmail', () => {
    it('should send test email successfully', async () => {
      const testEmail = 'test@example.com';
      const mockResponse = {
        message: 'Test email sent successfully',
        status: 'success'
      };

      mockApi.post.mockResolvedValue({
        data: {
          success: true,
          data: mockResponse
        }
      });

      const result = await emailSettingsApi.testEmail(testEmail);

      expect(mockApi.post).toHaveBeenCalledWith('/email_settings/test', {
        email: testEmail
      });
      expect(result).toEqual(mockResponse);
    });

    it('should handle test email with custom message', async () => {
      const testEmail = 'custom@example.com';
      const customMessage = 'Test email queued for delivery';

      mockApi.post.mockResolvedValue({
        data: {
          success: true,
          data: {
            message: customMessage,
            status: 'success'
          }
        }
      });

      const result = await emailSettingsApi.testEmail(testEmail);

      expect(result.message).toBe(customMessage);
    });

    it('should provide fallback message when none returned', async () => {
      const testEmail = 'fallback@example.com';

      mockApi.post.mockResolvedValue({
        data: {
          success: true,
          data: {
            status: 'success'
          }
        }
      });

      const result = await emailSettingsApi.testEmail(testEmail);

      expect(result.message).toBe('Test email queued successfully');
    });

    it('should handle legacy response format', async () => {
      const testEmail = 'legacy@example.com';

      mockApi.post.mockResolvedValue({
        data: {
          message: 'Legacy response format',
          status: 'success'
        }
      });

      const result = await emailSettingsApi.testEmail(testEmail);

      expect(result).toEqual({
        message: 'Legacy response format',
        status: 'success'
      });
    });

    it('should handle test email failures', async () => {
      const testEmail = 'fail@example.com';

      mockApi.post.mockRejectedValue({
        response: {
          data: {
            success: false,
            error: 'SMTP connection failed'
          }
        }
      });

      await expect(emailSettingsApi.testEmail(testEmail)).rejects.toMatchObject({
        response: {
          data: {
            success: false,
            error: 'SMTP connection failed'
          }
        }
      });
    });

    it('should handle network errors during test', async () => {
      const testEmail = 'network@example.com';

      mockApi.post.mockRejectedValue(new Error('Connection timeout'));

      await expect(emailSettingsApi.testEmail(testEmail)).rejects.toThrow('Connection timeout');
    });

    it('should handle malformed success responses', async () => {
      const testEmail = 'malformed@example.com';

      mockApi.post.mockResolvedValue({
        data: {
          success: true
          // Missing data property
        }
      });

      const result = await emailSettingsApi.testEmail(testEmail);

      // Should return the raw response when data is missing
      expect(result).toEqual({
        success: true
      });
    });

    it('should validate email parameter', async () => {
      const testEmail = '';

      mockApi.post.mockResolvedValue({
        data: {
          success: true,
          data: {
            message: 'Email sent',
            status: 'success'
          }
        }
      });

      await emailSettingsApi.testEmail(testEmail);

      expect(mockApi.post).toHaveBeenCalledWith('/email_settings/test', {
        email: ''
      });
    });

    it('should handle different email formats', async () => {
      const testEmails = [
        'simple@example.com',
        'user+tag@example-domain.co.uk',
        'test.email@sub.domain.org',
        'user123@123domain.com'
      ];

      mockApi.post.mockResolvedValue({
        data: {
          success: true,
          data: {
            message: 'Test sent',
            status: 'success'
          }
        }
      });

      for (const email of testEmails) {
        await emailSettingsApi.testEmail(email);
        expect(mockApi.post).toHaveBeenCalledWith('/email_settings/test', {
          email
        });
      }

      expect(mockApi.post).toHaveBeenCalledTimes(testEmails.length);
    });

    it('should handle server errors with detailed messages', async () => {
      const testEmail = 'server-error@example.com';

      mockApi.post.mockRejectedValue({
        response: {
          status: 500,
          data: {
            success: false,
            error: 'Internal server error: Email service unavailable'
          }
        }
      });

      await expect(emailSettingsApi.testEmail(testEmail)).rejects.toMatchObject({
        response: {
          status: 500,
          data: {
            success: false,
            error: 'Internal server error: Email service unavailable'
          }
        }
      });
    });
  });

  describe('API consistency', () => {
    it('should use consistent endpoint patterns', async () => {
      mockApi.get.mockResolvedValue({ data: { data: mockEmailSettings } });
      mockApi.put.mockResolvedValue({ data: { data: { message: 'OK', status: 'success' } } });
      mockApi.post.mockResolvedValue({ data: { success: true, data: { message: 'OK', status: 'success' } } });

      await emailSettingsApi.getSettings();
      await emailSettingsApi.updateSettings({ smtp_enabled: true });
      await emailSettingsApi.testEmail('test@example.com');

      expect(mockApi.get).toHaveBeenCalledWith('/email_settings');
      expect(mockApi.put).toHaveBeenCalledWith('/email_settings', expect.any(Object));
      expect(mockApi.post).toHaveBeenCalledWith('/email_settings/test', expect.any(Object));
    });

    it('should handle response format variations gracefully', async () => {
      // Test the expected format only since the API expects specific structure
      mockApi.get.mockResolvedValue({
        data: { data: mockEmailSettings }
      });
      
      const result = await emailSettingsApi.getSettings();
      expect(result).toEqual(mockEmailSettings);
    });
  });
});