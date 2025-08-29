import React, { useState, useEffect, useCallback } from 'react';
import { Shield, Key, Clock, AlertTriangle, CheckCircle, XCircle, RefreshCw } from 'lucide-react';
import { SettingsCard, ToggleSettingItem, FormField, Input, Select, SectionHeader } from './SettingsComponents';
import { useNotification } from '@/shared/hooks/useNotification';
import { adminSettingsApi } from '@/features/admin/services/adminSettingsApi';

interface SecurityConfig {
  csrf: {
    enabled: boolean;
    token_name: string;
    protection_method: string; // 'header' | 'parameter' | 'both'
    require_ssl: boolean;
  };
  jwt: {
    access_token_ttl: number; // minutes
    refresh_token_ttl: number; // hours  
    algorithm: string;
    blacklist_enabled: boolean;
    require_fresh_tokens_for_sensitive_operations: boolean;
  };
  authentication: {
    max_failed_attempts: number;
    lockout_duration: number; // minutes
    require_2fa_for_admin: boolean;
    session_timeout: number; // minutes
  };
  api_security: {
    rate_limiting_enabled: boolean;
    cors_enabled: boolean;
    allowed_origins: string[];
    require_api_key_for_write_operations: boolean;
  };
}

const defaultConfig: SecurityConfig = {
  csrf: {
    enabled: true,
    token_name: 'X-CSRF-Token',
    protection_method: 'header',
    require_ssl: true
  },
  jwt: {
    access_token_ttl: 15,
    refresh_token_ttl: 168, // 7 days
    algorithm: 'HS256',
    blacklist_enabled: true,
    require_fresh_tokens_for_sensitive_operations: true
  },
  authentication: {
    max_failed_attempts: 5,
    lockout_duration: 15,
    require_2fa_for_admin: false,
    session_timeout: 60
  },
  api_security: {
    rate_limiting_enabled: true,
    cors_enabled: true,
    allowed_origins: ['http://localhost:3001', 'https://app.powernode.com'],
    require_api_key_for_write_operations: false
  }
};

export const SecuritySettings: React.FC = () => {
  const [config, setConfig] = useState<SecurityConfig>(defaultConfig);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const { showNotification } = useNotification();

  const loadSecurityConfig = useCallback(async () => {
    setLoading(true);
    try {
      const response = await adminSettingsApi.getSecurityConfig();
      setConfig(response);
    } catch (error) {
      showNotification('Failed to load security configuration', 'error');
    } finally {
      setLoading(false);
    }
  }, [showNotification]);

  useEffect(() => {
    loadSecurityConfig();
  }, [loadSecurityConfig]);

  const saveSecurityConfig = async () => {
    setSaving(true);
    try {
      const response = await adminSettingsApi.updateSecurityConfig(config);
      showNotification(response.message || 'Security configuration updated successfully', 'success');
    } catch (error) {
      showNotification('Failed to save security configuration', 'error');
    } finally {
      setSaving(false);
    }
  };

  const updateConfig = (section: keyof SecurityConfig, key: string, value: string | number | boolean) => {
    setConfig(prev => ({
      ...prev,
      [section]: {
        ...prev[section],
        [key]: value
      }
    }));
  };

  const addAllowedOrigin = () => {
    const origin = prompt('Enter allowed origin URL:');
    if (origin && origin.trim()) {
      setConfig(prev => ({
        ...prev,
        api_security: {
          ...prev.api_security,
          allowed_origins: [...prev.api_security.allowed_origins, origin.trim()]
        }
      }));
    }
  };

  const removeAllowedOrigin = (index: number) => {
    setConfig(prev => ({
      ...prev,
      api_security: {
        ...prev.api_security,
        allowed_origins: prev.api_security.allowed_origins.filter((_, i) => i !== index)
      }
    }));
  };

  const testAuthenticationConfiguration = async () => {
    setLoading(true);
    showNotification('Testing authentication configuration...', 'info');
    try {
      const response = await adminSettingsApi.testSecurityConfiguration();
      if (response.overall_status === 'healthy') {
        showNotification('Security configuration test passed', 'success');
      } else {
        showNotification(`Security test issues detected: ${response.details.join(', ')}`, 'warning');
      }
    } catch (error) {
      showNotification('Failed to test security configuration', 'error');
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center p-12">
        <RefreshCw className="w-8 h-8 animate-spin text-theme-interactive-primary" />
        <span className="ml-3 text-theme-secondary">Loading security configuration...</span>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* CSRF Protection */}
      <SettingsCard 
        title="CSRF Protection" 
        description="Cross-Site Request Forgery protection for API endpoints"
        icon="🛡️"
      >
        <div className="space-y-4">
          <ToggleSettingItem
            title="Enable CSRF Protection"
            description="Protect API write operations from CSRF attacks. Recommended for production environments."
            checked={config.csrf.enabled}
            onChange={(checked) => updateConfig('csrf', 'enabled', checked)}
            variant="primary"
          />

          {config.csrf.enabled && (
            <div className="space-y-4 pl-4 border-l-2 border-theme-interactive-primary border-opacity-30">
              <FormField label="CSRF Token Header Name">
                <Input
                  value={config.csrf.token_name}
                  onChange={(e) => updateConfig('csrf', 'token_name', e.target.value)}
                  placeholder="X-CSRF-Token"
                />
              </FormField>

              <FormField label="Protection Method">
                <Select
                  value={config.csrf.protection_method}
                  onChange={(e) => updateConfig('csrf', 'protection_method', e.target.value as string)}
                >
                  <option value="header">Header Only</option>
                  <option value="parameter">Parameter Only</option>
                  <option value="both">Header and Parameter</option>
                </Select>
              </FormField>

              <ToggleSettingItem
                title="Require SSL for CSRF Token"
                description="Only accept CSRF tokens over secure HTTPS connections"
                checked={config.csrf.require_ssl}
                onChange={(checked) => updateConfig('csrf', 'require_ssl', checked)}
                variant="warning"
              />
            </div>
          )}
        </div>
      </SettingsCard>

      {/* JWT Configuration */}
      <SettingsCard 
        title="JWT Token Configuration" 
        description="JSON Web Token settings for authentication"
        icon="🔑"
      >
        <div className="space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <FormField label="Access Token TTL (minutes)">
              <Input
                type="number"
                min="5"
                max="1440"
                value={config.jwt.access_token_ttl}
                onChange={(e) => updateConfig('jwt', 'access_token_ttl', parseInt(e.target.value))}
              />
            </FormField>

            <FormField label="Refresh Token TTL (hours)">
              <Input
                type="number"
                min="24"
                max="8760"
                value={config.jwt.refresh_token_ttl}
                onChange={(e) => updateConfig('jwt', 'refresh_token_ttl', parseInt(e.target.value))}
              />
            </FormField>
          </div>

          <FormField label="JWT Algorithm">
            <Select
              value={config.jwt.algorithm}
              onChange={(e) => updateConfig('jwt', 'algorithm', e.target.value)}
            >
              <option value="HS256">HS256 (HMAC SHA-256)</option>
              <option value="HS384">HS384 (HMAC SHA-384)</option>
              <option value="HS512">HS512 (HMAC SHA-512)</option>
            </Select>
          </FormField>

          <ToggleSettingItem
            title="Enable Token Blacklisting"
            description="Track and reject blacklisted tokens for enhanced security"
            checked={config.jwt.blacklist_enabled}
            onChange={(checked) => updateConfig('jwt', 'blacklist_enabled', checked)}
            variant="success"
          />

          <ToggleSettingItem
            title="Require Fresh Tokens for Sensitive Operations"
            description="Force token refresh for sensitive operations like role changes"
            checked={config.jwt.require_fresh_tokens_for_sensitive_operations}
            onChange={(checked) => updateConfig('jwt', 'require_fresh_tokens_for_sensitive_operations', checked)}
            variant="warning"
          />
        </div>
      </SettingsCard>

      {/* Authentication Security */}
      <SettingsCard 
        title="Authentication Security" 
        description="Login security and account protection settings"
        icon="🔐"
      >
        <div className="space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <FormField label="Max Failed Login Attempts">
              <Input
                type="number"
                min="3"
                max="20"
                value={config.authentication.max_failed_attempts}
                onChange={(e) => updateConfig('authentication', 'max_failed_attempts', parseInt(e.target.value))}
              />
            </FormField>

            <FormField label="Account Lockout Duration (minutes)">
              <Input
                type="number"
                min="5"
                max="1440"
                value={config.authentication.lockout_duration}
                onChange={(e) => updateConfig('authentication', 'lockout_duration', parseInt(e.target.value))}
              />
            </FormField>
          </div>

          <FormField label="Session Timeout (minutes)">
            <Input
              type="number"
              min="15"
              max="480"
              value={config.authentication.session_timeout}
              onChange={(e) => updateConfig('authentication', 'session_timeout', parseInt(e.target.value))}
            />
          </FormField>

          <ToggleSettingItem
            title="Require 2FA for Admin Users"
            description="Force two-factor authentication for all admin accounts"
            checked={config.authentication.require_2fa_for_admin}
            onChange={(checked) => updateConfig('authentication', 'require_2fa_for_admin', checked)}
            variant="error"
          />
        </div>
      </SettingsCard>

      {/* API Security */}
      <SettingsCard 
        title="API Security" 
        description="API access control and security policies"
        icon="⚡"
      >
        <div className="space-y-4">
          <ToggleSettingItem
            title="Enable Rate Limiting"
            description="Limit API request rates to prevent abuse and DDoS attacks"
            checked={config.api_security.rate_limiting_enabled}
            onChange={(checked) => updateConfig('api_security', 'rate_limiting_enabled', checked)}
            variant="primary"
          />

          <ToggleSettingItem
            title="Enable CORS"
            description="Configure Cross-Origin Resource Sharing for browser access"
            checked={config.api_security.cors_enabled}
            onChange={(checked) => updateConfig('api_security', 'cors_enabled', checked)}
            variant="success"
          />

          {config.api_security.cors_enabled && (
            <div className="pl-4 border-l-2 border-theme-success border-opacity-30">
              <SectionHeader
                title="Allowed Origins"
                description="Domains permitted to access the API"
                action={
                  <button
                    onClick={addAllowedOrigin}
                    className="btn-primary btn-sm"
                  >
                    Add Origin
                  </button>
                }
              />

              <div className="space-y-2 mt-4">
                {config.api_security.allowed_origins.map((origin, index) => (
                  <div key={index} className="flex items-center justify-between p-3 bg-theme-background-secondary rounded-lg border border-theme">
                    <span className="text-sm font-mono text-theme-primary">{origin}</span>
                    <button
                      onClick={() => removeAllowedOrigin(index)}
                      className="text-theme-error hover:text-theme-error/80 transition-colors"
                    >
                      <XCircle className="w-4 h-4" />
                    </button>
                  </div>
                ))}

                {config.api_security.allowed_origins.length === 0 && (
                  <div className="p-4 text-center text-theme-secondary bg-theme-background-secondary rounded-lg border border-theme">
                    No allowed origins configured. Click "Add Origin" to add domains.
                  </div>
                )}
              </div>
            </div>
          )}

          <ToggleSettingItem
            title="Require API Keys for Write Operations"
            description="Require additional API key authentication for POST/PUT/PATCH operations"
            checked={config.api_security.require_api_key_for_write_operations}
            onChange={(checked) => updateConfig('api_security', 'require_api_key_for_write_operations', checked)}
            variant="warning"
          />
        </div>
      </SettingsCard>

      {/* Actions */}
      <div className="flex justify-between items-center p-6 bg-theme-background-secondary rounded-lg border border-theme">
        <div>
          <button
            onClick={testAuthenticationConfiguration}
            className="btn-secondary mr-3"
            disabled={saving}
          >
            <Shield className="w-4 h-4 mr-2" />
            Test Configuration
          </button>
        </div>

        <button
          onClick={saveSecurityConfig}
          disabled={saving}
          className="btn-primary"
        >
          {saving ? (
            <>
              <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
              Saving...
            </>
          ) : (
            <>
              <CheckCircle className="w-4 h-4 mr-2" />
              Save Security Settings
            </>
          )}
        </button>
      </div>

      {/* Security Status Summary */}
      <SettingsCard 
        title="Security Status" 
        description="Current security configuration overview"
        icon="📊"
      >
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <div className="p-4 rounded-lg border border-theme bg-theme-background">
            <div className="flex items-center justify-between">
              <span className="text-sm text-theme-secondary">CSRF Protection</span>
              {config.csrf.enabled ? (
                <CheckCircle className="w-5 h-5 text-theme-success" />
              ) : (
                <AlertTriangle className="w-5 h-5 text-theme-warning" />
              )}
            </div>
            <p className="text-lg font-semibold text-theme-primary mt-1">
              {config.csrf.enabled ? 'Enabled' : 'Disabled'}
            </p>
          </div>

          <div className="p-4 rounded-lg border border-theme bg-theme-background">
            <div className="flex items-center justify-between">
              <span className="text-sm text-theme-secondary">Token Expiry</span>
              <Clock className="w-5 h-5 text-theme-info" />
            </div>
            <p className="text-lg font-semibold text-theme-primary mt-1">
              {config.jwt.access_token_ttl}m
            </p>
          </div>

          <div className="p-4 rounded-lg border border-theme bg-theme-background">
            <div className="flex items-center justify-between">
              <span className="text-sm text-theme-secondary">Rate Limiting</span>
              {config.api_security.rate_limiting_enabled ? (
                <CheckCircle className="w-5 h-5 text-theme-success" />
              ) : (
                <XCircle className="w-5 h-5 text-theme-error" />
              )}
            </div>
            <p className="text-lg font-semibold text-theme-primary mt-1">
              {config.api_security.rate_limiting_enabled ? 'Active' : 'Inactive'}
            </p>
          </div>

          <div className="p-4 rounded-lg border border-theme bg-theme-background">
            <div className="flex items-center justify-between">
              <span className="text-sm text-theme-secondary">CORS Origins</span>
              <Key className="w-5 h-5 text-theme-interactive-primary" />
            </div>
            <p className="text-lg font-semibold text-theme-primary mt-1">
              {config.api_security.allowed_origins.length}
            </p>
          </div>
        </div>
      </SettingsCard>
    </div>
  );
};

export default SecuritySettings;