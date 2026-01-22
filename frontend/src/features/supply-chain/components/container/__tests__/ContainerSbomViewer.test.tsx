import { render, screen, fireEvent } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { ContainerSbomViewer } from '../ContainerSbomViewer';

// Mock Card component
jest.mock('@/shared/components/ui/Card', () => ({
  Card: ({ children, className }: any) => <div data-testid="card" className={className}>{children}</div>,
}));

// Mock Badge component
jest.mock('@/shared/components/ui/Badge', () => ({
  Badge: ({ children, variant, size }: any) => (
    <span data-testid={`badge-${variant}`} data-size={size}>
      {children}
    </span>
  ),
}));

// Mock LoadingSpinner component
jest.mock('@/shared/components/ui/LoadingSpinner', () => ({
  LoadingSpinner: ({ size }: any) => <div data-testid="loading-spinner" data-size={size}>Loading...</div>,
}));

// Mock icons
jest.mock('lucide-react', () => ({
  Package: () => <span data-testid="package-icon">📦</span>,
  Search: () => <span data-testid="search-icon">🔍</span>,
  FileText: () => <span data-testid="file-text-icon">📄</span>,
}));

describe('ContainerSbomViewer', () => {
  const mockSbom = {
    id: 'sbom-123',
    format: 'cyclonedx',
    component_count: 5,
    components: [
      {
        name: 'lodash',
        version: '4.17.21',
        type: 'npm',
        licenses: ['MIT'],
      },
      {
        name: 'express',
        version: '4.18.2',
        type: 'npm',
        licenses: ['MIT'],
      },
      {
        name: 'openssl',
        version: '3.0.0',
        type: 'system',
        licenses: ['Apache-2.0', 'OpenSSL'],
      },
      {
        name: 'curl',
        version: '7.85.0',
        type: 'system',
        licenses: ['MIT'],
      },
      {
        name: 'postgres-client',
        version: '14.5',
        type: 'system',
        licenses: ['PostgreSQL'],
      },
    ],
    generated_at: new Date().toISOString(),
  };

  describe('Loading State', () => {
    it('shows loading spinner when loading is true', () => {
      render(
        <ContainerSbomViewer sbom={null} loading={true} />
      );

      expect(screen.getByTestId('loading-spinner')).toBeInTheDocument();
      expect(screen.getByTestId('loading-spinner')).toHaveAttribute('data-size', 'lg');
    });

    it('hides content when loading', () => {
      render(
        <ContainerSbomViewer sbom={mockSbom} loading={true} />
      );

      expect(screen.queryByText('CYCLONEDX')).not.toBeInTheDocument();
    });

    it('shows card wrapper during loading', () => {
      render(
        <ContainerSbomViewer sbom={null} loading={true} />
      );

      expect(screen.getByTestId('card')).toBeInTheDocument();
    });
  });

  describe('Error State', () => {
    it('displays error message when error is provided', () => {
      const errorMessage = 'Failed to load SBOM data';
      render(
        <ContainerSbomViewer sbom={null} loading={false} error={errorMessage} />
      );

      expect(screen.getByText(errorMessage)).toBeInTheDocument();
    });

    it('shows error in red color', () => {
      render(
        <ContainerSbomViewer sbom={null} loading={false} error="Test error" />
      );

      const errorElement = screen.getByText('Test error');
      expect(errorElement).toHaveClass('text-theme-error');
    });

    it('hides SBOM content when error occurs', () => {
      render(
        <ContainerSbomViewer sbom={mockSbom} loading={false} error="Error loading SBOM" />
      );

      expect(screen.queryByText('CYCLONEDX')).not.toBeInTheDocument();
    });
  });

  describe('Empty State', () => {
    it('shows empty state when sbom is null', () => {
      render(
        <ContainerSbomViewer sbom={null} loading={false} />
      );

      expect(screen.getByText('No SBOM data available')).toBeInTheDocument();
      expect(screen.getByTestId('file-text-icon')).toBeInTheDocument();
    });

    it('shows muted text color for empty state', () => {
      render(
        <ContainerSbomViewer sbom={null} loading={false} />
      );

      const emptyText = screen.getByText('No SBOM data available');
      expect(emptyText.parentElement).toHaveClass('text-theme-muted');
    });
  });

  describe('SBOM Format and Component Count Display', () => {
    it('renders SBOM format badge', () => {
      render(
        <ContainerSbomViewer sbom={mockSbom} loading={false} />
      );

      const formatBadge = screen.getByText('CYCLONEDX');
      expect(formatBadge).toBeInTheDocument();
      expect(formatBadge).toHaveAttribute('data-testid', 'badge-info');
      expect(formatBadge).toHaveAttribute('data-size', 'lg');
    });

    it('displays component count correctly', () => {
      render(
        <ContainerSbomViewer sbom={mockSbom} loading={false} />
      );

      expect(screen.getByText('5')).toBeInTheDocument();
      expect(screen.getByText('components')).toBeInTheDocument();
    });

    it('renders SBOM generation date', () => {
      const sbomDate = new Date('2024-01-15T10:30:00Z');
      render(
        <ContainerSbomViewer sbom={{ ...mockSbom, generated_at: sbomDate.toISOString() }} loading={false} />
      );

      const dateText = sbomDate.toLocaleDateString('en-US', {
        year: 'numeric',
        month: 'short',
        day: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
      });

      expect(screen.getByText(new RegExp(dateText))).toBeInTheDocument();
    });
  });

  describe('Component List Display', () => {
    it('renders all components', () => {
      render(
        <ContainerSbomViewer sbom={mockSbom} loading={false} />
      );

      mockSbom.components.forEach((component) => {
        expect(screen.getByText(component.name)).toBeInTheDocument();
        expect(screen.getByText(component.version)).toBeInTheDocument();
      });
    });

    it('displays package icon for each component', () => {
      render(
        <ContainerSbomViewer sbom={mockSbom} loading={false} />
      );

      const packageIcons = screen.getAllByTestId('package-icon');
      expect(packageIcons).toHaveLength(mockSbom.components.length);
    });

    it('renders component type badge', () => {
      render(
        <ContainerSbomViewer sbom={mockSbom} loading={false} />
      );

      // npm appears as both filter option and badge - check for multiple
      expect(screen.getAllByText('npm').length).toBeGreaterThan(1);
      expect(screen.getAllByText('system').length).toBeGreaterThan(2);
    });

    it('shows component licenses', () => {
      render(
        <ContainerSbomViewer sbom={mockSbom} loading={false} />
      );

      expect(screen.getAllByText('MIT').length).toBeGreaterThan(0);
      expect(screen.getByText('Apache-2.0')).toBeInTheDocument();
      expect(screen.getByText('OpenSSL')).toBeInTheDocument();
      expect(screen.getByText('PostgreSQL')).toBeInTheDocument();
    });

    it('renders license badges with secondary variant', () => {
      render(
        <ContainerSbomViewer sbom={mockSbom} loading={false} />
      );

      const licenseBadges = screen.getAllByTestId('badge-secondary');
      expect(licenseBadges.length).toBeGreaterThan(0);
    });

    it('displays multiple licenses per component', () => {
      render(
        <ContainerSbomViewer sbom={mockSbom} loading={false} />
      );

      // openssl component has 2 licenses
      const openSSLComponent = screen.getByText('openssl').closest('.p-4');
      expect(openSSLComponent?.textContent).toContain('Apache-2.0');
      expect(openSSLComponent?.textContent).toContain('OpenSSL');
    });

    it('handles components without licenses gracefully', () => {
      const sbomWithoutLicenses = {
        ...mockSbom,
        components: [
          {
            name: 'test-package',
            version: '1.0.0',
            type: 'npm',
            licenses: [],
          },
        ],
      };

      render(
        <ContainerSbomViewer sbom={sbomWithoutLicenses} loading={false} />
      );

      expect(screen.getByText('test-package')).toBeInTheDocument();
    });
  });

  describe('Search Functionality', () => {
    it('renders search input', () => {
      render(
        <ContainerSbomViewer sbom={mockSbom} loading={false} />
      );

      const searchInput = screen.getByPlaceholderText('Search components...');
      expect(searchInput).toBeInTheDocument();
    });

    it('shows search icon', () => {
      render(
        <ContainerSbomViewer sbom={mockSbom} loading={false} />
      );

      expect(screen.getByTestId('search-icon')).toBeInTheDocument();
    });

    it('filters components by name', async () => {
      const user = userEvent.setup();
      render(
        <ContainerSbomViewer sbom={mockSbom} loading={false} />
      );

      const searchInput = screen.getByPlaceholderText('Search components...') as HTMLInputElement;
      await user.type(searchInput, 'lodash');

      // Should show only lodash component
      expect(screen.getByText('lodash')).toBeInTheDocument();
      expect(screen.queryByText('express')).not.toBeInTheDocument();
    });

    it('filters components by version', async () => {
      const user = userEvent.setup();
      render(
        <ContainerSbomViewer sbom={mockSbom} loading={false} />
      );

      const searchInput = screen.getByPlaceholderText('Search components...') as HTMLInputElement;
      await user.type(searchInput, '4.17.21');

      // Should show only lodash with this version
      expect(screen.getByText('lodash')).toBeInTheDocument();
      expect(screen.getByText('4.17.21')).toBeInTheDocument();
    });

    it('shows no results message when search has no matches', async () => {
      const user = userEvent.setup();
      render(
        <ContainerSbomViewer sbom={mockSbom} loading={false} />
      );

      const searchInput = screen.getByPlaceholderText('Search components...') as HTMLInputElement;
      await user.type(searchInput, 'nonexistent-package');

      expect(screen.getByText("No components match your filters")).toBeInTheDocument();
    });

    it('search is case-insensitive', async () => {
      const user = userEvent.setup();
      render(
        <ContainerSbomViewer sbom={mockSbom} loading={false} />
      );

      const searchInput = screen.getByPlaceholderText('Search components...') as HTMLInputElement;
      await user.type(searchInput, 'LODASH');

      expect(screen.getByText('lodash')).toBeInTheDocument();
    });

    it('clears search results when input is cleared', async () => {
      const user = userEvent.setup();
      render(
        <ContainerSbomViewer sbom={mockSbom} loading={false} />
      );

      const searchInput = screen.getByPlaceholderText('Search components...') as HTMLInputElement;
      await user.type(searchInput, 'lodash');
      expect(screen.queryByText('express')).not.toBeInTheDocument();

      await user.clear(searchInput);
      expect(screen.getByText('express')).toBeInTheDocument();
    });
  });

  describe('Type Filter Functionality', () => {
    it('renders type filter dropdown', () => {
      render(
        <ContainerSbomViewer sbom={mockSbom} loading={false} />
      );

      const filterSelect = screen.getByDisplayValue('All Types');
      expect(filterSelect).toBeInTheDocument();
    });

    it('displays all unique component types as options', () => {
      render(
        <ContainerSbomViewer sbom={mockSbom} loading={false} />
      );

      expect(screen.getByDisplayValue('All Types')).toBeInTheDocument();
      expect(screen.getByRole('option', { name: 'npm' })).toBeInTheDocument();
      expect(screen.getByRole('option', { name: 'system' })).toBeInTheDocument();
    });

    it('filters components by type', async () => {
      const user = userEvent.setup();
      render(
        <ContainerSbomViewer sbom={mockSbom} loading={false} />
      );

      const filterSelect = screen.getByDisplayValue('All Types');
      await user.selectOptions(filterSelect, 'npm');

      // Should show only npm components
      expect(screen.getByText('lodash')).toBeInTheDocument();
      expect(screen.getByText('express')).toBeInTheDocument();
      expect(screen.queryByText('openssl')).not.toBeInTheDocument();
    });

    it('shows all components when All Types is selected', async () => {
      const user = userEvent.setup();
      render(
        <ContainerSbomViewer sbom={mockSbom} loading={false} />
      );

      const filterSelect = screen.getByDisplayValue('All Types');
      await user.selectOptions(filterSelect, 'npm');
      await user.selectOptions(filterSelect, '');

      mockSbom.components.forEach((component) => {
        expect(screen.getByText(component.name)).toBeInTheDocument();
      });
    });
  });

  describe('Combined Search and Filter', () => {
    it('combines search and type filter', async () => {
      const user = userEvent.setup();
      render(
        <ContainerSbomViewer sbom={mockSbom} loading={false} />
      );

      // Filter by system type
      const filterSelect = screen.getByDisplayValue('All Types');
      await user.selectOptions(filterSelect, 'system');

      // Search for openssl
      const searchInput = screen.getByPlaceholderText('Search components...') as HTMLInputElement;
      await user.type(searchInput, 'openssl');

      // Should show only openssl
      expect(screen.getByText('openssl')).toBeInTheDocument();
      expect(screen.queryByText('curl')).not.toBeInTheDocument();
      expect(screen.queryByText('lodash')).not.toBeInTheDocument();
    });

    it('shows no results when filters have no matches', async () => {
      const user = userEvent.setup();
      render(
        <ContainerSbomViewer sbom={mockSbom} loading={false} />
      );

      const filterSelect = screen.getByDisplayValue('All Types');
      await user.selectOptions(filterSelect, 'npm');

      const searchInput = screen.getByPlaceholderText('Search components...') as HTMLInputElement;
      await user.type(searchInput, 'openssl');

      expect(screen.getByText("No components match your filters")).toBeInTheDocument();
    });
  });

  describe('Component Hover States', () => {
    it('components have hover effect styling', () => {
      render(
        <ContainerSbomViewer sbom={mockSbom} loading={false} />
      );

      const componentRow = screen.getByText('lodash').closest('.hover\\:bg-theme-surface-hover');
      expect(componentRow).toHaveClass('hover:bg-theme-surface-hover', 'transition-colors');
    });
  });

  describe('Scrollable Component List', () => {
    it('renders scrollable container', () => {
      render(
        <ContainerSbomViewer sbom={mockSbom} loading={false} />
      );

      const scrollContainer = screen.getByText('lodash').closest('.max-h-96');
      expect(scrollContainer).toHaveClass('max-h-96', 'overflow-y-auto');
    });
  });

  describe('Empty SBOM Components', () => {
    it('handles SBOM with no components', () => {
      const emptyComponentsSbom = {
        ...mockSbom,
        component_count: 0,
        components: [],
      };

      render(
        <ContainerSbomViewer sbom={emptyComponentsSbom} loading={false} />
      );

      expect(screen.getByText('0')).toBeInTheDocument();
      expect(screen.getByText("No components match your filters")).toBeInTheDocument();
    });
  });
});
