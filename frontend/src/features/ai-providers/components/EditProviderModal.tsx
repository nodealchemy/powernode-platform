import React, { useState, useEffect } from 'react';
import { X, Save, Key, Plus, Trash2, TestTube } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import { Modal } from '@/shared/components/ui/Modal';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { providersApi } from '@/shared/services/ai';
import type { AiProvider, AiProviderCredential } from '@/shared/types/ai';
import { getErrorMessage } from '@/shared/utils/typeGuards';

interface EditProviderModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: () => void;
  providerId: string;
}

export const EditProviderModal: React.FC<EditProviderModalProps> = ({
  isOpen,
  onClose,
  onSuccess,
  providerId
}) => {
  const [loading, setLoading] = useState(false);
  const [initialLoading, setInitialLoading] = useState(false);
  const [credentials, setCredentials] = useState<AiProviderCredential[]>([]);
  const [formData, setFormData] = useState({
    name: '',
    slug: '',
    provider_type: '',
    description: '',
    api_base_url: '',
    capabilities: [] as string[],
    documentation_url: '',
    status_url: '',
    is_active: true
  });
  
  // Credential form state
  const [credentialData, setCredentialData] = useState({
    name: '',
    api_key: '',
    org_id: '',
    expires_at: ''
  });
  const [credentialLoading, setCredentialLoading] = useState(false);

  const { addNotification } = useNotifications();

  // Load provider data when modal opens
  // eslint-disable-next-line react-hooks/exhaustive-deps -- Load when modal opens
  useEffect(() => {
    if (isOpen && providerId) {
      loadProvider();
    }
  }, [isOpen, providerId]);

  const loadProvider = async () => {
    try {
      setInitialLoading(true);
      const response = await providersApi.getProvider(providerId);
      // Response is already unwrapped by BaseApiService
      const providerData = response as AiProvider;
      
      // Populate form with provider data
      setFormData({
        name: providerData.name || '',
        slug: providerData.slug || '',
        provider_type: providerData.provider_type || '',
        description: providerData.description || '',
        api_base_url: providerData.api_base_url || '',
        capabilities: providerData.capabilities || [],
        documentation_url: providerData.documentation_url || '',
        status_url: providerData.status_url || '',
        is_active: providerData.is_active !== undefined ? providerData.is_active : true
      });

      // Load existing credentials
      await loadCredentials();
    } catch (error) {
      console.error('Failed to load provider:', error);
      addNotification({
        type: 'error',
        title: 'Loading Failed',
        message: 'Failed to load provider details. Please try again.'
      });
    } finally {
      setInitialLoading(false);
    }
  };

  const loadCredentials = async () => {
    try {
      const response = await providersApi.getCredentials(providerId);
      // Response is already unwrapped by BaseApiService - could be array or object with credentials property
      const credentialsData = Array.isArray(response) ? response : [];
      setCredentials(credentialsData);
    } catch (error) {
      console.error('Failed to load credentials:', error);
      // Don't show error notification for credentials - it's not critical
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);

    try {
      // Ensure data is not nested - extract only the fields we need
      const providerUpdateData: Record<string, unknown> = {
        name: formData.name,
        description: formData.description,
        api_base_url: formData.api_base_url,
        capabilities: formData.capabilities.length > 0 ? formData.capabilities : ['text_generation'],
        documentation_url: formData.documentation_url,
        status_url: formData.status_url,
        is_active: formData.is_active
      };

      // Remove empty values to avoid overriding with blanks
      Object.keys(providerUpdateData).forEach(key => {
        if (providerUpdateData[key] === '' || providerUpdateData[key] === null || providerUpdateData[key] === undefined) {
          delete providerUpdateData[key];
        }
      });

      // Call API to update provider
      await providersApi.updateProvider(providerId, providerUpdateData);

      // Handle credential creation if fields are filled
      if (credentialData.name.trim() && credentialData.api_key.trim()) {
        try {
          const credentialsToSubmit: Record<string, unknown> = {
            api_key: credentialData.api_key.trim()
          };

          // Add optional fields if provided
          if (credentialData.org_id?.trim()) {
            credentialsToSubmit.org_id = credentialData.org_id.trim();
          }

          // Create credential - response is { credential: {...} } after BaseApiService unwrapping
          await providersApi.createCredential(providerId, {
            name: credentialData.name.trim(),
            credentials: credentialsToSubmit,
            ...(credentialData.expires_at ? { expires_at: credentialData.expires_at } : {})
          });

          // Reset credential form after successful creation
          setCredentialData({
            name: '',
            api_key: '',
            org_id: '',
            expires_at: ''
          });

          // Reload credentials list to show the new credential
          await loadCredentials();

          addNotification({
            type: 'success',
            title: 'Provider and Credential Updated',
            message: `${formData.name} and new credential have been saved successfully`
          });
        } catch (credError: unknown) {
          // Extract error message from response - check multiple possible locations
          let errorMessage = 'Failed to create credential. Please try again.';

          if (typeof credError === 'object' && credError !== null && 'response' in credError) {
            const axiosError = credError as {
              response?: {
                data?: {
                  error?: string;
                  message?: string;
                  data?: {
                    error?: string;
                    message?: string;
                  };
                };
              };
              message?: string;
            };

            errorMessage = axiosError.response?.data?.error
              || axiosError.response?.data?.data?.error
              || axiosError.response?.data?.message
              || axiosError.response?.data?.data?.message
              || axiosError.message
              || errorMessage;
          } else {
            errorMessage = getErrorMessage(credError);
          }

          addNotification({
            type: 'error',
            title: 'Credential Creation Failed',
            message: errorMessage
          });
        }
      } else {
        addNotification({
          type: 'success',
          title: 'Provider Updated',
          message: `${formData.name} has been updated successfully`
        });
      }

      onSuccess();
      onClose();
    } catch (error) {
      console.error('Failed to update provider:', error);
      addNotification({
        type: 'error',
        title: 'Update Failed',
        message: 'Failed to update AI provider. Please try again.'
      });
    } finally {
      setLoading(false);
    }
  };

  const handleInputChange = (field: string, value: string | boolean) => {
    setFormData(prev => ({ ...prev, [field]: value }));
  };

  const handleCredentialChange = (field: string, value: string) => {
    setCredentialData(prev => ({ ...prev, [field]: value }));
  };

  const handleCapabilityChange = (capability: string, checked: boolean) => {
    setFormData(prev => ({
      ...prev,
      capabilities: checked
        ? [...prev.capabilities, capability]
        : prev.capabilities.filter(c => c !== capability)
    }));
  };

  const handleDeleteCredential = async (credentialId: string) => {
    if (!confirm('Are you sure you want to delete this credential? This action cannot be undone.')) {
      return;
    }

    try {
      setCredentialLoading(true);
      await providersApi.deleteCredential(providerId, credentialId);
      await loadCredentials(); // Reload credentials list
      addNotification({
        type: 'success',
        title: 'Credential Deleted',
        message: 'Credential has been deleted successfully'
      });
    } catch (error: unknown) {
      // Extract specific error message from validation response
      let errorMessage = 'Failed to delete credential. Please try again.';

      if (typeof error === 'object' && error !== null && 'response' in error) {
        const axiosError = error as {
          response?: {
            data?: {
              error?: string;
              message?: string;
              data?: {
                error?: string;
                message?: string;
              };
              details?: {
                errors?: string[];
              };
            };
          };
          message?: string;
        };

        errorMessage = axiosError.response?.data?.error
          || axiosError.response?.data?.data?.error
          || axiosError.response?.data?.message
          || axiosError.response?.data?.details?.errors?.[0]
          || axiosError.message
          || errorMessage;
      } else {
        errorMessage = getErrorMessage(error);
      }

      addNotification({
        type: 'error',
        title: 'Deletion Failed',
        message: errorMessage
      });
    } finally {
      setCredentialLoading(false);
    }
  };

  const handleTestCredential = async (credentialId: string) => {
    try {
      setCredentialLoading(true);
      const response = await providersApi.testCredential(providerId, credentialId);
      // Response is already unwrapped by BaseApiService

      addNotification({
        type: response.success ? 'success' : 'error',
        title: 'Credential Test',
        message: response.success
          ? `Connection successful${response.response_time_ms ? ` (${response.response_time_ms}ms)` : ''}`
          : `Connection failed: ${response.error || 'Unknown error'}`
      });
    } catch (error) {
      console.error('Failed to test credential:', error);
      addNotification({
        type: 'error',
        title: 'Test Failed',
        message: 'Failed to test credential connection'
      });
    } finally {
      setCredentialLoading(false);
    }
  };

  const availableCapabilities = [
    'text_generation',
    'chat',
    'vision',
    'function_calling',
    'code_execution',
    'image_generation',
    'embeddings'
  ];

  const handleClose = () => {
    // Reset form data
    setFormData({
      name: '',
      slug: '',
      provider_type: '',
      description: '',
      api_base_url: '',
      capabilities: [],
      documentation_url: '',
      status_url: '',
      is_active: true
    });

    // Reset credential data
    setCredentialData({
      name: '',
      api_key: '',
      org_id: '',
      expires_at: ''
    });

    setCredentials([]);
    onClose();
  };

  if (initialLoading) {
    return (
      <Modal isOpen={isOpen} onClose={handleClose} size="lg">
        <div className="flex items-center justify-between p-6 border-b border-theme">
          <h2 className="text-xl font-semibold text-theme-primary">Loading Provider...</h2>
          <Button
            variant="ghost"
            size="sm"
            onClick={handleClose}
            className="h-8 w-8 p-0"
          >
            <X className="h-4 w-4" />
          </Button>
        </div>
        <div className="p-6 flex items-center justify-center">
          <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-theme-interactive-primary"></div>
        </div>
      </Modal>
    );
  }

  return (
    <Modal isOpen={isOpen} onClose={handleClose} size="lg">
      <div className="flex items-center justify-between p-6 border-b border-theme">
        <h2 className="text-xl font-semibold text-theme-primary">Edit AI Provider</h2>
        <Button
          variant="ghost"
          size="sm"
          onClick={handleClose}
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
              disabled={true} // Usually slugs shouldn't be changed after creation
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
              value={formData.provider_type}
              onChange={(value) => handleInputChange('provider_type', value)}
              disabled={true}
              className="bg-theme-secondary/10"
            >
              <option value="">Select a provider type</option>
              <option value="openai">OpenAI</option>
              <option value="anthropic">Anthropic (Claude)</option>
              <option value="google">Google (Gemini/Vertex AI)</option>
              <option value="cohere">Cohere</option>
              <option value="huggingface">Hugging Face</option>
              <option value="ollama">Ollama (Local)</option>
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
              value={formData.is_active ? 'active' : 'inactive'}
              onChange={(value) => handleInputChange('is_active', value === 'active')}
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
            value={formData.description}
            onChange={(e) => handleInputChange('description', e.target.value)}
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
            value={formData.api_base_url}
            onChange={(e) => handleInputChange('api_base_url', e.target.value)}
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

        {/* Credentials Management */}
        <div className="space-y-4">
          <div className="border-t border-theme pt-4">
            <h4 className="text-sm font-semibold text-theme-primary flex items-center gap-2">
              <Key className="h-4 w-4" />
              Credentials Management
            </h4>
            <p className="text-sm text-theme-muted mt-1">
              Manage API credentials for this provider. Existing credentials are listed below, and you can add a new credential using the form.
            </p>
          </div>

          {/* Existing Credentials */}
          {credentials.length > 0 && (
            <div className="space-y-2">
              <h5 className="text-sm font-medium text-theme-secondary">Existing Credentials</h5>
              <div className="space-y-2">
                {credentials.map((credential) => (
                  <div key={credential.id} className="flex items-center justify-between p-3 bg-theme-secondary/10 rounded-lg border border-theme">
                    <div>
                      <p className="text-sm font-medium text-theme-primary">{credential.name}</p>
                      <p className="text-xs text-theme-muted">
                        Status: {credential.is_active ? 'Active' : 'Inactive'} • 
                        {credential.is_default && ' Default • '}
                        Last used: {credential.last_used_at ? new Date(credential.last_used_at).toLocaleDateString() : 'Never'}
                      </p>
                    </div>
                    <div className="flex items-center gap-2">
                      <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        onClick={() => handleTestCredential(credential.id)}
                        disabled={credentialLoading}
                        className="flex items-center gap-1"
                      >
                        <TestTube className="h-3 w-3" />
                        Test
                      </Button>
                      <Button
                        type="button"
                        variant="outline"
                        size="sm"
                        onClick={() => handleDeleteCredential(credential.id)}
                        disabled={credentialLoading}
                        className="text-theme-danger hover:text-theme-danger/80"
                      >
                        <Trash2 className="h-3 w-3" />
                      </Button>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Add New Credential Form */}
          <div className="space-y-4 p-4 bg-theme-info/5 border border-theme-info/20 rounded-lg">
            <h5 className="text-sm font-medium text-theme-primary flex items-center gap-2">
              <Plus className="h-4 w-4" />
              Add New Credential (Optional)
            </h5>
            <p className="text-xs text-theme-muted">
              Leave fields blank to update provider without adding credentials.
            </p>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-theme-secondary mb-1">
                  Credential Name
                </label>
                <Input
                  value={credentialData.name}
                  onChange={(e) => handleCredentialChange('name', e.target.value)}
                  placeholder="e.g., Production API Key"
                  disabled={loading}
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-theme-secondary mb-1">
                  API Key
                </label>
                <Input
                  type="password"
                  value={credentialData.api_key}
                  onChange={(e) => handleCredentialChange('api_key', e.target.value)}
                  placeholder="sk-..."
                  disabled={loading}
                />
              </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-theme-secondary mb-1">
                  Organization ID (Optional)
                </label>
                <Input
                  value={credentialData.org_id}
                  onChange={(e) => handleCredentialChange('org_id', e.target.value)}
                  placeholder="org-..."
                  disabled={loading}
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-theme-secondary mb-1">
                  Expires At (Optional)
                </label>
                <Input
                  type="date"
                  value={credentialData.expires_at}
                  onChange={(e) => handleCredentialChange('expires_at', e.target.value)}
                  disabled={loading}
                />
              </div>
            </div>

            {(credentialData.name || credentialData.api_key) && (
              <div className="text-xs text-theme-info">
                <strong>Note:</strong> A new credential will be created with these details when you save the provider.
              </div>
            )}
          </div>
        </div>

        <div className="flex items-center justify-end space-x-3 pt-4 border-t border-theme">
          <Button
            type="button"
            variant="outline"
            onClick={handleClose}
            disabled={loading}
          >
            Cancel
          </Button>
          <Button
            type="submit"
            disabled={loading || !formData.name}
            className="flex items-center gap-2"
          >
            <Save className="h-4 w-4" />
            {loading ? 'Updating...' : 'Update Provider'}
          </Button>
        </div>
      </form>
    </Modal>
  );
};