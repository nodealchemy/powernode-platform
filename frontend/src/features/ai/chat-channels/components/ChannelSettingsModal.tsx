import React, { useState, useEffect } from 'react';
import { Settings, RefreshCw, Copy } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Loading } from '@/shared/components/ui/Loading';
import { chatChannelsApi } from '@/shared/services/ai';
import type { ChatChannel, ChannelRoutingConfig, ChannelAgentPersonality } from '@/shared/services/ai';

interface ChannelSettingsModalProps {
  isOpen: boolean;
  onClose: () => void;
  channelId: string | null;
  onSaved: () => void;
}

const ROUTING_STRATEGIES: { value: ChannelRoutingConfig['routing_strategy']; label: string }[] = [
  { value: 'default', label: 'Default Agent' },
  { value: 'skill_based', label: 'Skill-Based Routing' },
  { value: 'round_robin', label: 'Round Robin' },
  { value: 'load_balanced', label: 'Load Balanced' },
];

const GREETING_STYLES: { value: NonNullable<ChannelAgentPersonality['greeting_style']>; label: string }[] = [
  { value: 'formal', label: 'Formal' },
  { value: 'casual', label: 'Casual' },
  { value: 'professional', label: 'Professional' },
];

const RESPONSE_LENGTHS: { value: NonNullable<ChannelAgentPersonality['response_length']>; label: string }[] = [
  { value: 'concise', label: 'Concise' },
  { value: 'standard', label: 'Standard' },
  { value: 'detailed', label: 'Detailed' },
];

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
  const [activeTab, setActiveTab] = useState<'general' | 'routing' | 'personality'>('general');
  const [formData, setFormData] = useState({
    name: '',
    rate_limit_per_minute: 60,
    welcome_message: '',
    session_timeout_minutes: 30,
  });
  const [routingConfig, setRoutingConfig] = useState<ChannelRoutingConfig>({
    routing_strategy: 'default',
    skill_routes: [],
    auto_handoff_enabled: false,
    max_context_messages: 20,
  });
  const [personality, setPersonality] = useState<ChannelAgentPersonality>({
    greeting_style: 'professional',
    response_length: 'standard',
    tone: '',
    display_name: '',
    custom_instructions: '',
  });
  const [webhookUrl, setWebhookUrl] = useState<string | null>(null);
  const [regenerating, setRegenerating] = useState(false);

  useEffect(() => {
    if (isOpen && channelId) {
      loadChannel(channelId);
      setActiveTab('general');
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
      if (ch.routing_config) {
        setRoutingConfig(prev => ({ ...prev, ...ch.routing_config }));
      }
      if (ch.agent_personality) {
        setPersonality(prev => ({ ...prev, ...ch.agent_personality }));
      }
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
        routing_config: routingConfig,
        agent_personality: personality,
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

  const inputClass = 'w-full px-3 py-2 rounded-lg border border-theme-border bg-theme-surface text-theme-primary';
  const selectClass = `${inputClass} appearance-none`;

  const renderGeneralTab = () => (
    <div className="space-y-4">
      {/* Channel Name */}
      <div>
        <label className="block text-sm font-medium text-theme-primary mb-1">
          Channel Name
        </label>
        <input
          type="text"
          value={formData.name}
          onChange={(e) => setFormData(prev => ({ ...prev, name: e.target.value }))}
          className={inputClass}
        />
      </div>

      {/* Platform (read-only) */}
      {channel && (
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">
            Platform
          </label>
          <p className="px-3 py-2 rounded-lg bg-theme-surface text-theme-secondary capitalize">
            {channel.platform}
          </p>
        </div>
      )}

      {/* Rate Limit */}
      <div>
        <label className="block text-sm font-medium text-theme-primary mb-1">
          Rate Limit (per minute)
        </label>
        <input
          type="number"
          value={formData.rate_limit_per_minute}
          onChange={(e) => setFormData(prev => ({ ...prev, rate_limit_per_minute: parseInt(e.target.value) || 60 }))}
          min={1}
          max={1000}
          className={inputClass}
        />
      </div>

      {/* Welcome Message */}
      <div>
        <label className="block text-sm font-medium text-theme-primary mb-1">
          Welcome Message
        </label>
        <textarea
          value={formData.welcome_message}
          onChange={(e) => setFormData(prev => ({ ...prev, welcome_message: e.target.value }))}
          rows={3}
          className={`${inputClass} resize-none`}
        />
      </div>

      {/* Session Timeout */}
      <div>
        <label className="block text-sm font-medium text-theme-primary mb-1">
          Session Timeout (minutes)
        </label>
        <input
          type="number"
          value={formData.session_timeout_minutes}
          onChange={(e) => setFormData(prev => ({ ...prev, session_timeout_minutes: parseInt(e.target.value) || 30 }))}
          min={1}
          className={inputClass}
        />
      </div>

      {/* Webhook URL */}
      {webhookUrl && (
        <div>
          <label className="block text-sm font-medium text-theme-primary mb-1">
            Webhook URL
          </label>
          <div className="flex items-center gap-2">
            <code className="flex-1 px-3 py-2 rounded-lg bg-theme-surface text-theme-secondary text-sm truncate">
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
  );

  const renderRoutingTab = () => (
    <div className="space-y-4">
      {/* Routing Strategy */}
      <div>
        <label className="block text-sm font-medium text-theme-primary mb-1">
          Routing Strategy
        </label>
        <select
          value={routingConfig.routing_strategy}
          onChange={(e) => setRoutingConfig(prev => ({
            ...prev,
            routing_strategy: e.target.value as ChannelRoutingConfig['routing_strategy'],
          }))}
          className={selectClass}
        >
          {ROUTING_STRATEGIES.map((s) => (
            <option key={s.value} value={s.value}>{s.label}</option>
          ))}
        </select>
        <p className="text-xs text-theme-secondary mt-1">
          Skill-based routing matches message content to specific agents by keyword or regex patterns.
        </p>
      </div>

      {/* Max Context Messages */}
      <div>
        <label className="block text-sm font-medium text-theme-primary mb-1">
          Max Context Messages
        </label>
        <input
          type="number"
          value={routingConfig.max_context_messages ?? 20}
          onChange={(e) => setRoutingConfig(prev => ({
            ...prev,
            max_context_messages: parseInt(e.target.value) || 20,
          }))}
          min={1}
          max={100}
          className={inputClass}
        />
        <p className="text-xs text-theme-secondary mt-1">
          Number of recent messages included as context when routing to an agent.
        </p>
      </div>

      {/* Auto-Handoff */}
      <div className="flex items-center justify-between">
        <div>
          <label className="text-sm font-medium text-theme-primary">
            Auto Context Handoff
          </label>
          <p className="text-xs text-theme-secondary">
            Automatically carry conversation context when transferring between channels.
          </p>
        </div>
        <button
          type="button"
          onClick={() => setRoutingConfig(prev => ({
            ...prev,
            auto_handoff_enabled: !prev.auto_handoff_enabled,
          }))}
          className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
            routingConfig.auto_handoff_enabled ? 'bg-theme-primary' : 'bg-theme-surface'
          }`}
        >
          <span
            className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
              routingConfig.auto_handoff_enabled ? 'translate-x-6' : 'translate-x-1'
            }`}
          />
        </button>
      </div>
    </div>
  );

  const renderPersonalityTab = () => (
    <div className="space-y-4">
      {/* Display Name */}
      <div>
        <label className="block text-sm font-medium text-theme-primary mb-1">
          Agent Display Name
        </label>
        <input
          type="text"
          value={personality.display_name ?? ''}
          onChange={(e) => setPersonality(prev => ({ ...prev, display_name: e.target.value }))}
          placeholder="e.g., Support Bot, Ada"
          className={inputClass}
        />
        <p className="text-xs text-theme-secondary mt-1">
          Name shown to users in this channel. Leave blank to use the agent's default name.
        </p>
      </div>

      {/* Greeting Style */}
      <div>
        <label className="block text-sm font-medium text-theme-primary mb-1">
          Greeting Style
        </label>
        <select
          value={personality.greeting_style ?? 'professional'}
          onChange={(e) => setPersonality(prev => ({
            ...prev,
            greeting_style: e.target.value as ChannelAgentPersonality['greeting_style'],
          }))}
          className={selectClass}
        >
          {GREETING_STYLES.map((s) => (
            <option key={s.value} value={s.value}>{s.label}</option>
          ))}
        </select>
      </div>

      {/* Response Length */}
      <div>
        <label className="block text-sm font-medium text-theme-primary mb-1">
          Response Length
        </label>
        <select
          value={personality.response_length ?? 'standard'}
          onChange={(e) => setPersonality(prev => ({
            ...prev,
            response_length: e.target.value as ChannelAgentPersonality['response_length'],
          }))}
          className={selectClass}
        >
          {RESPONSE_LENGTHS.map((s) => (
            <option key={s.value} value={s.value}>{s.label}</option>
          ))}
        </select>
      </div>

      {/* Tone */}
      <div>
        <label className="block text-sm font-medium text-theme-primary mb-1">
          Tone
        </label>
        <input
          type="text"
          value={personality.tone ?? ''}
          onChange={(e) => setPersonality(prev => ({ ...prev, tone: e.target.value }))}
          placeholder="e.g., friendly, empathetic, technical"
          className={inputClass}
        />
      </div>

      {/* Custom Instructions */}
      <div>
        <label className="block text-sm font-medium text-theme-primary mb-1">
          Custom Instructions
        </label>
        <textarea
          value={personality.custom_instructions ?? ''}
          onChange={(e) => setPersonality(prev => ({ ...prev, custom_instructions: e.target.value }))}
          rows={4}
          placeholder="Additional instructions for the agent when responding in this channel..."
          className={`${inputClass} resize-none`}
        />
      </div>
    </div>
  );

  const tabs = [
    { id: 'general' as const, label: 'General' },
    { id: 'routing' as const, label: 'Routing' },
    { id: 'personality' as const, label: 'Personality' },
  ];

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
            <div className="p-3 rounded-lg bg-theme-danger/10 text-theme-danger text-sm">
              {error}
            </div>
          )}

          {/* Tabs */}
          <div className="flex border-b border-theme-border">
            {tabs.map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`px-4 py-2 text-sm font-medium border-b-2 transition-colors ${
                  activeTab === tab.id
                    ? 'border-theme-primary text-theme-primary'
                    : 'border-transparent text-theme-secondary hover:text-theme-primary'
                }`}
              >
                {tab.label}
              </button>
            ))}
          </div>

          {/* Tab Content */}
          {activeTab === 'general' && renderGeneralTab()}
          {activeTab === 'routing' && renderRoutingTab()}
          {activeTab === 'personality' && renderPersonalityTab()}
        </div>
      )}
    </Modal>
  );
};
