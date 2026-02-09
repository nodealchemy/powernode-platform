import React, { useState, useEffect } from 'react';
import { Settings, RefreshCw, Copy } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Loading } from '@/shared/components/ui/Loading';
import { chatChannelsApi } from '@/shared/services/ai';
import type { ChatChannel } from '@/shared/services/ai';

interface ChannelSettingsModalProps {
  isOpen: boolean;
  onClose: () => void;
  channelId: string | null;
  onSaved: () => void;
}

export const ChannelSettingsModal: React.FC<ChannelSettingsModalProps> = ({
  isOpen,
  onClose,
  channelId,
  onSaved,
}) => {
  const [channel, setChannel] = useState<ChatChannel | null>(null);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [formData, setFormData] = useState({
    name: '',
    rate_limit_per_minute: 60,
    welcome_message: '',
    session_timeout_minutes: 30,
  });
  const [webhookUrl, setWebhookUrl] = useState<string | null>(null);
  const [regenerating, setRegenerating] = useState(false);

  useEffect(() => {
    if (isOpen && channelId) {
      loadChannel(channelId);
    }
  }, [isOpen, channelId]);

  const loadChannel = async (id: string) => {
    try {
      setLoading(true);
      setError(null);
      const response = await chatChannelsApi.getChannel(id);
      const ch = response.channel;
      setChannel(ch);
      setFormData({
        name: ch.name || '',
        rate_limit_per_minute: ch.rate_limit_per_minute || 60,
        welcome_message: ch.welcome_message || '',
        session_timeout_minutes: ch.session_timeout_minutes || 30,
      });
      setWebhookUrl(ch.webhook_url || null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load channel');
    } finally {
      setLoading(false);
    }
  };

  const handleSave = async () => {
    if (!channelId) return;

    try {
      setSaving(true);
      setError(null);
      await chatChannelsApi.updateChannel(channelId, {
        name: formData.name,
        rate_limit_per_minute: formData.rate_limit_per_minute,
        welcome_message: formData.welcome_message,
        session_timeout_minutes: formData.session_timeout_minutes,
      });
      onSaved();
      onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save settings');
    } finally {
      setSaving(false);
    }
  };

  const handleRegenerateToken = async () => {
    if (!channelId) return;

    try {
      setRegenerating(true);
      const response = await chatChannelsApi.regenerateToken(channelId);
      setWebhookUrl(response.webhook_url);
      setChannel(response.channel);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to regenerate token');
    } finally {
      setRegenerating(false);
    }
  };

  const copyWebhookUrl = () => {
    if (webhookUrl) {
      navigator.clipboard.writeText(webhookUrl);
    }
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title="Channel Settings"
      icon={<Settings className="w-5 h-5" />}
      maxWidth="lg"
      footer={
        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={onClose} disabled={saving}>
            Cancel
          </Button>
          <Button variant="primary" onClick={handleSave} disabled={saving || loading}>
            {saving ? <Loading size="sm" /> : 'Save Changes'}
          </Button>
        </div>
      }
    >
      {loading ? (
        <div className="flex justify-center p-8">
          <Loading size="lg" />
        </div>
      ) : (
        <div className="space-y-4">
          {error && (
            <div className="p-3 rounded-lg bg-theme-status-error/10 text-theme-status-error text-sm">
              {error}
            </div>
          )}

          {/* Channel Name */}
          <div>
            <label className="block text-sm font-medium text-theme-text-primary mb-1">
              Channel Name
            </label>
            <input
              type="text"
              value={formData.name}
              onChange={(e) => setFormData(prev => ({ ...prev, name: e.target.value }))}
              className="w-full px-3 py-2 rounded-lg border border-theme-border bg-theme-bg-primary text-theme-text-primary"
            />
          </div>

          {/* Platform (read-only) */}
          {channel && (
            <div>
              <label className="block text-sm font-medium text-theme-text-primary mb-1">
                Platform
              </label>
              <p className="px-3 py-2 rounded-lg bg-theme-bg-secondary text-theme-text-secondary capitalize">
                {channel.platform}
              </p>
            </div>
          )}

          {/* Rate Limit */}
          <div>
            <label className="block text-sm font-medium text-theme-text-primary mb-1">
              Rate Limit (per minute)
            </label>
            <input
              type="number"
              value={formData.rate_limit_per_minute}
              onChange={(e) => setFormData(prev => ({ ...prev, rate_limit_per_minute: parseInt(e.target.value) || 60 }))}
              min={1}
              max={1000}
              className="w-full px-3 py-2 rounded-lg border border-theme-border bg-theme-bg-primary text-theme-text-primary"
            />
          </div>

          {/* Welcome Message */}
          <div>
            <label className="block text-sm font-medium text-theme-text-primary mb-1">
              Welcome Message
            </label>
            <textarea
              value={formData.welcome_message}
              onChange={(e) => setFormData(prev => ({ ...prev, welcome_message: e.target.value }))}
              rows={3}
              className="w-full px-3 py-2 rounded-lg border border-theme-border bg-theme-bg-primary text-theme-text-primary resize-none"
            />
          </div>

          {/* Session Timeout */}
          <div>
            <label className="block text-sm font-medium text-theme-text-primary mb-1">
              Session Timeout (minutes)
            </label>
            <input
              type="number"
              value={formData.session_timeout_minutes}
              onChange={(e) => setFormData(prev => ({ ...prev, session_timeout_minutes: parseInt(e.target.value) || 30 }))}
              min={1}
              className="w-full px-3 py-2 rounded-lg border border-theme-border bg-theme-bg-primary text-theme-text-primary"
            />
          </div>

          {/* Webhook URL */}
          {webhookUrl && (
            <div>
              <label className="block text-sm font-medium text-theme-text-primary mb-1">
                Webhook URL
              </label>
              <div className="flex items-center gap-2">
                <code className="flex-1 px-3 py-2 rounded-lg bg-theme-bg-secondary text-theme-text-secondary text-sm truncate">
                  {webhookUrl}
                </code>
                <Button variant="ghost" size="sm" onClick={copyWebhookUrl}>
                  <Copy className="w-4 h-4" />
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={handleRegenerateToken}
                  disabled={regenerating}
                >
                  <RefreshCw className={`w-4 h-4 ${regenerating ? 'animate-spin' : ''}`} />
                </Button>
              </div>
            </div>
          )}
        </div>
      )}
    </Modal>
  );
};
