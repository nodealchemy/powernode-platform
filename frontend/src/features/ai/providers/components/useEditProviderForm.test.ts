import type React from 'react';
import { renderHook, act, waitFor } from '@testing-library/react';
import { useEditProviderForm, modelSyncSuffix } from './useEditProviderForm';
import { providersApi } from '@/shared/services/ai';

jest.mock('@/shared/services/ai', () => ({
  providersApi: {
    getProvider: jest.fn(),
    getCredentials: jest.fn(),
    updateProvider: jest.fn(),
    createCredential: jest.fn(),
  },
}));

const mockAddNotification = jest.fn();
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: mockAddNotification }),
}));

const PROVIDER = {
  id: 'p1',
  name: 'Ollama',
  slug: 'ollama',
  provider_type: 'ollama',
  description: '',
  api_base_url: 'http://ollama.internal:11434',
  capabilities: ['text_generation'],
  documentation_url: '',
  status_url: '',
  is_active: false,
};

const submitEvent = { preventDefault: jest.fn() } as unknown as React.FormEvent;

const renderForm = async (onSuccess = jest.fn(), onClose = jest.fn()) => {
  const hook = renderHook(() => useEditProviderForm('p1', true, onSuccess, onClose));
  await waitFor(() => expect(hook.result.current.initialLoading).toBe(false));
  return { ...hook, onSuccess, onClose };
};

describe('useEditProviderForm save outcome', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (providersApi.getProvider as jest.Mock).mockResolvedValue(PROVIDER);
    (providersApi.getCredentials as jest.Mock).mockResolvedValue([]);
  });

  it('reports the synced model count when the save synced', async () => {
    (providersApi.updateProvider as jest.Mock).mockResolvedValue({
      provider: { ...PROVIDER, is_active: true },
      model_sync: { success: true, model_count: 2, error: null, activated: true },
    });
    const { result, onSuccess, onClose } = await renderForm();

    act(() => result.current.handleInputChange('is_active', true));
    await act(async () => { await result.current.handleSubmit(submitEvent); });

    expect(mockAddNotification).toHaveBeenCalledWith(expect.objectContaining({
      type: 'success',
      message: expect.stringContaining('Synced 2 models'),
    }));
    expect(onSuccess).toHaveBeenCalled();
    expect(onClose).toHaveBeenCalled();
  });

  it('shows the server message and keeps the form open when enabling fails its sync (422)', async () => {
    const message = 'Could not enable Ollama: Could not connect to Ollama API at http://ollama.internal:11434. ' +
      'Other changes were saved; the provider stays inactive.';
    (providersApi.updateProvider as jest.Mock).mockRejectedValue({
      response: {
        status: 422,
        data: {
          success: false,
          error: message,
          code: 'model_sync_failed',
          details: { provider: PROVIDER, model_sync: { success: false, model_count: 0, error: 'Could not connect' } },
        },
      },
    });
    const { result, onSuccess, onClose } = await renderForm();

    act(() => result.current.handleInputChange('is_active', true));
    await act(async () => { await result.current.handleSubmit(submitEvent); });

    expect(mockAddNotification).toHaveBeenCalledWith({ type: 'error', title: 'Provider Not Enabled', message });
    expect(onSuccess).toHaveBeenCalled();
    expect(onClose).not.toHaveBeenCalled();
    expect(result.current.formData.is_active).toBe(false);
    expect(result.current.loading).toBe(false);
  });

  it('warns once, with the server warning, when the save succeeded but its model sync failed', async () => {
    const warning = 'Ollama was saved and keeps its previous models for now, but its model sync against ' +
      'http://x:11434 failed: Could not connect. It will be disabled if the background retry also fails.';
    (providersApi.updateProvider as jest.Mock).mockResolvedValue({
      provider: { ...PROVIDER, is_active: true },
      model_sync: { success: false, model_count: 3, error: 'Could not connect to Ollama API at http://x:11434' },
      warning,
    });
    const { result } = await renderForm();

    await act(async () => { await result.current.handleSubmit(submitEvent); });

    expect(mockAddNotification).toHaveBeenCalledTimes(1);
    expect(mockAddNotification).toHaveBeenCalledWith(expect.objectContaining({ type: 'warning', message: warning }));
  });

  it('shows a skipped sync as deferred, not failed, and once', async () => {
    (providersApi.updateProvider as jest.Mock).mockResolvedValue({
      provider: { ...PROVIDER, is_active: true },
      model_sync: { success: false, skipped: true, deferred: true, model_count: 3,
                    error: 'no active credential for OpenAI — model sync deferred until credentials are configured' },
    });
    const { result } = await renderForm();

    await act(async () => { await result.current.handleSubmit(submitEvent); });

    expect(mockAddNotification).toHaveBeenCalledTimes(1);
    const note = mockAddNotification.mock.calls[0][0];
    expect(note.type).toBe('info');
    expect(note.title).toMatch(/deferred/i);
    expect(`${note.title} ${note.message}`).not.toMatch(/failed/i);
  });

  it('says when enabling made it the default provider', async () => {
    (providersApi.updateProvider as jest.Mock).mockResolvedValue({
      provider: { ...PROVIDER, is_active: true },
      model_sync: { success: true, model_count: 2, error: null, activated: true, default: true },
      became_default: true,
    });
    const { result } = await renderForm();

    await act(async () => { await result.current.handleSubmit(submitEvent); });

    expect(mockAddNotification).toHaveBeenCalledWith(expect.objectContaining({
      type: 'success',
      message: expect.stringContaining('it is now your default provider'),
    }));
  });

  describe('with a new credential in the same save', () => {
    const fillCredential = (result: { current: ReturnType<typeof useEditProviderForm> }) => {
      act(() => {
        result.current.handleCredentialChange('name', 'Key');
        result.current.handleCredentialChange('api_key', 'placeholder-key');
        result.current.handleInputChange('is_active', true);
      });
    };

    it('saves the credential BEFORE the provider, so enabling can sync with it', async () => {
      (providersApi.createCredential as jest.Mock).mockResolvedValue({});
      (providersApi.updateProvider as jest.Mock).mockResolvedValue({
        provider: { ...PROVIDER, is_active: true },
        model_sync: { success: true, model_count: 2, error: null, activated: true },
      });
      const { result } = await renderForm();
      fillCredential(result);

      await act(async () => { await result.current.handleSubmit(submitEvent); });

      const credOrder = (providersApi.createCredential as jest.Mock).mock.invocationCallOrder[0];
      const patchOrder = (providersApi.updateProvider as jest.Mock).mock.invocationCallOrder[0];
      expect(credOrder).toBeLessThan(patchOrder);
    });

    it('keeps the credential saved when enabling is then refused (422)', async () => {
      (providersApi.createCredential as jest.Mock).mockResolvedValue({});
      (providersApi.updateProvider as jest.Mock).mockRejectedValue({
        response: { status: 422, data: { success: false, error: 'Could not enable', code: 'model_sync_failed' } },
      });
      const { result } = await renderForm();
      fillCredential(result);

      await act(async () => { await result.current.handleSubmit(submitEvent); });

      expect(providersApi.createCredential).toHaveBeenCalledTimes(1);
      expect(mockAddNotification).toHaveBeenCalledWith(expect.objectContaining({ title: 'Provider Not Enabled' }));
    });

    it('does not save the provider when the credential is refused', async () => {
      (providersApi.createCredential as jest.Mock).mockRejectedValue({
        response: { status: 422, data: { error: 'Validation failed: bad key' } },
      });
      const { result, onClose } = await renderForm();
      fillCredential(result);

      await act(async () => { await result.current.handleSubmit(submitEvent); });

      expect(providersApi.updateProvider).not.toHaveBeenCalled();
      expect(mockAddNotification).toHaveBeenCalledWith(expect.objectContaining({
        type: 'error', title: 'Credential Creation Failed', message: 'Validation failed: bad key',
      }));
      expect(onClose).not.toHaveBeenCalled();
    });
  });

  it('keeps the generic message for errors that are not a model sync failure', async () => {
    (providersApi.updateProvider as jest.Mock).mockRejectedValue({ response: { status: 500, data: {} } });
    const { result, onSuccess } = await renderForm();

    await act(async () => { await result.current.handleSubmit(submitEvent); });

    expect(mockAddNotification).toHaveBeenCalledWith(expect.objectContaining({ type: 'error', title: 'Update Failed' }));
    expect(onSuccess).not.toHaveBeenCalled();
  });
});

describe('modelSyncSuffix', () => {
  it('says nothing for a save that did not sync', () => {
    expect(modelSyncSuffix(undefined)).toBe('');
  });

  it('uses the singular for one model', () => {
    expect(modelSyncSuffix({ success: true, model_count: 1, error: null })).toBe(' Synced 1 model.');
  });
});
