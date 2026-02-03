import React, { useState, useEffect } from 'react';
import { Brain, Sparkles } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { FormField } from '@/shared/components/forms/FormField';
import { SelectField } from '@/shared/components/forms/SelectField';
import { TextAreaField } from '@/shared/components/forms/TextAreaField';
import { useForm } from '@/shared/hooks/useForm';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { agentsApi, providersApi } from '@/shared/services/ai';
import type { CreateAgentRequest } from '@/shared/services/ai/types/agent-api-types';
import type { AiProvider, AiAgent } from '@/shared/types/ai';

interface CreateAgentModalProps {
  isOpen: boolean;
  onClose: () => void;
  onAgentCreated?: (agent: AiAgent) => void;
  defaultAgentType?: string;
}

interface CreateAgentFormData {
  ai_provider_id: string;
  name: string;
  description: string;
  agent_type: string;
  model: string;
  temperature: number;
  max_tokens: number;
  system_prompt: string;
}

const AGENT_TYPES = [
  { value: 'assistant', label: 'Assistant' },
  { value: 'code_assistant', label: 'Code Assistant' },
  { value: 'data_analyst', label: 'Data Analyst' },
  { value: 'content_generator', label: 'Content Generator' },
  { value: 'image_generator', label: 'Image Generator' },
  { value: 'workflow_optimizer', label: 'Workflow Optimizer' },
  { value: 'workflow_operations', label: 'Workflow Operations' }
];

export const CreateAgentModal: React.FC<CreateAgentModalProps> = ({
  isOpen,
  onClose,
  onAgentCreated,
  defaultAgentType
}) => {
  const [providers, setProviders] = useState<AiProvider[]>([]);
  const [selectedProvider, setSelectedProvider] = useState<AiProvider | null>(null);
  const [loadingProviders, setLoadingProviders] = useState(false);
  const { addNotification } = useNotifications();

  const form = useForm<CreateAgentFormData>({
    initialValues: {
      ai_provider_id: '',
      name: '',
      description: '',
      agent_type: defaultAgentType || 'assistant',
      model: '',
      temperature: 0.7,
      max_tokens: 2048,
      system_prompt: ''
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
          if (isNaN(num) || num < 0 || num > 2) {
            return 'Temperature must be between 0 and 2';
          }
          return null;
        }
      },
      max_tokens: {
        required: true,
        custom: (value) => {
          const num = Number(value);
          if (isNaN(num) || num < 1 || num > 32000) {
            return 'Max tokens must be between 1 and 32000';
          }
          return null;
        }
      },
      system_prompt: { maxLength: 2000 }
    },
    onSubmit: async (values) => {
      const agentData: CreateAgentRequest = {
        ai_provider_id: values.ai_provider_id,
        name: values.name,
        description: values.description || undefined,
        agent_type: values.agent_type,
        model_name: values.model,
        system_instructions: values.system_prompt || undefined,
        configuration: {
          model: values.model,
          temperature: values.temperature,
          max_tokens: values.max_tokens
        }
      };

      const agent = await agentsApi.createAgent(agentData);
      onAgentCreated?.(agent);
      onClose();
    },
    enableRealTimeValidation: true,
    resetAfterSubmit: false,
    showSuccessNotification: true,
    successMessage: 'AI agent created successfully'
  });

  // Load providers on mount
  useEffect(() => {
    if (isOpen) {
      loadProviders();
    }
     
  }, [isOpen]);

  // Update selected provider when provider changes
  useEffect(() => {
    if (form.values.ai_provider_id && providers && Array.isArray(providers)) {
      const provider = providers.find(p => p.id === form.values.ai_provider_id);
      setSelectedProvider(provider || null);

      // Reset model selection when provider changes if current model not supported
      if (provider && provider.supported_models && Array.isArray(provider.supported_models) && provider.supported_models.length > 0) {
        const modelExists = provider.supported_models.some(model => model.id === form.values.model);
        if (!modelExists && form.values.model) {
          form.setValue('model', '');
        }
      }
    } else {
      setSelectedProvider(null);
    }
     
  }, [form.values.ai_provider_id, providers]);

  const loadProviders = async () => {
    try {
      setLoadingProviders(true);
      const { items: providersData } = await providersApi.getProviders({ status: 'active' });
      setProviders(providersData || []);
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Error',
        message: 'Failed to load AI providers'
      });
    } finally {
      setLoadingProviders(false);
    }
  };

  const getProviderOptions = () => {
    if (!providers || !Array.isArray(providers)) {
      return [];
    }
    return providers.map(provider => ({
      value: provider.id,
      label: `${provider.name} (${provider.provider_type})`,
      disabled: !provider.is_active
    }));
  };

  const getModelOptions = () => {
    if (!selectedProvider || !selectedProvider.supported_models || !Array.isArray(selectedProvider.supported_models)) {
      return [];
    }
    
    return selectedProvider.supported_models.map(model => ({
      value: model.id,
      label: model.name || model.id
    }));
  };

  const handleClose = () => {
    form.reset();
    onClose();
  };

  const modalFooter = (
    <>
      <Button
        variant="ghost"
        onClick={handleClose}
        disabled={form.isSubmitting}
      >
        Cancel
      </Button>
      <Button
        onClick={form.handleSubmit}
        loading={form.isSubmitting}
        disabled={!form.isValid}
      >
        Create Agent
      </Button>
    </>
  );

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title="Create AI Agent"
      subtitle="Configure a new AI agent for automation and task execution"
      icon={<Brain />}
      maxWidth="2xl"
      footer={modalFooter}
    >
      <form onSubmit={form.handleSubmit} className="space-y-6">
        {/* Basic Information */}
        <div className="space-y-4">
          <h4 className="text-sm font-semibold text-theme-primary border-b border-theme pb-2">
            Basic Information
          </h4>
          
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <FormField
              label="Agent Name"
              name="name"
              placeholder="e.g., Content Generator"
              required
              form={form}
              helpText="A descriptive name for your AI agent"
            />
            
            <SelectField
              label="Agent Type"
              name="agent_type"
              options={AGENT_TYPES}
              required
              form={form}
              helpText="The primary function of this agent"
            />
          </div>

          <TextAreaField
            label="Description"
            name="description"
            placeholder="Describe what this agent does and how it should be used..."
            form={form}
            rows={3}
            maxLength={500}
            showCharacterCount
            helpText="Optional description of the agent's purpose and capabilities"
          />
        </div>

        {/* AI Provider Configuration */}
        <div className="space-y-4">
          <h4 className="text-sm font-semibold text-theme-primary border-b border-theme pb-2">
            AI Provider Configuration
          </h4>
          
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <SelectField
              label="AI Provider"
              name="ai_provider_id"
              options={getProviderOptions()}
              placeholder={loadingProviders ? "Loading providers..." : "Select an AI provider"}
              required
              form={form}
              disabled={loadingProviders}
              helpText="The AI service that will power this agent"
            />
            
            <SelectField
              label="Model"
              name="model"
              options={getModelOptions()}
              placeholder={selectedProvider ? "Select a model" : "Choose provider first"}
              required
              form={form}
              disabled={!selectedProvider}
              helpText="The specific AI model to use"
            />
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <FormField
              label="Temperature"
              name="temperature"
              type="number"
              placeholder="0.7"
              required
              form={form}
              helpText="Controls randomness (0.0 = deterministic, 2.0 = very creative)"
            />
            
            <FormField
              label="Max Tokens"
              name="max_tokens"
              type="number"
              placeholder="2048"
              required
              form={form}
              helpText="Maximum response length in tokens"
            />
          </div>
        </div>

        {/* Advanced Configuration */}
        <div className="space-y-4">
          <h4 className="text-sm font-semibold text-theme-primary border-b border-theme pb-2">
            Advanced Configuration
          </h4>
          
          <TextAreaField
            label="System Prompt"
            name="system_prompt"
            placeholder="You are a helpful AI assistant. Your role is to..."
            form={form}
            rows={4}
            maxLength={2000}
            showCharacterCount
            helpText="Instructions that define the agent's behavior and personality"
          />
        </div>

        {/* Provider Info Card */}
        {selectedProvider && (
          <div className="bg-theme-surface border border-theme rounded-lg p-4">
            <div className="flex items-start gap-3">
              <div className="h-10 w-10 bg-theme-info bg-opacity-10 rounded-lg flex items-center justify-center">
                <Sparkles className="h-5 w-5 text-theme-info" />
              </div>
              <div>
                <h5 className="font-semibold text-theme-primary">{selectedProvider.name}</h5>
                <p className="text-sm text-theme-secondary">{selectedProvider.description}</p>
                <div className="mt-2 flex flex-wrap gap-2">
                  {selectedProvider.capabilities && Array.isArray(selectedProvider.capabilities) && selectedProvider.capabilities.slice(0, 3).map(capability => (
                    <span
                      key={capability}
                      className="px-2 py-1 text-xs bg-theme-info bg-opacity-10 text-theme-info rounded"
                    >
                      {capability}
                    </span>
                  ))}
                  {selectedProvider.capabilities && selectedProvider.capabilities.length > 3 && (
                    <span className="px-2 py-1 text-xs bg-theme-surface text-theme-tertiary rounded">
                      +{selectedProvider.capabilities.length - 3} more
                    </span>
                  )}
                </div>
              </div>
            </div>
          </div>
        )}
      </form>
    </Modal>
  );
};