import { render, screen, fireEvent } from '@testing-library/react';
import { GitProviderCard } from '../components/GitProviderCard';
import { AvailableProvider } from '../types';

// Mock lucide-react icons
jest.mock('lucide-react', () => ({
  GitBranch: () => <span data-testid="icon-git-branch" />,
  Plus: () => <span data-testid="icon-plus" />,
  CheckCircle: () => <span data-testid="icon-check-circle" />,
  Settings: () => <span data-testid="icon-settings" />,
  ExternalLink: () => <span data-testid="icon-external" />,
}));

describe('GitProviderCard', () => {
  const mockProvider: AvailableProvider = {
    id: 'github',
    name: 'GitHub',
    slug: 'github',
    provider_type: 'github',
    description: 'Connect to GitHub repositories',
    supports_oauth: true,
    supports_pat: true,
    supports_devops: true,
    capabilities: ['repositories', 'webhooks', 'devops', 'oauth'],
    configured: false,
  };

  const configuredProvider: AvailableProvider = {
    ...mockProvider,
    configured: true,
  };

  const defaultProps = {
    provider: mockProvider,
    onAddCredential: jest.fn(),
    canManage: true,
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('rendering', () => {
    it('renders provider name', () => {
      render(<GitProviderCard {...defaultProps} />);

      expect(screen.getByText('GitHub')).toBeInTheDocument();
    });

    it('renders provider description', () => {
      render(<GitProviderCard {...defaultProps} />);

      expect(screen.getByText('Connect to GitHub repositories')).toBeInTheDocument();
    });

    it('renders provider type', () => {
      render(<GitProviderCard {...defaultProps} />);

      expect(screen.getByText('github')).toBeInTheDocument();
    });

    it('renders provider icon for GitHub', () => {
      const { container } = render(<GitProviderCard {...defaultProps} />);

      // Component uses inline SVG icons instead of external images
      const svg = container.querySelector('svg');
      expect(svg).toBeInTheDocument();
    });

    it('renders provider icon for GitLab', () => {
      const gitlabProvider: AvailableProvider = {
        ...mockProvider,
        id: 'gitlab',
        name: 'GitLab',
        slug: 'gitlab',
        provider_type: 'gitlab',
      };

      const { container } = render(<GitProviderCard {...defaultProps} provider={gitlabProvider} />);

      // Component uses inline SVG icons instead of external images
      const svg = container.querySelector('svg');
      expect(svg).toBeInTheDocument();
    });

    it('renders provider icon for Gitea', () => {
      const giteaProvider: AvailableProvider = {
        ...mockProvider,
        id: 'gitea',
        name: 'Gitea',
        slug: 'gitea',
        provider_type: 'gitea',
      };

      const { container } = render(<GitProviderCard {...defaultProps} provider={giteaProvider} />);

      // Component uses inline SVG icons instead of external images
      const svg = container.querySelector('svg');
      expect(svg).toBeInTheDocument();
    });

    it('renders fallback icon for unknown provider type', () => {
      const unknownProvider: AvailableProvider = {
        ...mockProvider,
        provider_type: 'unknown',
        slug: 'unknown',
      };

      render(<GitProviderCard {...defaultProps} provider={unknownProvider} />);

      expect(screen.getByTestId('icon-git-branch')).toBeInTheDocument();
    });

    it('shows check icon when provider is configured', () => {
      render(<GitProviderCard {...defaultProps} provider={configuredProvider} />);

      expect(screen.getByTestId('icon-check-circle')).toBeInTheDocument();
    });

    it('does not show check icon when provider is not configured', () => {
      render(<GitProviderCard {...defaultProps} />);

      expect(screen.queryByTestId('icon-check-circle')).not.toBeInTheDocument();
    });
  });

  describe('capabilities badges', () => {
    it('shows OAuth badge when supports_oauth is true', () => {
      render(<GitProviderCard {...defaultProps} />);

      expect(screen.getByText('OAuth')).toBeInTheDocument();
    });

    it('shows PAT badge when supports_pat is true', () => {
      render(<GitProviderCard {...defaultProps} />);

      expect(screen.getByText('PAT')).toBeInTheDocument();
    });

    it('shows DevOps badge when supports_devops is true', () => {
      render(<GitProviderCard {...defaultProps} />);

      expect(screen.getByText('DevOps')).toBeInTheDocument();
    });

    it('does not show OAuth badge when supports_oauth is false', () => {
      const noOAuthProvider: AvailableProvider = {
        ...mockProvider,
        supports_oauth: false,
      };

      render(<GitProviderCard {...defaultProps} provider={noOAuthProvider} />);

      expect(screen.queryByText('OAuth')).not.toBeInTheDocument();
    });

    it('does not show PAT badge when supports_pat is false', () => {
      const noPatProvider: AvailableProvider = {
        ...mockProvider,
        supports_pat: false,
      };

      render(<GitProviderCard {...defaultProps} provider={noPatProvider} />);

      expect(screen.queryByText('PAT')).not.toBeInTheDocument();
    });

    it('does not show DevOps badge when supports_devops is false', () => {
      const noDevopsProvider: AvailableProvider = {
        ...mockProvider,
        supports_devops: false,
      };

      render(<GitProviderCard {...defaultProps} provider={noDevopsProvider} />);

      expect(screen.queryByText('DevOps')).not.toBeInTheDocument();
    });
  });

  describe('action buttons', () => {
    it('shows Connect button when not configured', () => {
      render(<GitProviderCard {...defaultProps} />);

      expect(screen.getByRole('button', { name: /connect/i })).toBeInTheDocument();
      expect(screen.getByTestId('icon-plus')).toBeInTheDocument();
    });

    it('shows Manage button when configured', () => {
      render(<GitProviderCard {...defaultProps} provider={configuredProvider} />);

      expect(screen.getByRole('button', { name: /manage/i })).toBeInTheDocument();
      expect(screen.getByTestId('icon-settings')).toBeInTheDocument();
    });

    it('calls onAddCredential when Connect button is clicked', () => {
      render(<GitProviderCard {...defaultProps} />);

      fireEvent.click(screen.getByRole('button', { name: /connect/i }));

      expect(defaultProps.onAddCredential).toHaveBeenCalled();
    });

    it('calls onAddCredential when Manage button is clicked', () => {
      const onAddCredential = jest.fn();
      render(
        <GitProviderCard
          {...defaultProps}
          provider={configuredProvider}
          onAddCredential={onAddCredential}
        />
      );

      fireEvent.click(screen.getByRole('button', { name: /manage/i }));

      expect(onAddCredential).toHaveBeenCalled();
    });

    it('disables Connect button when canManage is false', () => {
      render(<GitProviderCard {...defaultProps} canManage={false} />);

      expect(screen.getByRole('button', { name: /connect/i })).toBeDisabled();
    });

    it('disables Manage button when canManage is false', () => {
      render(
        <GitProviderCard
          {...defaultProps}
          provider={configuredProvider}
          canManage={false}
        />
      );

      expect(screen.getByRole('button', { name: /manage/i })).toBeDisabled();
    });

    it('enables Connect button when canManage is true', () => {
      render(<GitProviderCard {...defaultProps} canManage={true} />);

      expect(screen.getByRole('button', { name: /connect/i })).not.toBeDisabled();
    });
  });

  describe('provider-specific styling', () => {
    it('applies GitHub styling', () => {
      const { container } = render(<GitProviderCard {...defaultProps} />);

      // GitHub uses brand color #24292f
      expect(container.querySelector('.bg-\\[\\#24292f\\]')).toBeInTheDocument();
    });

    it('applies GitLab styling', () => {
      const gitlabProvider: AvailableProvider = {
        ...mockProvider,
        provider_type: 'gitlab',
        slug: 'gitlab',
      };

      const { container } = render(
        <GitProviderCard {...defaultProps} provider={gitlabProvider} />
      );

      // GitLab uses brand color #FC6D26
      expect(container.querySelector('.bg-\\[\\#FC6D26\\]')).toBeInTheDocument();
    });

    it('applies Gitea styling', () => {
      const giteaProvider: AvailableProvider = {
        ...mockProvider,
        provider_type: 'gitea',
        slug: 'gitea',
      };

      const { container } = render(
        <GitProviderCard {...defaultProps} provider={giteaProvider} />
      );

      // Gitea uses brand color #609926
      expect(container.querySelector('.bg-\\[\\#609926\\]')).toBeInTheDocument();
    });
  });

  describe('accessibility', () => {
    it('has accessible provider name as heading', () => {
      render(<GitProviderCard {...defaultProps} />);

      expect(screen.getByRole('heading', { name: 'GitHub' })).toBeInTheDocument();
    });

    it('Connect button is keyboard accessible', () => {
      render(<GitProviderCard {...defaultProps} />);

      const connectButton = screen.getByRole('button', { name: /connect/i });
      connectButton.focus();
      expect(document.activeElement).toBe(connectButton);
    });

    it('provider icon is rendered', () => {
      const { container } = render(<GitProviderCard {...defaultProps} />);

      // Component uses inline SVG icons instead of img elements
      expect(container.querySelector('svg')).toBeInTheDocument();
    });
  });

  describe('without description', () => {
    it('renders without description', () => {
      const providerWithoutDescription: AvailableProvider = {
        ...mockProvider,
        description: undefined,
      };

      render(
        <GitProviderCard {...defaultProps} provider={providerWithoutDescription} />
      );

      expect(screen.getByText('GitHub')).toBeInTheDocument();
      expect(
        screen.queryByText('Connect to GitHub repositories')
      ).not.toBeInTheDocument();
    });
  });
});
