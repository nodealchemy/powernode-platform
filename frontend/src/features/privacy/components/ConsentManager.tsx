import React, { useState } from 'react';
import { InformationCircleIcon } from '@heroicons/react/24/outline';
import type { ConsentPreferences } from '../services/privacyApi';

interface ConsentManagerProps {
  consents: ConsentPreferences;
  onUpdate: (consents: Partial<Record<string, boolean>>) => Promise<void>;
  loading?: boolean;
}

const CONSENT_LABELS: Record<string, { label: string; icon: string }> = {
  marketing: { label: 'Marketing Communications', icon: '📢' },
  analytics: { label: 'Usage Analytics', icon: '📊' },
  cookies: { label: 'Non-Essential Cookies', icon: '🍪' },
  data_sharing: { label: 'Data Sharing', icon: '🔗' },
  third_party: { label: 'Third-Party Integrations', icon: '🔌' },
  communications: { label: 'Service Communications', icon: '📧' },
  newsletter: { label: 'Newsletter', icon: '📰' },
  promotional: { label: 'Promotional Content', icon: '🎁' },
};

export const ConsentManager: React.FC<ConsentManagerProps> = ({
  consents,
  onUpdate,
  loading = false,
}) => {
  const [localConsents, setLocalConsents] = useState(consents);
  const [saving, setSaving] = useState(false);
  const [hasChanges, setHasChanges] = useState(false);

  const handleToggle = (type: string, value: boolean) => {
    const consent = consents[type as keyof ConsentPreferences];
    if (consent?.required) return; // Can't toggle required consents

    setLocalConsents((prev) => ({
      ...prev,
      [type]: { ...prev[type as keyof ConsentPreferences], granted: value },
    }));
    setHasChanges(true);
  };

  const handleSave = async () => {
    setSaving(true);
    try {
      const updates: Partial<Record<string, boolean>> = {};
      Object.entries(localConsents).forEach(([key, value]) => {
        if (value.granted !== consents[key as keyof ConsentPreferences]?.granted) {
          updates[key] = value.granted;
        }
      });

      if (Object.keys(updates).length > 0) {
        await onUpdate(updates);
        setHasChanges(false);
      }
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="bg-theme-surface rounded-lg border border-theme p-6">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h3 className="text-lg font-semibold text-theme-primary">Consent Preferences</h3>
          <p className="text-sm text-theme-secondary mt-1">
            Manage how your data is used
          </p>
        </div>
        {hasChanges && (
          <button
            onClick={handleSave}
            disabled={saving}
            className="px-4 py-2 bg-theme-primary text-white rounded-lg hover:bg-theme-primary-dark transition-colors disabled:opacity-50"
          >
            {saving ? 'Saving...' : 'Save Changes'}
          </button>
        )}
      </div>

      <div className="space-y-4">
        {Object.entries(localConsents).map(([type, consent]) => {
          const config = CONSENT_LABELS[type] || { label: type, icon: '⚙️' };

          return (
            <div
              key={type}
              className="flex items-center justify-between p-4 bg-theme-background rounded-lg"
            >
              <div className="flex items-start space-x-3">
                <span className="text-2xl">{config.icon}</span>
                <div>
                  <div className="flex items-center space-x-2">
                    <span className="font-medium text-theme-primary">{config.label}</span>
                    {consent.required && (
                      <span className="px-2 py-0.5 text-xs bg-theme-primary/10 text-theme-primary rounded">
                        Required
                      </span>
                    )}
                  </div>
                  <p className="text-sm text-theme-secondary mt-1">{consent.description}</p>
                  {consent.granted && consent.granted_at && (
                    <p className="text-xs text-theme-tertiary mt-1">
                      Granted: {new Date(consent.granted_at).toLocaleDateString()}
                    </p>
                  )}
                </div>
              </div>

              <button
                type="button"
                role="switch"
                aria-checked={consent.granted}
                onClick={() => handleToggle(type, !consent.granted)}
                disabled={consent.required || loading}
                className={`${
                  consent.granted ? 'bg-theme-success' : 'bg-theme-muted/50'
                } relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
                  consent.required ? 'opacity-50 cursor-not-allowed' : ''
                }`}
              >
                <span
                  className={`${
                    consent.granted ? 'translate-x-6' : 'translate-x-1'
                  } inline-block h-4 w-4 transform rounded-full bg-white transition-transform`}
                />
              </button>
            </div>
          );
        })}
      </div>

      <div className="mt-6 p-4 bg-theme-info/10 dark:bg-theme-info/20 rounded-lg">
        <div className="flex items-start space-x-3">
          <InformationCircleIcon className="h-5 w-5 text-theme-info mt-0.5" />
          <div className="text-sm text-theme-info">
            <p className="font-medium">Your Privacy Rights</p>
            <p className="mt-1">
              You can withdraw consent at any time. Required consents are necessary for core service
              functionality. Changes are logged for compliance purposes.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
};

export default ConsentManager;
