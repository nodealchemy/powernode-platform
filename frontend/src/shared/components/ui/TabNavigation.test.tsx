import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { TabNavigation, MobileTabNavigation } from './TabNavigation';

describe('TabNavigation', () => {
  const mockTabs = [
    { id: 'overview', label: 'Overview', path: '/app/settings' },
    { id: 'security', label: 'Security', path: '/app/settings/security' },
    { id: 'billing', label: 'Billing', path: '/app/settings/billing', badge: 3 },
    { id: 'disabled', label: 'Disabled', path: '/app/settings/disabled', disabled: true }
  ] as const;

  const renderWithRouter = (
    component: React.ReactElement,
    initialPath: string = '/app/settings'
  ) => {
    return render(
      <MemoryRouter initialEntries={[initialPath]} future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
        {component}
      </MemoryRouter>
    );
  };

  describe('rendering', () => {
    it('renders all tab labels', () => {
      renderWithRouter(<TabNavigation tabs={mockTabs} />);

      expect(screen.getByText('Overview')).toBeInTheDocument();
      expect(screen.getByText('Security')).toBeInTheDocument();
      expect(screen.getByText('Billing')).toBeInTheDocument();
      expect(screen.getByText('Disabled')).toBeInTheDocument();
    });

    it('renders badges when provided', () => {
      renderWithRouter(<TabNavigation tabs={mockTabs} />);

      expect(screen.getByText('3')).toBeInTheDocument();
    });

    it('renders tabs as links', () => {
      renderWithRouter(<TabNavigation tabs={mockTabs} />);

      const links = screen.getAllByRole('link');
      expect(links.length).toBe(3); // 3 enabled tabs
    });

    it('renders disabled tabs as spans', () => {
      renderWithRouter(<TabNavigation tabs={mockTabs} />);

      // Disabled tab should not be a link
      const disabledTab = screen.getByText('Disabled');
      expect(disabledTab.closest('a')).toBeNull();
      expect(disabledTab.closest('span')).not.toBeNull();
    });

    it('applies custom className', () => {
      renderWithRouter(<TabNavigation tabs={mockTabs} className="custom-class" />);

      const nav = screen.getByRole('navigation');
      expect(nav.parentElement).toHaveClass('custom-class');
    });
  });

  describe('active tab detection', () => {
    it('marks exact path match as active', () => {
      renderWithRouter(<TabNavigation tabs={mockTabs} />, '/app/settings');

      const overviewLink = screen.getByText('Overview').closest('a');
      expect(overviewLink).toHaveAttribute('aria-current', 'page');
    });

    it('marks nested path as active for parent tab', () => {
      renderWithRouter(<TabNavigation tabs={mockTabs} />, '/app/settings/security/2fa');

      const securityLink = screen.getByText('Security').closest('a');
      expect(securityLink).toHaveAttribute('aria-current', 'page');
    });

    it('selects most specific matching tab', () => {
      renderWithRouter(<TabNavigation tabs={mockTabs} />, '/app/settings/billing');

      const billingLink = screen.getByText('Billing').closest('a');
      expect(billingLink).toHaveAttribute('aria-current', 'page');
    });
  });

  describe('styling', () => {
    it('applies active styling to current tab', () => {
      renderWithRouter(<TabNavigation tabs={mockTabs} />, '/app/settings');

      const overviewLink = screen.getByText('Overview').closest('a');
      expect(overviewLink).toHaveClass('border-theme-interactive-primary');
    });

    it('applies disabled styling to disabled tabs', () => {
      renderWithRouter(<TabNavigation tabs={mockTabs} />);

      // The disabled text is in an inner span, but the styling is on the outer span
      const disabledText = screen.getByText('Disabled');
      const outerSpan = disabledText.parentElement;
      expect(outerSpan).toHaveClass('opacity-50', 'cursor-not-allowed');
    });
  });

  describe('accessibility', () => {
    it('has navigation aria-label', () => {
      renderWithRouter(<TabNavigation tabs={mockTabs} />);

      expect(screen.getByRole('navigation', { name: 'Tabs' })).toBeInTheDocument();
    });

    it('marks active tab with aria-current', () => {
      renderWithRouter(<TabNavigation tabs={mockTabs} />, '/app/settings/billing');

      const billingLink = screen.getByText('Billing').closest('a');
      expect(billingLink).toHaveAttribute('aria-current', 'page');
    });
  });
});

describe('MobileTabNavigation', () => {
  const mockTabs = [
    { id: 'overview', label: 'Overview', path: '/app/settings' },
    { id: 'security', label: 'Security', path: '/app/settings/security' },
    { id: 'billing', label: 'Billing', path: '/app/settings/billing', badge: 3 }
  ] as const;

  const renderWithRouter = (
    component: React.ReactElement,
    initialPath: string = '/app/settings'
  ) => {
    return render(
      <MemoryRouter initialEntries={[initialPath]} future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
        {component}
      </MemoryRouter>
    );
  };

  describe('rendering', () => {
    it('renders select element', () => {
      renderWithRouter(<MobileTabNavigation tabs={mockTabs} />);

      expect(screen.getByRole('combobox')).toBeInTheDocument();
    });

    it('renders all options', () => {
      renderWithRouter(<MobileTabNavigation tabs={mockTabs} />);

      const select = screen.getByRole('combobox');
      const options = select.querySelectorAll('option');
      expect(options.length).toBe(3);
    });

    it('includes badges in option labels', () => {
      renderWithRouter(<MobileTabNavigation tabs={mockTabs} />);

      expect(screen.getByText('Billing (3)')).toBeInTheDocument();
    });

    it('shows current tab as selected', () => {
      renderWithRouter(<MobileTabNavigation tabs={mockTabs} />, '/app/settings/security');

      const select = screen.getByRole('combobox') as HTMLSelectElement;
      expect(select.value).toBe('/app/settings/security');
    });

    it('applies custom className', () => {
      renderWithRouter(<MobileTabNavigation tabs={mockTabs} className="custom-mobile" />);

      const container = screen.getByRole('combobox').closest('div');
      expect(container).toHaveClass('custom-mobile');
    });
  });

  describe('accessibility', () => {
    it('has screen reader label', () => {
      renderWithRouter(<MobileTabNavigation tabs={mockTabs} />);

      expect(screen.getByLabelText('Select a tab')).toBeInTheDocument();
    });
  });
});
