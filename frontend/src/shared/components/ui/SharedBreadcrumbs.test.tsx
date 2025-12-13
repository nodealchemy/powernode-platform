import type { ReactElement } from 'react';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { SharedBreadcrumbs } from './SharedBreadcrumbs';
import { Home } from 'lucide-react';

describe('SharedBreadcrumbs', () => {
  const renderWithRouter = (
    component: ReactElement,
    initialPath: string = '/app/settings'
  ) => {
    return render(
      <MemoryRouter initialEntries={[initialPath]}>
        {component}
      </MemoryRouter>
    );
  };

  describe('rendering with custom items', () => {
    const customItems = [
      { label: 'Home', href: '/app', icon: Home },
      { label: 'Settings', href: '/app/settings' },
      { label: 'Security' }
    ];

    it('renders all breadcrumb items', () => {
      renderWithRouter(<SharedBreadcrumbs items={customItems} />);

      expect(screen.getByText('Home')).toBeInTheDocument();
      expect(screen.getByText('Settings')).toBeInTheDocument();
      expect(screen.getByText('Security')).toBeInTheDocument();
    });

    it('renders links for items with href', () => {
      renderWithRouter(<SharedBreadcrumbs items={customItems} />);

      expect(screen.getByRole('link', { name: /Home/i })).toHaveAttribute('href', '/app');
      expect(screen.getByRole('link', { name: /Settings/i })).toHaveAttribute('href', '/app/settings');
    });

    it('renders last item as non-link', () => {
      renderWithRouter(<SharedBreadcrumbs items={customItems} />);

      const security = screen.getByText('Security');
      expect(security.closest('a')).toBeNull();
    });

    it('renders separators between items', () => {
      renderWithRouter(<SharedBreadcrumbs items={customItems} />);

      // ChevronRight separators
      const items = screen.getAllByRole('listitem');
      expect(items.length).toBe(3);
    });
  });

  describe('auto-generated breadcrumbs', () => {
    it('generates breadcrumbs from path', () => {
      renderWithRouter(<SharedBreadcrumbs />, '/app/settings/security');

      expect(screen.getByText('Dashboard')).toBeInTheDocument();
      expect(screen.getByText('Settings')).toBeInTheDocument();
      expect(screen.getByText('Security')).toBeInTheDocument();
    });

    it('shows home/dashboard when showHome is true', () => {
      renderWithRouter(<SharedBreadcrumbs showHome={true} />, '/app/settings');

      expect(screen.getByText('Dashboard')).toBeInTheDocument();
    });

    it('hides home/dashboard when showHome is false', () => {
      renderWithRouter(<SharedBreadcrumbs showHome={false} />, '/app/settings');

      expect(screen.queryByText('Dashboard')).not.toBeInTheDocument();
    });

    it('formats segment names nicely', () => {
      renderWithRouter(<SharedBreadcrumbs />, '/app/admin-settings');

      expect(screen.getByText(/Admin/i)).toBeInTheDocument();
    });
  });

  describe('accessibility', () => {
    it('has navigation aria-label', () => {
      renderWithRouter(<SharedBreadcrumbs items={[{ label: 'Test' }]} />);

      expect(screen.getByRole('navigation', { name: 'Breadcrumb' })).toBeInTheDocument();
    });

    it('uses ordered list for items', () => {
      renderWithRouter(<SharedBreadcrumbs items={[{ label: 'Test' }]} />);

      expect(screen.getByRole('list')).toBeInTheDocument();
    });
  });

  describe('styling', () => {
    it('applies custom className', () => {
      renderWithRouter(
        <SharedBreadcrumbs items={[{ label: 'Test' }]} className="custom-breadcrumb" />
      );

      const nav = screen.getByRole('navigation');
      expect(nav).toHaveClass('custom-breadcrumb');
    });

    it('applies font-medium to last item', () => {
      const items = [
        { label: 'Home', href: '/app' },
        { label: 'Current' }
      ];
      renderWithRouter(<SharedBreadcrumbs items={items} />);

      const current = screen.getByText('Current');
      expect(current.closest('span')).toHaveClass('font-medium');
    });
  });

  describe('empty state', () => {
    it('returns null when no items and empty path', () => {
      const { container } = renderWithRouter(
        <SharedBreadcrumbs items={[]} showHome={false} />,
        '/'
      );

      expect(container.querySelector('nav')).toBeNull();
    });
  });

  describe('special label mappings', () => {
    it('uses mapped labels for known paths', () => {
      renderWithRouter(<SharedBreadcrumbs />, '/app/payment-gateways');

      expect(screen.getByText('Payment Gateways')).toBeInTheDocument();
    });

    it('uses mapped labels for webhooks', () => {
      renderWithRouter(<SharedBreadcrumbs />, '/app/webhooks');

      expect(screen.getByText('Webhooks')).toBeInTheDocument();
    });
  });
});
