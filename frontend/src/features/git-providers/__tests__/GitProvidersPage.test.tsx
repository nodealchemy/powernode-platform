import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { GitProvidersPage } from '../components/GitProvidersPage';
import { useGitProviders, useGitCredentials } from '../hooks/useGitProviders';
import { useAuth } from '@/shared/hooks/useAuth';
import { useNotification } from '@/shared/hooks/useNotification';
import { AvailableProvider } from '../types';

// Mock hooks
jest.mock('../hooks/useGitProviders');
jest.mock('@/shared/hooks/useAuth');
jest.mock('@/shared/hooks/useNotification');

// Mock components
jest.mock('../components/GitProviderCard', () => ({
  GitProviderCard: ({
    provider,
    onAddCredential,
    canManage,
  }: {
    provider: AvailableProvider;
    onAddCredential: () => void;
    canManage?: boolean;
  }) => (
    <div data-testid={`provider-card-${provider.id}`}>
      <span>{provider.name}</span>
      <span data-testid="configured-status">
        {provider.configured ? 'configured' : 'not-configured'}
      </span>
      <button onClick={onAddCredential} disabled={!canManage}>
        Connect
      </button>
    </div>
  ),
}));

jest.mock('../components/CredentialModal', () => ({
  CredentialModal: ({
    isOpen,
    onClose,
    provider,
    onSuccess,
  }: {
    isOpen: boolean;
    onClose: () => void;
    provider: AvailableProvider;
    onSuccess: () => void;
  }) =>
    isOpen ? (
      <div data-testid="credential-modal">
        <span>Modal for {provider.name}</span>
        <button onClick={onClose}>Close</button>
        <button onClick={onSuccess}>Success</button>
      </div>
    ) : null,
}));

// Mock lucide-react icons
jest.mock('lucide-react', () => ({
  GitBranch: () => <span data-testid="icon-git-branch" />,
  Plus: () => <span data-testid="icon-plus" />,
  RefreshCw: () => <span data-testid="icon-refresh" />,
  Settings: () => <span data-testid="icon-settings" />,
}));

// Mock PageContainer
jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({
    children,
    title,
    actions,
  }: {
    children: React.ReactNode;
    title: string;
    actions?: Array<{ id: string; label: string; onClick: () => void }>;
  }) => (
    <div data-testid="page-container">
      <h1>{title}</h1>
      {actions?.map((action) => (
        <button key={action.id} onClick={action.onClick} data-testid={`action-${action.id}`}>
          {action.label}
        </button>
      ))}
      {children}
    </div>
  ),
}));

const mockUseGitProviders = useGitProviders as jest.MockedFunction<typeof useGitProviders>;
const mockUseGitCredentials = useGitCredentials as jest.MockedFunction<typeof useGitCredentials>;
const mockUseAuth = useAuth as jest.MockedFunction<typeof useAuth>;
const mockUseNotification = useNotification as jest.MockedFunction<typeof useNotification>;

describe('GitProvidersPage', () => {
  const mockRefreshAvailable = jest.fn();
  const mockShowNotification = jest.fn();

  const mockProviders: AvailableProvider[] = [
    {
      id: 'github',
      name: 'GitHub',
      provider_type: 'github',
      description: 'Connect to GitHub',
      supports_oauth: true,
      supports_pat: true,
      supports_ci_cd: true,
      configured: true,
    },
    {
      id: 'gitlab',
      name: 'GitLab',
      provider_type: 'gitlab',
      description: 'Connect to GitLab',
      supports_oauth: true,
      supports_pat: true,
      supports_ci_cd: true,
      configured: false,
    },
    {
      id: 'gitea',
      name: 'Gitea',
      provider_type: 'gitea',
      description: 'Connect to Gitea',
      supports_oauth: false,
      supports_pat: true,
      supports_ci_cd: true,
      configured: false,
    },
  ];

  beforeEach(() => {
    jest.clearAllMocks();

    mockUseAuth.mockReturnValue({
      currentUser: {
        id: 'user-1',
        email: 'test@example.com',
        permissions: ['git.providers.create', 'git.providers.read'],
      },
      loading: false,
      isAuthenticated: true,
      login: jest.fn(),
      logout: jest.fn(),
      refreshToken: jest.fn(),
    } as ReturnType<typeof useAuth>);

    mockUseNotification.mockReturnValue({
      showNotification: mockShowNotification,
    } as ReturnType<typeof useNotification>);

    mockUseGitProviders.mockReturnValue({
      availableProviders: mockProviders,
      loading: false,
      error: null,
      refreshAvailable: mockRefreshAvailable,
      credentials: [],
      credentialsLoading: false,
      credentialsError: null,
      fetchCredentials: jest.fn(),
    } as ReturnType<typeof useGitProviders>);

    mockUseGitCredentials.mockReturnValue({
      credentials: [],
      loading: false,
      error: null,
      refresh: jest.fn(),
      createCredential: jest.fn(),
      deleteCredential: jest.fn(),
      testConnection: jest.fn(),
      syncRepositories: jest.fn(),
    } as ReturnType<typeof useGitCredentials>);
  });

  describe('loading state', () => {
    it('renders loading spinner when loading', () => {
      mockUseGitProviders.mockReturnValue({
        availableProviders: [],
        loading: true,
        error: null,
        refreshAvailable: mockRefreshAvailable,
        credentials: [],
        credentialsLoading: false,
        credentialsError: null,
        fetchCredentials: jest.fn(),
      } as ReturnType<typeof useGitProviders>);

      const { container } = render(<GitProvidersPage />);

      expect(screen.getByText('Git Providers')).toBeInTheDocument();
      // Check for the loading spinner using class selector
      expect(container.querySelector('.animate-spin')).toBeInTheDocument();
    });
  });

  describe('error state', () => {
    it('renders error message when there is an error', () => {
      mockUseGitProviders.mockReturnValue({
        availableProviders: [],
        loading: false,
        error: 'Failed to load providers',
        refreshAvailable: mockRefreshAvailable,
        credentials: [],
        credentialsLoading: false,
        credentialsError: null,
        fetchCredentials: jest.fn(),
      } as ReturnType<typeof useGitProviders>);

      render(<GitProvidersPage />);

      expect(screen.getByText('Failed to load providers')).toBeInTheDocument();
    });
  });

  describe('empty state', () => {
    it('renders empty state when no providers available', () => {
      mockUseGitProviders.mockReturnValue({
        availableProviders: [],
        loading: false,
        error: null,
        refreshAvailable: mockRefreshAvailable,
        credentials: [],
        credentialsLoading: false,
        credentialsError: null,
        fetchCredentials: jest.fn(),
      } as ReturnType<typeof useGitProviders>);

      render(<GitProvidersPage />);

      expect(screen.getByText('No Git Providers')).toBeInTheDocument();
      expect(
        screen.getByText('Add a Git provider to connect your repositories.')
      ).toBeInTheDocument();
    });
  });

  describe('provider display', () => {
    it('renders all providers', () => {
      render(<GitProvidersPage />);

      expect(screen.getByTestId('provider-card-github')).toBeInTheDocument();
      expect(screen.getByTestId('provider-card-gitlab')).toBeInTheDocument();
      expect(screen.getByTestId('provider-card-gitea')).toBeInTheDocument();
    });

    it('shows providers in a grid layout', () => {
      const { container } = render(<GitProvidersPage />);

      // All 3 providers should be in a grid
      const cards = screen.getAllByTestId(/provider-card-/);
      expect(cards).toHaveLength(3);

      // Check grid container exists
      expect(container.querySelector('.grid')).toBeInTheDocument();
    });

    it('shows configured status for each provider', () => {
      render(<GitProvidersPage />);

      // Check the configured statuses
      const githubCard = screen.getByTestId('provider-card-github');
      expect(githubCard.querySelector('[data-testid="configured-status"]')?.textContent).toBe(
        'configured'
      );

      const gitlabCard = screen.getByTestId('provider-card-gitlab');
      expect(gitlabCard.querySelector('[data-testid="configured-status"]')?.textContent).toBe(
        'not-configured'
      );
    });

    it('renders unconfigured providers correctly', () => {
      mockUseGitProviders.mockReturnValue({
        availableProviders: mockProviders.filter((p) => !p.configured),
        loading: false,
        error: null,
        refreshAvailable: mockRefreshAvailable,
        credentials: [],
        credentialsLoading: false,
        credentialsError: null,
        fetchCredentials: jest.fn(),
      } as ReturnType<typeof useGitProviders>);

      render(<GitProvidersPage />);

      // Should not have any card with "configured" status
      const cards = screen.getAllByTestId(/provider-card-/);
      cards.forEach((card) => {
        expect(card.querySelector('[data-testid="configured-status"]')?.textContent).toBe(
          'not-configured'
        );
      });
    });
  });

  describe('actions', () => {
    it('calls refreshAvailable when refresh button is clicked', () => {
      render(<GitProvidersPage />);

      fireEvent.click(screen.getByTestId('action-refresh'));

      expect(mockRefreshAvailable).toHaveBeenCalled();
    });
  });

  describe('credential modal', () => {
    it('opens modal when connect is clicked on an unconfigured provider', () => {
      render(<GitProvidersPage />);

      // Modal should not be visible initially
      expect(screen.queryByTestId('credential-modal')).not.toBeInTheDocument();

      // Click connect on GitLab (unconfigured provider)
      const gitlabCard = screen.getByTestId('provider-card-gitlab');
      fireEvent.click(gitlabCard.querySelector('button')!);

      // Modal should now be visible for unconfigured providers
      expect(screen.getByTestId('credential-modal')).toBeInTheDocument();
      expect(screen.getByText('Modal for GitLab')).toBeInTheDocument();
    });

    it('closes modal when close is clicked', () => {
      render(<GitProvidersPage />);

      // Open modal on unconfigured provider
      const gitlabCard = screen.getByTestId('provider-card-gitlab');
      fireEvent.click(gitlabCard.querySelector('button')!);

      expect(screen.getByTestId('credential-modal')).toBeInTheDocument();

      // Close modal
      fireEvent.click(screen.getByText('Close'));

      expect(screen.queryByTestId('credential-modal')).not.toBeInTheDocument();
    });

    it('shows notification and refreshes on success', async () => {
      render(<GitProvidersPage />);

      // Open modal on unconfigured provider
      const gitlabCard = screen.getByTestId('provider-card-gitlab');
      fireEvent.click(gitlabCard.querySelector('button')!);

      // Trigger success
      fireEvent.click(screen.getByText('Success'));

      await waitFor(() => {
        expect(mockShowNotification).toHaveBeenCalledWith({
          type: 'success',
          message: 'Git credential created successfully',
        });
        expect(mockRefreshAvailable).toHaveBeenCalled();
      });

      // Modal should be closed
      expect(screen.queryByTestId('credential-modal')).not.toBeInTheDocument();
    });
  });

  describe('permissions', () => {
    it('disables connect button when user lacks permission', () => {
      mockUseAuth.mockReturnValue({
        currentUser: {
          id: 'user-1',
          email: 'test@example.com',
          permissions: ['git.providers.read'], // No create permission
        },
        loading: false,
        isAuthenticated: true,
        login: jest.fn(),
        logout: jest.fn(),
        refreshToken: jest.fn(),
      } as ReturnType<typeof useAuth>);

      render(<GitProvidersPage />);

      const githubCard = screen.getByTestId('provider-card-github');
      const connectButton = githubCard.querySelector('button');

      expect(connectButton).toBeDisabled();
    });

    it('enables connect button when user has permission', () => {
      render(<GitProvidersPage />);

      const githubCard = screen.getByTestId('provider-card-github');
      const connectButton = githubCard.querySelector('button');

      expect(connectButton).not.toBeDisabled();
    });
  });

  describe('page structure', () => {
    it('renders page title', () => {
      render(<GitProvidersPage />);

      expect(screen.getByText('Git Providers')).toBeInTheDocument();
    });

    it('renders within PageContainer', () => {
      render(<GitProvidersPage />);

      expect(screen.getByTestId('page-container')).toBeInTheDocument();
    });
  });
});
