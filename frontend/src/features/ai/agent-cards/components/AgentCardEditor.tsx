import React, { useState, useEffect } from 'react';
import {
  Bot,
  Globe,
  Lock,
  Building2,
  Plus,
  Trash2,
  Save,
  X,
  AlertCircle,
} from 'lucide-react';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { Loading } from '@/shared/components/ui/Loading';
import { agentCardsApiService, agentsApi } from '@/shared/services/ai';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { cn } from '@/shared/utils/cn';
import type {
  AgentCard,
  CreateAgentCardRequest,
  UpdateAgentCardRequest,
  A2aSkill,
} from '@/shared/services/ai/types/a2a-types';
import type { AiAgent } from '@/shared/types/ai';

interface AgentCardEditorProps {
  cardId?: string; // If provided, edit mode; otherwise create mode
  onSave?: (card: AgentCard) => void;
  onCancel?: () => void;
  className?: string;
}

interface SkillInput {
  id: string;
  name: string;
  description: string;
  tags: string;
  inputSchema: string;
  outputSchema: string;
}

const emptySkill: SkillInput = {
  id: '',
  name: '',
  description: '',
  tags: '',
  inputSchema: '',
  outputSchema: '',
};

export const AgentCardEditor: React.FC<AgentCardEditorProps> = ({
  cardId,
  onSave,
  onCancel,
  className,
}) => {
  const [loading, setLoading] = useState(!!cardId);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [agents, setAgents] = useState<AiAgent[]>([]);

  // Form fields
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [visibility, setVisibility] = useState<'private' | 'internal' | 'public'>('private');
  const [protocolVersion, setProtocolVersion] = useState('0.3');
  const [endpointUrl, setEndpointUrl] = useState('');
  const [selectedAgentId, setSelectedAgentId] = useState('');
  const [skills, setSkills] = useState<SkillInput[]>([{ ...emptySkill, id: crypto.randomUUID() }]);
  const [streamingEnabled, setStreamingEnabled] = useState(true);
  const [pushNotificationsEnabled, setPushNotificationsEnabled] = useState(false);
  const [authSchemes, setAuthSchemes] = useState<string[]>([]);

  const { addNotification } = useNotifications();

  const isEditMode = !!cardId;

  useEffect(() => {
    loadAgents();
    if (cardId) {
      loadCard();
    }
  }, [cardId]);

  const loadAgents = async () => {
    try {
      const response = await agentsApi.getAgents({ per_page: 100 });
      setAgents(response.items || []);
    } catch (err) {
      // Non-critical, just won't show agent options
    }
  };

  const loadCard = async () => {
    if (!cardId) return;
    try {
      setLoading(true);
      const response = await agentCardsApiService.getAgentCard(cardId);
      const card = response.agent_card;

      setName(card.name);
      setDescription(card.description || '');
      setVisibility(card.visibility);
      setProtocolVersion(card.protocol_version || '0.3');
      setEndpointUrl(card.endpoint_url || '');
      setSelectedAgentId(card.agent_id || '');
      setStreamingEnabled(card.capabilities?.streaming ?? true);
      setPushNotificationsEnabled(card.capabilities?.push_notifications ?? false);
      setAuthSchemes(card.authentication?.schemes || []);

      if (card.capabilities?.skills && card.capabilities.skills.length > 0) {
        setSkills(
          card.capabilities.skills.map((skill) => ({
            id: skill.id,
            name: skill.name || '',
            description: skill.description || '',
            tags: skill.tags?.join(', ') || '',
            inputSchema: skill.inputSchema ? JSON.stringify(skill.inputSchema, null, 2) : '',
            outputSchema: skill.outputSchema ? JSON.stringify(skill.outputSchema, null, 2) : '',
          }))
        );
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load agent card');
    } finally {
      setLoading(false);
    }
  };

  const handleAddSkill = () => {
    setSkills([...skills, { ...emptySkill, id: crypto.randomUUID() }]);
  };

  const handleRemoveSkill = (index: number) => {
    setSkills(skills.filter((_, i) => i !== index));
  };

  const handleSkillChange = (index: number, field: keyof SkillInput, value: string) => {
    const updated = [...skills];
    updated[index] = { ...updated[index], [field]: value };
    setSkills(updated);
  };

  const handleAuthSchemeToggle = (scheme: string) => {
    if (authSchemes.includes(scheme)) {
      setAuthSchemes(authSchemes.filter((s) => s !== scheme));
    } else {
      setAuthSchemes([...authSchemes, scheme]);
    }
  };

  const parseSkills = (): A2aSkill[] => {
    return skills
      .filter((s) => s.id.trim() || s.name.trim())
      .map((s) => {
        const skill: A2aSkill = {
          id: s.id.trim() || s.name.trim().toLowerCase().replace(/\s+/g, '_'),
          name: s.name.trim() || s.id.trim(),
        };
        if (s.description.trim()) skill.description = s.description.trim();
        if (s.tags.trim()) skill.tags = s.tags.split(',').map((t) => t.trim()).filter(Boolean);
        if (s.inputSchema.trim()) {
          try {
            skill.inputSchema = JSON.parse(s.inputSchema);
          } catch {
            // Invalid JSON, skip
          }
        }
        if (s.outputSchema.trim()) {
          try {
            skill.outputSchema = JSON.parse(s.outputSchema);
          } catch {
            // Invalid JSON, skip
          }
        }
        return skill;
      });
  };

  const handleSave = async () => {
    if (!name.trim()) {
      setError('Name is required');
      return;
    }

    try {
      setSaving(true);
      setError(null);

      const parsedSkills = parseSkills();

      if (isEditMode && cardId) {
        const updateData: UpdateAgentCardRequest = {
          name: name.trim(),
          description: description.trim() || undefined,
          visibility,
          endpoint_url: endpointUrl.trim() || undefined,
          capabilities: {
            skills: parsedSkills,
            streaming: streamingEnabled,
            push_notifications: pushNotificationsEnabled,
          },
          authentication: authSchemes.length > 0 ? { schemes: authSchemes } : undefined,
        };

        const response = await agentCardsApiService.updateAgentCard(cardId, updateData);
        addNotification({ type: 'success', title: 'Saved', message: 'Agent card updated' });
        onSave?.(response.agent_card);
      } else {
        const createData: CreateAgentCardRequest = {
          name: name.trim(),
          description: description.trim() || undefined,
          visibility,
          protocol_version: protocolVersion,
          endpoint_url: endpointUrl.trim() || undefined,
          agent_id: selectedAgentId || undefined,
          capabilities: {
            skills: parsedSkills,
            streaming: streamingEnabled,
            push_notifications: pushNotificationsEnabled,
          },
          authentication: authSchemes.length > 0 ? { schemes: authSchemes } : undefined,
        };

        const response = await agentCardsApiService.createAgentCard(createData);
        addNotification({ type: 'success', title: 'Created', message: 'Agent card created' });
        onSave?.(response.agent_card);
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to save agent card';
      setError(message);
      addNotification({ type: 'error', title: 'Error', message });
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return (
      <Card className={className}>
        <CardContent className="flex items-center justify-center py-12">
          <Loading size="lg" message="Loading agent card..." />
        </CardContent>
      </Card>
    );
  }

  return (
    <div className={cn('space-y-6', className)}>
      {/* Header */}
      <Card>
        <CardHeader
          title={isEditMode ? 'Edit Agent Card' : 'Create Agent Card'}
          icon={<Bot className="h-5 w-5" />}
          action={
            <div className="flex items-center gap-2">
              <Button variant="outline" size="sm" onClick={onCancel}>
                <X className="h-4 w-4 mr-2" />
                Cancel
              </Button>
              <Button variant="primary" size="sm" onClick={handleSave} disabled={saving}>
                <Save className="h-4 w-4 mr-2" />
                {saving ? 'Saving...' : 'Save'}
              </Button>
            </div>
          }
        />
      </Card>

      {/* Error */}
      {error && (
        <div className="p-4 bg-theme-danger/10 border border-theme-danger/30 rounded-lg">
          <div className="flex items-center gap-2 text-theme-danger">
            <AlertCircle className="h-4 w-4" />
            <span>{error}</span>
          </div>
        </div>
      )}

      {/* Basic Info */}
      <Card>
        <CardHeader title="Basic Information" />
        <CardContent className="space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-theme-secondary mb-1">
                Name <span className="text-theme-danger">*</span>
              </label>
              <Input
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="My Agent Card"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-secondary mb-1">
                Visibility
              </label>
              <Select
                value={visibility}
                onChange={(e) => setVisibility(e.target.value as 'private' | 'internal' | 'public')}
              >
                <option value="private">Private - Only you</option>
                <option value="internal">Internal - Your organization</option>
                <option value="public">Public - Anyone</option>
              </Select>
            </div>
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">
              Description
            </label>
            <textarea
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="What does this agent do?"
              className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary"
              rows={3}
            />
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {!isEditMode && (
              <div>
                <label className="block text-sm font-medium text-theme-secondary mb-1">
                  Link to Agent
                </label>
                <Select
                  value={selectedAgentId}
                  onChange={(e) => setSelectedAgentId(e.target.value)}
                >
                  <option value="">No linked agent</option>
                  {agents.map((agent) => (
                    <option key={agent.id} value={agent.id}>
                      {agent.name}
                    </option>
                  ))}
                </Select>
              </div>
            )}

            <div>
              <label className="block text-sm font-medium text-theme-secondary mb-1">
                External Endpoint URL
              </label>
              <Input
                value={endpointUrl}
                onChange={(e) => setEndpointUrl(e.target.value)}
                placeholder="https://example.com/.well-known/agent.json"
              />
            </div>
          </div>
        </CardContent>
      </Card>

      {/* Skills */}
      <Card>
        <CardHeader
          title="Skills / Capabilities"
          action={
            <Button variant="outline" size="sm" onClick={handleAddSkill}>
              <Plus className="h-4 w-4 mr-2" />
              Add Skill
            </Button>
          }
        />
        <CardContent className="space-y-4">
          {skills.map((skill, index) => (
            <div
              key={skill.id || index}
              className="p-4 border border-theme rounded-lg space-y-3"
            >
              <div className="flex items-center justify-between">
                <span className="text-sm font-medium text-theme-secondary">
                  Skill {index + 1}
                </span>
                {skills.length > 1 && (
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => handleRemoveSkill(index)}
                  >
                    <Trash2 className="h-4 w-4 text-theme-danger" />
                  </Button>
                )}
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs text-theme-muted mb-1">ID</label>
                  <Input
                    value={skill.id}
                    onChange={(e) => handleSkillChange(index, 'id', e.target.value)}
                    placeholder="summarize_text"
                  />
                </div>
                <div>
                  <label className="block text-xs text-theme-muted mb-1">Name</label>
                  <Input
                    value={skill.name}
                    onChange={(e) => handleSkillChange(index, 'name', e.target.value)}
                    placeholder="Summarize Text"
                  />
                </div>
              </div>

              <div>
                <label className="block text-xs text-theme-muted mb-1">Description</label>
                <Input
                  value={skill.description}
                  onChange={(e) => handleSkillChange(index, 'description', e.target.value)}
                  placeholder="Summarizes long text into key points"
                />
              </div>

              <div>
                <label className="block text-xs text-theme-muted mb-1">Tags (comma-separated)</label>
                <Input
                  value={skill.tags}
                  onChange={(e) => handleSkillChange(index, 'tags', e.target.value)}
                  placeholder="analysis, text, summarization"
                />
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs text-theme-muted mb-1">Input Schema (JSON)</label>
                  <textarea
                    value={skill.inputSchema}
                    onChange={(e) => handleSkillChange(index, 'inputSchema', e.target.value)}
                    placeholder='{"type": "object", "properties": {...}}'
                    className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary font-mono text-xs focus:outline-none focus:ring-2 focus:ring-theme-primary"
                    rows={3}
                  />
                </div>
                <div>
                  <label className="block text-xs text-theme-muted mb-1">Output Schema (JSON)</label>
                  <textarea
                    value={skill.outputSchema}
                    onChange={(e) => handleSkillChange(index, 'outputSchema', e.target.value)}
                    placeholder='{"type": "object", "properties": {...}}'
                    className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary font-mono text-xs focus:outline-none focus:ring-2 focus:ring-theme-primary"
                    rows={3}
                  />
                </div>
              </div>
            </div>
          ))}
        </CardContent>
      </Card>

      {/* Advanced Options */}
      <Card>
        <CardHeader title="Advanced Options" />
        <CardContent className="space-y-4">
          <div className="flex items-center gap-6">
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={streamingEnabled}
                onChange={(e) => setStreamingEnabled(e.target.checked)}
                className="rounded border-theme"
              />
              <span className="text-sm text-theme-primary">Enable Streaming</span>
            </label>

            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={pushNotificationsEnabled}
                onChange={(e) => setPushNotificationsEnabled(e.target.checked)}
                className="rounded border-theme"
              />
              <span className="text-sm text-theme-primary">Enable Push Notifications</span>
            </label>
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-2">
              Authentication Schemes
            </label>
            <div className="flex items-center gap-4">
              {['bearer', 'api_key', 'oauth2', 'none'].map((scheme) => (
                <label key={scheme} className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={authSchemes.includes(scheme)}
                    onChange={() => handleAuthSchemeToggle(scheme)}
                    className="rounded border-theme"
                  />
                  <span className="text-sm text-theme-primary capitalize">{scheme.replace('_', ' ')}</span>
                </label>
              ))}
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
};

export default AgentCardEditor;
