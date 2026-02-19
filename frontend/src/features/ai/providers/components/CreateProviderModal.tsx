import React, { useState } from 'react';
import { X, Plus } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { Modal } from '@/shared/components/ui/Modal';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { providersApi } from '@/shared/services/ai';

interface CreateProviderModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
}

export const CreateProviderModal: React.FC<CreateProviderModalProps> = ({
  isOpen,
  onClose,
  onSuccess
}) => {
  const [loading, setLoadingSpinner] = useState(false);
  const [formData, setFormData] = useState({
    name: '',
    slug: '',
    provider_type: 'custom',
    description: '',
    api_base_url: '',
    capabilities: ['text_generation'],
    documentation_url: '',
    status_url: ''
  });

  const { addNotification } = useNotifications();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoadingSpinner(true);

    try {
      await providersApi.createProvider({
        name: formData.name,
        provider_type: formData.provider_type,
        slug: formData.slug,
        description: formData.description,
        api_base_url: formData.api_base_url || undefined,
        api_endpoint: formData.api_base_url || undefined,
        capabilities: formData.capabilities,
        documentation_url: formData.documentation_url || undefined,
        status_url: formData.status_url || undefined,
        supported_models: [{ name: 'default', id: 'default' }],
        configuration_schema: {
          type: 'object',
          properties: {
            api_key: {
              type: 'string',
              description: 'API key for authentication'
            }
          },
          required: ['api_key']
        },
        is_active: true
      });

      addNotification({
        type: 'success',
        title: 'Provider Created',
        message: `${formData.name} has been created successfully`
      });

      onSuccess();
      onClose();
      
      // Reset form
      setFormData({
        name: '',
        slug: '',
        provider_type: 'custom',
        description: '',
        api_base_url: '',
        capabilities: ['text_generation'],
        documentation_url: '',
        status_url: ''
      });
    } catch (_error) {
      addNotification({
        type: 'error',
        title: 'Creation Failed',
        message: 'Failed to create AI provider. Please try again.'
      });
    } finally {
      setLoadingSpinner(false);
    }
  };

  const handleInputChange = (field: string, value: string) => {
    setFormData(prev => ({ ...prev, [field]: value }));

    // Auto-generate slug from name
    if (field === 'name') {
      const slug = value.toLowerCase().replace(/[^a-z0-9]/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '');
      setFormData(prev => ({ ...prev, slug }));
    }
  };

  const handleCapabilityChange = (capability: string, checked: boolean) => {
    setFormData(prev => ({
      ...prev,
      capabilities: checked
        ? [...prev.capabilities, capability]
        : prev.capabilities.filter(c => c !== capability)
    }));
  };

  const availableCapabilities = [
    'text_generation',
    'chat',
    'vision',
    'function_calling',
    'code_execution',
    'image_generation',
    'text_embedding'
  ];

  return (
    <Modal isOpen={isOpen} onClose={onClose} size="lg">
      <div className="flex items-center justify-between p-6 border-b border-theme">
        <h2 className="text-xl font-semibold text-theme-primary">Create AI Provider</h2>
        <Button
          variant="ghost"
          size="sm"
          onClick={onClose}
          className="h-8 w-8 p-0"
        >
          <X className="h-4 w-4" />
        </Button>
      </div>

      <form onSubmit={handleSubmit} className="p-6 space-y-6">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">
              Provider Name *
            </label>
            <Input
              value={formData.name}
              onChange={(e) => handleInputChange('name', e.target.value)}
              placeholder="e.g., Custom AI Provider"
              required
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">
              Slug *
            </label>
            <Input
              value={formData.slug}
              onChange={(e) => handleInputChange('slug', e.target.value)}
              placeholder="custom-ai-provider"
              required
            />
          </div>
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Provider Type *
          </label>
          <Select
            value={formData.provider_type}
            onChange={(value) => handleInputChange('provider_type', value)}
          >
            <option value="">Select a provider type</option>
            <option value="openai">OpenAI</option>
            <option value="anthropic">Anthropic</option>
            <option value="google">Google</option>
            <option value="azure">Azure</option>
            <option value="huggingface">HuggingFace</option>
            <option value="ollama">Ollama</option>
            <option value="local">Local</option>
            <option value="api_gateway">API Gateway</option>
            <option value="custom">Custom</option>
          </Select>
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            Description
          </label>
          <textarea
            value={formData.description}
            onChange={(e) => handleInputChange('description', e.target.value)}
            placeholder="Brief description of the AI provider..."
            rows={3}
            className="w-full px-3 py-2 border border-theme rounded-md bg-theme-surface text-theme-primary placeholder-theme-tertiary focus:outline-none focus:ring-2 focus:ring-theme-info focus:border-transparent"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-1">
            API Base URL *
          </label>
          <Input
            value={formData.api_base_url}
            onChange={(e) => handleInputChange('api_base_url', e.target.value)}
            placeholder="https://api.provider.com/v1"
            type="url"
            required
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
                  checked={formData.capabilities.includes(capability)}
                  onChange={(e) => handleCapabilityChange(capability, e.target.checked)}
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
              value={formData.documentation_url}
              onChange={(e) => handleInputChange('documentation_url', e.target.value)}
              placeholder="https://docs.provider.com"
              type="url"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">
              Status URL
            </label>
            <Input
              value={formData.status_url}
              onChange={(e) => handleInputChange('status_url', e.target.value)}
              placeholder="https://status.provider.com"
              type="url"
            />
          </div>
        </div>

        <div className="flex items-center justify-end space-x-3 pt-4 border-t border-theme">
          <Button
            type="button"
            variant="outline"
            onClick={onClose}
            disabled={loading}
          >
            Cancel
          </Button>
          <Button
            type="submit"
            disabled={loading || !formData.name || !formData.slug || !formData.api_base_url}
            className="flex items-center gap-2"
          >
            <Plus className="h-4 w-4" />
            {loading ? 'Creating...' : 'Create Provider'}
          </Button>
        </div>
      </form>
    </Modal>
  );
};