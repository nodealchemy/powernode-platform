import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { CredentialModal } from '../components/CredentialModal';
import { useGitCredentials } from '../hooks/useGitProviders';
import { AvailableProvider } from '../types';

// Mock hooks
jest.mock('../hooks/useGitProviders', () => ({
  useGitCredentials: jest.fn(),
}));

// Mock lucide-react icons
jest.mock('lucide-react', () => ({
  X: () => <span data-testid="icon-x" />,
  Key: () => <span data-testid="icon-key" />,
  Globe: () => <span data-testid="icon-globe" />,
  Eye: () => <span data-testid="icon-eye" />,
  EyeOff: () => <span data-testid="icon-eye-off" />,
  AlertCircle: () => <span data-testid="icon-alert" />,
}));

const mockUseGitCredentials = useGitCredentials as jest.MockedFunction<
  typeof useGitCredentials
>;

describe('CredentialModal', () => {
  const mockCreateCredential = jest.fn();
  const mockOnClose = jest.fn();
  const mockOnSuccess = jest.fn();

  const githubProvider: AvailableProvider = {
    id: 'provider-github',
    name: 'GitHub',
    slug: 'github',
    provider_type: 'github',
    description: 'Connect to GitHub',
    supports_oauth: true,
    supports_pat: true,
    supports_ci_cd: true,
    capabilities: ['repositories', 'webhooks', 'ci_cd', 'oauth'],
    configured: false,
  };

  const giteaProvider: AvailableProvider = {
    id: 'provider-gitea',
    name: 'Gitea',
    slug: 'gitea',
    provider_type: 'gitea',
    description: 'Connect to Gitea',
    supports_oauth: false,
    supports_pat: true,
    supports_ci_cd: true,
    capabilities: ['repositories', 'webhooks', 'ci_cd'],
    configured: false,
  };

  const defaultProps = {
    isOpen: true,
    onClose: mockOnClose,
    provider: githubProvider,
    onSuccess: mockOnSuccess,
  };

  beforeEach(() => {
    jest.clearAllMocks();

    mockUseGitCredentials.mockReturnValue({
      credentials: [],
      loading: false,
      error: null,
      refresh: jest.fn(),
      createCredential: mockCreateCredential,
      updateCredential: jest.fn(),
      deleteCredential: jest.fn(),
      testCredential: jest.fn(),
      makeDefault: jest.fn(),
      syncRepositories: jest.fn(),
    } as ReturnType<typeof useGitCredentials>);

    mockCreateCredential.mockResolvedValue({ id: 'new-cred' });
  });

  // Helper to get form elements by placeholder or label text
  const getNameInput = () => screen.getByPlaceholderText('My GitHub Token');
  const getTokenInput = () => screen.getByPlaceholderText('ghp_xxxxxxxxxxxx');
  const getAutoSyncCheckbox = () => screen.getByRole('checkbox');

  describe('rendering', () => {
    it('renders modal when isOpen is true', () => {
      render(<CredentialModal {...defaultProps} />);

      expect(screen.getByText('Connect GitHub')).toBeInTheDocument();
    });

    it('does not render modal when isOpen is false', () => {
      render(<CredentialModal {...defaultProps} isOpen={false} />);

      expect(screen.queryByText('Connect GitHub')).not.toBeInTheDocument();
    });

    it('renders form fields', () => {
      render(<CredentialModal {...defaultProps} />);

      expect(screen.getByText('Credential Name')).toBeInTheDocument();
      expect(screen.getByPlaceholderText('ghp_xxxxxxxxxxxx')).toBeInTheDocument();
      expect(screen.getByRole('checkbox')).toBeInTheDocument();
    });

    it('renders default credential name with provider name', () => {
      render(<CredentialModal {...defaultProps} />);

      const nameInput = getNameInput();
      expect(nameInput).toHaveValue('GitHub Token');
    });

    it('renders connect and cancel buttons', () => {
      render(<CredentialModal {...defaultProps} />);

      expect(screen.getByRole('button', { name: /connect/i })).toBeInTheDocument();
      expect(screen.getByRole('button', { name: /cancel/i })).toBeInTheDocument();
    });

    it('displays GitHub-specific token help text', () => {
      render(<CredentialModal {...defaultProps} />);

      expect(
        screen.getByText(/GitHub.*Settings.*Developer settings.*Personal access tokens/i)
      ).toBeInTheDocument();
    });

    it('displays GitLab-specific token help text', () => {
      const gitlabProvider: AvailableProvider = {
        ...githubProvider,
        id: 'provider-gitlab',
        name: 'GitLab',
        slug: 'gitlab',
        provider_type: 'gitlab',
      };

      render(<CredentialModal {...defaultProps} provider={gitlabProvider} />);

      expect(
        screen.getByText(/GitLab.*Preferences.*Access Tokens/i)
      ).toBeInTheDocument();
    });
  });

  describe('self-hosted providers (Gitea)', () => {
    it('renders URL fields for Gitea provider', () => {
      render(<CredentialModal {...defaultProps} provider={giteaProvider} />);

      // Check for API Base URL field
      expect(screen.getByPlaceholderText('https://git.example.com/api/v1')).toBeInTheDocument();
      // Check for Web Base URL field
      expect(screen.getByPlaceholderText('https://git.example.com')).toBeInTheDocument();
    });

    it('does not render URL fields for GitHub provider', () => {
      render(<CredentialModal {...defaultProps} />);

      expect(screen.queryByPlaceholderText('https://git.example.com/api/v1')).not.toBeInTheDocument();
      expect(screen.queryByPlaceholderText('https://git.example.com')).not.toBeInTheDocument();
    });

    it('shows Gitea-specific token help text', () => {
      render(<CredentialModal {...defaultProps} provider={giteaProvider} />);

      expect(
        screen.getByText(/Settings.*Applications.*Generate New Token/i)
      ).toBeInTheDocument();
    });

    it('shows API URL help text for Gitea', () => {
      render(<CredentialModal {...defaultProps} provider={giteaProvider} />);

      expect(
        screen.getByText(/API endpoint of your Gitea instance/i)
      ).toBeInTheDocument();
    });
  });

  describe('form interactions', () => {
    it('updates credential name on input', async () => {
      render(<CredentialModal {...defaultProps} />);

      const nameInput = getNameInput();
      await userEvent.clear(nameInput);
      await userEvent.type(nameInput, 'My Custom Token');

      expect(nameInput).toHaveValue('My Custom Token');
    });

    it('updates token on input', async () => {
      render(<CredentialModal {...defaultProps} />);

      const tokenInput = getTokenInput();
      await userEvent.type(tokenInput, 'ghp_test_token_123');

      expect(tokenInput).toHaveValue('ghp_test_token_123');
    });

    it('toggles auto sync checkbox', async () => {
      render(<CredentialModal {...defaultProps} />);

      const checkbox = getAutoSyncCheckbox();
      expect(checkbox).toBeChecked();

      await userEvent.click(checkbox);
      expect(checkbox).not.toBeChecked();

      await userEvent.click(checkbox);
      expect(checkbox).toBeChecked();
    });
  });

  describe('token visibility toggle', () => {
    it('hides token by default', () => {
      render(<CredentialModal {...defaultProps} />);

      const tokenInput = getTokenInput();
      expect(tokenInput).toHaveAttribute('type', 'password');
    });

    it('toggles token visibility when eye icon is clicked', async () => {
      render(<CredentialModal {...defaultProps} />);

      const tokenInput = getTokenInput();
      expect(tokenInput).toHaveAttribute('type', 'password');

      // Click to show
      const toggleButton = screen.getByTestId('icon-eye').parentElement;
      await userEvent.click(toggleButton!);

      expect(tokenInput).toHaveAttribute('type', 'text');

      // Click to hide again
      const hideButton = screen.getByTestId('icon-eye-off').parentElement;
      await userEvent.click(hideButton!);

      expect(tokenInput).toHaveAttribute('type', 'password');
    });
  });

  describe('form validation', () => {
    it('has required attribute on token input', () => {
      render(<CredentialModal {...defaultProps} />);

      const tokenInput = getTokenInput();
      expect(tokenInput).toHaveAttribute('required');
    });

    it('has required attribute on API URL for Gitea', () => {
      render(<CredentialModal {...defaultProps} provider={giteaProvider} />);

      const apiUrlInput = screen.getByPlaceholderText('https://git.example.com/api/v1');
      expect(apiUrlInput).toHaveAttribute('required');
    });

    it('has required attribute on credential name', () => {
      render(<CredentialModal {...defaultProps} />);

      const nameInput = getNameInput();
      expect(nameInput).toHaveAttribute('required');
    });
  });

  describe('form submission', () => {
    it('submits form with correct data for GitHub', async () => {
      render(<CredentialModal {...defaultProps} />);

      const tokenInput = getTokenInput();
      await userEvent.type(tokenInput, 'ghp_test_token');

      fireEvent.click(screen.getByRole('button', { name: /connect/i }));

      await waitFor(() => {
        expect(mockCreateCredential).toHaveBeenCalledWith(
          expect.objectContaining({
            name: 'GitHub Token',
            auth_type: 'personal_access_token',
            credentials: {
              access_token: 'ghp_test_token',
            },
            is_active: true,
            is_default: true,
          }),
          true // auto_sync
        );
      });
    });

    it('submits form with correct data for Gitea', async () => {
      render(<CredentialModal {...defaultProps} provider={giteaProvider} />);

      const tokenInput = screen.getByPlaceholderText('ghp_xxxxxxxxxxxx');
      await userEvent.type(tokenInput, 'gitea_token');

      const apiUrlInput = screen.getByPlaceholderText('https://git.example.com/api/v1');
      await userEvent.type(apiUrlInput, 'https://git.example.com/api/v1');

      const webUrlInput = screen.getByPlaceholderText('https://git.example.com');
      await userEvent.type(webUrlInput, 'https://git.example.com');

      fireEvent.click(screen.getByRole('button', { name: /connect/i }));

      await waitFor(() => {
        expect(mockCreateCredential).toHaveBeenCalledWith(
          expect.objectContaining({
            name: 'Gitea Token',
            auth_type: 'personal_access_token',
            credentials: {
              access_token: 'gitea_token',
              api_base_url: 'https://git.example.com/api/v1',
              web_base_url: 'https://git.example.com',
            },
          }),
          true
        );
      });
    });

    it('uses API URL as web URL when web URL is empty for Gitea', async () => {
      render(<CredentialModal {...defaultProps} provider={giteaProvider} />);

      const tokenInput = screen.getByPlaceholderText('ghp_xxxxxxxxxxxx');
      await userEvent.type(tokenInput, 'gitea_token');

      const apiUrlInput = screen.getByPlaceholderText('https://git.example.com/api/v1');
      await userEvent.type(apiUrlInput, 'https://git.example.com/api/v1');

      // Don't fill web URL

      fireEvent.click(screen.getByRole('button', { name: /connect/i }));

      await waitFor(() => {
        expect(mockCreateCredential).toHaveBeenCalledWith(
          expect.objectContaining({
            credentials: expect.objectContaining({
              web_base_url: 'https://git.example.com/api/v1',
            }),
          }),
          true
        );
      });
    });

    it('calls onSuccess after successful submission', async () => {
      render(<CredentialModal {...defaultProps} />);

      const tokenInput = getTokenInput();
      await userEvent.type(tokenInput, 'ghp_test_token');

      fireEvent.click(screen.getByRole('button', { name: /connect/i }));

      await waitFor(() => {
        expect(mockOnSuccess).toHaveBeenCalled();
      });
    });

    it('submits with auto_sync false when unchecked', async () => {
      render(<CredentialModal {...defaultProps} />);

      const tokenInput = getTokenInput();
      await userEvent.type(tokenInput, 'ghp_test_token');

      const checkbox = getAutoSyncCheckbox();
      await userEvent.click(checkbox);

      fireEvent.click(screen.getByRole('button', { name: /connect/i }));

      await waitFor(() => {
        expect(mockCreateCredential).toHaveBeenCalledWith(
          expect.anything(),
          false // auto_sync unchecked
        );
      });
    });
  });

  describe('error handling', () => {
    it('displays error message when submission fails', async () => {
      mockCreateCredential.mockRejectedValue(new Error('Network error'));

      render(<CredentialModal {...defaultProps} />);

      const tokenInput = getTokenInput();
      await userEvent.type(tokenInput, 'ghp_test_token');

      fireEvent.click(screen.getByRole('button', { name: /connect/i }));

      await waitFor(() => {
        expect(screen.getByText('Network error')).toBeInTheDocument();
      });

      expect(mockOnSuccess).not.toHaveBeenCalled();
    });

    it('displays generic error for non-Error throws', async () => {
      mockCreateCredential.mockRejectedValue('Unknown error');

      render(<CredentialModal {...defaultProps} />);

      const tokenInput = getTokenInput();
      await userEvent.type(tokenInput, 'ghp_test_token');

      fireEvent.click(screen.getByRole('button', { name: /connect/i }));

      await waitFor(() => {
        expect(screen.getByText('Failed to create credential')).toBeInTheDocument();
      });
    });

    it('shows error message when API call fails', async () => {
      mockCreateCredential.mockRejectedValue(new Error('Connection failed'));

      render(<CredentialModal {...defaultProps} />);

      const tokenInput = getTokenInput();
      await userEvent.type(tokenInput, 'ghp_test_token');

      fireEvent.click(screen.getByRole('button', { name: /connect/i }));

      await waitFor(() => {
        expect(screen.getByText('Connection failed')).toBeInTheDocument();
      });
    });
  });

  describe('loading state', () => {
    it('shows loading text on submit button while submitting', async () => {
      // Make createCredential hang to simulate loading
      mockCreateCredential.mockImplementation(
        () => new Promise((resolve) => setTimeout(resolve, 1000))
      );

      render(<CredentialModal {...defaultProps} />);

      const tokenInput = getTokenInput();
      await userEvent.type(tokenInput, 'ghp_test_token');

      fireEvent.click(screen.getByRole('button', { name: /connect/i }));

      expect(screen.getByText('Connecting...')).toBeInTheDocument();
    });

    it('disables buttons while loading', async () => {
      mockCreateCredential.mockImplementation(
        () => new Promise((resolve) => setTimeout(resolve, 1000))
      );

      render(<CredentialModal {...defaultProps} />);

      const tokenInput = getTokenInput();
      await userEvent.type(tokenInput, 'ghp_test_token');

      fireEvent.click(screen.getByRole('button', { name: /connect/i }));

      await waitFor(() => {
        expect(screen.getByRole('button', { name: /connecting/i })).toBeDisabled();
        expect(screen.getByRole('button', { name: /cancel/i })).toBeDisabled();
      });
    });
  });

  describe('modal close', () => {
    it('calls onClose when cancel button is clicked', () => {
      render(<CredentialModal {...defaultProps} />);

      fireEvent.click(screen.getByRole('button', { name: /cancel/i }));

      expect(mockOnClose).toHaveBeenCalled();
    });

    it('calls onClose when X button is clicked', () => {
      render(<CredentialModal {...defaultProps} />);

      const closeButton = screen.getByTestId('icon-x').parentElement;
      fireEvent.click(closeButton!);

      expect(mockOnClose).toHaveBeenCalled();
    });

    it('calls onClose when backdrop is clicked', () => {
      render(<CredentialModal {...defaultProps} />);

      // Find the backdrop (the element with bg-black/50)
      const backdrop = document.querySelector('.bg-black\\/50');
      fireEvent.click(backdrop!);

      expect(mockOnClose).toHaveBeenCalled();
    });
  });

  describe('accessibility', () => {
    it('has accessible form elements', () => {
      render(<CredentialModal {...defaultProps} />);

      expect(screen.getByText('Credential Name')).toBeInTheDocument();
      expect(screen.getByPlaceholderText('ghp_xxxxxxxxxxxx')).toBeInTheDocument();
      expect(screen.getByRole('checkbox')).toBeInTheDocument();
    });

    it('form fields are keyboard accessible', async () => {
      render(<CredentialModal {...defaultProps} />);

      const nameInput = getNameInput();
      const tokenInput = getTokenInput();

      nameInput.focus();
      expect(document.activeElement).toBe(nameInput);

      await userEvent.tab();
      expect(document.activeElement).toBe(tokenInput);
    });
  });
});
