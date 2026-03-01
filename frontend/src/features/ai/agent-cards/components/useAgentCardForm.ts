import { useState, useEffect } from 'react';
import { agentCardsApiService, agentsApi } from '@/shared/services/ai';
import { useNotifications } from '@/shared/hooks/useNotifications';
import type {
  AgentCard,
  CreateAgentCardRequest,
  UpdateAgentCardRequest,
  AgentSkill,
} from '@/shared/services/ai/types/a2a-types';
import type { AiAgent } from '@/shared/types/ai';
import type { SkillInput } from './SkillEditor';

const emptySkill: SkillInput = {
  id: '',
  name: '',
  description: '',
  tags: '',
  inputSchema: '',
  outputSchema: '',
};

interface UseAgentCardFormOptions {
  cardId?: string;
  onSave?: (card: AgentCard) => void;
}

export function useAgentCardForm({ cardId, onSave }: UseAgentCardFormOptions) {
  const [loading, setLoading] = useState(!!cardId);
  const [saving, setSaving] = useState(false);
  const [validating, setValidating] = useState(false);
  const [validationResult, setValidationResult] = useState<{ valid: boolean; errors: string[] } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [agents, setAgents] = useState<AiAgent[]>([]);

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
    if (cardId) loadCard();
  }, [cardId]);

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
        // Agent may not have skills
      }
    };
    loadAgentSkills();
  }, [selectedAgentId, isEditMode]);

  const loadAgents = async () => {
    try {
      const response = await agentsApi.getAgents({ per_page: 100 });
      setAgents(response.items || []);
    } catch {
      // Silent fail
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
            if (typeof skill === 'string') {
              return { id: skill, name: skill, description: '', tags: '', inputSchema: '', outputSchema: '' };
            }
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
    if (!name.trim()) errors.push('Name is required');
    if (endpointUrl.trim()) {
      try { new URL(endpointUrl); } catch { errors.push('Endpoint URL is not a valid URL'); }
    }
    skills.forEach((skill, index) => {
      const skillNum = index + 1;
      if (!skill.id.trim() && !skill.name.trim()) errors.push(`Skill ${skillNum}: Must have an ID or Name`);
      if (skill.inputSchema.trim()) {
        try { JSON.parse(skill.inputSchema); } catch { errors.push(`Skill ${skillNum}: Input Schema is not valid JSON`); }
      }
      if (skill.outputSchema.trim()) {
        try { JSON.parse(skill.outputSchema); } catch { errors.push(`Skill ${skillNum}: Output Schema is not valid JSON`); }
      }
    });
    setValidationResult({ valid: errors.length === 0, errors });
    setValidating(false);
    if (errors.length === 0) {
      addNotification({ type: 'success', title: 'Valid', message: 'All fields are valid' });
    }
  };

  const parseSkills = (): AgentSkill[] =>
    skills
      .filter((s) => s.id.trim() || s.name.trim())
      .map((s) => {
        const skill: AgentSkill = {
          id: s.id.trim() || s.name.trim().toLowerCase().replace(/\s+/g, '_'),
          name: s.name.trim() || s.id.trim(),
        };
        if (s.description.trim()) skill.description = s.description.trim();
        if (s.inputSchema.trim()) {
          try { skill.inputSchema = JSON.parse(s.inputSchema); } catch { /* skip */ }
        }
        if (s.outputSchema.trim()) {
          try { skill.outputSchema = JSON.parse(s.outputSchema); } catch { /* skip */ }
        }
        return skill;
      });

  const handleSave = async () => {
    if (!name.trim()) { setError('Name is required'); return; }
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
          capabilities: { skills: parsedSkills, streaming: streamingEnabled, push_notifications: pushNotificationsEnabled },
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
          capabilities: { skills: parsedSkills, streaming: streamingEnabled, push_notifications: pushNotificationsEnabled },
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

  return {
    loading, saving, validating, validationResult, error, agents, isEditMode,
    name, setName, description, setDescription, visibility, setVisibility,
    endpointUrl, setEndpointUrl, selectedAgentId, setSelectedAgentId,
    skills, streamingEnabled, setStreamingEnabled,
    pushNotificationsEnabled, setPushNotificationsEnabled,
    authSchemes,
    handleAddSkill, handleRemoveSkill, handleSkillChange,
    handleAuthSchemeToggle, handleValidate, handleSave,
  };
}
