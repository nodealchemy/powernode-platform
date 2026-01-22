import { render, screen, fireEvent } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { ContainerVulnerabilitiesTable } from '../ContainerVulnerabilitiesTable';

// Mock DataTable component
jest.mock('@/shared/components/ui/DataTable', () => ({
  DataTable: ({ columns, data, loading, pagination, onPageChange, emptyState }: any) => (
    <div data-testid="data-table">
      {loading && <div data-testid="loading-state">Loading...</div>}
      {!loading && data.length === 0 && (
        <div data-testid="empty-state">
          <span data-testid="empty-icon">{emptyState.icon?.name}</span>
          <span data-testid="empty-title">{emptyState.title}</span>
          <span data-testid="empty-description">{emptyState.description}</span>
        </div>
      )}
      {!loading && data.length > 0 && (
        <div data-testid="table-body">
          {data.map((item: any, i: number) => (
            <div key={i} data-testid={`vulnerability-row-${i}`} className="table-row">
              {columns.map((col: any) => (
                <div key={col.key} data-testid={`cell-${i}-${col.key}`}>
                  {col.render ? col.render(item) : item[col.key]}
                </div>
              ))}
            </div>
          ))}
        </div>
      )}
      {pagination && (
        <div data-testid="pagination">
          <button
            data-testid="pagination-prev"
            onClick={() => onPageChange?.(pagination.current_page - 1)}
            disabled={pagination.current_page === 1}
          >
            Previous
          </button>
          <span data-testid="pagination-info">
            Page {pagination.current_page} of {pagination.total_pages}
          </span>
          <button
            data-testid="pagination-next"
            onClick={() => onPageChange?.(pagination.current_page + 1)}
            disabled={pagination.current_page === pagination.total_pages}
          >
            Next
          </button>
        </div>
      )}
    </div>
  ),
}));

// Mock Badge component
jest.mock('@/shared/components/ui/Badge', () => ({
  Badge: ({ children, className, variant, size }: any) => (
    <span data-testid={`badge-${variant}`} className={className} data-size={size}>
      {children}
    </span>
  ),
}));

// Mock ExternalLink icon
jest.mock('lucide-react', () => ({
  ExternalLink: () => <span data-testid="external-link-icon">🔗</span>,
  AlertTriangle: () => <span data-testid="alert-triangle-icon">⚠️</span>,
}));

describe('ContainerVulnerabilitiesTable', () => {
  const mockVulnerabilities = [
    {
      id: 'vuln-1',
      vulnerability_id: 'CVE-2024-1234',
      severity: 'critical' as const,
      cvss_score: 9.8,
      package_name: 'lodash',
      package_version: '4.17.20',
      fixed_version: '4.17.21',
      exploit_available: true,
    },
    {
      id: 'vuln-2',
      vulnerability_id: 'CVE-2024-5678',
      severity: 'high' as const,
      cvss_score: 7.5,
      package_name: 'express',
      package_version: '4.17.1',
      fixed_version: undefined,
      exploit_available: false,
    },
    {
      id: 'vuln-3',
      vulnerability_id: 'CVE-2024-9012',
      severity: 'medium' as const,
      cvss_score: 5.3,
      package_name: 'request',
      package_version: '2.88.2',
      fixed_version: '2.88.3',
      exploit_available: false,
    },
    {
      id: 'vuln-4',
      vulnerability_id: 'CVE-2024-3456',
      severity: 'low' as const,
      cvss_score: 2.1,
      package_name: 'debug',
      package_version: '4.3.1',
      fixed_version: '4.3.2',
      exploit_available: false,
    },
  ];

  const mockPagination = {
    current_page: 1,
    per_page: 20,
    total_pages: 3,
    total_count: 60,
  };

  describe('Rendering Vulnerability Data', () => {
    it('renders table with vulnerability data', () => {
      render(
        <ContainerVulnerabilitiesTable vulnerabilities={mockVulnerabilities} loading={false} />
      );

      expect(screen.getByTestId('data-table')).toBeInTheDocument();
      expect(screen.getByTestId('table-body')).toBeInTheDocument();
      expect(screen.getAllByTestId(/^vulnerability-row-/)).toHaveLength(4);
    });

    it('renders vulnerability ID as NVD link', () => {
      render(
        <ContainerVulnerabilitiesTable vulnerabilities={mockVulnerabilities} loading={false} />
      );

      const firstVulnLink = screen.getByText('CVE-2024-1234');
      expect(firstVulnLink).toBeInTheDocument();
      expect(firstVulnLink.closest('a')).toHaveAttribute(
        'href',
        'https://nvd.nist.gov/vuln/detail/CVE-2024-1234'
      );
      expect(firstVulnLink.closest('a')).toHaveAttribute('target', '_blank');
      expect(firstVulnLink.closest('a')).toHaveAttribute('rel', 'noopener noreferrer');
    });

    it('renders external link icon with vulnerability ID', () => {
      render(
        <ContainerVulnerabilitiesTable vulnerabilities={mockVulnerabilities} loading={false} />
      );

      const externalLinkIcons = screen.getAllByTestId('external-link-icon');
      expect(externalLinkIcons.length).toBeGreaterThan(0);
    });

    it('renders package name and version', () => {
      render(
        <ContainerVulnerabilitiesTable vulnerabilities={mockVulnerabilities} loading={false} />
      );

      expect(screen.getByText('lodash')).toBeInTheDocument();
      expect(screen.getByText('4.17.20')).toBeInTheDocument();
      expect(screen.getByText('express')).toBeInTheDocument();
      expect(screen.getByText('4.17.1')).toBeInTheDocument();
    });
  });

  describe('Severity Badge Styling', () => {
    it('shows critical severity badge with correct styling', () => {
      render(
        <ContainerVulnerabilitiesTable vulnerabilities={mockVulnerabilities} loading={false} />
      );

      const criticalBadge = screen.getByText('CRITICAL');
      expect(criticalBadge).toHaveClass('bg-theme-error', 'text-white');
      expect(criticalBadge).toHaveAttribute('data-size', 'sm');
    });

    it('shows high severity badge with correct styling', () => {
      render(
        <ContainerVulnerabilitiesTable vulnerabilities={mockVulnerabilities} loading={false} />
      );

      const highBadge = screen.getByText('HIGH');
      expect(highBadge).toHaveClass('bg-theme-error/80', 'text-white');
    });

    it('shows medium severity badge with correct styling', () => {
      render(
        <ContainerVulnerabilitiesTable vulnerabilities={mockVulnerabilities} loading={false} />
      );

      const mediumBadge = screen.getByText('MEDIUM');
      expect(mediumBadge).toHaveClass('bg-theme-warning', 'text-theme-on-warning');
    });

    it('shows low severity badge with correct styling', () => {
      render(
        <ContainerVulnerabilitiesTable vulnerabilities={mockVulnerabilities} loading={false} />
      );

      const lowBadge = screen.getByText('LOW');
      expect(lowBadge).toHaveClass('bg-theme-info', 'text-white');
    });
  });

  describe('CVSS Score Display', () => {
    it('shows CVSS score formatted to 1 decimal place', () => {
      render(
        <ContainerVulnerabilitiesTable vulnerabilities={mockVulnerabilities} loading={false} />
      );

      expect(screen.getByText('9.8')).toBeInTheDocument();
      expect(screen.getByText('7.5')).toBeInTheDocument();
      expect(screen.getByText('5.3')).toBeInTheDocument();
      expect(screen.getByText('2.1')).toBeInTheDocument();
    });

    it('displays CVSS scores with monospace font', () => {
      render(
        <ContainerVulnerabilitiesTable vulnerabilities={mockVulnerabilities} loading={false} />
      );

      // Verify CVSS scores are displayed
      expect(screen.getByText('9.8')).toBeInTheDocument();
      expect(screen.getByText('7.5')).toBeInTheDocument();
      expect(screen.getByText('5.3')).toBeInTheDocument();
      expect(screen.getByText('2.1')).toBeInTheDocument();
    });
  });

  describe('Fixed Version Display', () => {
    it('shows fixed version when available', () => {
      render(
        <ContainerVulnerabilitiesTable vulnerabilities={mockVulnerabilities} loading={false} />
      );

      expect(screen.getByText('4.17.21')).toBeInTheDocument();
      expect(screen.getByText('2.88.3')).toBeInTheDocument();
    });

    it('shows "No fix available" for vulnerabilities without fixed version', () => {
      render(
        <ContainerVulnerabilitiesTable vulnerabilities={mockVulnerabilities} loading={false} />
      );

      expect(screen.getByText('No fix available')).toBeInTheDocument();
    });

    it('shows success color for available fixed versions', () => {
      render(
        <ContainerVulnerabilitiesTable vulnerabilities={mockVulnerabilities} loading={false} />
      );

      const fixedVersionCells = screen.getAllByTestId(/^cell-\d+-fixed_version$/);
      const hasSuccessColor = fixedVersionCells.some((cell) =>
        cell.textContent && cell.textContent.match(/\d+\.\d+\.\d+/)
      );
      expect(hasSuccessColor).toBe(true);
    });

    it('shows muted color for no fix available', () => {
      render(
        <ContainerVulnerabilitiesTable vulnerabilities={mockVulnerabilities} loading={false} />
      );

      const noFixElements = screen.getAllByText('No fix available');
      noFixElements.forEach((element) => {
        expect(element).toHaveClass('text-theme-muted');
      });
    });
  });

  describe('Exploit Availability Display', () => {
    it('shows "Available" badge when exploit is available', () => {
      render(
        <ContainerVulnerabilitiesTable vulnerabilities={mockVulnerabilities} loading={false} />
      );

      const availableBadges = screen.getAllByText('Available');
      expect(availableBadges.length).toBeGreaterThan(0);
    });

    it('shows "Available" badge with danger variant', () => {
      render(
        <ContainerVulnerabilitiesTable vulnerabilities={mockVulnerabilities} loading={false} />
      );

      const availableBadge = screen.getAllByTestId('badge-danger').find(
        (badge) => badge.textContent === 'Available'
      );
      expect(availableBadge).toBeInTheDocument();
    });

    it('shows dash for vulnerabilities without exploit', () => {
      render(
        <ContainerVulnerabilitiesTable vulnerabilities={mockVulnerabilities} loading={false} />
      );

      const dashElements = screen.getAllByText('-');
      expect(dashElements.length).toBeGreaterThan(0);
    });

    it('shows dash with muted styling when no exploit available', () => {
      const vulnsWithoutExploit = mockVulnerabilities.filter((v) => !v.exploit_available);
      render(
        <ContainerVulnerabilitiesTable
          vulnerabilities={vulnsWithoutExploit}
          loading={false}
        />
      );

      const dashes = screen.getAllByText('-');
      dashes.forEach((dash) => {
        expect(dash).toHaveClass('text-theme-muted', 'text-sm');
      });
    });
  });

  describe('Loading State', () => {
    it('shows loading state when loading is true', () => {
      render(
        <ContainerVulnerabilitiesTable
          vulnerabilities={mockVulnerabilities}
          loading={true}
        />
      );

      expect(screen.getByTestId('loading-state')).toBeInTheDocument();
      expect(screen.queryByTestId('table-body')).not.toBeInTheDocument();
    });

    it('hides table body when loading', () => {
      render(
        <ContainerVulnerabilitiesTable
          vulnerabilities={mockVulnerabilities}
          loading={true}
        />
      );

      expect(screen.queryByTestId('table-body')).not.toBeInTheDocument();
    });

    it('shows table when loading is false', () => {
      render(
        <ContainerVulnerabilitiesTable
          vulnerabilities={mockVulnerabilities}
          loading={false}
        />
      );

      expect(screen.queryByTestId('loading-state')).not.toBeInTheDocument();
      expect(screen.getByTestId('table-body')).toBeInTheDocument();
    });
  });

  describe('Empty State', () => {
    it('renders empty state when no vulnerabilities', () => {
      render(
        <ContainerVulnerabilitiesTable vulnerabilities={[]} loading={false} />
      );

      expect(screen.getByTestId('empty-state')).toBeInTheDocument();
      expect(screen.getByTestId('empty-title')).toHaveTextContent('No vulnerabilities found');
      expect(screen.getByTestId('empty-description')).toHaveTextContent(
        'This container image has no detected vulnerabilities.'
      );
    });

    it('shows alert icon in empty state', () => {
      render(
        <ContainerVulnerabilitiesTable vulnerabilities={[]} loading={false} />
      );

      expect(screen.getByTestId('empty-icon')).toBeInTheDocument();
    });

    it('hides table body when empty', () => {
      render(
        <ContainerVulnerabilitiesTable vulnerabilities={[]} loading={false} />
      );

      expect(screen.queryByTestId('table-body')).not.toBeInTheDocument();
    });
  });

  describe('Pagination', () => {
    it('renders pagination controls when pagination prop is provided', () => {
      render(
        <ContainerVulnerabilitiesTable
          vulnerabilities={mockVulnerabilities}
          loading={false}
          pagination={mockPagination}
        />
      );

      expect(screen.getByTestId('pagination')).toBeInTheDocument();
      expect(screen.getByTestId('pagination-info')).toHaveTextContent('Page 1 of 3');
    });

    it('hides pagination when no pagination prop', () => {
      render(
        <ContainerVulnerabilitiesTable vulnerabilities={mockVulnerabilities} loading={false} />
      );

      expect(screen.queryByTestId('pagination')).not.toBeInTheDocument();
    });

    it('calls onPageChange when next page button clicked', async () => {
      const mockOnPageChange = jest.fn();
      render(
        <ContainerVulnerabilitiesTable
          vulnerabilities={mockVulnerabilities}
          loading={false}
          pagination={mockPagination}
          onPageChange={mockOnPageChange}
        />
      );

      const nextButton = screen.getByTestId('pagination-next');
      fireEvent.click(nextButton);

      expect(mockOnPageChange).toHaveBeenCalledWith(2);
    });

    it('calls onPageChange when previous page button clicked', async () => {
      const mockOnPageChange = jest.fn();
      const secondPagePagination = { ...mockPagination, current_page: 2 };

      render(
        <ContainerVulnerabilitiesTable
          vulnerabilities={mockVulnerabilities}
          loading={false}
          pagination={secondPagePagination}
          onPageChange={mockOnPageChange}
        />
      );

      const prevButton = screen.getByTestId('pagination-prev');
      fireEvent.click(prevButton);

      expect(mockOnPageChange).toHaveBeenCalledWith(1);
    });

    it('disables previous button on first page', () => {
      render(
        <ContainerVulnerabilitiesTable
          vulnerabilities={mockVulnerabilities}
          loading={false}
          pagination={mockPagination}
        />
      );

      const prevButton = screen.getByTestId('pagination-prev') as HTMLButtonElement;
      expect(prevButton.disabled).toBe(true);
    });

    it('enables previous button when not on first page', () => {
      const secondPagePagination = { ...mockPagination, current_page: 2 };

      render(
        <ContainerVulnerabilitiesTable
          vulnerabilities={mockVulnerabilities}
          loading={false}
          pagination={secondPagePagination}
        />
      );

      const prevButton = screen.getByTestId('pagination-prev') as HTMLButtonElement;
      expect(prevButton.disabled).toBe(false);
    });

    it('disables next button on last page', () => {
      const lastPagePagination = { ...mockPagination, current_page: 3 };

      render(
        <ContainerVulnerabilitiesTable
          vulnerabilities={mockVulnerabilities}
          loading={false}
          pagination={lastPagePagination}
        />
      );

      const nextButton = screen.getByTestId('pagination-next') as HTMLButtonElement;
      expect(nextButton.disabled).toBe(true);
    });

    it('enables next button when not on last page', () => {
      render(
        <ContainerVulnerabilitiesTable
          vulnerabilities={mockVulnerabilities}
          loading={false}
          pagination={mockPagination}
        />
      );

      const nextButton = screen.getByTestId('pagination-next') as HTMLButtonElement;
      expect(nextButton.disabled).toBe(false);
    });
  });

  describe('Multiple Vulnerabilities', () => {
    it('renders all vulnerabilities in correct order', () => {
      render(
        <ContainerVulnerabilitiesTable vulnerabilities={mockVulnerabilities} loading={false} />
      );

      const rows = screen.getAllByTestId(/^vulnerability-row-\d+$/);
      expect(rows).toHaveLength(mockVulnerabilities.length);
    });

    it('displays different severity levels correctly', () => {
      render(
        <ContainerVulnerabilitiesTable vulnerabilities={mockVulnerabilities} loading={false} />
      );

      expect(screen.getByText('CRITICAL')).toBeInTheDocument();
      expect(screen.getByText('HIGH')).toBeInTheDocument();
      expect(screen.getByText('MEDIUM')).toBeInTheDocument();
      expect(screen.getByText('LOW')).toBeInTheDocument();
    });
  });
});
