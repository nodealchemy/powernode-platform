import { useState, useEffect } from 'react';
import { useNotifications } from '@/shared/hooks/useNotifications';
import { providersApi } from '@/shared/services/ai';
import type { ProviderModelSyncResult, ProviderUpdateResult } from '@/shared/services/ai';
import type { AiProviderCredential } from '@/shared/types/ai';
import { getErrorMessage } from '@/shared/utils/typeGuards';

/** " Synced N models." for a save whose model sync succeeded, else "". */
export function modelSyncSuffix(sync?: ProviderModelSyncResult): string {
  if (!sync?.success) return '';
  return ` Synced ${sync.model_count} model${sync.model_count === 1 ? '' : 's'}.`;
}

const DEFAULT_SUFFIX = ' and it is now your default provider.';

/**
 * The ONE notification for a saved edit: a sync that deferred itself (no
 * credential) is "deferred", a failed one a warning (the server's warning when
 * it sent one), otherwise success with the synced count. Never a warning
 * followed by a success toast.
 */
export function saveNotification(
  name: string,
  result: ProviderUpdateResult | undefined,
  credentialSaved: boolean
): { type: 'success' | 'warning' | 'info'; title: string; message: string } {
  const sync = result?.model_sync;
  const madeDefault = result?.became_default ? ` ${name} was enabled${DEFAULT_SUFFIX}` : '';

  if (sync?.skipped) {
    return {
      type: 'info',
      title: 'Saved, Model Sync Deferred',
      message: `${name} was saved. Model sync deferred: ${sync.error || 'no credential to sync with yet'}.${madeDefault}`
    };
  }
  if (sync && !sync.success) {
    return {
      type: 'warning',
      title: 'Saved, Model Sync Failed',
      message: result?.warning
        || `${name} was saved, but its model sync failed: ${sync.error || 'unknown error'}. It will be retried in the background.`
    };
  }
  const saved = credentialSaved
    ? `${name} and new credential have been saved successfully.`
    : `${name} has been updated successfully.`;
  return {
    type: 'success',
    title: credentialSaved ? 'Provider and Credential Updated' : 'Provider Updated',
    message: `${saved}${modelSyncSuffix(sync)}${madeDefault}`
  };
}

/**
 * The server's message when enabling failed because the model sync did
 * (422, code model_sync_failed); null for any other error.
 */
export function modelSyncFailureMessage(error: unknown): string | null {
  if (typeof error !== 'object' || error === null || !('response' in error)) return null;
  const response = (error as { response?: { status?: number; data?: { code?: string; error?: string } } }).response;
  if (response?.status !== 422 || response.data?.code !== 'model_sync_failed') return null;
  return response.data.error || 'Model sync failed; the provider was not enabled.';
}

export function useEditProviderForm(providerId: string, isOpen: boolean, onSuccess: () => void, onClose: () => void) {
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

  const [credentialData, setCredentialData] = useState({
    name: '',
    api_key: '',
    org_id: '',
    expires_at: ''
  });
  const [credentialLoading, setCredentialLoading] = useState(false);

  const [editingCredentialId, setEditingCredentialId] = useState<string | null>(null);
  const [editCredentialData, setEditCredentialData] = useState({
    name: '',
    api_key: '',
    org_id: '',
    is_active: true
  });

  const { addNotification } = useNotifications();

  useEffect(() => {
    if (isOpen && providerId) {
      setInitialLoading(true);
      setCredentials([]);
      loadProvider();
    }
  }, [isOpen, providerId]);

  const loadProvider = async () => {
    try {
      setInitialLoading(true);
      const response = await providersApi.getProvider(providerId);
      const providerData = response;

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

      await loadCredentials();
    } catch (_error) {
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
      let credentialsData: AiProviderCredential[] = [];
      if (Array.isArray(response)) {
        credentialsData = response;
      } else if (response && typeof response === 'object' && 'credentials' in response) {
        credentialsData = (response as { credentials: AiProviderCredential[] }).credentials || [];
      }
      setCredentials(credentialsData);
    } catch (_error) {
      // Don't show error notification for credentials - it's not critical
    }
  };

  // Saves the credential typed into the form, if any: true when saved, null
  // when there was none, false when it was refused (already notified).
  const saveNewCredential = async (): Promise<boolean | null> => {
    if (!(credentialData.name.trim() && credentialData.api_key.trim())) return null;

    const credentialsToSubmit: Record<string, unknown> = { api_key: credentialData.api_key.trim() };
    if (credentialData.org_id?.trim()) {
      credentialsToSubmit.org_id = credentialData.org_id.trim();
    }

    try {
      await providersApi.createCredential(providerId, {
        name: credentialData.name.trim(),
        credentials: credentialsToSubmit,
        ...(credentialData.expires_at ? { expires_at: credentialData.expires_at } : {})
      });
      setCredentialData({ name: '', api_key: '', org_id: '', expires_at: '' });
      return true;
    } catch (credError: unknown) {
      let errorMessage = 'Failed to create credential. Please try again.';

      if (typeof credError === 'object' && credError !== null && 'response' in credError) {
        const axiosError = credError as {
          response?: {
            data?: {
              error?: string;
              message?: string;
              data?: { error?: string; message?: string };
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

      addNotification({ type: 'error', title: 'Credential Creation Failed', message: errorMessage });
      return false;
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);

    try {
      const providerUpdateData: Record<string, unknown> = {
        name: formData.name,
        description: formData.description,
        api_base_url: formData.api_base_url,
        capabilities: formData.capabilities.length > 0 ? formData.capabilities : ['text_generation'],
        documentation_url: formData.documentation_url,
        status_url: formData.status_url,
        is_active: formData.is_active
      };

      Object.keys(providerUpdateData).forEach(key => {
        if (providerUpdateData[key] === '' || providerUpdateData[key] === null || providerUpdateData[key] === undefined) {
          delete providerUpdateData[key];
        }
      });

      // The new credential goes FIRST: enabling a provider syncs its models,
      // and that sync needs the key. A refused credential saves nothing else.
      // Known wrinkle: when the same save also changes an Ollama base URL, the
      // credential's own sync and connection test run against the OLD URL, so
      // the new credential can show last_test_status "failed" even though the
      // PATCH's sync against the new URL then succeeds. "Test" on the
      // credential clears it; the model-list sync is not a connection test, so
      // its success does not reset the credential's counters.
      const credentialSaved = await saveNewCredential();
      if (credentialSaved === false) return;

      const result = await providersApi.updateProvider(providerId, providerUpdateData);
      addNotification(saveNotification(formData.name, result, credentialSaved === true));
      if (credentialSaved) await loadCredentials();

      onSuccess();
      onClose();
    } catch (error) {
      const syncFailure = modelSyncFailureMessage(error);
      if (syncFailure) {
        // The other edits (and any new credential) were saved and the provider
        // stayed inactive: refresh, keep the form open on the true state so
        // the URL or key can be fixed.
        setFormData(prev => ({ ...prev, is_active: false }));
        await loadCredentials();
        addNotification({ type: 'error', title: 'Provider Not Enabled', message: syncFailure });
        onSuccess();
        return;
      }
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
      await loadCredentials();
      addNotification({ type: 'success', title: 'Credential Deleted', message: 'Credential has been deleted successfully' });
    } catch (error) {
      let errorMessage = 'Failed to delete credential. Please try again.';

      if (typeof error === 'object' && error !== null && 'response' in error) {
        const axiosError = error as {
          response?: {
            data?: {
              error?: string;
              message?: string;
              data?: { error?: string; message?: string };
              details?: { errors?: string[] };
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

      addNotification({ type: 'error', title: 'Deletion Failed', message: errorMessage });
    } finally {
      setCredentialLoading(false);
    }
  };

  const handleTestCredential = async (credentialId: string) => {
    try {
      setCredentialLoading(true);
      const response = await providersApi.testCredential(providerId, credentialId);

      addNotification({
        type: response.success ? 'success' : 'error',
        title: 'Credential Test',
        message: response.success
          ? `Connection successful${response.response_time_ms ? ` (${response.response_time_ms}ms)` : ''}`
          : `Connection failed: ${response.error || 'Unknown error'}`
      });

      await loadCredentials();
    } catch (_error) {
      addNotification({ type: 'error', title: 'Test Failed', message: 'Failed to test credential connection' });
    } finally {
      setCredentialLoading(false);
    }
  };

  const handleStartEditCredential = (credential: AiProviderCredential) => {
    setEditingCredentialId(credential.id);
    setEditCredentialData({
      name: credential.name,
      api_key: '',
      org_id: '',
      is_active: credential.is_active
    });
  };

  const handleCancelEditCredential = () => {
    setEditingCredentialId(null);
    setEditCredentialData({ name: '', api_key: '', org_id: '', is_active: true });
  };

  const handleSaveEditCredential = async () => {
    if (!editingCredentialId) return;

    try {
      setCredentialLoading(true);

      const updateData: Record<string, unknown> = {
        name: editCredentialData.name,
        is_active: editCredentialData.is_active
      };

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

      addNotification({ type: 'success', title: 'Credential Updated', message: 'Credential has been updated successfully' });
      handleCancelEditCredential();
    } catch (error) {
      addNotification({ type: 'error', title: 'Update Failed', message: getErrorMessage(error) });
    } finally {
      setCredentialLoading(false);
    }
  };

  const handleMakeDefault = async (credentialId: string) => {
    try {
      setCredentialLoading(true);
      await providersApi.makeCredentialDefault(providerId, credentialId);
      await loadCredentials();
      addNotification({ type: 'success', title: 'Default Updated', message: 'Credential is now the default for this provider' });
    } catch (error) {
      addNotification({ type: 'error', title: 'Update Failed', message: getErrorMessage(error) });
    } finally {
      setCredentialLoading(false);
    }
  };

  const handleClose = () => {
    setFormData({
      name: '', slug: '', provider_type: '', description: '', api_base_url: '',
      capabilities: [], documentation_url: '', status_url: '', is_active: true
    });
    setCredentialData({ name: '', api_key: '', org_id: '', expires_at: '' });
    setCredentials([]);
    onClose();
  };

  return {
    loading,
    initialLoading,
    credentials,
    formData,
    credentialData,
    credentialLoading,
    editingCredentialId,
    editCredentialData,
    setEditCredentialData,
    handleSubmit,
    handleInputChange,
    handleCredentialChange,
    handleCapabilityChange,
    handleDeleteCredential,
    handleTestCredential,
    handleStartEditCredential,
    handleCancelEditCredential,
    handleSaveEditCredential,
    handleMakeDefault,
    handleClose,
  };
}
