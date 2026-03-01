import React, { useState } from 'react';
import { X } from 'lucide-react';
import { logger } from '@/shared/utils/logger';
import type { CampaignFormData, CampaignType, ChannelType } from '../types';

interface CampaignEditorProps {
  initialData?: Partial<CampaignFormData>;
  onSave: (data: CampaignFormData) => Promise<void>;
  onCancel: () => void;
  isEditing?: boolean;
}

const CAMPAIGN_TYPES: { value: CampaignType; label: string }[] = [
  { value: 'email', label: 'Email' },
  { value: 'social', label: 'Social Media' },
  { value: 'multi_channel', label: 'Multi-Channel' },
  { value: 'sms', label: 'SMS' },
  { value: 'push', label: 'Push Notification' },
];

const CHANNEL_OPTIONS: { value: ChannelType; label: string }[] = [
  { value: 'email', label: 'Email' },
  { value: 'twitter', label: 'Twitter' },
  { value: 'linkedin', label: 'LinkedIn' },
  { value: 'facebook', label: 'Facebook' },
  { value: 'instagram', label: 'Instagram' },
  { value: 'sms', label: 'SMS' },
  { value: 'push', label: 'Push' },
];

export const CampaignEditor: React.FC<CampaignEditorProps> = ({
  initialData,
  onSave,
  onCancel,
  isEditing = false,
}) => {
  const [formData, setFormData] = useState<CampaignFormData>({
    name: initialData?.name || '',
    description: initialData?.description || '',
    campaign_type: initialData?.campaign_type || 'email',
    channels: initialData?.channels || [],
    scheduled_at: initialData?.scheduled_at || null,
    budget_cents: initialData?.budget_cents || 0,
    target_audience: initialData?.target_audience || '',
    tags: initialData?.tags || [],
  });
  const [tagInput, setTagInput] = useState('');
  const [saving, setSaving] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      setSaving(true);
      await onSave(formData);
    } catch (err) {
      logger.error('Failed to save campaign:', err);
    } finally {
      setSaving(false);
    }
  };

  const toggleChannel = (channel: ChannelType) => {
    setFormData(prev => ({
      ...prev,
      channels: prev.channels.includes(channel)
        ? prev.channels.filter(c => c !== channel)
        : [...prev.channels, channel],
    }));
  };

  const addTag = () => {
    if (tagInput.trim() && !formData.tags.includes(tagInput.trim())) {
      setFormData(prev => ({ ...prev, tags: [...prev.tags, tagInput.trim()] }));
      setTagInput('');
    }
  };

  const removeTag = (tag: string) => {
    setFormData(prev => ({ ...prev, tags: prev.tags.filter(t => t !== tag) }));
  };

  return (
    <form onSubmit={handleSubmit} className="card-theme p-6 space-y-6">
      <h2 className="text-lg font-semibold text-theme-primary">
        {isEditing ? 'Edit Campaign' : 'Create Campaign'}
      </h2>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* Name */}
        <div className="md:col-span-2">
          <label className="block text-sm font-medium text-theme-primary mb-1">Campaign Name</label>
          <input
            type="text"
            required
            value={formData.name}
            onChange={(e) => setFormData(prev => ({ ...prev, name: e.target.value }))}
            className="input-theme w-full"
            placeholder="Enter campaign name"
          />
        </div>

        {/* Description */}
        <div className="md:col-span-2">
          <label className="block text-sm font-medium text-theme-primary mb-1">Description</label>
          <textarea
            value={formData.description}
            onChange={(e) => setFormData(prev => ({ ...prev, description: e.target.value }))}
            className="input-theme w-full"
            rows={3}
            placeholder="Describe the campaign objectives"
          />
        </div>

        {/* Campaign Type */}
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">Campaign Type</label>
          <select
            value={formData.campaign_type}
            onChange={(e) => setFormData(prev => ({ ...prev, campaign_type: e.target.value as CampaignType }))}
            className="input-theme w-full"
          >
            {CAMPAIGN_TYPES.map(t => (
              <option key={t.value} value={t.value}>{t.label}</option>
            ))}
          </select>
        </div>

        {/* Budget */}
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">Budget ($)</label>
          <input
            type="number"
            min={0}
            step={0.01}
            value={formData.budget_cents / 100}
            onChange={(e) => setFormData(prev => ({ ...prev, budget_cents: Math.round(parseFloat(e.target.value || '0') * 100) }))}
            className="input-theme w-full"
            placeholder="0.00"
          />
        </div>

        {/* Schedule */}
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">Schedule Date</label>
          <input
            type="datetime-local"
            value={formData.scheduled_at || ''}
            onChange={(e) => setFormData(prev => ({ ...prev, scheduled_at: e.target.value || null }))}
            className="input-theme w-full"
          />
        </div>

        {/* Target Audience */}
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">Target Audience</label>
          <input
            type="text"
            value={formData.target_audience}
            onChange={(e) => setFormData(prev => ({ ...prev, target_audience: e.target.value }))}
            className="input-theme w-full"
            placeholder="e.g., Newsletter subscribers"
          />
        </div>

        {/* Channels */}
        <div className="md:col-span-2">
          <label className="block text-sm font-medium text-theme-primary mb-2">Channels</label>
          <div className="flex flex-wrap gap-2">
            {CHANNEL_OPTIONS.map(ch => (
              <button
                key={ch.value}
                type="button"
                onClick={() => toggleChannel(ch.value)}
                className={`px-3 py-1.5 rounded-lg text-sm font-medium border transition-colors ${
                  formData.channels.includes(ch.value)
                    ? 'bg-theme-primary text-theme-on-primary border-transparent'
                    : 'bg-theme-surface text-theme-secondary border-theme-border hover:bg-theme-surface-hover'
                }`}
              >
                {ch.label}
              </button>
            ))}
          </div>
        </div>

        {/* Tags */}
        <div className="md:col-span-2">
          <label className="block text-sm font-medium text-theme-primary mb-1">Tags</label>
          <div className="flex gap-2 mb-2 flex-wrap">
            {formData.tags.map(tag => (
              <span key={tag} className="inline-flex items-center gap-1 px-2 py-1 rounded bg-theme-surface text-theme-secondary text-xs">
                {tag}
                <button type="button" onClick={() => removeTag(tag)}>
                  <X className="w-3 h-3" />
                </button>
              </span>
            ))}
          </div>
          <div className="flex gap-2">
            <input
              type="text"
              value={tagInput}
              onChange={(e) => setTagInput(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); addTag(); } }}
              className="input-theme flex-1"
              placeholder="Add a tag and press Enter"
            />
            <button type="button" onClick={addTag} className="btn-theme btn-theme-secondary">
              Add
            </button>
          </div>
        </div>
      </div>

      {/* Actions */}
      <div className="flex justify-end gap-3 pt-4 border-t border-theme-border">
        <button type="button" onClick={onCancel} className="btn-theme btn-theme-secondary">
          Cancel
        </button>
        <button type="submit" disabled={saving} className="btn-theme btn-theme-primary">
          {saving ? 'Saving...' : isEditing ? 'Update Campaign' : 'Create Campaign'}
        </button>
      </div>
    </form>
  );
};
