import React, { useState } from 'react';
import { Save, Loader2 } from 'lucide-react';

interface ConversationProfile {
  tone: string;
  verbosity: string;
  response_format: string;
  custom_instructions: string;
}

interface ConversationProfileEditorProps {
  initialProfile?: Partial<ConversationProfile>;
  onSave: (profile: ConversationProfile) => Promise<void>;
}

const TONE_OPTIONS = [
  { value: 'professional', label: 'Professional' },
  { value: 'casual', label: 'Casual' },
  { value: 'technical', label: 'Technical' },
  { value: 'friendly', label: 'Friendly' },
  { value: 'concise', label: 'Concise' },
];

const VERBOSITY_OPTIONS = [
  { value: 'minimal', label: 'Minimal' },
  { value: 'standard', label: 'Standard' },
  { value: 'detailed', label: 'Detailed' },
];

const FORMAT_OPTIONS = [
  { value: 'prose', label: 'Prose' },
  { value: 'bullets', label: 'Bullets' },
  { value: 'structured', label: 'Structured' },
];

const DEFAULT_PROFILE: ConversationProfile = {
  tone: 'professional',
  verbosity: 'standard',
  response_format: 'prose',
  custom_instructions: '',
};

export const ConversationProfileEditor: React.FC<ConversationProfileEditorProps> = ({
  initialProfile,
  onSave,
}) => {
  const [profile, setProfile] = useState<ConversationProfile>({
    ...DEFAULT_PROFILE,
    ...initialProfile,
  });
  const [saving, setSaving] = useState(false);

  const handleSave = async () => {
    setSaving(true);
    try {
      await onSave(profile);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="space-y-4">
      <h4 className="text-sm font-semibold text-theme-primary border-b border-theme pb-2">
        Conversation Style
      </h4>

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
        <div>
          <label className="block text-xs font-medium text-theme-secondary mb-1">Tone</label>
          <select
            value={profile.tone}
            onChange={(e) => setProfile(p => ({ ...p, tone: e.target.value }))}
            className="w-full px-2.5 py-1.5 text-sm bg-theme-background border border-theme rounded-md text-theme-primary focus:outline-none focus:ring-1 focus:ring-theme-interactive-primary"
          >
            {TONE_OPTIONS.map(o => (
              <option key={o.value} value={o.value}>{o.label}</option>
            ))}
          </select>
        </div>

        <div>
          <label className="block text-xs font-medium text-theme-secondary mb-1">Verbosity</label>
          <select
            value={profile.verbosity}
            onChange={(e) => setProfile(p => ({ ...p, verbosity: e.target.value }))}
            className="w-full px-2.5 py-1.5 text-sm bg-theme-background border border-theme rounded-md text-theme-primary focus:outline-none focus:ring-1 focus:ring-theme-interactive-primary"
          >
            {VERBOSITY_OPTIONS.map(o => (
              <option key={o.value} value={o.value}>{o.label}</option>
            ))}
          </select>
        </div>

        <div>
          <label className="block text-xs font-medium text-theme-secondary mb-1">Response Format</label>
          <select
            value={profile.response_format}
            onChange={(e) => setProfile(p => ({ ...p, response_format: e.target.value }))}
            className="w-full px-2.5 py-1.5 text-sm bg-theme-background border border-theme rounded-md text-theme-primary focus:outline-none focus:ring-1 focus:ring-theme-interactive-primary"
          >
            {FORMAT_OPTIONS.map(o => (
              <option key={o.value} value={o.value}>{o.label}</option>
            ))}
          </select>
        </div>
      </div>

      <div>
        <label className="block text-xs font-medium text-theme-secondary mb-1">Custom Instructions</label>
        <textarea
          value={profile.custom_instructions}
          onChange={(e) => setProfile(p => ({ ...p, custom_instructions: e.target.value }))}
          placeholder="Add any specific instructions for how the agent should respond..."
          rows={3}
          maxLength={1000}
          className="w-full px-2.5 py-1.5 text-sm bg-theme-background border border-theme rounded-md text-theme-primary placeholder:text-theme-text-tertiary focus:outline-none focus:ring-1 focus:ring-theme-interactive-primary resize-none"
        />
        <div className="text-right text-[10px] text-theme-text-tertiary mt-0.5">
          {profile.custom_instructions.length}/1000
        </div>
      </div>

      <button
        type="button"
        onClick={handleSave}
        disabled={saving}
        className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-white bg-theme-interactive-primary rounded-md hover:opacity-90 disabled:opacity-50 transition-opacity"
      >
        {saving ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Save className="h-3.5 w-3.5" />}
        {saving ? 'Saving...' : 'Save Profile'}
      </button>
    </div>
  );
};
