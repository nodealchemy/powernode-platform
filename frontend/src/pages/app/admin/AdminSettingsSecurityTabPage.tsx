import React, { useState, useEffect } from 'react';
import { useSelector } from 'react-redux';
import { Navigate } from 'react-router-dom';
import { adminSettingsApi, AdminSettings } from '@/features/admin/services/adminSettingsApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { ToggleSwitch, SettingsCard } from '@/features/admin/components/settings/SettingsComponents';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { Shield, Lock, Users, Clock, Settings, AlertTriangle } from 'lucide-react';
import { RootState } from '@/shared/services';
import { hasPermissions } from '@/shared/utils/permissionUtils';

export const AdminSettingsSecurityTabPage: React.FC = () => {
  const { user } = useSelector((state: RootState) => state.auth);
  const { showNotification } = useNotifications();
  const [systemSettings, setSystemSettings] = useState<Partial<AdminSettings>>({});
  const [saving, setSaving] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Check if user has security settings permission
  const canManageSecurity = hasPermissions(user, ['admin.settings.security']);

  const [securityScores, setSecurityScores] = useState({
    overall: 85,
    authentication: 90,
    access: 80,
    rateLimiting: 75,
    advanced: 90
  });
  const [expandedSections, setExpandedSections] = useState<{[key: string]: boolean}>({
    authentication: true,
    access: true,
    rateLimiting: false,
    advanced: false,
    audit: false
  });

  useEffect(() => {
    if (canManageSecurity) {
      loadSettings();
    }
  }, [canManageSecurity]);

  // Redirect if user doesn't have permission
  if (!canManageSecurity) {
    return <Navigate to="/app/admin/settings" replace />;
  }

  const loadSettings = async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await adminSettingsApi.getOverview();
      const settingsSummary = response.data?.settings_summary || {};
      setSystemSettings(settingsSummary);

      // Calculate security scores based on current settings
      calculateSecurityScores(settingsSummary);
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Failed to load security settings');
      showNotification('Failed to load security settings', 'error');
    } finally {
      setLoading(false);
    }
  };

  const calculateSecurityScores = (settings: Partial<AdminSettings>) => {
    let authScore = 60;
    if (settings.password_complexity_level === 'high') authScore += 30;
    else if (settings.password_complexity_level === 'medium') authScore += 20;
    else if (settings.password_complexity_level === 'low') authScore += 10;
    
    let accessScore = settings.email_verification_required ? 80 : 60;
    if (settings.maintenance_mode) accessScore += 10;
    
    const rateScore = settings.rate_limiting?.enabled ? 80 : 40;
    
    const avgScore = Math.round((authScore + accessScore + rateScore) / 3);
    
    setSecurityScores({
      overall: avgScore,
      authentication: authScore,
      access: accessScore,
      rateLimiting: rateScore,
      advanced: 90
    });
  };

  const handleSettingsUpdate = async (newSettings: Partial<AdminSettings>) => {
    try {
      setSaving(true);
      await adminSettingsApi.updateSettings(newSettings);
      const updatedSettings = { ...systemSettings, ...newSettings };
      setSystemSettings(updatedSettings);
      calculateSecurityScores(updatedSettings);
      showNotification('Security settings updated successfully', 'success');
    } catch (_error) {
      showNotification('Failed to update security settings', 'error');
    } finally {
      setSaving(false);
    }
  };

  const handleRateLimitingUpdate = async (rateLimitingSettings: Partial<NonNullable<AdminSettings['rate_limiting']>>) => {
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


  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <LoadingSpinner size="lg" message="Loading security settings..." />
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-theme-surface rounded-lg border border-theme p-6">
        <div className="text-center">
          <div className="text-6xl mb-4">🔒</div>
          <h3 className="text-lg font-medium text-theme-primary mb-2">Error Loading Security Settings</h3>
          <p className="text-theme-secondary mb-4">{error}</p>
          <button 
            onClick={loadSettings}
            className="btn-theme btn-theme-primary"
          >
            Try Again
          </button>
        </div>
      </div>
    );
  }

  const getScoreColor = (score: number) => {
    if (score >= 90) return 'text-theme-success';
    if (score >= 70) return 'text-theme-warning';
    return 'text-theme-error';
  };

  const getScoreBgColor = (score: number) => {
    if (score >= 90) return 'bg-theme-success-background';
    if (score >= 70) return 'bg-theme-warning-background';
    return 'bg-theme-error-background';
  };

  return (
    <div className="space-y-6">
      {/* Security Overview */}
      <SettingsCard
        title="Security Overview"
        description="Current security posture and recommendations"
        icon="🛡️"
      >
        <div className="space-y-6">
          {/* Overall Security Score */}
          <div className={`p-6 rounded-lg ${getScoreBgColor(securityScores.overall)} border border-theme`}>
            <div className="flex items-center justify-between">
              <div>
                <h3 className="text-lg font-semibold text-theme-primary">Overall Security Score</h3>
                <p className="text-sm text-theme-secondary">Based on current security configurations</p>
              </div>
              <div className="text-right">
                <div className={`text-3xl font-bold ${getScoreColor(securityScores.overall)}`}>
                  {securityScores.overall}%
                </div>
                <div className="text-sm text-theme-secondary">
                  {securityScores.overall >= 90 ? 'Excellent' :
                   securityScores.overall >= 70 ? 'Good' : 'Needs Improvement'}
                </div>
              </div>
            </div>
          </div>

          {/* Security Categories */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <div className="p-4 bg-theme-background rounded-lg border border-theme text-center">
              <Lock className="w-8 h-8 text-theme-interactive-primary mx-auto mb-2" />
              <div className={`text-xl font-bold ${getScoreColor(securityScores.authentication)}`}>
                {securityScores.authentication}%
              </div>
              <div className="text-sm text-theme-secondary">Authentication</div>
            </div>
            <div className="p-4 bg-theme-background rounded-lg border border-theme text-center">
              <Users className="w-8 h-8 text-theme-interactive-primary mx-auto mb-2" />
              <div className={`text-xl font-bold ${getScoreColor(securityScores.access)}`}>
                {securityScores.access}%
              </div>
              <div className="text-sm text-theme-secondary">Access Control</div>
            </div>
            <div className="p-4 bg-theme-background rounded-lg border border-theme text-center">
              <Clock className="w-8 h-8 text-theme-interactive-primary mx-auto mb-2" />
              <div className={`text-xl font-bold ${getScoreColor(securityScores.rateLimiting)}`}>
                {securityScores.rateLimiting}%
              </div>
              <div className="text-sm text-theme-secondary">Rate Limiting</div>
            </div>
            <div className="p-4 bg-theme-background rounded-lg border border-theme text-center">
              <Settings className="w-8 h-8 text-theme-interactive-primary mx-auto mb-2" />
              <div className={`text-xl font-bold ${getScoreColor(securityScores.advanced)}`}>
                {securityScores.advanced}%
              </div>
              <div className="text-sm text-theme-secondary">Advanced</div>
            </div>
          </div>

          {/* Quick Security Recommendations */}
          <div className="p-4 bg-theme-info-background border border-theme-info rounded-lg">
            <h4 className="flex items-center gap-2 font-medium text-theme-info mb-2">
              <AlertTriangle className="w-5 h-5" />
              Security Recommendations
            </h4>
            <ul className="space-y-1 text-sm text-theme-info">
              {!systemSettings.rate_limiting?.enabled && (
                <li>• Enable rate limiting to protect against abuse</li>
              )}
              {systemSettings.password_complexity_level !== 'high' && (
                <li>• Set password complexity to high for better security</li>
              )}
              {!systemSettings.email_verification_required && (
                <li>• Enable email verification for new accounts</li>
              )}
              {securityScores.overall >= 90 && (
                <li className="text-theme-success">• Your security configuration looks excellent!</li>
              )}
            </ul>
          </div>
        </div>
      </SettingsCard>
      {/* Authentication & Passwords Section */}
      {expandedSections.authentication && (
        <SettingsCard
          title="Authentication & Passwords"
          description="Configure password requirements and authentication security"
          icon="🔐"
        >
          <div className="space-y-6">
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
        </SettingsCard>
      )}

      {/* Access Control Section */}
      {expandedSections.access && (
        <SettingsCard
          title="Access Control"
          description="Control user registration and access to the platform"
          icon="👥"
        >
          <div className="space-y-6">
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
                  variant="primary"
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
                  variant="primary"
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
                  variant="primary"
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
                  variant="primary"
                />
              </div>
            </div>
          </div>
        </SettingsCard>
      )}

      {/* Rate Limiting Section */}
      {expandedSections.rateLimiting && (
        <SettingsCard
          title="Rate Limiting"
          description="Configure API and action rate limits to prevent abuse"
          icon="⏰"
        >
          <div className="space-y-6">
            <div className="flex items-center justify-between mb-6">
              <div>
                <p className="font-medium text-theme-primary">Enable Rate Limiting</p>
                <p className="text-sm text-theme-secondary">Protect against abuse and excessive requests</p>
              </div>
              <ToggleSwitch
                checked={systemSettings.rate_limiting?.enabled || false}
                onChange={(checked) => handleRateLimitingUpdate({ enabled: checked })}
                disabled={saving}
                variant="primary"
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
        </SettingsCard>
      )}

      {/* Advanced Security Section */}
      {expandedSections.advanced && (
        <SettingsCard
          title="Advanced Security"
          description="Advanced security features and monitoring"
          icon="⚙️"
        >
          <div className="space-y-6">
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
        </SettingsCard>
      )}

      {/* Section Toggle Controls */}
      <SettingsCard
        title="Security Sections"
        description="Show or hide security configuration sections"
        icon="👁️"
      >
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <button
            onClick={() => toggleSection('authentication')}
            className={`p-3 rounded-lg border text-center transition-colors ${
              expandedSections.authentication 
                ? 'bg-theme-interactive-primary text-theme-on-primary border-theme-interactive-primary' 
                : 'bg-theme-background border-theme hover:bg-theme-surface-hover'
            }`}
          >
            <Lock className="w-5 h-5 mx-auto mb-1" />
            <div className="text-sm font-medium">Authentication</div>
          </button>
          <button
            onClick={() => toggleSection('access')}
            className={`p-3 rounded-lg border text-center transition-colors ${
              expandedSections.access 
                ? 'bg-theme-interactive-primary text-theme-on-primary border-theme-interactive-primary' 
                : 'bg-theme-background border-theme hover:bg-theme-surface-hover'
            }`}
          >
            <Users className="w-5 h-5 mx-auto mb-1" />
            <div className="text-sm font-medium">Access Control</div>
          </button>
          <button
            onClick={() => toggleSection('rateLimiting')}
            className={`p-3 rounded-lg border text-center transition-colors ${
              expandedSections.rateLimiting 
                ? 'bg-theme-interactive-primary text-theme-on-primary border-theme-interactive-primary' 
                : 'bg-theme-background border-theme hover:bg-theme-surface-hover'
            }`}
          >
            <Clock className="w-5 h-5 mx-auto mb-1" />
            <div className="text-sm font-medium">Rate Limiting</div>
          </button>
          <button
            onClick={() => toggleSection('advanced')}
            className={`p-3 rounded-lg border text-center transition-colors ${
              expandedSections.advanced 
                ? 'bg-theme-interactive-primary text-theme-on-primary border-theme-interactive-primary' 
                : 'bg-theme-background border-theme hover:bg-theme-surface-hover'
            }`}
          >
            <Settings className="w-5 h-5 mx-auto mb-1" />
            <div className="text-sm font-medium">Advanced</div>
          </button>
        </div>
      </SettingsCard>

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