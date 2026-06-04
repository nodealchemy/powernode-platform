import { render, screen, fireEvent } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { NavigationItem } from './NavigationItem';
import { NavigationItem as NavItem } from '@/shared/types/navigation';
import { Home } from 'lucide-react';

// Mock the NavigationContext
const mockHasPermission = jest.fn();
jest.mock('@/shared/hooks/NavigationContext', () => ({
  useNavigation: () => ({
    hasPermission: mockHasPermission,
    state: { activePath: '/', expandedSections: [], isCollapsed: false, isMobileOpen: false },
    updateState: jest.fn(),
    config: { items: [], sections: [] },
    theme: 'default',
  }),
}));

// Probe component to surface the current router location in the DOM so we can
// assert that native <Link> navigation actually changed the path.
const LocationProbe = () => {
  const location = useLocation();
  return <div data-testid="location-probe">{location.pathname}</div>;
};

describe('NavigationItem', () => {
  const defaultItem: NavItem = {
    id: 'dashboard',
    name: 'Dashboard',
    href: '/app',
    icon: Home,
    permissions: ['dashboard.view'],
  };

  const renderNavigationItem = (
    item: NavItem = defaultItem,
    props: Partial<React.ComponentProps<typeof NavigationItem>> = {},
    initialPath = '/'
  ) => {
    return render(
      <MemoryRouter initialEntries={[initialPath]}>
        <NavigationItem item={item} {...props} />
      </MemoryRouter>
    );
  };

  beforeEach(() => {
    jest.clearAllMocks();
    mockHasPermission.mockReturnValue(true);
  });

  describe('rendering', () => {
    it('renders navigation link with name', () => {
      renderNavigationItem();

      expect(screen.getByText('Dashboard')).toBeInTheDocument();
    });

    it('renders link to correct href', () => {
      renderNavigationItem();

      const link = screen.getByRole('link');
      expect(link).toHaveAttribute('href', '/app');
    });

    it('renders icon component', () => {
      const { container } = renderNavigationItem();

      const icon = container.querySelector('svg');
      expect(icon).toBeInTheDocument();
    });

    it('resolves a string icon to a Lucide icon component', () => {
      // String icons are interpreted as Lucide icon names and rendered as SVGs,
      // not printed as literal text.
      const itemWithLucideName: NavItem = {
        ...defaultItem,
        icon: 'Home',
      };

      const { container } = renderNavigationItem(itemWithLucideName);

      const icon = container.querySelector('svg');
      expect(icon).toBeInTheDocument();
    });

    it('falls back to the Puzzle icon for an unknown string icon', () => {
      // A non-Lucide string (e.g. an emoji) is not a valid icon name, so the
      // component renders the Puzzle fallback SVG rather than the raw string.
      const itemWithUnknownIcon: NavItem = {
        ...defaultItem,
        icon: '🏠',
      };

      const { container } = renderNavigationItem(itemWithUnknownIcon);

      const icon = container.querySelector('svg.lucide-puzzle');
      expect(icon).toBeInTheDocument();
      expect(screen.queryByText('🏠')).not.toBeInTheDocument();
    });
  });

  describe('permission checking', () => {
    it('does not render when user lacks permission', () => {
      mockHasPermission.mockReturnValue(false);

      const { container } = renderNavigationItem();

      expect(container.firstChild).toBeNull();
    });

    it('renders when user has permission', () => {
      mockHasPermission.mockReturnValue(true);

      renderNavigationItem();

      expect(screen.getByText('Dashboard')).toBeInTheDocument();
    });

    it('checks correct permissions', () => {
      renderNavigationItem();

      expect(mockHasPermission).toHaveBeenCalledWith(['dashboard.view']);
    });
  });

  describe('active state', () => {
    it('applies active styling when path matches exactly', () => {
      renderNavigationItem(defaultItem, {}, '/app');

      const link = screen.getByRole('link');
      expect(link).toHaveClass('bg-theme-surface-selected');
    });

    it('does not apply active styling when path does not match', () => {
      renderNavigationItem(defaultItem, {}, '/other');

      const link = screen.getByRole('link');
      expect(link).not.toHaveClass('bg-theme-surface-selected');
    });
  });

  describe('collapsed state', () => {
    it('hides name when collapsed', () => {
      renderNavigationItem(defaultItem, { isCollapsed: true });

      // Name should not be visible (only shown in title attribute)
      expect(screen.queryByText('Dashboard')).not.toBeInTheDocument();
    });

    it('shows tooltip on hover when collapsed', () => {
      renderNavigationItem(defaultItem, { isCollapsed: true, showTooltip: true });

      // Hover to show tooltip
      const wrapper = screen.getByRole('link').closest('.relative');
      fireEvent.mouseEnter(wrapper!);

      // Tooltip should appear - check for element with tooltip styling
      const tooltip = document.querySelector('.bg-theme-surface-pressed');
      expect(tooltip).toBeInTheDocument();
    });

    it('sets title attribute when collapsed', () => {
      renderNavigationItem(defaultItem, { isCollapsed: true });

      const link = screen.getByRole('link');
      expect(link).toHaveAttribute('title', 'Dashboard');
    });
  });

  describe('external links', () => {
    const externalItem: NavItem = {
      ...defaultItem,
      id: 'external',
      name: 'External Link',
      href: 'https://example.com',
      isExternal: true,
    };

    it('renders as anchor for external links', () => {
      renderNavigationItem(externalItem);

      const link = screen.getByRole('link');
      expect(link).toHaveAttribute('href', 'https://example.com');
    });

    it('sets target="_blank" for external links', () => {
      renderNavigationItem(externalItem);

      const link = screen.getByRole('link');
      expect(link).toHaveAttribute('target', '_blank');
    });

    it('sets rel="noopener noreferrer" for external links', () => {
      renderNavigationItem(externalItem);

      const link = screen.getByRole('link');
      expect(link).toHaveAttribute('rel', 'noopener noreferrer');
    });

    it('shows external link icon', () => {
      const { container } = renderNavigationItem(externalItem);

      // ExternalLink icon should be present
      const icons = container.querySelectorAll('svg');
      expect(icons.length).toBeGreaterThan(1);
    });
  });

  describe('badge', () => {
    const itemWithBadge: NavItem = {
      ...defaultItem,
      badge: '5',
    };

    it('renders badge when provided', () => {
      renderNavigationItem(itemWithBadge);

      expect(screen.getByText('5')).toBeInTheDocument();
    });

    it('badge has proper styling', () => {
      renderNavigationItem(itemWithBadge);

      const badge = screen.getByText('5');
      expect(badge).toHaveClass('bg-theme-error', 'text-white', 'rounded-full');
    });

    it('does not render badge when collapsed', () => {
      renderNavigationItem(itemWithBadge, { isCollapsed: true });

      // Badge should be hidden in collapsed state
      const badges = screen.queryAllByText('5');
      // The badge is rendered but may be hidden via CSS
      expect(badges.length).toBe(0);
    });
  });

  describe('click handling', () => {
    it('navigates to the item href on click', () => {
      // Render with a location probe so we can assert that native <Link>
      // navigation actually changed the router path.
      render(
        <MemoryRouter initialEntries={['/']}>
          <NavigationItem item={defaultItem} />
          <LocationProbe />
        </MemoryRouter>
      );

      // Starts at the initial route, not the item's destination.
      expect(screen.getByTestId('location-probe')).toHaveTextContent('/');

      const link = screen.getByRole('link');
      fireEvent.click(link);

      // Native <Link> navigation updates the router location to the href.
      expect(screen.getByTestId('location-probe')).toHaveTextContent('/app');
    });
  });

  describe('styling', () => {
    it('applies base styling classes', () => {
      renderNavigationItem();

      const link = screen.getByRole('link');
      expect(link).toHaveClass('flex', 'items-center', 'text-sm', 'font-medium', 'rounded-md');
    });

    it('has border-l-4 for indicator', () => {
      renderNavigationItem();

      const link = screen.getByRole('link');
      expect(link).toHaveClass('border-l-4');
    });

    it('applies level indentation', () => {
      renderNavigationItem(defaultItem, { level: 1 });

      const link = screen.getByRole('link');
      expect(link).toHaveClass('ml-4');
    });

    it('centers icon in collapsed mode', () => {
      renderNavigationItem(defaultItem, { isCollapsed: true });

      const link = screen.getByRole('link');
      expect(link).toHaveClass('justify-center');
    });
  });
});
