import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';

interface ProviderFormData {
  name: string;
  slug: string;
  provider_type: string;
  description: string;
  api_base_url: string;
  capabilities: string[];
  documentation_url: string;
  status_url: string;
  is_active: boolean;
}

interface ProviderFormFieldsProps {
  data: ProviderFormData;
  onChange: (field: string, value: string | boolean) => void;
  onCapabilityChange: (capability: string, checked: boolean) => void;
}

const availableCapabilities = [
  'text_generation',
  'chat',
  'vision',
  'function_calling',
  'code_execution',
  'image_generation',
  'embeddings'
];

export const ProviderFormFields: React.FC<ProviderFormFieldsProps> = ({
  data,
  onChange,
  onCapabilityChange
}) => {
  return (
    <>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Provider Name *
          </label>
          <Input
            value={data.name}
            onChange={(e) => onChange('name', e.target.value)}
            placeholder="e.g., Custom AI Provider"
            required
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Slug *
          </label>
          <Input
            value={data.slug}
            onChange={(e) => onChange('slug', e.target.value)}
            placeholder="custom-ai-provider"
            required
            disabled={true}
            className="bg-theme-secondary/10"
          />
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Provider Type *
          </label>
          <Select
            value={data.provider_type}
            onChange={(value) => onChange('provider_type', value)}
            disabled={true}
            className="bg-theme-secondary/10"
          >
            <option value="">Select a provider type</option>
            <option value="openai">OpenAI</option>
            <option value="anthropic">Anthropic (Claude)</option>
            <option value="google">Google (Gemini/Vertex AI)</option>
            <option value="cohere">Cohere</option>
            <option value="huggingface">Hugging Face</option>
            <option value="ollama">Ollama</option>
            <option value="azure_openai">Azure OpenAI</option>
            <option value="mistral">Mistral AI</option>
            <option value="custom">Custom/Other</option>
          </Select>
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Status
          </label>
          <Select
            value={data.is_active ? 'active' : 'inactive'}
            onChange={(value) => onChange('is_active', value === 'active')}
          >
            <option value="active">Active</option>
            <option value="inactive">Inactive</option>
          </Select>
        </div>
      </div>

      <div>
        <label className="block text-sm font-medium text-theme-secondary mb-1">
          Description
        </label>
        <textarea
          value={data.description}
          onChange={(e) => onChange('description', e.target.value)}
          placeholder="Brief description of the AI provider..."
          rows={3}
          className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-info focus:border-transparent"
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-theme-secondary mb-1">
          API Base URL
        </label>
        <Input
          value={data.api_base_url}
          onChange={(e) => onChange('api_base_url', e.target.value)}
          placeholder="https://api.provider.com/v1"
          type="url"
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-theme-secondary mb-2">
          Capabilities
        </label>
        <div className="grid grid-cols-2 md:grid-cols-3 gap-2">
          {availableCapabilities.map((capability) => (
            <label key={capability} className="flex items-center space-x-2">
              <input
                type="checkbox"
                checked={data.capabilities.includes(capability)}
                onChange={(e) => onCapabilityChange(capability, e.target.checked)}
                className="rounded border-theme-300 text-theme-info focus:ring-theme-info"
              />
              <span className="text-sm text-theme-secondary capitalize">
                {capability.replace('_', ' ')}
              </span>
            </label>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Documentation URL
          </label>
          <Input
            value={data.documentation_url}
            onChange={(e) => onChange('documentation_url', e.target.value)}
            placeholder="https://docs.provider.com"
            type="url"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Status URL
          </label>
          <Input
            value={data.status_url}
            onChange={(e) => onChange('status_url', e.target.value)}
            placeholder="https://status.provider.com"
            type="url"
          />
        </div>
      </div>
    </>
  );
};
