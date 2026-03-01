import { useState, useEffect, useCallback } from 'react';
import { useForm } from '@/shared/hooks/useForm';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { agentsApi, providersApi } from '@/shared/services/ai';
import { skillsApi } from '@/features/ai/skills/services/skillsApi';
import type { AiAgent, AiProvider } from '@/shared/types/ai';
import type { AiAgentSkill, AgentStats } from '@/shared/services/ai/types/agent-api-types';

export interface SkillOption {
  id: string;
  name: string;
  slug: string;
  category: string;
}

export interface EditAgentFormData {
  ai_provider_id: string;
  name: string;
  description: string;
  agent_type: string;
  model: string;
  temperature: number;
  max_tokens: number;
  system_prompt: string;
  is_active: boolean;
}

export const AGENT_TYPES = [
  { value: 'assistant', label: 'Assistant' },
  { value: 'code_assistant', label: 'Code Assistant' },
  { value: 'data_analyst', label: 'Data Analyst' },
  { value: 'content_generator', label: 'Content Generator' },
  { value: 'image_generator', label: 'Image Generator' },
  { value: 'workflow_optimizer', label: 'Workflow Optimizer' }
];

interface UseEditAgentFormOptions {
  agent: AiAgent | null;
  isOpen: boolean;
  onAgentUpdated?: (agent: AiAgent) => void;
  onAgentDeleted?: (agentId: string) => void;
  onClose: () => void;
}

export function useEditAgentForm({ agent, isOpen, onAgentUpdated, onAgentDeleted, onClose }: UseEditAgentFormOptions) {
  const [providers, setProviders] = useState<AiProvider[]>([]);
  const [selectedProvider, setSelectedProvider] = useState<AiProvider | null>(null);
  const [loadingProviders, setLoadingProviders] = useState(false);
  const [agentStats, setAgentStats] = useState<AgentStats | null>(null);
  const [, setLoadingStats] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [previousProviderId, setPreviousProviderId] = useState<string | null>(null);
  const [assignedSkills, setAssignedSkills] = useState<AiAgentSkill[]>([]);
  const [availableSkills, setAvailableSkills] = useState<SkillOption[]>([]);
  const [loadingSkills, setLoadingSkills] = useState(true);
  const { addNotification } = useNotifications();

  const form = useForm<EditAgentFormData>({
    initialValues: {
      ai_provider_id: agent?.provider?.id || '',
      name: agent?.name || '',
      description: agent?.description || '',
      agent_type: agent?.agent_type || 'assistant',
      model: agent?.model || '',
      temperature: agent?.temperature ?? 0.7,
      max_tokens: agent?.max_tokens ?? 2048,
      system_prompt: agent?.system_prompt || '',
      is_active: agent?.status === 'active',
    },
    validationRules: {
      ai_provider_id: { required: true },
      name: { required: true, minLength: 2, maxLength: 100 },
      description: { maxLength: 500 },
      agent_type: { required: true },
      model: { required: true },
      temperature: {
        required: true,
        custom: (value) => {
          const num = Number(value);
          if (isNaN(num) || num < 0 || num > 2) return 'Temperature must be between 0 and 2';
          return null;
        }
      },
      max_tokens: {
        required: true,
        custom: (value) => {
          const num = Number(value);
          if (isNaN(num) || num < 1 || num > 32000) return 'Max tokens must be between 1 and 32000';
          return null;
        }
      },
      system_prompt: { maxLength: 2000 }
    },
    onSubmit: async (values) => {
      if (!agent) return;
      const updateData = {
        ai_provider_id: values.ai_provider_id,
        name: values.name,
        description: values.description || undefined,
        agent_type: values.agent_type as AiAgent['agent_type'],
        model: values.model,
        temperature: values.temperature,
        max_tokens: values.max_tokens,
        system_prompt: values.system_prompt || undefined,
        status: values.is_active ? 'active' : 'inactive',
      };
      const updatedAgent = await agentsApi.updateAgent(agent.id, updateData);
      onAgentUpdated?.(updatedAgent);
      onClose();
    },
    enableRealTimeValidation: true,
    resetAfterSubmit: false,
    showSuccessNotification: true,
    successMessage: 'AI agent updated successfully'
  });

  useEffect(() => {
    if (agent && isOpen) {
      setPreviousProviderId(null);
      form.setValue('ai_provider_id', agent.provider?.id || '');
      form.setValue('name', agent.name);
      form.setValue('description', agent.description || '');
      form.setValue('agent_type', agent.agent_type);
      form.setValue('model', agent.model || '');
      form.setValue('temperature', agent.temperature ?? 0.7);
      form.setValue('max_tokens', agent.max_tokens ?? 2048);
      form.setValue('system_prompt', agent.system_prompt || '');
      form.setValue('is_active', agent.status === 'active');
    }
  }, [agent, isOpen]);

  useEffect(() => {
    if (isOpen && agent) {
      loadProviders();
      loadAgentStats();
      loadSkills();
    }
  }, [isOpen, agent]);

  const loadSkills = async () => {
    if (!agent) return;
    setLoadingSkills(true);
    try {
      const [agentSkillsRes, allSkillsRes] = await Promise.all([
        agentsApi.getAgentSkills(agent.id),
        skillsApi.getSkills(1, 100),
      ]);
      setAssignedSkills(agentSkillsRes ?? []);
      if (allSkillsRes.success && allSkillsRes.data?.skills) {
        setAvailableSkills(allSkillsRes.data.skills.map((s: { id: string; name: string; slug: string; category: string }) => ({
          id: s.id, name: s.name, slug: s.slug, category: s.category,
        })));
      }
    } catch (_error) {
      setAssignedSkills([]);
      setAvailableSkills([]);
    } finally {
      setLoadingSkills(false);
    }
  };

  const handleAssignSkill = useCallback(async (skillId: string) => {
    if (!agent) return;
    try {
      await agentsApi.assignSkill(agent.id, skillId);
      loadSkills();
    } catch (_error) {
      addNotification({ type: 'error', title: 'Error', message: 'Failed to assign skill' });
    }
  }, [agent]);

  const handleRemoveSkill = useCallback(async (skillId: string) => {
    if (!agent) return;
    try {
      await agentsApi.removeSkill(agent.id, skillId);
      loadSkills();
    } catch (_error) {
      addNotification({ type: 'error', title: 'Error', message: 'Failed to remove skill' });
    }
  }, [agent]);

  useEffect(() => {
    const fetchProviderDetails = async () => {
      if (!form.values.ai_provider_id) {
        setSelectedProvider(null);
        return;
      }
      try {
        const providerDetail = await providersApi.getProvider(form.values.ai_provider_id);
        setSelectedProvider(providerDetail);
        const isProviderChange = previousProviderId !== null && previousProviderId !== form.values.ai_provider_id;
        if (isProviderChange && providerDetail.supported_models?.length > 0) {
          const modelInList = providerDetail.supported_models.some((model: { id: string; name: string }) =>
            model.id === form.values.model || model.name === form.values.model
          );
          if (!modelInList) form.setValue('model', '');
        }
        setPreviousProviderId(form.values.ai_provider_id);
      } catch (_error) {
        const provider = providers.find(p => p.id === form.values.ai_provider_id);
        setSelectedProvider(provider || null);
      }
    };
    fetchProviderDetails();
  }, [form.values.ai_provider_id]);

  const loadProviders = async () => {
    try {
      setLoadingProviders(true);
      const response = await providersApi.getProviders({ status: 'active' });
      setProviders(response.items || []);
    } catch (_error) {
      setProviders([]);
      addNotification({ type: 'error', title: 'Error', message: 'Failed to load AI providers' });
    } finally {
      setLoadingProviders(false);
    }
  };

  const loadAgentStats = async () => {
    if (!agent) return;
    try {
      setLoadingStats(true);
      const stats = await agentsApi.getAgentStats(agent.id);
      setAgentStats(stats);
    } catch (error) {
      const httpError = error as { response?: { status?: number } };
      if (httpError?.response?.status === 404) {
        setAgentStats({
          total_executions: agent.execution_stats?.total_executions || 0,
          successful_executions: agent.execution_stats?.successful_executions || 0,
          failed_executions: agent.execution_stats?.failed_executions || 0,
          success_rate: agent.execution_stats?.success_rate || 0,
          avg_execution_time: agent.execution_stats?.avg_execution_time || 0,
          estimated_total_cost: '0.00',
          created_at: agent.created_at
        });
      } else {
        setAgentStats(null);
      }
    } finally {
      setLoadingStats(false);
    }
  };

  const handleDeleteAgent = async () => {
    if (!agent) return;
    try {
      setDeleting(true);
      await agentsApi.deleteAgent(agent.id);
      onAgentDeleted?.(agent.id);
      addNotification({ type: 'success', title: 'Success', message: 'AI agent deleted successfully' });
      onClose();
    } catch (_error) {
      addNotification({ type: 'error', title: 'Error', message: 'Failed to delete AI agent' });
    } finally {
      setDeleting(false);
      setShowDeleteConfirm(false);
    }
  };

  const getProviderOptions = () => {
    if (!providers || !Array.isArray(providers)) return [];
    return providers.map(provider => ({
      value: provider.id,
      label: `${provider.name} (${provider.provider_type})`,
      disabled: !provider.is_active
    }));
  };

  const getModelOptions = () => {
    if (!selectedProvider?.supported_models?.length) return [];
    return selectedProvider.supported_models.map(model => ({
      value: model.id,
      label: model.name || model.id
    }));
  };

  const handleClose = () => {
    form.reset();
    setShowDeleteConfirm(false);
    onClose();
  };

  return {
    form,
    providers,
    selectedProvider,
    loadingProviders,
    agentStats,
    showDeleteConfirm,
    setShowDeleteConfirm,
    deleting,
    assignedSkills,
    availableSkills,
    loadingSkills,
    handleAssignSkill,
    handleRemoveSkill,
    handleDeleteAgent,
    getProviderOptions,
    getModelOptions,
    handleClose,
  };
}
