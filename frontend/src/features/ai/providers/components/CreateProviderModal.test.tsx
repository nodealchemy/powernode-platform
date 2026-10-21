import { render, screen, fireEvent, waitFor } from '@testing-library/react';
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

const KNOWN = ['text_generation', 'chat', 'text_embedding', 'vision', 'search'];

const CATALOG = [
  {
    name: 'OpenAI',
    slug: 'openai',
    provider_type: 'openai',
    api_base_url: 'https://api.example-openai.test/v1',
    capabilities: ['text_generation', 'chat', 'text_embedding'],
    default_model: 'model-a',
    default_embedding_model: null,
    models: ['model-a'],
    requires_auth: true,
    credential_fields: [{ key: 'api_key', label: 'API Key', type: 'password', required: true }],
  },
];

describe('CreateProviderModal catalog auto-fill', () => {
  beforeEach(() => {
    (providersApi.getCatalog as jest.Mock).mockResolvedValue({ items: CATALOG, known_capabilities: KNOWN });
    (providersApi.createProvider as jest.Mock).mockResolvedValue({});
  });

  const renderModal = async () => {
    render(<CreateProviderModal isOpen onClose={jest.fn()} onSuccess={jest.fn()} />);
    // The capability list comes from the catalog: once it renders, the catalog
    // state is set and a type change can auto-fill (no fixed number of ticks).
    await screen.findByLabelText(/^search$/i);
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

  it('offers only the capabilities valid for the selected type, from the backend list', async () => {
    await renderModal();
    // Custom type: every backend-known capability, and no stale 'embeddings'.
    expect(screen.getByLabelText(/^search$/i)).toBeInTheDocument();
    expect(screen.queryByLabelText(/^embeddings$/i)).not.toBeInTheDocument();

    fireEvent.change(screen.getByRole('combobox'), { target: { value: 'openai' } });

    await waitFor(() => expect(screen.queryByLabelText(/^search$/i)).not.toBeInTheDocument());
    expect(screen.getByLabelText(/text embedding/i)).toBeInTheDocument();
    expect(screen.queryByLabelText(/^vision$/i)).not.toBeInTheDocument();
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
