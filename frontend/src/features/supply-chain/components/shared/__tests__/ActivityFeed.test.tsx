import { render, screen } from '@testing-library/react';
import { ActivityFeed } from '../ActivityFeed';

jest.mock('lucide-react', () => ({
  FileCode: ({ className }: { className?: string }) => (
    <span data-testid="file-code-icon" className={className} />
  ),
  Container: ({ className }: { className?: string }) => (
    <span data-testid="container-icon" className={className} />
  ),
  Shield: ({ className }: { className?: string }) => (
    <span data-testid="shield-icon" className={className} />
  ),
  Building2: ({ className }: { className?: string }) => (
    <span data-testid="building2-icon" className={className} />
  ),
  Scale: ({ className }: { className?: string }) => (
    <span data-testid="scale-icon" className={className} />
  ),
  Clock: ({ className }: { className?: string }) => (
    <span data-testid="clock-icon" className={className} />
  ),
}));

describe('ActivityFeed', () => {
  describe('empty state', () => {
    it('renders empty state when no activity items', () => {
      render(<ActivityFeed items={[]} />);
      expect(screen.getByText('Recent Activity')).toBeInTheDocument();
      expect(screen.getByText('No recent activity')).toBeInTheDocument();
    });

    it('displays Clock icon in empty state', () => {
      render(<ActivityFeed items={[]} />);
      expect(screen.getByTestId('clock-icon')).toBeInTheDocument();
    });

    it('applies correct styling to empty state icon', () => {
      render(<ActivityFeed items={[]} />);
      const icon = screen.getByTestId('clock-icon');
      expect(icon).toHaveClass('w-8');
      expect(icon).toHaveClass('h-8');
      expect(icon).toHaveClass('text-theme-tertiary');
    });
  });

  describe('activity item rendering', () => {
    it('renders single activity item', () => {
      const item = {
        id: 'activity-1',
        action: 'created',
        entity_type: 'sbom',
        entity_name: 'Production App',
        user_name: 'alice',
        details: 'SBOM generated',
        created_at: new Date().toISOString(),
      };
      render(<ActivityFeed items={[item]} />);
      expect(screen.getByText('created')).toBeInTheDocument();
      expect(screen.getByText('Production App')).toBeInTheDocument();
    });

    it('renders multiple activity items', () => {
      const items = [
        {
          id: 'activity-1',
          action: 'created',
          entity_type: 'sbom',
          entity_name: 'App 1',
          user_name: 'alice',
          details: 'SBOM created',
          created_at: new Date().toISOString(),
        },
        {
          id: 'activity-2',
          action: 'updated',
          entity_type: 'container_image',
          entity_name: 'App 2',
          user_name: 'bob',
          details: 'Image scanned',
          created_at: new Date().toISOString(),
        },
        {
          id: 'activity-3',
          action: 'verified',
          entity_type: 'attestation',
          entity_name: 'App 3',
          user_name: 'charlie',
          details: 'Attestation verified',
          created_at: new Date().toISOString(),
        },
      ];
      render(<ActivityFeed items={items} />);
      expect(screen.getByText('App 1')).toBeInTheDocument();
      expect(screen.getByText('App 2')).toBeInTheDocument();
      expect(screen.getByText('App 3')).toBeInTheDocument();
    });
  });

  describe('entity type icons', () => {
    it('renders FileCode icon for sbom entity type', () => {
      const item = {
        id: 'activity-1',
        action: 'created',
        entity_type: 'sbom',
        entity_name: 'App SBOM',
        user_name: 'alice',
        details: 'SBOM generated',
        created_at: new Date().toISOString(),
      };
      render(<ActivityFeed items={[item]} />);
      expect(screen.getByTestId('file-code-icon')).toBeInTheDocument();
    });

    it('renders Container icon for container_image entity type', () => {
      const item = {
        id: 'activity-1',
        action: 'scanned',
        entity_type: 'container_image',
        entity_name: 'App Image',
        user_name: 'bob',
        details: 'Image scanned',
        created_at: new Date().toISOString(),
      };
      render(<ActivityFeed items={[item]} />);
      expect(screen.getByTestId('container-icon')).toBeInTheDocument();
    });

    it('renders Shield icon for attestation entity type', () => {
      const item = {
        id: 'activity-1',
        action: 'verified',
        entity_type: 'attestation',
        entity_name: 'App Attestation',
        user_name: 'charlie',
        details: 'Attestation verified',
        created_at: new Date().toISOString(),
      };
      render(<ActivityFeed items={[item]} />);
      expect(screen.getByTestId('shield-icon')).toBeInTheDocument();
    });

    it('renders Building2 icon for vendor entity type', () => {
      const item = {
        id: 'activity-1',
        action: 'assessed',
        entity_type: 'vendor',
        entity_name: 'Vendor Corp',
        user_name: 'diana',
        details: 'Risk assessment completed',
        created_at: new Date().toISOString(),
      };
      render(<ActivityFeed items={[item]} />);
      expect(screen.getByTestId('building2-icon')).toBeInTheDocument();
    });

    it('renders Scale icon for license_violation entity type', () => {
      const item = {
        id: 'activity-1',
        action: 'detected',
        entity_type: 'license_violation',
        entity_name: 'GPL Violation',
        user_name: 'eve',
        details: 'License violation found',
        created_at: new Date().toISOString(),
      };
      render(<ActivityFeed items={[item]} />);
      expect(screen.getByTestId('scale-icon')).toBeInTheDocument();
    });

    it('defaults to FileCode icon for unknown entity type', () => {
      const item = {
        id: 'activity-1',
        action: 'processed',
        entity_type: 'unknown_type',
        entity_name: 'Unknown Entity',
        user_name: 'frank',
        details: 'Item processed',
        created_at: new Date().toISOString(),
      };
      render(<ActivityFeed items={[item]} />);
      expect(screen.getByTestId('file-code-icon')).toBeInTheDocument();
    });
  });

  describe('icon styling', () => {
    it('applies correct styling to entity icons', () => {
      const item = {
        id: 'activity-1',
        action: 'created',
        entity_type: 'sbom',
        entity_name: 'App',
        user_name: 'alice',
        details: 'Created',
        created_at: new Date().toISOString(),
      };
      render(<ActivityFeed items={[item]} />);
      const icon = screen.getByTestId('file-code-icon');
      expect(icon).toHaveClass('w-4');
      expect(icon).toHaveClass('h-4');
      expect(icon).toHaveClass('text-theme-primary');
    });

    it('icon is centered in its container', () => {
      const item = {
        id: 'activity-1',
        action: 'created',
        entity_type: 'sbom',
        entity_name: 'App',
        user_name: 'alice',
        details: 'Created',
        created_at: new Date().toISOString(),
      };
      const { container } = render(<ActivityFeed items={[item]} />);
      const iconContainer = container.querySelector('div[class*="p-1.5"]');
      expect(iconContainer).toHaveClass('rounded');
      expect(iconContainer).toHaveClass('bg-theme-primary/10');
    });
  });

  describe('text content', () => {
    it('displays action text', () => {
      const item = {
        id: 'activity-1',
        action: 'created',
        entity_type: 'sbom',
        entity_name: 'App',
        user_name: 'alice',
        details: 'SBOM created',
        created_at: new Date().toISOString(),
      };
      render(<ActivityFeed items={[item]} />);
      expect(screen.getByText('created')).toBeInTheDocument();
    });

    it('displays entity name', () => {
      const item = {
        id: 'activity-1',
        action: 'created',
        entity_type: 'sbom',
        entity_name: 'Production App',
        user_name: 'alice',
        details: 'SBOM created',
        created_at: new Date().toISOString(),
      };
      render(<ActivityFeed items={[item]} />);
      expect(screen.getByText('Production App')).toBeInTheDocument();
    });

    it('displays user name when provided', () => {
      const item = {
        id: 'activity-1',
        action: 'created',
        entity_type: 'sbom',
        entity_name: 'App',
        user_name: 'alice',
        details: 'SBOM created',
        created_at: new Date().toISOString(),
      };
      render(<ActivityFeed items={[item]} />);
      expect(screen.getByText('by alice')).toBeInTheDocument();
    });

    it('does not display user name when not provided', () => {
      const item = {
        id: 'activity-1',
        action: 'created',
        entity_type: 'sbom',
        entity_name: 'App',
        details: 'SBOM created',
        created_at: new Date().toISOString(),
      };
      render(<ActivityFeed items={[item]} />);
      expect(screen.queryByText(/^by /)).not.toBeInTheDocument();
    });
  });

  describe('relative time formatting', () => {
    it('displays "Just now" for very recent activity', () => {
      const now = new Date();
      const item = {
        id: 'activity-1',
        action: 'created',
        entity_type: 'sbom',
        entity_name: 'App',
        user_name: 'alice',
        details: 'Created',
        created_at: now.toISOString(),
      };
      render(<ActivityFeed items={[item]} />);
      expect(screen.getByText('Just now')).toBeInTheDocument();
    });

    it('displays minutes ago for recent activity', () => {
      const tenMinutesAgo = new Date(Date.now() - 10 * 60 * 1000);
      const item = {
        id: 'activity-1',
        action: 'created',
        entity_type: 'sbom',
        entity_name: 'App',
        user_name: 'alice',
        details: 'Created',
        created_at: tenMinutesAgo.toISOString(),
      };
      render(<ActivityFeed items={[item]} />);
      expect(screen.getByText('10m ago')).toBeInTheDocument();
    });

    it('displays hours ago for activity from earlier today', () => {
      const twoHoursAgo = new Date(Date.now() - 2 * 60 * 60 * 1000);
      const item = {
        id: 'activity-1',
        action: 'created',
        entity_type: 'sbom',
        entity_name: 'App',
        user_name: 'alice',
        details: 'Created',
        created_at: twoHoursAgo.toISOString(),
      };
      render(<ActivityFeed items={[item]} />);
      expect(screen.getByText('2h ago')).toBeInTheDocument();
    });

    it('displays days ago for older activity', () => {
      const threeDaysAgo = new Date(Date.now() - 3 * 24 * 60 * 60 * 1000);
      const item = {
        id: 'activity-1',
        action: 'created',
        entity_type: 'sbom',
        entity_name: 'App',
        user_name: 'alice',
        details: 'Created',
        created_at: threeDaysAgo.toISOString(),
      };
      render(<ActivityFeed items={[item]} />);
      expect(screen.getByText('3d ago')).toBeInTheDocument();
    });

    it('displays date for very old activity', () => {
      const eightDaysAgo = new Date(Date.now() - 8 * 24 * 60 * 60 * 1000);
      const item = {
        id: 'activity-1',
        action: 'created',
        entity_type: 'sbom',
        entity_name: 'App',
        user_name: 'alice',
        details: 'Created',
        created_at: eightDaysAgo.toISOString(),
      };
      render(<ActivityFeed items={[item]} />);
      const dateStr = eightDaysAgo.toLocaleDateString();
      expect(screen.getByText(dateStr)).toBeInTheDocument();
    });

    it('displays timestamp as right-aligned whitespace-nowrap', () => {
      const item = {
        id: 'activity-1',
        action: 'created',
        entity_type: 'sbom',
        entity_name: 'App',
        user_name: 'alice',
        details: 'Created',
        created_at: new Date().toISOString(),
      };
      const { container } = render(<ActivityFeed items={[item]} />);
      const timestamps = container.querySelectorAll('span[class*="whitespace-nowrap"]');
      expect(timestamps.length).toBeGreaterThan(0);
    });
  });

  describe('maxItems prop', () => {
    it('limits display to default 5 items', () => {
      const items = Array.from({ length: 10 }, (_, i) => ({
        id: `activity-${i}`,
        action: 'created',
        entity_type: 'sbom' as const,
        entity_name: `App ${i}`,
        user_name: `user-${i}`,
        details: `Details ${i}`,
        created_at: new Date().toISOString(),
      }));
      render(<ActivityFeed items={items} />);
      expect(screen.getByText('App 0')).toBeInTheDocument();
      expect(screen.getByText('App 4')).toBeInTheDocument();
      expect(screen.queryByText('App 5')).not.toBeInTheDocument();
    });

    it('respects custom maxItems', () => {
      const items = Array.from({ length: 10 }, (_, i) => ({
        id: `activity-${i}`,
        action: 'created',
        entity_type: 'sbom' as const,
        entity_name: `App ${i}`,
        user_name: `user-${i}`,
        details: `Details ${i}`,
        created_at: new Date().toISOString(),
      }));
      render(<ActivityFeed items={items} maxItems={2} />);
      expect(screen.getByText('App 0')).toBeInTheDocument();
      expect(screen.getByText('App 1')).toBeInTheDocument();
      expect(screen.queryByText('App 2')).not.toBeInTheDocument();
    });

    it('displays all items if fewer than maxItems', () => {
      const items = Array.from({ length: 3 }, (_, i) => ({
        id: `activity-${i}`,
        action: 'created',
        entity_type: 'sbom' as const,
        entity_name: `App ${i}`,
        user_name: `user-${i}`,
        details: `Details ${i}`,
        created_at: new Date().toISOString(),
      }));
      render(<ActivityFeed items={items} maxItems={5} />);
      expect(screen.getByText('App 0')).toBeInTheDocument();
      expect(screen.getByText('App 1')).toBeInTheDocument();
      expect(screen.getByText('App 2')).toBeInTheDocument();
    });
  });

  describe('panel structure', () => {
    it('displays panel title', () => {
      render(<ActivityFeed items={[]} />);
      expect(screen.getByText('Recent Activity')).toBeInTheDocument();
    });

    it('has proper styling and layout', () => {
      const { container } = render(<ActivityFeed items={[]} />);
      const panel = container.querySelector('div[class*="bg-theme-surface"]');
      expect(panel).toHaveClass('rounded-lg');
      expect(panel).toHaveClass('p-4');
    });

    it('title has correct styling', () => {
      render(<ActivityFeed items={[]} />);
      const title = screen.getByText('Recent Activity');
      expect(title).toHaveClass('font-semibold');
      expect(title).toHaveClass('text-theme-primary');
      expect(title).toHaveClass('mb-3');
    });
  });

  describe('layout and spacing', () => {
    it('activity items have proper spacing', () => {
      const item = {
        id: 'activity-1',
        action: 'created',
        entity_type: 'sbom',
        entity_name: 'App',
        user_name: 'alice',
        details: 'Created',
        created_at: new Date().toISOString(),
      };
      const { container } = render(<ActivityFeed items={[item]} />);
      const itemsContainer = container.querySelector('div[class*="space-y-3"]');
      expect(itemsContainer).toBeInTheDocument();
    });

    it('each activity item has correct layout', () => {
      const item = {
        id: 'activity-1',
        action: 'created',
        entity_type: 'sbom',
        entity_name: 'App',
        user_name: 'alice',
        details: 'Created',
        created_at: new Date().toISOString(),
      };
      const { container } = render(<ActivityFeed items={[item]} />);
      const itemLayout = container.querySelector('div[class*="flex items-start gap-3"]');
      expect(itemLayout).toHaveClass('flex');
      expect(itemLayout).toHaveClass('items-start');
      expect(itemLayout).toHaveClass('gap-3');
    });
  });

  describe('text color and styling', () => {
    it('action and entity name display with proper colors', () => {
      const item = {
        id: 'activity-1',
        action: 'created',
        entity_type: 'sbom',
        entity_name: 'App',
        user_name: 'alice',
        details: 'Created',
        created_at: new Date().toISOString(),
      };
      const { container } = render(<ActivityFeed items={[item]} />);
      const primaryText = container.querySelector('p[class*="text-theme-primary"]');
      expect(primaryText).toBeInTheDocument();
    });

    it('user name displays with secondary color', () => {
      const item = {
        id: 'activity-1',
        action: 'created',
        entity_type: 'sbom',
        entity_name: 'App',
        user_name: 'alice',
        details: 'Created',
        created_at: new Date().toISOString(),
      };
      const { container } = render(<ActivityFeed items={[item]} />);
      const userText = container.querySelector('p[class*="text-theme-tertiary"]');
      expect(userText).toBeInTheDocument();
    });
  });

  describe('multiple activity items with mixed types', () => {
    it('renders diverse activity items with different entity types', () => {
      const items = [
        {
          id: 'activity-1',
          action: 'created',
          entity_type: 'sbom',
          entity_name: 'Production SBOM',
          user_name: 'alice',
          details: 'SBOM generated',
          created_at: new Date().toISOString(),
        },
        {
          id: 'activity-2',
          action: 'verified',
          entity_type: 'attestation',
          entity_name: 'Build Attestation',
          user_name: 'bob',
          details: 'Attestation verified',
          created_at: new Date(Date.now() - 60 * 60 * 1000).toISOString(),
        },
        {
          id: 'activity-3',
          action: 'scanned',
          entity_type: 'container_image',
          entity_name: 'app:latest',
          user_name: 'charlie',
          details: 'Image scanned for vulnerabilities',
          created_at: new Date(Date.now() - 2 * 60 * 60 * 1000).toISOString(),
        },
      ];
      render(<ActivityFeed items={items} />);
      expect(screen.getByText('Production SBOM')).toBeInTheDocument();
      expect(screen.getByText('Build Attestation')).toBeInTheDocument();
      expect(screen.getByText('app:latest')).toBeInTheDocument();
      expect(screen.getByTestId('file-code-icon')).toBeInTheDocument();
      expect(screen.getByTestId('shield-icon')).toBeInTheDocument();
      expect(screen.getByTestId('container-icon')).toBeInTheDocument();
    });
  });
});
