import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { Breadcrumb, BreadcrumbItem } from './Breadcrumb';

describe('Breadcrumb', () => {
  const renderBreadcrumb = (items: BreadcrumbItem[], className?: string) => {
    return render(
      <MemoryRouter future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
        <Breadcrumb items={items} className={className} />
      </MemoryRouter>
    );
  };

  describe('rendering', () => {
    it('renders breadcrumb items', () => {
      const items: BreadcrumbItem[] = [
        { label: 'Home', path: '/' },
        { label: 'Products', path: '/products' },
        { label: 'Details' },
      ];

      renderBreadcrumb(items);

      expect(screen.getByText('Home')).toBeInTheDocument();
      expect(screen.getByText('Products')).toBeInTheDocument();
      expect(screen.getByText('Details')).toBeInTheDocument();
    });

    it('renders items with icons', () => {
      const items: BreadcrumbItem[] = [
        { label: 'Home', path: '/', icon: '🏠' },
        { label: 'Settings', icon: '⚙️' },
      ];

      renderBreadcrumb(items);

      expect(screen.getByText('🏠')).toBeInTheDocument();
      expect(screen.getByText('⚙️')).toBeInTheDocument();
    });

    it('applies custom className', () => {
      const items: BreadcrumbItem[] = [{ label: 'Home' }];

      const { container } = renderBreadcrumb(items, 'custom-class');

      expect(container.querySelector('nav')).toHaveClass('custom-class');
    });
  });

  describe('navigation', () => {
    it('renders links for items with paths', () => {
      const items: BreadcrumbItem[] = [
        { label: 'Home', path: '/' },
        { label: 'Products', path: '/products' },
        { label: 'Current' },
      ];

      renderBreadcrumb(items);

      const homeLink = screen.getByText('Home').closest('a');
      expect(homeLink).toHaveAttribute('href', '/');

      const productsLink = screen.getByText('Products').closest('a');
      expect(productsLink).toHaveAttribute('href', '/products');
    });

    it('renders current item as text, not link', () => {
      const items: BreadcrumbItem[] = [
        { label: 'Home', path: '/' },
        { label: 'Current Page', path: '/current' },
      ];

      renderBreadcrumb(items);

      // Last item should be text even if it has a path
      const currentItem = screen.getByText('Current Page');
      expect(currentItem.closest('a')).toBeNull();
      expect(currentItem.closest('span')).toBeInTheDocument();
    });

    it('renders item without path as text', () => {
      const items: BreadcrumbItem[] = [
        { label: 'Home', path: '/' },
        { label: 'No Link Item' },
      ];

      renderBreadcrumb(items);

      const noLinkItem = screen.getByText('No Link Item');
      expect(noLinkItem.closest('a')).toBeNull();
    });
  });

  describe('separators', () => {
    it('renders separators between items', () => {
      const items: BreadcrumbItem[] = [
        { label: 'Home', path: '/' },
        { label: 'Products', path: '/products' },
        { label: 'Details' },
      ];

      const { container } = renderBreadcrumb(items);

      // Should have 2 separators (between 3 items)
      const separators = container.querySelectorAll('svg[aria-hidden="true"]');
      expect(separators.length).toBe(2);
    });

    it('does not render separator before first item', () => {
      const items: BreadcrumbItem[] = [
        { label: 'Home', path: '/' },
        { label: 'Products' },
      ];

      const { container } = renderBreadcrumb(items);

      const firstListItem = container.querySelector('li');
      const separatorInFirstItem = firstListItem?.querySelector('svg[aria-hidden="true"]');
      expect(separatorInFirstItem).toBeNull();
    });
  });

  describe('accessibility', () => {
    it('has nav with aria-label', () => {
      const items: BreadcrumbItem[] = [{ label: 'Home' }];

      const { container } = renderBreadcrumb(items);

      const nav = container.querySelector('nav');
      expect(nav).toHaveAttribute('aria-label', 'Breadcrumb');
    });

    it('has ordered list', () => {
      const items: BreadcrumbItem[] = [
        { label: 'Home', path: '/' },
        { label: 'Products' },
      ];

      const { container } = renderBreadcrumb(items);

      expect(container.querySelector('ol')).toBeInTheDocument();
    });

    it('marks separators as aria-hidden', () => {
      const items: BreadcrumbItem[] = [
        { label: 'Home', path: '/' },
        { label: 'Products' },
      ];

      const { container } = renderBreadcrumb(items);

      const separator = container.querySelector('svg');
      expect(separator).toHaveAttribute('aria-hidden', 'true');
    });
  });

  describe('styling', () => {
    it('has flex layout', () => {
      const items: BreadcrumbItem[] = [{ label: 'Home' }];

      const { container } = renderBreadcrumb(items);

      expect(container.querySelector('nav')).toHaveClass('flex');
    });

    it('list has proper styling', () => {
      const items: BreadcrumbItem[] = [{ label: 'Home' }];

      const { container } = renderBreadcrumb(items);

      const list = container.querySelector('ol');
      expect(list).toHaveClass('flex', 'items-center', 'space-x-2');
    });

    it('links have hover styling classes', () => {
      const items: BreadcrumbItem[] = [
        { label: 'Home', path: '/' },
        { label: 'Current' },
      ];

      renderBreadcrumb(items);

      const link = screen.getByText('Home').closest('a');
      expect(link).toHaveClass('text-theme-secondary', 'hover:text-theme-primary');
    });

    it('current item has primary text color', () => {
      const items: BreadcrumbItem[] = [
        { label: 'Home', path: '/' },
        { label: 'Current Page' },
      ];

      renderBreadcrumb(items);

      // The text is in an inner span, but the styling is on the parent span
      const current = screen.getByText('Current Page').parentElement;
      expect(current).toHaveClass('text-theme-primary');
    });
  });

  describe('single item', () => {
    it('renders single item without separator', () => {
      const items: BreadcrumbItem[] = [{ label: 'Home' }];

      const { container } = renderBreadcrumb(items);

      expect(screen.getByText('Home')).toBeInTheDocument();
      expect(container.querySelector('svg')).toBeNull();
    });
  });
});
