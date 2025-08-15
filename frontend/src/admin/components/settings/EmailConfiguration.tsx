import React, { useState, useEffect, useCallback } from 'react';
import { Mail, Send, CheckCircle, AlertCircle, Settings, Eye, EyeOff } from 'lucide-react';
import { LoadingSpinner } from '../../../components/ui/LoadingSpinner';
import { useNotification } from '../../../hooks/useNotification';
import { emailSettingsApi, EmailSettings } from '../../../services/emailSettingsApi';

export const EmailConfiguration: React.FC = () => {
  const [emailSettings, setEmailSettings] = useState<EmailSettings>({
    email_provider: 'smtp',
    smtp_enabled: false,
    smtp_host: '',
    smtp_port: 587,
    smtp_username: '',
    smtp_password: '',
    smtp_encryption: 'tls',
    smtp_authentication: true,
    smtp_from_address: '',
    smtp_from_name: '',
    smtp_domain: '',
    sendgrid_api_key: '',
    ses_access_key: '',
    ses_secret_key: '',
    ses_region: 'us-east-1',
    mailgun_api_key: '',
    mailgun_domain: '',
    email_verification_expiry_hours: 24,
    password_reset_expiry_hours: 2,
    max_email_retries: 3,
    email_retry_delay_seconds: 60
  });
  
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [hasChanges, setHasChanges] = useState(false);
  const [originalSettings, setOriginalSettings] = useState<EmailSettings | null>(null);
  const [showPassword, setShowPassword] = useState(false);
  const [testEmail, setTestEmail] = useState('');
  const [testing, setTesting] = useState(false);
  
  const { showNotification } = useNotification();

  const loadSettings = useCallback(async () => {
    try {
      setLoading(true);
      const settings = await emailSettingsApi.getSettings();
      // Ensure email_provider defaults to 'smtp' if not set
      const normalizedSettings = {
        ...settings,
        email_provider: settings.email_provider || 'smtp'
      };
      setEmailSettings(normalizedSettings);
      setOriginalSettings({ ...normalizedSettings });
      setHasChanges(false);
    } catch (error) {
      console.error('Failed to load email settings:', error);
      showNotification('Failed to load email settings', 'error');
    } finally {
      setLoading(false);
    }
  }, []); // Remove showNotification from dependencies to prevent refresh loop

  useEffect(() => {
    loadSettings();
  }, [loadSettings]);

  const handleChange = (field: keyof EmailSettings, value: string | boolean | number) => {
    setEmailSettings(prev => ({
      ...prev,
      [field]: value
    }));
    setHasChanges(true);
  };

  const handleSave = async () => {
    try {
      setSaving(true);
      await emailSettingsApi.updateSettings(emailSettings);
      setOriginalSettings({ ...emailSettings });
      setHasChanges(false);
      showNotification('Email settings updated successfully', 'success');
    } catch (error: any) {
      console.error('Failed to update email settings:', error);
      showNotification(
        error.response?.data?.error || 'Failed to update email settings',
        'error'
      );
    } finally {
      setSaving(false);
    }
  };

  const handleReset = () => {
    if (originalSettings) {
      setEmailSettings({ ...originalSettings });
      setHasChanges(false);
    }
  };

  const handleTestEmail = async () => {
    if (!testEmail) {
      showNotification('Please enter a test email address', 'error');
      return;
    }
    
    setTesting(true);
    try {
      const response = await emailSettingsApi.testEmail(testEmail);
      showNotification(response.message || `Test email sent to ${testEmail}`, 'success');
    } catch (error: any) {
      showNotification(
        error.response?.data?.error || 'Failed to send test email',
        'error'
      );
    } finally {
      setTesting(false);
    }
  };

  if (loading) {
    return (
      <div className="space-y-6">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="p-2 bg-theme-interactive-primary bg-opacity-10 rounded-lg">
              <Mail className="w-5 h-5 text-theme-interactive-primary" />
            </div>
            <div>
              <h2 className="text-xl font-semibold text-theme-primary">Email Server Configuration</h2>
              <p className="text-sm text-theme-secondary">Configure SMTP and email provider settings</p>
            </div>
          </div>
        </div>

        <div className="bg-theme-surface rounded-lg border border-theme p-6 space-y-6">
          {/* Email Provider Selection - Show during loading */}
          <div>
            <h3 className="text-lg font-medium text-theme-primary mb-4">Provider Settings</h3>
            <div className="mb-6">
              <label htmlFor="email_provider" className="block text-sm font-medium text-theme-primary mb-2">
                Email Provider
              </label>
              <select
                id="email_provider"
                value={emailSettings.email_provider}
                onChange={(e) => handleChange('email_provider', e.target.value)}
                disabled={loading}
                className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus disabled:opacity-50"
              >
                <option value="smtp">SMTP Server</option>
                <option value="sendgrid">SendGrid</option>
                <option value="ses">Amazon SES</option>
                <option value="mailgun">Mailgun</option>
              </select>
            </div>

            {/* SMTP Enable Toggle - Show during loading if SMTP is selected */}
            {emailSettings.email_provider === 'smtp' && (
              <div className="flex items-center justify-between p-4 bg-theme-background rounded-lg border border-theme">
                <div>
                  <span className="text-sm font-medium text-theme-primary">Enable SMTP Server</span>
                  <p className="text-xs text-theme-secondary mt-1">
                    Enable this to activate SMTP email delivery
                  </p>
                </div>
                <input
                  type="checkbox"
                  checked={emailSettings.smtp_enabled || false}
                  onChange={(e) => handleChange('smtp_enabled', e.target.checked)}
                  disabled={loading}
                  className="h-4 w-4 text-theme-interactive-primary border-theme rounded focus:ring-theme-interactive-primary disabled:opacity-50"
                />
              </div>
            )}
          </div>

          <div className="flex items-center justify-center py-8">
            <LoadingSpinner size="lg" />
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="p-2 bg-theme-interactive-primary bg-opacity-10 rounded-lg">
            <Mail className="w-5 h-5 text-theme-interactive-primary" />
          </div>
          <div>
            <h2 className="text-xl font-semibold text-theme-primary">Email Server Configuration</h2>
            <p className="text-sm text-theme-secondary">Configure SMTP and email provider settings</p>
          </div>
        </div>
        
        <div className="flex items-center gap-2">
          <button
            onClick={handleReset}
            disabled={!hasChanges || saving}
            className="px-3 py-2 text-sm bg-theme-background text-theme-primary rounded-md hover:bg-theme-surface transition-colors duration-200 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <Settings className="w-4 h-4 mr-1 inline" />
            Reset
          </button>
          <button
            onClick={handleSave}
            disabled={!hasChanges || saving}
            className="px-4 py-2 bg-theme-interactive-primary text-white rounded-md hover:bg-theme-interactive-primary-hover disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2 transition-colors duration-200"
          >
            {saving ? (
              <>
                <LoadingSpinner size="sm" />
                Saving...
              </>
            ) : (
              <>
                <CheckCircle className="w-4 h-4" />
                Save Changes
              </>
            )}
          </button>
        </div>
      </div>

      <div className="bg-theme-surface rounded-lg border border-theme p-6 space-y-6">
        {/* Email Provider Selection */}
        <div>
          <h3 className="text-lg font-medium text-theme-primary mb-4">Provider Settings</h3>
          <div className="mb-6">
            <label htmlFor="email_provider" className="block text-sm font-medium text-theme-primary mb-2">
              Email Provider
            </label>
            <select
              id="email_provider"
              value={emailSettings.email_provider}
              onChange={(e) => handleChange('email_provider', e.target.value)}
              className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
            >
              <option value="smtp">SMTP Server</option>
              <option value="sendgrid">SendGrid</option>
              <option value="ses">Amazon SES</option>
              <option value="mailgun">Mailgun</option>
            </select>
          </div>

          {/* SMTP Enable Toggle - Always show when SMTP Server is selected */}
          {emailSettings.email_provider === 'smtp' && (
            <div className="flex items-center justify-between p-4 bg-theme-background rounded-lg border border-theme">
              <div>
                <span className="text-sm font-medium text-theme-primary">Enable SMTP Server</span>
                <p className="text-xs text-theme-secondary mt-1">
                  Enable this to activate SMTP email delivery
                </p>
              </div>
              <input
                type="checkbox"
                checked={emailSettings.smtp_enabled || false}
                onChange={(e) => handleChange('smtp_enabled', e.target.checked)}
                className="h-4 w-4 text-theme-interactive-primary border-theme rounded focus:ring-theme-interactive-primary"
              />
            </div>
          )}
        </div>

        {/* SMTP Configuration */}
        {emailSettings.email_provider === 'smtp' && (
          <>
            <div className="border-t border-theme pt-6">
              <h3 className="text-lg font-medium text-theme-primary mb-4">SMTP Configuration</h3>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
                <div>
                  <label htmlFor="smtp_host" className="block text-sm font-medium text-theme-primary mb-2">
                    SMTP Host
                  </label>
                  <input
                    id="smtp_host"
                    type="text"
                    value={emailSettings.smtp_host}
                    onChange={(e) => handleChange('smtp_host', e.target.value)}
                    className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                    placeholder="smtp.gmail.com"
                    disabled={!emailSettings.smtp_enabled}
                  />
                </div>

                <div>
                  <label htmlFor="smtp_port" className="block text-sm font-medium text-theme-primary mb-2">
                    SMTP Port
                  </label>
                  <input
                    id="smtp_port"
                    type="number"
                    value={emailSettings.smtp_port}
                    onChange={(e) => handleChange('smtp_port', parseInt(e.target.value) || 587)}
                    className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                    disabled={!emailSettings.smtp_enabled}
                  />
                </div>

                <div>
                  <label htmlFor="smtp_encryption" className="block text-sm font-medium text-theme-primary mb-2">
                    Encryption
                  </label>
                  <select
                    id="smtp_encryption"
                    value={emailSettings.smtp_encryption}
                    onChange={(e) => handleChange('smtp_encryption', e.target.value)}
                    className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                    disabled={!emailSettings.smtp_enabled}
                  >
                    <option value="none">None</option>
                    <option value="tls">TLS/STARTTLS</option>
                    <option value="ssl">SSL</option>
                  </select>
                </div>

                <div className="flex items-center gap-4">
                  <input
                    type="checkbox"
                    id="smtp_authentication"
                    checked={emailSettings.smtp_authentication}
                    onChange={(e) => handleChange('smtp_authentication', e.target.checked)}
                    className="h-4 w-4 text-theme-interactive-primary border-theme rounded focus:ring-theme-interactive-primary"
                    disabled={!emailSettings.smtp_enabled}
                  />
                  <label htmlFor="smtp_authentication" className="text-sm font-medium text-theme-primary">
                    Require Authentication
                  </label>
                </div>

                {emailSettings.smtp_authentication && (
                  <>
                    <div>
                      <label htmlFor="smtp_username" className="block text-sm font-medium text-theme-primary mb-2">
                        Username
                      </label>
                      <input
                        id="smtp_username"
                        type="text"
                        value={emailSettings.smtp_username}
                        onChange={(e) => handleChange('smtp_username', e.target.value)}
                        className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                        disabled={!emailSettings.smtp_enabled}
                      />
                    </div>

                    <div>
                      <label htmlFor="smtp_password" className="block text-sm font-medium text-theme-primary mb-2">
                        Password
                      </label>
                      <div className="relative">
                        <input
                          id="smtp_password"
                          type={showPassword ? "text" : "password"}
                          value={emailSettings.smtp_password}
                          onChange={(e) => handleChange('smtp_password', e.target.value)}
                          className="w-full px-3 py-2 pr-10 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                          disabled={!emailSettings.smtp_enabled}
                        />
                        <button
                          type="button"
                          onClick={() => setShowPassword(!showPassword)}
                          className="absolute right-2 top-2.5 text-theme-secondary hover:text-theme-primary"
                        >
                          {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                        </button>
                      </div>
                    </div>
                  </>
                )}

                <div>
                  <label htmlFor="smtp_from_address" className="block text-sm font-medium text-theme-primary mb-2">
                    From Email Address
                  </label>
                  <input
                    id="smtp_from_address"
                    type="email"
                    value={emailSettings.smtp_from_address}
                    onChange={(e) => handleChange('smtp_from_address', e.target.value)}
                    className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                    placeholder="noreply@yourdomain.com"
                  />
                </div>

                <div>
                  <label htmlFor="smtp_from_name" className="block text-sm font-medium text-theme-primary mb-2">
                    From Display Name
                  </label>
                  <input
                    id="smtp_from_name"
                    type="text"
                    value={emailSettings.smtp_from_name}
                    onChange={(e) => handleChange('smtp_from_name', e.target.value)}
                    className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                    placeholder="Powernode Platform"
                  />
                </div>

                <div>
                  <label htmlFor="smtp_domain" className="block text-sm font-medium text-theme-primary mb-2">
                    SMTP Domain
                  </label>
                  <input
                    id="smtp_domain"
                    type="text"
                    value={emailSettings.smtp_domain}
                    onChange={(e) => handleChange('smtp_domain', e.target.value)}
                    className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                    placeholder="yourdomain.com"
                  />
                  <p className="text-xs text-theme-secondary mt-1">
                    Domain used for HELO/EHLO SMTP command
                  </p>
                </div>
              </div>
            </div>
          </>
        )}

        {/* SendGrid Configuration */}
        {emailSettings.email_provider === 'sendgrid' && (
          <div className="border-t border-theme pt-6">
            <h3 className="text-lg font-medium text-theme-primary mb-4">SendGrid Configuration</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div className="md:col-span-2">
                <label htmlFor="sendgrid_api_key" className="block text-sm font-medium text-theme-primary mb-2">
                  SendGrid API Key
                </label>
                <div className="relative">
                  <input
                    id="sendgrid_api_key"
                    type={showPassword ? "text" : "password"}
                    value={emailSettings.sendgrid_api_key}
                    onChange={(e) => handleChange('sendgrid_api_key', e.target.value)}
                    className="w-full px-3 py-2 pr-10 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                    placeholder="SG.xxxxxx"
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute right-2 top-2.5 text-theme-secondary hover:text-theme-primary"
                  >
                    {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                  </button>
                </div>
              </div>
            </div>
          </div>
        )}

        {/* Amazon SES Configuration */}
        {emailSettings.email_provider === 'ses' && (
          <div className="border-t border-theme pt-6">
            <h3 className="text-lg font-medium text-theme-primary mb-4">Amazon SES Configuration</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label htmlFor="ses_access_key" className="block text-sm font-medium text-theme-primary mb-2">
                  Access Key ID
                </label>
                <input
                  id="ses_access_key"
                  type="text"
                  value={emailSettings.ses_access_key}
                  onChange={(e) => handleChange('ses_access_key', e.target.value)}
                  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                  placeholder="AKIAXXXXXXXXXXXXXXXX"
                />
              </div>

              <div>
                <label htmlFor="ses_secret_key" className="block text-sm font-medium text-theme-primary mb-2">
                  Secret Access Key
                </label>
                <div className="relative">
                  <input
                    id="ses_secret_key"
                    type={showPassword ? "text" : "password"}
                    value={emailSettings.ses_secret_key}
                    onChange={(e) => handleChange('ses_secret_key', e.target.value)}
                    className="w-full px-3 py-2 pr-10 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                    placeholder="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute right-2 top-2.5 text-theme-secondary hover:text-theme-primary"
                  >
                    {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                  </button>
                </div>
              </div>

              <div>
                <label htmlFor="ses_region" className="block text-sm font-medium text-theme-primary mb-2">
                  AWS Region
                </label>
                <select
                  id="ses_region"
                  value={emailSettings.ses_region}
                  onChange={(e) => handleChange('ses_region', e.target.value)}
                  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                >
                  <option value="us-east-1">US East (N. Virginia)</option>
                  <option value="us-west-2">US West (Oregon)</option>
                  <option value="eu-west-1">Europe (Ireland)</option>
                </select>
              </div>
            </div>
          </div>
        )}

        {/* Mailgun Configuration */}
        {emailSettings.email_provider === 'mailgun' && (
          <div className="border-t border-theme pt-6">
            <h3 className="text-lg font-medium text-theme-primary mb-4">Mailgun Configuration</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label htmlFor="mailgun_api_key" className="block text-sm font-medium text-theme-primary mb-2">
                  Mailgun API Key
                </label>
                <div className="relative">
                  <input
                    id="mailgun_api_key"
                    type={showPassword ? "text" : "password"}
                    value={emailSettings.mailgun_api_key}
                    onChange={(e) => handleChange('mailgun_api_key', e.target.value)}
                    className="w-full px-3 py-2 pr-10 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                    placeholder="key-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute right-2 top-2.5 text-theme-secondary hover:text-theme-primary"
                  >
                    {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                  </button>
                </div>
              </div>

              <div>
                <label htmlFor="mailgun_domain" className="block text-sm font-medium text-theme-primary mb-2">
                  Mailgun Domain
                </label>
                <input
                  id="mailgun_domain"
                  type="text"
                  value={emailSettings.mailgun_domain}
                  onChange={(e) => handleChange('mailgun_domain', e.target.value)}
                  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                  placeholder="mg.yourdomain.com"
                />
              </div>
            </div>
          </div>
        )}

        {/* Email Behavior Settings */}
        <div className="border-t border-theme pt-6">
          <h3 className="text-lg font-medium text-theme-primary mb-4">Email Behavior Settings</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label htmlFor="email_verification_expiry_hours" className="block text-sm font-medium text-theme-primary mb-2">
                Email Verification Expiry (Hours)
              </label>
              <input
                id="email_verification_expiry_hours"
                type="number"
                min="1"
                max="168"
                value={emailSettings.email_verification_expiry_hours}
                onChange={(e) => handleChange('email_verification_expiry_hours', parseInt(e.target.value) || 24)}
                className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
              />
            </div>

            <div>
              <label htmlFor="password_reset_expiry_hours" className="block text-sm font-medium text-theme-primary mb-2">
                Password Reset Expiry (Hours)
              </label>
              <input
                id="password_reset_expiry_hours"
                type="number"
                min="1"
                max="24"
                value={emailSettings.password_reset_expiry_hours}
                onChange={(e) => handleChange('password_reset_expiry_hours', parseInt(e.target.value) || 2)}
                className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
              />
            </div>

            <div>
              <label htmlFor="max_email_retries" className="block text-sm font-medium text-theme-primary mb-2">
                Maximum Email Retries
              </label>
              <input
                id="max_email_retries"
                type="number"
                min="1"
                max="10"
                value={emailSettings.max_email_retries}
                onChange={(e) => handleChange('max_email_retries', parseInt(e.target.value) || 3)}
                className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
              />
            </div>

            <div>
              <label htmlFor="email_retry_delay_seconds" className="block text-sm font-medium text-theme-primary mb-2">
                Retry Delay (Seconds)
              </label>
              <input
                id="email_retry_delay_seconds"
                type="number"
                min="30"
                max="3600"
                value={emailSettings.email_retry_delay_seconds}
                onChange={(e) => handleChange('email_retry_delay_seconds', parseInt(e.target.value) || 60)}
                className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
              />
            </div>
          </div>
        </div>

        {/* Test Email Section */}
        <div className="border-t border-theme pt-6">
          <h3 className="text-lg font-medium text-theme-primary mb-4">Test Email Configuration</h3>
          <div className="flex items-center gap-4">
            <input
              type="email"
              value={testEmail}
              onChange={(e) => setTestEmail(e.target.value)}
              placeholder="Enter test email address"
              className="flex-1 px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
            />
            <button
              onClick={handleTestEmail}
              disabled={testing || !testEmail}
              className="px-4 py-2 bg-theme-interactive-secondary text-white rounded-md hover:bg-theme-interactive-secondary-hover disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
            >
              {testing ? (
                <>
                  <LoadingSpinner size="sm" />
                  Sending...
                </>
              ) : (
                <>
                  <Send className="w-4 h-4" />
                  Send Test
                </>
              )}
            </button>
          </div>
        </div>

        {/* Email Status Indicators */}
        <div className="border-t border-theme pt-6">
          <h3 className="text-lg font-medium text-theme-primary mb-4">Configuration Status</h3>
          <div className="flex items-center gap-3 p-3 bg-theme-background rounded-lg border border-theme">
            {emailSettings.smtp_enabled || emailSettings.email_provider !== 'smtp' ? (
              <CheckCircle className="w-4 h-4 text-theme-success" />
            ) : (
              <AlertCircle className="w-4 h-4 text-theme-warning" />
            )}
            <span className="text-sm text-theme-primary">
              Email service: {emailSettings.smtp_enabled || emailSettings.email_provider !== 'smtp' ? 'Configured' : 'Not configured'}
            </span>
          </div>
        </div>
      </div>
    </div>
  );
};

export default EmailConfiguration;