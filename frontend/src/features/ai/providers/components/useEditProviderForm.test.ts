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

  it('warns when the save succeeded but its model sync failed', async () => {
    (providersApi.updateProvider as jest.Mock).mockResolvedValue({
      provider: { ...PROVIDER, is_active: true },
      model_sync: { success: false, model_count: 3, error: 'Could not connect to Ollama API at http://x:11434' },
    });
    const { result } = await renderForm();

    await act(async () => { await result.current.handleSubmit(submitEvent); });

    expect(mockAddNotification).toHaveBeenCalledWith(expect.objectContaining({
      type: 'warning',
      message: expect.stringContaining('Could not connect to Ollama API at http://x:11434'),
    }));
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
