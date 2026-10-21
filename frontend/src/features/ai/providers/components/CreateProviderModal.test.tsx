import { act, render, screen, fireEvent, waitFor } from '@testing-library/react';
import { CreateProviderModal } from './CreateProviderModal';
import { providersApi } from '@/shared/services/ai';

jest.mock('@/shared/services/ai', () => ({
  providersApi: {
    getCatalog: jest.fn(),
    createProvider: jest.fn(),
  },
}));

jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ addNotification: jest.fn() }),
}));

const CATALOG = [
  {
    name: 'OpenAI',
    slug: 'openai',
    provider_type: 'openai',
    api_base_url: 'https://api.example-openai.test/v1',
    capabilities: ['text_generation', 'chat', 'text_embedding'],
    default_model: 'model-a',
    requires_auth: true,
    credential_fields: [{ key: 'api_key', label: 'API Key', type: 'password', required: true }],
  },
];

describe('CreateProviderModal catalog auto-fill', () => {
  beforeEach(() => {
    (providersApi.getCatalog as jest.Mock).mockResolvedValue(CATALOG);
    (providersApi.createProvider as jest.Mock).mockResolvedValue({});
  });

  const renderModal = async () => {
    render(<CreateProviderModal isOpen onClose={jest.fn()} onSuccess={jest.fn()} />);
    await waitFor(() => expect(providersApi.getCatalog).toHaveBeenCalled());
    await act(async () => {});
  };

  it('fills name, slug, base URL and capabilities when a type is selected', async () => {
    await renderModal();

    fireEvent.change(screen.getByRole('combobox'), { target: { value: 'openai' } });

    await waitFor(() =>
      expect(screen.getByPlaceholderText('e.g., Custom AI Provider')).toHaveValue('OpenAI')
    );
    expect(screen.getByPlaceholderText('custom-ai-provider')).toHaveValue('openai');
    expect(screen.getByPlaceholderText('https://api.provider.com/v1')).toHaveValue(
      'https://api.example-openai.test/v1'
    );
    expect(screen.getByLabelText(/text embedding/i)).toBeChecked();
  });

  it('keeps the filled fields editable', async () => {
    await renderModal();
    fireEvent.change(screen.getByRole('combobox'), { target: { value: 'openai' } });
    const name = screen.getByPlaceholderText('e.g., Custom AI Provider');
    await waitFor(() => expect(name).toHaveValue('OpenAI'));

    fireEvent.change(name, { target: { value: 'My OpenAI' } });

    expect(screen.getByPlaceholderText('e.g., Custom AI Provider')).toHaveValue('My OpenAI');
  });
});
