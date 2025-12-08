import React, { useState, useEffect } from 'react';
import { PageContainer } from '@/shared/components/layout/PageContainer';
import { siteSettingsApi } from '@/features/settings/services/siteSettingsApi';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { 
  Settings, 
  Save, 
  RotateCcw, 
  Globe, 
  Lock,
  Eye,
  EyeOff
} from 'lucide-react';

interface FooterSettingsForm {
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
  footer_cache_enabled: boolean;
}

export const SiteSettingsPage: React.FC = () => {
  const { showNotification } = useNotifications();
  const [footerSettings, setFooterSettings] = useState<FooterSettingsForm>({
    site_name: '',
    copyright_text: '',
    copyright_year: '',
    footer_description: '',
    contact_email: '',
    contact_phone: '',
    company_address: '',
    social_facebook: '',
    social_twitter: '',
    social_linkedin: '',
    social_instagram: '',
    social_youtube: '',
    footer_cache_enabled: true
  });
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [showSensitive, setShowSensitive] = useState(false);

  useEffect(() => {
    loadSettings();
  }, []);

  const loadSettings = async () => {
    try {
      setLoading(true);
      const response = await siteSettingsApi.getFooterSettings();
      if (response.success) {
        // Convert settings array to form object
        const formData: FooterSettingsForm = {
          site_name: '',
          copyright_text: '',
          copyright_year: '',
          footer_description: '',
          contact_email: '',
          contact_phone: '',
          company_address: '',
          social_facebook: '',
          social_twitter: '',
          social_linkedin: '',
          social_instagram: '',
          social_youtube: '',
          footer_cache_enabled: true
        };
        
        response.data.settings.forEach(setting => {
          if (setting.key in formData) {
            if (setting.setting_type === 'boolean') {
              (formData as any)[setting.key] = setting.parsed_value === true || setting.value === 'true';
            } else {
              (formData as any)[setting.key] = setting.value || '';
            }
          }
        });
        
        setFooterSettings(formData);
      } else {
        showNotification('Failed to load site settings', 'error');
      }
    } catch (error: any) {
      showNotification(error.message || 'Failed to load site settings', 'error');
    } finally {
      setLoading(false);
    }
  };

  const handleInputChange = (key: keyof FooterSettingsForm, value: string | boolean) => {
    setFooterSettings(prev => ({
      ...prev,
      [key]: value
    }));
  };

  const handleSave = async () => {
    try {
      setSaving(true);
      
      // Convert form data to bulk update format
      const bulkUpdateData: Record<string, any> = {};
      Object.entries(footerSettings).forEach(([key, value]) => {
        // Determine setting type and public visibility
        const settingType = key === 'footer_cache_enabled' ? 'boolean' : 'string';
        const isPublic = key !== 'footer_cache_enabled'; // Cache setting is admin-only
        
        bulkUpdateData[key] = {
          value: settingType === 'boolean' ? value.toString() : value,
          setting_type: settingType,
          is_public: isPublic
        };
      });
      
      const response = await siteSettingsApi.bulkUpdateSettings(bulkUpdateData);
      if (response.success) {
        showNotification('Site settings updated successfully', 'success');
        await loadSettings(); // Reload to get updated data
      } else {
        showNotification('Failed to update site settings', 'error');
      }
    } catch (error: any) {
      showNotification(error.message || 'Failed to update site settings', 'error');
    } finally {
      setSaving(false);
    }
  };

  const handleReset = () => {
    loadSettings();
  };

  if (loading) {
    return (
      <PageContainer title="Site Settings" description="Manage site-wide settings and footer information">
        <div className="flex items-center justify-center p-8">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-primary"></div>
        </div>
      </PageContainer>
    );
  }

  return (
    <PageContainer 
      title="Site Settings" 
      description="Manage site-wide settings including footer information and social media links"
      actions={[
        {
          id: 'reset',
          label: 'Reset',
          onClick: handleReset,
          variant: 'secondary',
          icon: RotateCcw
        },
        {
          id: 'save',
          label: saving ? 'Saving...' : 'Save Changes',
          onClick: handleSave,
          variant: 'primary',
          icon: Save
        }
      ]}
    >
      <div className="space-y-8">
        {/* Basic Site Information */}
        <div className="surface rounded-2xl p-6">
          <div className="flex items-center mb-6">
            <div className="w-10 h-10 bg-theme-primary/10 rounded-xl flex items-center justify-center mr-4">
              <Settings className="w-5 h-5 text-theme-primary" />
            </div>
            <div>
              <h3 className="text-lg font-semibold text-theme-primary">Basic Information</h3>
              <p className="text-sm text-theme-secondary">Core site information displayed in the footer</p>
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Site Name
              </label>
              <input
                type="text"
                value={footerSettings.site_name}
                onChange={(e) => handleInputChange('site_name', e.target.value)}
                className="input-theme"
                placeholder="Powernode"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Copyright Year
              </label>
              <input
                type="text"
                value={footerSettings.copyright_year}
                onChange={(e) => handleInputChange('copyright_year', e.target.value)}
                className="input-theme"
                placeholder="2025"
              />
            </div>

            <div className="md:col-span-2">
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Copyright Text
              </label>
              <input
                type="text"
                value={footerSettings.copyright_text}
                onChange={(e) => handleInputChange('copyright_text', e.target.value)}
                className="input-theme"
                placeholder="All rights reserved."
              />
            </div>

            <div className="md:col-span-2">
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Footer Description
              </label>
              <textarea
                value={footerSettings.footer_description}
                onChange={(e) => handleInputChange('footer_description', e.target.value)}
                rows={3}
                className="input-theme resize-none"
                placeholder="Powerful subscription management platform designed to help businesses grow..."
              />
            </div>
          </div>
        </div>

        {/* Contact Information */}
        <div className="surface rounded-2xl p-6">
          <div className="flex items-center mb-6">
            <div className="w-10 h-10 bg-theme-info/20 rounded-xl flex items-center justify-center mr-4">
              <Globe className="w-5 h-5 text-theme-info" />
            </div>
            <div>
              <h3 className="text-lg font-semibold text-theme-primary">Contact Information</h3>
              <p className="text-sm text-theme-secondary">Contact details displayed in the footer</p>
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Contact Email
              </label>
              <input
                type="email"
                value={footerSettings.contact_email}
                onChange={(e) => handleInputChange('contact_email', e.target.value)}
                className="input-theme"
                placeholder="hello@example.com"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Contact Phone
              </label>
              <input
                type="text"
                value={footerSettings.contact_phone}
                onChange={(e) => handleInputChange('contact_phone', e.target.value)}
                className="input-theme"
                placeholder="+1 (555) 123-4567"
              />
            </div>

            <div className="md:col-span-2">
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Company Address
              </label>
              <textarea
                value={footerSettings.company_address}
                onChange={(e) => handleInputChange('company_address', e.target.value)}
                rows={2}
                className="input-theme resize-none"
                placeholder="123 Innovation Drive, Tech City, TC 12345"
              />
            </div>
          </div>
        </div>

        {/* Social Media Links */}
        <div className="surface rounded-2xl p-6">
          <div className="flex items-center justify-between mb-6">
            <div className="flex items-center">
              <div className="w-10 h-10 bg-theme-interactive-primary/20 rounded-xl flex items-center justify-center mr-4">
                <Globe className="w-5 h-5 text-theme-interactive-primary" />
              </div>
              <div>
                <h3 className="text-lg font-semibold text-theme-primary">Social Media Links</h3>
                <p className="text-sm text-theme-secondary">Social media profiles (leave empty to hide)</p>
              </div>
            </div>
            <button
              onClick={() => setShowSensitive(!showSensitive)}
              className="flex items-center text-sm text-theme-secondary hover:text-theme-primary"
            >
              {showSensitive ? <EyeOff className="w-4 h-4 mr-1" /> : <Eye className="w-4 h-4 mr-1" />}
              {showSensitive ? 'Hide URLs' : 'Show URLs'}
            </button>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Facebook Page URL
              </label>
              <input
                type={showSensitive ? "text" : "password"}
                value={footerSettings.social_facebook}
                onChange={(e) => handleInputChange('social_facebook', e.target.value)}
                className="input-theme"
                placeholder="https://facebook.com/yourpage"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Twitter/X Profile URL
              </label>
              <input
                type={showSensitive ? "text" : "password"}
                value={footerSettings.social_twitter}
                onChange={(e) => handleInputChange('social_twitter', e.target.value)}
                className="input-theme"
                placeholder="https://twitter.com/yourhandle"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                LinkedIn Profile URL
              </label>
              <input
                type={showSensitive ? "text" : "password"}
                value={footerSettings.social_linkedin}
                onChange={(e) => handleInputChange('social_linkedin', e.target.value)}
                className="input-theme"
                placeholder="https://linkedin.com/company/yourcompany"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-primary mb-2">
                Instagram Profile URL
              </label>
              <input
                type={showSensitive ? "text" : "password"}
                value={footerSettings.social_instagram}
                onChange={(e) => handleInputChange('social_instagram', e.target.value)}
                className="input-theme"
                placeholder="https://instagram.com/yourhandle"
              />
            </div>

            <div className="md:col-span-2">
              <label className="block text-sm font-medium text-theme-primary mb-2">
                YouTube Channel URL
              </label>
              <input
                type={showSensitive ? "text" : "password"}
                value={footerSettings.social_youtube}
                onChange={(e) => handleInputChange('social_youtube', e.target.value)}
                className="input-theme"
                placeholder="https://youtube.com/channel/yourchannel"
              />
            </div>
          </div>
        </div>

        {/* Performance Settings */}
        <div className="surface rounded-2xl p-6">
          <div className="flex items-center mb-6">
            <div className="w-10 h-10 bg-theme-success/20 rounded-xl flex items-center justify-center mr-4">
              <Settings className="w-5 h-5 text-theme-success" />
            </div>
            <div>
              <h3 className="text-lg font-semibold text-theme-primary">Performance Settings</h3>
              <p className="text-sm text-theme-secondary">Optimize footer loading and caching</p>
            </div>
          </div>

          <div className="grid grid-cols-1 gap-6">
            <div className="flex items-center justify-between p-4 border border-theme rounded-lg">
              <div className="flex-1">
                <h4 className="text-sm font-medium text-theme-primary mb-1">Footer Caching</h4>
                <p className="text-xs text-theme-secondary">Cache footer data for improved performance (1 hour cache)</p>
              </div>
              <div className="ml-4">
                <label className="relative inline-flex items-center cursor-pointer">
                  <input
                    type="checkbox"
                    checked={footerSettings.footer_cache_enabled}
                    onChange={(e) => handleInputChange('footer_cache_enabled', e.target.checked)}
                    className="sr-only peer"
                  />
                  <div className="w-11 h-6 bg-theme-border peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-theme-info/30 dark:peer-focus:ring-theme-info/50 rounded-full peer dark:bg-theme-surface-elevated peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-theme after:border after:rounded-full after:h-5 after:w-5 after:transition-all dark:border-theme peer-checked:bg-theme-info"></div>
                </label>
              </div>
            </div>
          </div>
        </div>

        {/* Settings Summary */}
        <div className="surface rounded-2xl p-6">
          <div className="flex items-center mb-4">
            <div className="w-10 h-10 bg-theme-success/20 rounded-xl flex items-center justify-center mr-4">
              <Globe className="w-5 h-5 text-theme-success" />
            </div>
            <div>
              <h3 className="text-lg font-semibold text-theme-primary">Settings Status</h3>
              <p className="text-sm text-theme-secondary">Footer settings visibility and caching status</p>
            </div>
          </div>
          
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            <div className="bg-theme-success/10 border border-theme-success/30 rounded-lg p-4">
              <div className="flex items-center">
                <Globe className="w-5 h-5 text-theme-success mr-2" />
                <span className="text-sm font-medium text-theme-success">Public Settings</span>
              </div>
              <p className="text-xs text-theme-success mt-1">Visible to all website visitors</p>
            </div>

            <div className="bg-theme-info/10 border border-theme-info/30 rounded-lg p-4">
              <div className="flex items-center">
                <Settings className="w-5 h-5 text-theme-info mr-2" />
                <span className="text-sm font-medium text-theme-info">Total Settings</span>
              </div>
              <p className="text-xs text-theme-info mt-1">{Object.keys(footerSettings).length - 1} public + 1 admin</p>
            </div>

            <div className={`border rounded-lg p-4 ${footerSettings.footer_cache_enabled ? 'bg-theme-success/10 border-theme-success/30' : 'bg-theme-warning/10 border-theme-warning/30'}`}>
              <div className="flex items-center">
                <Settings className={`w-5 h-5 mr-2 ${footerSettings.footer_cache_enabled ? 'text-theme-success' : 'text-theme-warning'}`} />
                <span className={`text-sm font-medium ${footerSettings.footer_cache_enabled ? 'text-theme-success' : 'text-theme-warning'}`}>Footer Caching</span>
              </div>
              <p className={`text-xs mt-1 ${footerSettings.footer_cache_enabled ? 'text-theme-success' : 'text-theme-warning'}`}>
                {footerSettings.footer_cache_enabled ? 'Enabled (1 hour cache)' : 'Disabled (no caching)'}
              </p>
            </div>

            <div className="bg-theme-interactive-primary/10 border border-theme-interactive-primary/30 rounded-lg p-4">
              <div className="flex items-center">
                <Lock className="w-5 h-5 text-theme-interactive-primary mr-2" />
                <span className="text-sm font-medium text-theme-interactive-primary">Access Level</span>
              </div>
              <p className="text-xs text-theme-interactive-primary mt-1">Admin only management</p>
            </div>
          </div>
        </div>
      </div>
    </PageContainer>
  );
};