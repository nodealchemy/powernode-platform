import React, { useState } from 'react';
import { logger } from '@/shared/utils/logger';
import { useCampaignContents } from '../hooks/useCampaignContents';
import type { CampaignContent, ContentFormData, ChannelType } from '../types';

interface CampaignContentEditorProps {
  campaignId: string;
  content: CampaignContent | null;
  onSave: () => void;
  onCancel: () => void;
}

const CHANNEL_OPTIONS: { value: ChannelType; label: string }[] = [
  { value: 'email', label: 'Email' },
  { value: 'twitter', label: 'Twitter' },
  { value: 'linkedin', label: 'LinkedIn' },
  { value: 'facebook', label: 'Facebook' },
  { value: 'instagram', label: 'Instagram' },
  { value: 'sms', label: 'SMS' },
  { value: 'push', label: 'Push' },
];

export const CampaignContentEditor: React.FC<CampaignContentEditorProps> = ({
  campaignId,
  content,
  onSave,
  onCancel,
}) => {
  const { createContent, updateContent } = useCampaignContents({ campaignId });
  const [formData, setFormData] = useState<ContentFormData>({
    channel: content?.channel || 'email',
    subject: content?.subject || '',
    body: content?.body || '',
    html_body: content?.html_body || null,
    media_urls: content?.media_urls || [],
    scheduled_at: content?.scheduled_at || null,
  });
  const [saving, setSaving] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      setSaving(true);
      if (content) {
        await updateContent(content.id, formData);
      } else {
        await createContent(formData);
      }
      onSave();
    } catch (err) {
      logger.error('Failed to save content:', err);
    } finally {
      setSaving(false);
    }
  };

  return (
    <form onSubmit={handleSubmit} className="card-theme p-6 space-y-4">
      <h3 className="text-lg font-medium text-theme-primary">
        {content ? 'Edit Content' : 'New Content'}
      </h3>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">Channel</label>
          <select
            value={formData.channel}
            onChange={(e) => setFormData(prev => ({ ...prev, channel: e.target.value as ChannelType }))}
            className="input-theme w-full"
            disabled={!!content}
          >
            {CHANNEL_OPTIONS.map(ch => (
              <option key={ch.value} value={ch.value}>{ch.label}</option>
            ))}
          </select>
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">Schedule</label>
          <input
            type="datetime-local"
            value={formData.scheduled_at || ''}
            onChange={(e) => setFormData(prev => ({ ...prev, scheduled_at: e.target.value || null }))}
            className="input-theme w-full"
          />
        </div>
      </div>

      <div>
        <label className="block text-sm font-medium text-theme-primary mb-1">Subject</label>
        <input
          type="text"
          required
          value={formData.subject}
          onChange={(e) => setFormData(prev => ({ ...prev, subject: e.target.value }))}
          className="input-theme w-full"
          placeholder="Content subject or headline"
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-theme-primary mb-1">Body</label>
        <textarea
          required
          value={formData.body}
          onChange={(e) => setFormData(prev => ({ ...prev, body: e.target.value }))}
          className="input-theme w-full"
          rows={8}
          placeholder="Write your content here..."
        />
      </div>

      {(formData.channel === 'email') && (
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">HTML Body (optional)</label>
          <textarea
            value={formData.html_body || ''}
            onChange={(e) => setFormData(prev => ({ ...prev, html_body: e.target.value || null }))}
            className="input-theme w-full font-mono text-xs"
            rows={6}
            placeholder="<html>...</html>"
          />
        </div>
      )}

      <div className="flex justify-end gap-3 pt-4 border-t border-theme-border">
        <button type="button" onClick={onCancel} className="btn-theme btn-theme-secondary">
          Cancel
        </button>
        <button type="submit" disabled={saving} className="btn-theme btn-theme-primary">
          {saving ? 'Saving...' : content ? 'Update Content' : 'Add Content'}
        </button>
      </div>
    </form>
  );
};
