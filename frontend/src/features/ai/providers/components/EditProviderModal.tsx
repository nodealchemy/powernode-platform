import React, { useState, useEffect } from 'react';
import { X, Save, Key } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Modal } from '@/shared/components/ui/Modal';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { providersApi } from '@/shared/services/ai';
import type { AiProviderCredential } from '@/shared/types/ai';
import { getErrorMessage } from '@/shared/utils/typeGuards';
import { CredentialCard, AddCredentialForm, ProviderFormFields } from './edit-provider';

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
  const [initialLoading, setInitialLoading] = useState(true);
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

  // Edit credential state
  const [editingCredentialId, setEditingCredentialId] = useState<string | null>(null);
  const [editCredentialData, setEditCredentialData] = useState({
    name: '',
    api_key: '',
    org_id: '',
    is_active: true
  });

  const { addNotification } = useNotifications();

  // Reset state and load when modal opens
  useEffect(() => {
    if (isOpen && providerId) {
      // Reset state for fresh load
      setInitialLoading(true);
      setCredentials([]);
      loadProvider();
    }
  }, [isOpen, providerId]); // eslint-disable-line react-hooks/exhaustive-deps

  const loadProvider = async () => {
    try {
      setInitialLoading(true);
      const response = await providersApi.getProvider(providerId);
      // Response is the provider object after service unwraps the { provider: {...} } envelope
      const providerData = response;
      
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
      // Response could be:
      // - Array directly: [...]
      // - Object with credentials property: { credentials: [...], pagination: {...} }
      let credentialsData: AiProviderCredential[] = [];
      if (Array.isArray(response)) {
        credentialsData = response;
      } else if (response && typeof response === 'object' && 'credentials' in response) {
        credentialsData = (response as { credentials: AiProviderCredential[] }).credentials || [];
      }
      setCredentials(credentialsData);
    } catch (error) {
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

      // Reload credentials to update test status
      await loadCredentials();
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Test Failed',
        message: 'Failed to test credential connection'
      });
    } finally {
      setCredentialLoading(false);
    }
  };

  const handleStartEditCredential = (credential: AiProviderCredential) => {
    setEditingCredentialId(credential.id);
    setEditCredentialData({
      name: credential.name,
      api_key: '', // Don't show existing API key for security
      org_id: '', // Don't show existing org_id for security
      is_active: credential.is_active
    });
  };

  const handleCancelEditCredential = () => {
    setEditingCredentialId(null);
    setEditCredentialData({
      name: '',
      api_key: '',
      org_id: '',
      is_active: true
    });
  };

  const handleSaveEditCredential = async () => {
    if (!editingCredentialId) return;

    try {
      setCredentialLoading(true);

      const updateData: Record<string, unknown> = {
        name: editCredentialData.name,
        is_active: editCredentialData.is_active
      };

      // Only include credentials if API key is provided (user wants to update it)
      if (editCredentialData.api_key.trim()) {
        const credentialsToUpdate: Record<string, string> = {
          api_key: editCredentialData.api_key.trim()
        };
        if (editCredentialData.org_id.trim()) {
          credentialsToUpdate.org_id = editCredentialData.org_id.trim();
        }
        updateData.credentials = credentialsToUpdate;
      }

      await providersApi.updateCredential(providerId, editingCredentialId, updateData);
      await loadCredentials();

      addNotification({
        type: 'success',
        title: 'Credential Updated',
        message: 'Credential has been updated successfully'
      });

      handleCancelEditCredential();
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Update Failed',
        message: getErrorMessage(error)
      });
    } finally {
      setCredentialLoading(false);
    }
  };

  const handleMakeDefault = async (credentialId: string) => {
    try {
      setCredentialLoading(true);
      await providersApi.makeCredentialDefault(providerId, credentialId);
      await loadCredentials();

      addNotification({
        type: 'success',
        title: 'Default Updated',
        message: 'Credential is now the default for this provider'
      });
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Update Failed',
        message: getErrorMessage(error)
      });
    } finally {
      setCredentialLoading(false);
    }
  };

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
        <ProviderFormFields
          data={formData}
          onChange={handleInputChange}
          onCapabilityChange={handleCapabilityChange}
        />

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
              <h5 className="text-sm font-medium text-theme-secondary">Existing Credentials ({credentials.length})</h5>
              <div className="space-y-2">
                {credentials.map((credential) => (
                  <CredentialCard
                    key={credential.id}
                    credential={credential}
                    isEditing={editingCredentialId === credential.id}
                    editData={editCredentialData}
                    isLoading={credentialLoading}
                    onStartEdit={() => handleStartEditCredential(credential)}
                    onCancelEdit={handleCancelEditCredential}
                    onSaveEdit={handleSaveEditCredential}
                    onEditDataChange={(data) => setEditCredentialData(prev => ({ ...prev, ...data }))}
                    onTest={() => handleTestCredential(credential.id)}
                    onDelete={() => handleDeleteCredential(credential.id)}
                    onMakeDefault={() => handleMakeDefault(credential.id)}
                  />
                ))}
              </div>
            </div>
          )}

          {/* Add New Credential Form */}
          <AddCredentialForm
            data={credentialData}
            onChange={handleCredentialChange}
            disabled={loading}
          />
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