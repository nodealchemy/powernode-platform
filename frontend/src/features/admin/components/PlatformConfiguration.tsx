import React, { useState, useEffect, useCallback } from 'react';
import { Save, Settings, RefreshCw, Info } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { adminSettingsApi } from '@/features/admin/services/adminSettingsApi';

interface PlatformSettings {
  system_name: string;
  copyright_text: string;
  system_email: string;
  support_email: string;
  maintenance_mode: boolean;
  registration_enabled: boolean;
  require_email_verification: boolean;
  trial_period_days: number;
  session_timeout_minutes: number;
}

export const PlatformConfiguration: React.FC = () => {
  const [settings, setSettings] = useState<PlatformSettings>({
    system_name: 'Powernode Platform',
    copyright_text: '© {year} Everett C. Haimes III. All rights reserved.',
    system_email: '',
    support_email: '',
    maintenance_mode: false,
    registration_enabled: true,
    require_email_verification: true,
    trial_period_days: 14,
    session_timeout_minutes: 60
  });
  
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [hasChanges, setHasChanges] = useState(false);
  const [originalSettings, setOriginalSettings] = useState<PlatformSettings | null>(null);
  
  const { showNotification } = useNotifications();

  const loadSettings = useCallback(async () => {
    try {
      setLoading(true);
      const response = await adminSettingsApi.getOverview();

      // Extract platform settings from the response
      const settingsSummary = response.data?.settings_summary;
      const platformSettings: PlatformSettings = {
        system_name: settingsSummary?.system_name || 'Powernode Platform',
        copyright_text: settingsSummary?.copyright_text || '© {year} Everett C. Haimes III. All rights reserved.',
        system_email: settingsSummary?.system_email || '',
        support_email: settingsSummary?.support_email || '',
        maintenance_mode: settingsSummary?.maintenance_mode || false,
        registration_enabled: settingsSummary?.registration_enabled ?? true,
        require_email_verification: settingsSummary?.require_email_verification ?? true,
        trial_period_days: settingsSummary?.trial_period_days || 14,
        session_timeout_minutes: settingsSummary?.session_timeout_minutes || 60
      };
      
      setSettings(platformSettings);
      setOriginalSettings({ ...platformSettings });
      setHasChanges(false);
    } catch (error) {
      showNotification('Failed to load platform settings', 'error');
    } finally {
      setLoading(false);
    }
  }, [showNotification]);

  useEffect(() => {
    loadSettings();
  }, [loadSettings]);

  const handleChange = (field: keyof PlatformSettings, value: string | boolean | number) => {
    setSettings(prev => ({
      ...prev,
      [field]: value
    }));
    setHasChanges(true);
  };

  const handleSave = async () => {
    try {
      setSaving(true);
      
      await adminSettingsApi.updateSettings(settings);
      
      setOriginalSettings({ ...settings });
      setHasChanges(false);
      showNotification('Platform configuration updated successfully', 'success');
      
      // Clear cached copyright if it was updated
      if (originalSettings?.copyright_text !== settings.copyright_text) {
        localStorage.removeItem('powernode_copyright');
        // Trigger a page refresh to update the footer
        setTimeout(() => {
          window.location.reload();
        }, 1000);
      }
    } catch (error: unknown) {
      const errorMessage = error instanceof Error && 'response' in error &&
        typeof error.response === 'object' && error.response !== null &&
        'data' in error.response && typeof error.response.data === 'object' &&
        error.response.data !== null && 'error' in error.response.data
        ? String(error.response.data.error)
        : 'Failed to update platform configuration';
      showNotification(errorMessage, 'error');
    } finally {
      setSaving(false);
    }
  };

  const handleReset = () => {
    if (originalSettings) {
      setSettings({ ...originalSettings });
      setHasChanges(false);
    }
  };

  const previewCopyright = () => {
    const currentYear = new Date().getFullYear();
    return settings.copyright_text.replace('{year}', currentYear.toString());
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-8">
        <LoadingSpinner size="lg" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="p-2 bg-theme-interactive-primary bg-opacity-10 rounded-lg">
            <Settings className="w-5 h-5 text-theme-interactive-primary" />
          </div>
          <div>
            <h2 className="text-xl font-semibold text-theme-primary">Platform Configuration</h2>
            <p className="text-sm text-theme-secondary">Configure global platform settings and branding</p>
          </div>
        </div>
        
        <div className="flex items-center gap-2">
          <Button onClick={handleReset} disabled={!hasChanges || saving} variant="ghost">
            <RefreshCw className="w-4 h-4 mr-1 inline" />
            Reset
          </Button>
          <Button onClick={handleSave} disabled={!hasChanges || saving} variant="primary">
            {saving ? (
              <>
                <LoadingSpinner size="sm" />
                Saving...
              </>
            ) : (
              <>
                <Save className="w-4 h-4" />
                Save Changes
              </>
            )}
          </Button>
        </div>
      </div>

      <div className="bg-theme-surface rounded-lg border border-theme p-6 space-y-6">
        {/* Branding Settings */}
        <div>
          <h3 className="text-lg font-medium text-theme-primary mb-4">Branding & Display</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label htmlFor="system_name" className="block text-sm font-medium text-theme-primary mb-2">
                System Name
              </label>
              <input
                id="system_name"
                type="text"
                value={settings.system_name}
                onChange={(e) => handleChange('system_name', e.target.value)}
                className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                placeholder="Powernode Platform"
              />
              <p className="text-xs text-theme-secondary mt-1">
                Displayed in the browser title and navigation
              </p>
            </div>

            <div>
              <label htmlFor="copyright_text" className="block text-sm font-medium text-theme-primary mb-2">
                Footer Copyright Text
              </label>
              <input
                id="copyright_text"
                type="text"
                value={settings.copyright_text}
                onChange={(e) => handleChange('copyright_text', e.target.value)}
                className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                placeholder="© {year} Your Company Name. All rights reserved."
              />
              <div className="mt-2">
                <div className="flex items-start gap-2 text-xs text-theme-secondary">
                  <Info className="w-3 h-3 mt-0.5 flex-shrink-0" />
                  <div>
                    <p>Use <code className="bg-theme-background px-1 py-0.5 rounded">{'{year}'}</code> to automatically insert the current year.</p>
                    <p className="mt-1">
                      <span className="font-medium">Preview:</span> {previewCopyright()}
                    </p>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Contact Settings */}
        <div className="border-t border-theme pt-6">
          <h3 className="text-lg font-medium text-theme-primary mb-4">Contact Information</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label htmlFor="system_email" className="block text-sm font-medium text-theme-primary mb-2">
                System Email Address
              </label>
              <input
                id="system_email"
                type="email"
                value={settings.system_email}
                onChange={(e) => handleChange('system_email', e.target.value)}
                className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                placeholder="system@yourcompany.com"
              />
              <p className="text-xs text-theme-secondary mt-1">
                Used as the from address for system emails
              </p>
            </div>

            <div>
              <label htmlFor="support_email" className="block text-sm font-medium text-theme-primary mb-2">
                Support Email Address
              </label>
              <input
                id="support_email"
                type="email"
                value={settings.support_email}
                onChange={(e) => handleChange('support_email', e.target.value)}
                className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
                placeholder="support@yourcompany.com"
              />
              <p className="text-xs text-theme-secondary mt-1">
                Displayed to users for support inquiries
              </p>
            </div>
          </div>
        </div>

        {/* System Settings */}
        <div className="border-t border-theme pt-6">
          <h3 className="text-lg font-medium text-theme-primary mb-4">System Settings</h3>
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <label className="text-sm font-medium text-theme-primary">Maintenance Mode</label>
                <p className="text-xs text-theme-secondary">Temporarily disable access to the platform</p>
              </div>
              <input
                type="checkbox"
                checked={settings.maintenance_mode}
                onChange={(e) => handleChange('maintenance_mode', e.target.checked)}
                className="h-4 w-4 text-theme-interactive-primary border-theme rounded focus:ring-theme-interactive-primary"
              />
            </div>

            <div className="flex items-center justify-between">
              <div>
                <label className="text-sm font-medium text-theme-primary">Registration Enabled</label>
                <p className="text-xs text-theme-secondary">Allow new users to create accounts</p>
              </div>
              <input
                type="checkbox"
                checked={settings.registration_enabled}
                onChange={(e) => handleChange('registration_enabled', e.target.checked)}
                className="h-4 w-4 text-theme-interactive-primary border-theme rounded focus:ring-theme-interactive-primary"
              />
            </div>

            <div className="flex items-center justify-between">
              <div>
                <label className="text-sm font-medium text-theme-primary">Require Email Verification</label>
                <p className="text-xs text-theme-secondary">Users must verify their email before accessing the platform</p>
              </div>
              <input
                type="checkbox"
                checked={settings.require_email_verification}
                onChange={(e) => handleChange('require_email_verification', e.target.checked)}
                className="h-4 w-4 text-theme-interactive-primary border-theme rounded focus:ring-theme-interactive-primary"
              />
            </div>
          </div>
        </div>

        {/* Numeric Settings */}
        <div className="border-t border-theme pt-6">
          <h3 className="text-lg font-medium text-theme-primary mb-4">Timeouts & Limits</h3>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label htmlFor="trial_period_days" className="block text-sm font-medium text-theme-primary mb-2">
                Trial Period (Days)
              </label>
              <input
                id="trial_period_days"
                type="number"
                min="0"
                max="365"
                value={settings.trial_period_days}
                onChange={(e) => handleChange('trial_period_days', parseInt(e.target.value) || 0)}
                className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
              />
              <p className="text-xs text-theme-secondary mt-1">
                Default trial period for new subscriptions
              </p>
            </div>

            <div>
              <label htmlFor="session_timeout_minutes" className="block text-sm font-medium text-theme-primary mb-2">
                Session Timeout (Minutes)
              </label>
              <input
                id="session_timeout_minutes"
                type="number"
                min="5"
                max="1440"
                value={settings.session_timeout_minutes}
                onChange={(e) => handleChange('session_timeout_minutes', parseInt(e.target.value) || 60)}
                className="w-full px-3 py-2 border border-theme rounded-md bg-theme-background text-theme-primary focus:outline-none focus:border-theme-focus"
              />
              <p className="text-xs text-theme-secondary mt-1">
                User session expires after this period of inactivity
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

