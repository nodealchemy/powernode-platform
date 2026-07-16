import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { ProviderCredentialForm } from './ProviderCredentialForm';

const mockPost = jest.fn();

jest.mock('@/shared/services/apiClient', () => ({
  __esModule: true,
  default: {
    get: jest.fn(),
    post: (...args: unknown[]) => mockPost(...args),
  },
  apiClient: {
    get: jest.fn(),
    post: (...args: unknown[]) => mockPost(...args),
  },
}));

beforeEach(() => {
  mockPost.mockReset();
});

describe('ProviderCredentialForm', () => {
  it('renders the AWS field schema with the default us-east-1 region prefilled', () => {
    render(<ProviderCredentialForm category="cloud" providerType="aws" />);
    expect(screen.getByTestId('provider-cred-field-access_key_id')).toBeInTheDocument();
    expect(screen.getByTestId('provider-cred-field-secret_access_key')).toBeInTheDocument();
    const region = screen.getByTestId('provider-cred-field-region') as HTMLInputElement;
    expect(region).toBeInTheDocument();
    expect(region.value).toBe('us-east-1');
  });

  it('renders the Hetzner schema with only an api_token field', () => {
    render(<ProviderCredentialForm category="cloud" providerType="hetzner" />);
    expect(screen.getByTestId('provider-cred-field-api_token')).toBeInTheDocument();
    expect(screen.queryByTestId('provider-cred-field-access_key_id')).toBeNull();
  });

  it('renders the Azure schema with all four service-principal fields', () => {
    render(<ProviderCredentialForm category="cloud" providerType="azure" />);
    ['tenant_id', 'client_id', 'client_secret', 'subscription_id'].forEach((key) => {
      expect(screen.getByTestId(`provider-cred-field-${key}`)).toBeInTheDocument();
    });
  });

  it('renders the GCP schema as a textarea for the service account JSON', () => {
    render(<ProviderCredentialForm category="cloud" providerType="gcp" />);
    const textarea = screen.getByTestId('provider-cred-field-service_account_json');
    expect(textarea.tagName).toBe('TEXTAREA');
  });

  it('renders the LocalQemu schema with the libvirt URI prefilled', () => {
    render(<ProviderCredentialForm category="cloud" providerType="local_qemu" />);
    const uri = screen.getByTestId('provider-cred-field-libvirt_uri') as HTMLInputElement;
    expect(uri.value).toBe('qemu:///system');
  });

  it('renders the GitHub schema with an access_token field (not personal_access_token)', () => {
    render(<ProviderCredentialForm category="git" providerType="github" />);
    expect(screen.getByTestId('provider-cred-field-access_token')).toBeInTheDocument();
    expect(screen.queryByTestId('provider-cred-field-personal_access_token')).toBeNull();
  });

  it('disables the Test button until all required fields are populated', () => {
    render(<ProviderCredentialForm category="cloud" providerType="aws" />);
    const testBtn = screen.getByTestId('provider-cred-test-btn');
    expect(testBtn).toBeDisabled();

    fireEvent.change(screen.getByTestId('provider-cred-field-access_key_id'), {
      target: { value: 'AKIA' },
    });
    fireEvent.change(screen.getByTestId('provider-cred-field-secret_access_key'), {
      target: { value: 'secret' },
    });
    expect(testBtn).not.toBeDisabled();
  });

  it('flags an inline error when GCP service account JSON is malformed', () => {
    render(<ProviderCredentialForm category="cloud" providerType="gcp" />);
    const textarea = screen.getByTestId('provider-cred-field-service_account_json');
    fireEvent.change(textarea, { target: { value: 'not-json' } });
    fireEvent.blur(textarea);
    expect(screen.getByTestId('provider-cred-error-service_account_json')).toBeInTheDocument();
    expect(screen.getByTestId('provider-cred-test-btn')).toBeDisabled();
  });

  it('POSTs to the BYOC test endpoint with provider_id + credentials and renders success', async () => {
    mockPost.mockResolvedValueOnce({ data: { data: { valid: true } } });
    render(<ProviderCredentialForm category="cloud" providerType="hetzner" />);

    fireEvent.change(screen.getByTestId('provider-cred-field-api_token'), {
      target: { value: 'token-abc' },
    });

    fireEvent.click(screen.getByTestId('provider-cred-test-btn'));

    await waitFor(() => {
      expect(screen.getByTestId('provider-cred-test-success')).toBeInTheDocument();
    });

    expect(mockPost).toHaveBeenCalledWith(
      '/system/provider_credentials/test',
      expect.objectContaining({
        provider_id: 'hetzner',
        provider_type: 'hetzner',
        credentials: { api_token: 'token-abc' },
      })
    );
  });

  it('renders the rejection reason when the test endpoint returns valid: false', async () => {
    mockPost.mockResolvedValueOnce({
      data: { data: { valid: false, error: 'AccessDenied' } },
    });
    render(<ProviderCredentialForm category="cloud" providerType="vultr" />);
    fireEvent.change(screen.getByTestId('provider-cred-field-api_key'), {
      target: { value: 'bad-key' },
    });
    fireEvent.click(screen.getByTestId('provider-cred-test-btn'));

    await waitFor(() => {
      expect(screen.getByTestId('provider-cred-test-error')).toHaveTextContent('AccessDenied');
    });
  });

  it('uses providerId override in the test payload when present', async () => {
    mockPost.mockResolvedValueOnce({ data: { data: { valid: true } } });
    render(
      <ProviderCredentialForm category="cloud" providerType="aws" providerId="11111111-2222-3333-4444-555555555555" />
    );

    fireEvent.change(screen.getByTestId('provider-cred-field-access_key_id'), {
      target: { value: 'AKIA' },
    });
    fireEvent.change(screen.getByTestId('provider-cred-field-secret_access_key'), {
      target: { value: 'secret' },
    });
    fireEvent.click(screen.getByTestId('provider-cred-test-btn'));

    await waitFor(() => {
      expect(mockPost).toHaveBeenCalledWith(
        '/system/provider_credentials/test',
        expect.objectContaining({
          provider_id: '11111111-2222-3333-4444-555555555555',
          provider_type: 'aws',
        })
      );
    });
  });

  it('clears the success indicator and notifies the parent when a value changes', async () => {
    mockPost.mockResolvedValueOnce({ data: { data: { valid: true } } });
    const onTestStatus = jest.fn();
    render(
      <ProviderCredentialForm
        category="cloud"
        providerType="hetzner"
        onTestStatusChange={onTestStatus}
      />
    );
    fireEvent.change(screen.getByTestId('provider-cred-field-api_token'), {
      target: { value: 'token-abc' },
    });
    fireEvent.click(screen.getByTestId('provider-cred-test-btn'));
    await waitFor(() =>
      expect(screen.getByTestId('provider-cred-test-success')).toBeInTheDocument()
    );
    expect(onTestStatus).toHaveBeenCalledWith('valid');

    fireEvent.change(screen.getByTestId('provider-cred-field-api_token'), {
      target: { value: 'token-changed' },
    });
    expect(screen.queryByTestId('provider-cred-test-success')).toBeNull();
    expect(onTestStatus).toHaveBeenLastCalledWith('idle');
  });
});
