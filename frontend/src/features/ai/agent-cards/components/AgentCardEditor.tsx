import React, { useState, useEffect } from 'react';
import {
  Bot,
  Plus,
  Trash2,
  Save,
  X,
  AlertCircle,
  CheckCircle,
} from 'lucide-react';
import { Card, CardHeader, CardContent } from '@/shared/components/ui/Card';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { Loading } from '@/shared/components/ui/Loading';
import ErrorAlert from '@/shared/components/ui/ErrorAlert';
import { agentCardsApiService, agentsApi } from '@/shared/services/ai';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { cn } from '@/shared/utils/cn';
import type {
  AgentCard,
  CreateAgentCardRequest,
  UpdateAgentCardRequest,
  AgentSkill,
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
  const [validating, setValidating] = useState(false);
  const [validationResult, setValidationResult] = useState<{ valid: boolean; errors: string[] } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [agents, setAgents] = useState<AiAgent[]>([]);

  // Form fields
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [visibility, setVisibility] = useState<'private' | 'internal' | 'public'>('private');
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

  // Auto-populate skills when agent selection changes
  useEffect(() => {
    if (!selectedAgentId || isEditMode) return;

    const loadAgentSkills = async () => {
      try {
        const agentSkills = await agentsApi.getAgentSkills(selectedAgentId);
        if (agentSkills && agentSkills.length > 0) {
          setSkills(
            agentSkills.map((s) => ({
              id: s.slug || s.id,
              name: s.name,
              description: '',
              tags: s.category || '',
              inputSchema: '',
              outputSchema: '',
            }))
          );
        }
      } catch {
        // Agent may not have skills assigned; keep current skills
      }
    };
    loadAgentSkills();
  }, [selectedAgentId, isEditMode]);

  const loadAgents = async () => {
    try {
      const response = await agentsApi.getAgents({ per_page: 100 });
      setAgents(response.items || []);
    } catch (err) {
      console.error('[AgentCardEditor] Failed to load agents:', err);
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
      setEndpointUrl(card.endpoint_url || '');
      setSelectedAgentId(card.ai_agent_id || '');
      setStreamingEnabled(card.capabilities?.streaming ?? true);
      setPushNotificationsEnabled(card.capabilities?.push_notifications ?? false);
      setAuthSchemes(card.authentication?.schemes || []);

      if (card.capabilities?.skills && card.capabilities.skills.length > 0) {
        setSkills(
          card.capabilities.skills.map((skill) => {
            // Handle both string and object skills from backend
            if (typeof skill === 'string') {
              return {
                id: skill,
                name: skill,
                description: '',
                tags: '',
                inputSchema: '',
                outputSchema: '',
              };
            }
            // AgentSkill type from A2A types
            return {
              id: String(skill.id || ''),
              name: String(skill.name || ''),
              description: String(skill.description || ''),
              tags: '',
              inputSchema: skill.inputSchema ? JSON.stringify(skill.inputSchema, null, 2) : '',
              outputSchema: skill.outputSchema ? JSON.stringify(skill.outputSchema, null, 2) : '',
            };
          })
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

  const handleValidate = () => {
    setValidating(true);
    setValidationResult(null);
    const errors: string[] = [];

    // Validate name
    if (!name.trim()) {
      errors.push('Name is required');
    }

    // Validate endpoint URL format
    if (endpointUrl.trim()) {
      try {
        new URL(endpointUrl);
      } catch {
        errors.push('Endpoint URL is not a valid URL');
      }
    }

    // Validate skills
    skills.forEach((skill, index) => {
      const skillNum = index + 1;

      // Check that skill has at least an ID or name
      if (!skill.id.trim() && !skill.name.trim()) {
        errors.push(`Skill ${skillNum}: Must have an ID or Name`);
      }

      // Validate input schema JSON
      if (skill.inputSchema.trim()) {
        try {
          JSON.parse(skill.inputSchema);
        } catch {
          errors.push(`Skill ${skillNum}: Input Schema is not valid JSON`);
        }
      }

      // Validate output schema JSON
      if (skill.outputSchema.trim()) {
        try {
          JSON.parse(skill.outputSchema);
        } catch {
          errors.push(`Skill ${skillNum}: Output Schema is not valid JSON`);
        }
      }
    });

    setValidationResult({
      valid: errors.length === 0,
      errors,
    });
    setValidating(false);

    if (errors.length === 0) {
      addNotification({ type: 'success', title: 'Valid', message: 'All fields are valid' });
    }
  };

  const parseSkills = (): AgentSkill[] => {
    return skills
      .filter((s) => s.id.trim() || s.name.trim())
      .map((s) => {
        const skill: AgentSkill = {
          id: s.id.trim() || s.name.trim().toLowerCase().replace(/\s+/g, '_'),
          name: s.name.trim() || s.id.trim(),
        };
        if (s.description.trim()) skill.description = s.description.trim();
        if (s.inputSchema.trim()) {
          try {
            skill.inputSchema = JSON.parse(s.inputSchema);
          } catch {
            // Invalid JSON ignored - user should run validation first
          }
        }
        if (s.outputSchema.trim()) {
          try {
            skill.outputSchema = JSON.parse(s.outputSchema);
          } catch {
            // Invalid JSON ignored - user should run validation first
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
          authentication: authSchemes.length > 0 ? { schemes: authSchemes as ('bearer' | 'api_key' | 'oauth2' | 'basic' | 'none')[] } : undefined,
        };

        const response = await agentCardsApiService.updateAgentCard(cardId, updateData);
        addNotification({ type: 'success', title: 'Saved', message: 'Agent card updated' });
        onSave?.(response.agent_card);
      } else {
        const createData: CreateAgentCardRequest = {
          name: name.trim(),
          description: description.trim() || undefined,
          visibility,
          endpoint_url: endpointUrl.trim() || undefined,
          ai_agent_id: selectedAgentId || undefined,
          capabilities: {
            skills: parsedSkills,
            streaming: streamingEnabled,
            push_notifications: pushNotificationsEnabled,
          },
          authentication: authSchemes.length > 0 ? { schemes: authSchemes as ('bearer' | 'api_key' | 'oauth2' | 'basic' | 'none')[] } : undefined,
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
              <Button variant="outline" size="sm" onClick={handleValidate} disabled={validating}>
                <CheckCircle className="h-4 w-4 mr-2" />
                {validating ? 'Validating...' : 'Validate'}
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
      {error && <ErrorAlert message={error} />}

      {/* Validation Result */}
      {validationResult && (
        <div className={cn(
          'p-4 rounded-lg border',
          validationResult.valid
            ? 'bg-theme-success/10 border-theme-success/30'
            : 'bg-theme-danger/10 border-theme-danger/30'
        )}>
          <div className={cn(
            'flex items-center gap-2',
            validationResult.valid ? 'text-theme-success' : 'text-theme-danger'
          )}>
            {validationResult.valid ? (
              <>
                <CheckCircle className="h-4 w-4" />
                <span className="font-medium">All validations passed</span>
              </>
            ) : (
              <>
                <AlertCircle className="h-4 w-4" />
                <span className="font-medium">Validation errors ({validationResult.errors.length})</span>
              </>
            )}
          </div>
          {validationResult.errors.length > 0 && (
            <ul className="mt-2 ml-6 list-disc text-sm text-theme-danger">
              {validationResult.errors.map((err, idx) => (
                <li key={idx}>{err}</li>
              ))}
            </ul>
          )}
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
                onChange={(value) => setVisibility(value as 'private' | 'internal' | 'public')}
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
                  onChange={(value) => setSelectedAgentId(value)}
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
                    rows={8}
                  />
                </div>
                <div>
                  <label className="block text-xs text-theme-muted mb-1">Output Schema (JSON)</label>
                  <textarea
                    value={skill.outputSchema}
                    onChange={(e) => handleSkillChange(index, 'outputSchema', e.target.value)}
                    placeholder='{"type": "object", "properties": {...}}'
                    className="w-full px-3 py-2 border border-theme rounded-lg bg-theme-surface text-theme-primary font-mono text-xs focus:outline-none focus:ring-2 focus:ring-theme-primary"
                    rows={8}
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
