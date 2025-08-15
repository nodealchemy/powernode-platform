import React, { useState, useEffect } from 'react';
import { adminApi, SystemSettings } from '../../services/adminApi';
import { useNotification } from '../../hooks/useNotification';
import { Shield, Lock, Users, Clock, Settings, Eye, EyeOff } from 'lucide-react';

export const AdminSettingsSecurityTabPage: React.FC = () => {
  const { showNotification } = useNotification();
  const [systemSettings, setSystemSettings] = useState<Partial<SystemSettings>>({});
  const [saving, setSaving] = useState(false);
  const [expandedSections, setExpandedSections] = useState<{[key: string]: boolean}>({
    authentication: true,
    access: true,
    rateLimiting: false,
    advanced: false
  });

  useEffect(() => {
    loadSettings();
  }, []);

  const loadSettings = async () => {
    try {
      const response = await adminApi.getAdminSettings();
      setSystemSettings(response.settings_summary || {});
    } catch (error) {
      console.error('Failed to load settings:', error);
      showNotification('Failed to load security settings', 'error');
    }
  };

  const handleSettingsUpdate = async (newSettings: Partial<SystemSettings>) => {
    try {
      setSaving(true);
      await adminApi.updateAdminSettings(newSettings);
      setSystemSettings(prev => ({ ...prev, ...newSettings }));
      showNotification('Security settings updated successfully', 'success');
    } catch (error) {
      console.error('Failed to update settings:', error);
      showNotification('Failed to update security settings', 'error');
    } finally {
      setSaving(false);
    }
  };

  const handleRateLimitingUpdate = async (rateLimitingSettings: Partial<NonNullable<SystemSettings['rate_limiting']>>) => {
    const updatedRateLimit = {
      ...systemSettings.rate_limiting,
      ...rateLimitingSettings
    };
    await handleSettingsUpdate({ rate_limiting: updatedRateLimit });
  };

  const toggleSection = (section: string) => {
    // Validate section name to prevent object injection
    const validSections = ['authentication', 'access', 'rateLimiting', 'advanced'];
    if (!validSections.includes(section)) return;
    
    setExpandedSections(prev => {
      const currentValue = prev[section as keyof typeof prev];
      return {
        ...prev,
        [section]: !currentValue
      };
    });
  };

  const SectionHeader: React.FC<{
    title: string;
    description: string;
    icon: React.ReactNode;
    section: string;
  }> = ({ title, description, icon, section }) => (
    <button
      onClick={() => toggleSection(section)}
      className="w-full flex items-center justify-between p-4 bg-theme-surface border border-theme rounded-lg hover:bg-theme-surface-hover transition-colors"
    >
      <div className="flex items-center space-x-3">
        <div className="text-theme-primary">{icon}</div>
        <div className="text-left">
          <h3 className="font-semibold text-theme-primary">{title}</h3>
          <p className="text-sm text-theme-secondary">{description}</p>
        </div>
      </div>
      <div className="text-theme-secondary">
        {expandedSections[section as keyof typeof expandedSections] ? <EyeOff className="h-5 w-5" /> : <Eye className="h-5 w-5" />}
      </div>
    </button>
  );

  const ToggleSwitch: React.FC<{
    checked: boolean;
    onChange: (checked: boolean) => void;
    disabled?: boolean;
  }> = ({ checked, onChange, disabled = false }) => (
    <label className="relative inline-flex items-center cursor-pointer">
      <input
        type="checkbox"
        checked={checked}
        onChange={(e) => onChange(e.target.checked)}
        disabled={disabled}
        className="sr-only peer"
      />
      <div className="w-11 h-6 bg-theme-surface-secondary rounded-full peer peer-disabled:opacity-50 peer-checked:after:translate-x-full peer-checked:after:border-theme-inverse after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-theme-inverse after:rounded-full after:h-5 after:w-5 after:transition-all peer-checked:bg-theme-interactive-primary"></div>
    </label>
  );

  return (
    <div className="space-y-6">
      {/* Authentication & Passwords Section */}
      <div className="space-y-4">
        <SectionHeader
          title="Authentication & Passwords"
          description="Configure password requirements and authentication security"
          icon={<Lock className="h-6 w-6" />}
          section="authentication"
        />
        
        {expandedSections.authentication && (
          <div className="bg-theme-surface rounded-lg border border-theme p-6 space-y-6">
            {/* Password Complexity */}
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-3">
                Password Complexity Level
              </label>
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                {(['low', 'medium', 'high'] as const).map((level) => (
                  <label key={level} className="relative">
                    <input
                      type="radio"
                      name="password_complexity"
                      value={level}
                      checked={systemSettings.password_complexity_level === level}
                      onChange={() => handleSettingsUpdate({ password_complexity_level: level })}
                      disabled={saving}
                      className="sr-only peer"
                    />
                    <div className="p-4 border border-theme rounded-lg cursor-pointer peer-checked:border-theme-interactive-primary peer-checked:bg-theme-interactive-primary/10 hover:bg-theme-surface-hover">
                      <div className="font-medium text-theme-primary capitalize">{level}</div>
                      <div className="text-sm text-theme-secondary mt-1">
                        {level === 'low' && '8+ characters'}
                        {level === 'medium' && '8+ chars, mixed case'}
                        {level === 'high' && '12+ chars, mixed case, numbers, symbols'}
                      </div>
                    </div>
                  </label>
                ))}
              </div>
            </div>

            {/* Session Security */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Session Timeout (minutes)
                </label>
                <input
                  type="number"
                  min="5"
                  max="1440"
                  value={systemSettings.session_timeout_minutes || 60}
                  onChange={(e) => handleSettingsUpdate({ session_timeout_minutes: parseInt(e.target.value) })}
                  disabled={saving}
                  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                />
                <p className="text-xs text-theme-secondary mt-1">Auto-logout inactive users</p>
              </div>

              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Max Failed Login Attempts
                </label>
                <input
                  type="number"
                  min="3"
                  max="10"
                  value={systemSettings.max_failed_login_attempts || 5}
                  onChange={(e) => handleSettingsUpdate({ max_failed_login_attempts: parseInt(e.target.value) })}
                  disabled={saving}
                  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                />
                <p className="text-xs text-theme-secondary mt-1">Before account lockout</p>
              </div>
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Account Lockout Duration (minutes)
              </label>
              <input
                type="number"
                min="5"
                max="1440"
                value={systemSettings.account_lockout_duration || 30}
                onChange={(e) => handleSettingsUpdate({ account_lockout_duration: parseInt(e.target.value) })}
                disabled={saving}
                className="w-full max-w-xs px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
              />
              <p className="text-xs text-theme-secondary mt-1">How long accounts remain locked</p>
            </div>
          </div>
        )}
      </div>

      {/* Access Control Section */}
      <div className="space-y-4">
        <SectionHeader
          title="Access Control"
          description="Control user registration and access to the platform"
          icon={<Users className="h-6 w-6" />}
          section="access"
        />
        
        {expandedSections.access && (
          <div className="bg-theme-surface rounded-lg border border-theme p-6 space-y-6">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div className="flex items-center justify-between">
                <div>
                  <p className="font-medium text-theme-primary">Maintenance Mode</p>
                  <p className="text-sm text-theme-secondary">Enable maintenance mode for system updates</p>
                </div>
                <ToggleSwitch
                  checked={systemSettings.maintenance_mode || false}
                  onChange={(checked) => handleSettingsUpdate({ maintenance_mode: checked })}
                  disabled={saving}
                />
              </div>
              
              <div className="flex items-center justify-between">
                <div>
                  <p className="font-medium text-theme-primary">User Registration</p>
                  <p className="text-sm text-theme-secondary">Allow new users to register accounts</p>
                </div>
                <ToggleSwitch
                  checked={systemSettings.registration_enabled || false}
                  onChange={(checked) => handleSettingsUpdate({ registration_enabled: checked })}
                  disabled={saving}
                />
              </div>
              
              <div className="flex items-center justify-between">
                <div>
                  <p className="font-medium text-theme-primary">Email Verification</p>
                  <p className="text-sm text-theme-secondary">Require email verification for new accounts</p>
                </div>
                <ToggleSwitch
                  checked={systemSettings.email_verification_required || false}
                  onChange={(checked) => handleSettingsUpdate({ email_verification_required: checked })}
                  disabled={saving}
                />
              </div>
              
              <div className="flex items-center justify-between">
                <div>
                  <p className="font-medium text-theme-primary">Account Deletion</p>
                  <p className="text-sm text-theme-secondary">Allow users to delete their own accounts</p>
                </div>
                <ToggleSwitch
                  checked={systemSettings.allow_account_deletion || false}
                  onChange={(checked) => handleSettingsUpdate({ allow_account_deletion: checked })}
                  disabled={saving}
                />
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Rate Limiting Section */}
      <div className="space-y-4">
        <SectionHeader
          title="Rate Limiting"
          description="Configure API and action rate limits to prevent abuse"
          icon={<Clock className="h-6 w-6" />}
          section="rateLimiting"
        />
        
        {expandedSections.rateLimiting && (
          <div className="bg-theme-surface rounded-lg border border-theme p-6 space-y-6">
            <div className="flex items-center justify-between mb-6">
              <div>
                <p className="font-medium text-theme-primary">Enable Rate Limiting</p>
                <p className="text-sm text-theme-secondary">Protect against abuse and excessive requests</p>
              </div>
              <ToggleSwitch
                checked={systemSettings.rate_limiting?.enabled || false}
                onChange={(checked) => handleRateLimitingUpdate({ enabled: checked })}
                disabled={saving}
              />
            </div>

            {systemSettings.rate_limiting?.enabled && (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    API Requests/Minute
                  </label>
                  <input
                    type="number"
                    min="10"
                    max="1000"
                    value={systemSettings.rate_limiting?.api_requests_per_minute || 60}
                    onChange={(e) => handleRateLimitingUpdate({ api_requests_per_minute: parseInt(e.target.value) })}
                    disabled={saving}
                    className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    Login Attempts/Hour
                  </label>
                  <input
                    type="number"
                    min="5"
                    max="100"
                    value={systemSettings.rate_limiting?.login_attempts_per_hour || 20}
                    onChange={(e) => handleRateLimitingUpdate({ login_attempts_per_hour: parseInt(e.target.value) })}
                    disabled={saving}
                    className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    Registration Attempts/Hour
                  </label>
                  <input
                    type="number"
                    min="1"
                    max="50"
                    value={systemSettings.rate_limiting?.registration_attempts_per_hour || 10}
                    onChange={(e) => handleRateLimitingUpdate({ registration_attempts_per_hour: parseInt(e.target.value) })}
                    disabled={saving}
                    className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    Password Reset/Hour
                  </label>
                  <input
                    type="number"
                    min="1"
                    max="20"
                    value={systemSettings.rate_limiting?.password_reset_attempts_per_hour || 5}
                    onChange={(e) => handleRateLimitingUpdate({ password_reset_attempts_per_hour: parseInt(e.target.value) })}
                    disabled={saving}
                    className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    Email Verification/Hour
                  </label>
                  <input
                    type="number"
                    min="1"
                    max="20"
                    value={systemSettings.rate_limiting?.email_verification_attempts_per_hour || 5}
                    onChange={(e) => handleRateLimitingUpdate({ email_verification_attempts_per_hour: parseInt(e.target.value) })}
                    disabled={saving}
                    className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                  />
                </div>

                <div>
                  <label className="block text-sm font-medium text-theme-primary mb-2">
                    Webhook Requests/Minute
                  </label>
                  <input
                    type="number"
                    min="5"
                    max="500"
                    value={systemSettings.rate_limiting?.webhook_requests_per_minute || 30}
                    onChange={(e) => handleRateLimitingUpdate({ webhook_requests_per_minute: parseInt(e.target.value) })}
                    disabled={saving}
                    className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                  />
                </div>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Advanced Security Section */}
      <div className="space-y-4">
        <SectionHeader
          title="Advanced Security"
          description="Advanced security features and monitoring"
          icon={<Settings className="h-6 w-6" />}
          section="advanced"
        />
        
        {expandedSections.advanced && (
          <div className="bg-theme-surface rounded-lg border border-theme p-6 space-y-6">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Trial Period (days)
                </label>
                <input
                  type="number"
                  min="0"
                  max="365"
                  value={systemSettings.trial_period_days || 14}
                  onChange={(e) => handleSettingsUpdate({ trial_period_days: parseInt(e.target.value) })}
                  disabled={saving}
                  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                />
                <p className="text-xs text-theme-secondary mt-1">Default trial period for new accounts</p>
              </div>

              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Payment Retry Attempts
                </label>
                <input
                  type="number"
                  min="1"
                  max="10"
                  value={systemSettings.payment_retry_attempts || 3}
                  onChange={(e) => handleSettingsUpdate({ payment_retry_attempts: parseInt(e.target.value) })}
                  disabled={saving}
                  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                />
                <p className="text-xs text-theme-secondary mt-1">Automatic payment retry attempts</p>
              </div>

              <div>
                <label className="block text-sm font-medium text-theme-primary mb-2">
                  Webhook Timeout (seconds)
                </label>
                <input
                  type="number"
                  min="5"
                  max="60"
                  value={systemSettings.webhook_timeout_seconds || 30}
                  onChange={(e) => handleSettingsUpdate({ webhook_timeout_seconds: parseInt(e.target.value) })}
                  disabled={saving}
                  className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
                />
                <p className="text-xs text-theme-secondary mt-1">Webhook request timeout</p>
              </div>
            </div>

            {/* Security Status Indicators */}
            <div className="border-t border-theme pt-6">
              <h4 className="font-medium text-theme-primary mb-4">Security Status</h4>
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div className="flex items-center space-x-3 p-3 bg-theme-background rounded-lg">
                  <Shield className="h-5 w-5 text-theme-success" />
                  <div>
                    <div className="text-sm font-medium text-theme-primary">Authentication</div>
                    <div className="text-xs text-theme-success">Secured</div>
                  </div>
                </div>
                <div className="flex items-center space-x-3 p-3 bg-theme-background rounded-lg">
                  <Lock className="h-5 w-5 text-theme-success" />
                  <div>
                    <div className="text-sm font-medium text-theme-primary">Rate Limiting</div>
                    <div className="text-xs text-theme-success">
                      {systemSettings.rate_limiting?.enabled ? 'Enabled' : 'Disabled'}
                    </div>
                  </div>
                </div>
                <div className="flex items-center space-x-3 p-3 bg-theme-background rounded-lg">
                  <Users className="h-5 w-5 text-theme-success" />
                  <div>
                    <div className="text-sm font-medium text-theme-primary">Access Control</div>
                    <div className="text-xs text-theme-success">Configured</div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Save Button */}
      {saving && (
        <div className="bg-theme-surface rounded-lg border border-theme p-4 text-center">
          <div className="flex items-center justify-center space-x-2">
            <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-theme-interactive-primary"></div>
            <span className="text-theme-secondary">Updating security settings...</span>
          </div>
        </div>
      )}
    </div>
  );
};

export default AdminSettingsSecurityTabPage;