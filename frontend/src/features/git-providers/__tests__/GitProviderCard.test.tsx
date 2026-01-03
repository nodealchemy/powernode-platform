import React from 'react';
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
    provider_type: 'github',
    description: 'Connect to GitHub repositories',
    supports_oauth: true,
    supports_pat: true,
    supports_ci_cd: true,
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
      render(<GitProviderCard {...defaultProps} />);

      const img = screen.getByAltText('GitHub');
      expect(img).toHaveAttribute('src', 'https://cdn.simpleicons.org/github');
    });

    it('renders provider icon for GitLab', () => {
      const gitlabProvider = {
        ...mockProvider,
        id: 'gitlab',
        name: 'GitLab',
        provider_type: 'gitlab',
      };

      render(<GitProviderCard {...defaultProps} provider={gitlabProvider} />);

      const img = screen.getByAltText('GitLab');
      expect(img).toHaveAttribute('src', 'https://cdn.simpleicons.org/gitlab');
    });

    it('renders provider icon for Gitea', () => {
      const giteaProvider = {
        ...mockProvider,
        id: 'gitea',
        name: 'Gitea',
        provider_type: 'gitea',
      };

      render(<GitProviderCard {...defaultProps} provider={giteaProvider} />);

      const img = screen.getByAltText('Gitea');
      expect(img).toHaveAttribute('src', 'https://cdn.simpleicons.org/gitea');
    });

    it('renders fallback icon for unknown provider type', () => {
      const unknownProvider = {
        ...mockProvider,
        provider_type: 'unknown',
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

    it('shows CI/CD badge when supports_ci_cd is true', () => {
      render(<GitProviderCard {...defaultProps} />);

      expect(screen.getByText('CI/CD')).toBeInTheDocument();
    });

    it('does not show OAuth badge when supports_oauth is false', () => {
      const noOAuthProvider = {
        ...mockProvider,
        supports_oauth: false,
      };

      render(<GitProviderCard {...defaultProps} provider={noOAuthProvider} />);

      expect(screen.queryByText('OAuth')).not.toBeInTheDocument();
    });

    it('does not show PAT badge when supports_pat is false', () => {
      const noPatProvider = {
        ...mockProvider,
        supports_pat: false,
      };

      render(<GitProviderCard {...defaultProps} provider={noPatProvider} />);

      expect(screen.queryByText('PAT')).not.toBeInTheDocument();
    });

    it('does not show CI/CD badge when supports_ci_cd is false', () => {
      const noCiCdProvider = {
        ...mockProvider,
        supports_ci_cd: false,
      };

      render(<GitProviderCard {...defaultProps} provider={noCiCdProvider} />);

      expect(screen.queryByText('CI/CD')).not.toBeInTheDocument();
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

      expect(container.querySelector('.bg-theme-background')).toBeInTheDocument();
    });

    it('applies GitLab styling', () => {
      const gitlabProvider = {
        ...mockProvider,
        provider_type: 'gitlab',
      };

      const { container } = render(
        <GitProviderCard {...defaultProps} provider={gitlabProvider} />
      );

      expect(container.querySelector('.bg-theme-warning')).toBeInTheDocument();
    });

    it('applies Gitea styling', () => {
      const giteaProvider = {
        ...mockProvider,
        provider_type: 'gitea',
      };

      const { container } = render(
        <GitProviderCard {...defaultProps} provider={giteaProvider} />
      );

      expect(container.querySelector('.bg-theme-success')).toBeInTheDocument();
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

    it('provider image has alt text', () => {
      render(<GitProviderCard {...defaultProps} />);

      expect(screen.getByAltText('GitHub')).toBeInTheDocument();
    });
  });

  describe('without description', () => {
    it('renders without description', () => {
      const providerWithoutDescription = {
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
