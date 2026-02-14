import React from 'react';
import { Sparkles } from 'lucide-react';
import { FormField } from '@/shared/components/forms/FormField';
import { SelectField } from '@/shared/components/forms/SelectField';
import { TextAreaField } from '@/shared/components/forms/TextAreaField';
import type { UseFormReturn } from '@/shared/hooks/useForm';
import type { AiProvider } from '@/shared/types/ai';
import type { EditAgentFormData, AGENT_TYPES } from './useEditAgentForm';

interface AgentFormFieldsProps {
  form: UseFormReturn<EditAgentFormData>;
  agentTypes: typeof AGENT_TYPES;
  providerOptions: Array<{ value: string; label: string; disabled?: boolean }>;
  modelOptions: Array<{ value: string; label: string }>;
  loadingProviders: boolean;
  selectedProvider: AiProvider | null;
}

export const AgentFormFields: React.FC<AgentFormFieldsProps> = ({
  form,
  agentTypes,
  providerOptions,
  modelOptions,
  loadingProviders,
  selectedProvider,
}) => {
  return (
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
            options={agentTypes}
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
            options={providerOptions}
            placeholder={loadingProviders ? "Loading providers..." : "Select an AI provider"}
            required
            form={form}
            disabled={loadingProviders}
            helpText="The AI service that will power this agent"
          />
          <SelectField
            label="Model"
            name="model"
            options={modelOptions}
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

      {/* Status Toggle */}
      <div className="space-y-4">
        <h4 className="text-sm font-semibold text-theme-primary border-b border-theme pb-2">
          Agent Status
        </h4>
        <label className="flex items-center justify-between p-4 bg-theme-surface border border-theme rounded-lg cursor-pointer hover:bg-theme-surface-hover transition-colors">
          <div className="flex items-center gap-3">
            <div className={`h-10 w-10 rounded-lg flex items-center justify-center ${
              form.values.is_active ? 'bg-theme-success bg-opacity-10' : 'bg-theme-muted bg-opacity-10'
            }`}>
              <Sparkles className={`h-5 w-5 ${form.values.is_active ? 'text-theme-success' : 'text-theme-muted'}`} />
            </div>
            <div>
              <div className="font-medium text-theme-primary">
                {form.values.is_active ? 'Agent Active' : 'Agent Inactive'}
              </div>
              <div className="text-sm text-theme-secondary">
                {form.values.is_active
                  ? 'This agent is available for workflows and conversations'
                  : 'This agent is disabled and cannot be used'}
              </div>
            </div>
          </div>
          <div className="relative">
            <input
              type="checkbox"
              checked={form.values.is_active}
              onChange={(e) => form.setValue('is_active', e.target.checked)}
              className="sr-only"
            />
            <div className={`w-11 h-6 rounded-full transition-colors ${
              form.values.is_active ? 'bg-theme-success' : 'bg-theme-muted'
            }`}>
              <div className={`absolute top-0.5 left-0.5 w-5 h-5 bg-white rounded-full shadow transform transition-transform ${
                form.values.is_active ? 'translate-x-5' : 'translate-x-0'
              }`} />
            </div>
          </div>
        </label>
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
                {selectedProvider.capabilities.slice(0, 3).map(capability => (
                  <span
                    key={capability}
                    className="px-2 py-1 text-xs bg-theme-info bg-opacity-10 text-theme-info rounded"
                  >
                    {capability}
                  </span>
                ))}
                {selectedProvider.capabilities.length > 3 && (
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
  );
};
