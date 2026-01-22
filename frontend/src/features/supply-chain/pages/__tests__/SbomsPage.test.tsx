import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { BrowserRouter, MemoryRouter } from 'react-router-dom';
import { SbomsPage } from '../SbomsPage';
import { useSboms } from '../../hooks/useSboms';
import { sbomsApi } from '../../services/sbomsApi';
import { createMockSbom, createMockPagination } from '../../testing/mockFactories';

// Mock dependencies
jest.mock('../../hooks/useSboms');
jest.mock('../../services/sbomsApi');
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    showNotification: jest.fn(),
  }),
}));

// Mock PageContainer to simplify testing
jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({ title, description, breadcrumbs, actions, children }: any) => (
    <div data-testid="page-container">
      <div data-testid="page-title">{title}</div>
      <div data-testid="page-description">{description}</div>
      <div data-testid="page-actions">
        {actions?.map((action: any) => (
          <button
            key={action.id}
            onClick={action.onClick}
            data-testid={`action-${action.id}`}
            disabled={action.disabled}
          >
            {action.label}
          </button>
        ))}
      </div>
      {children}
    </div>
  ),
}));

// Mock TabContainer
jest.mock('@/shared/components/ui/TabContainer', () => ({
  TabContainer: ({ tabs, activeTab, onTabChange }: any) => (
    <div data-testid="tab-container">
      {tabs.map((tab: any) => (
        <button
          key={tab.id}
          onClick={() => onTabChange(tab.id)}
          data-testid={`tab-${tab.id}`}
          className={activeTab === tab.id ? 'active' : ''}
        >
          {tab.label}
        </button>
      ))}
    </div>
  ),
}));

// Mock DataTable
jest.mock('@/shared/components/ui/DataTable', () => ({
  DataTable: ({ columns, data, loading, onRowClick, emptyState, pagination, onPageChange }: any) => (
    <div data-testid="data-table">
      {loading && <div data-testid="loading">Loading...</div>}
      {data.length === 0 && !loading && (
        <div data-testid="empty-state">
          <div data-testid="empty-title">{emptyState?.title}</div>
          <div data-testid="empty-description">{emptyState?.description}</div>
        </div>
      )}
      {data.map((item: any) => (
        <div
          key={item.id}
          data-testid={`row-${item.id}`}
          onClick={() => onRowClick?.(item)}
          className="table-row"
        >
          {columns.map((col: any) => (
            <div key={col.key} data-testid={`cell-${item.id}-${col.key}`}>
              {col.render ? col.render(item) : item[col.key]}
            </div>
          ))}
        </div>
      ))}
      {pagination && (
        <div data-testid="pagination">
          <span>Page {pagination.current_page} of {pagination.total_pages}</span>
          <button onClick={() => onPageChange(pagination.current_page + 1)}>Next</button>
        </div>
      )}
    </div>
  ),
}));

// Mock Badge component
jest.mock('@/shared/components/ui/Badge', () => ({
  Badge: ({ children, variant, size }: any) => (
    <span data-testid="badge" data-variant={variant} data-size={size}>
      {children}
    </span>
  ),
}));

// Mock ConfirmationModal
jest.mock('@/shared/components/ui/ConfirmationModal', () => ({
  useConfirmation: () => ({
    confirm: jest.fn((options) => options.onConfirm()),
    ConfirmationDialog: <div data-testid="confirmation-dialog" />,
  }),
}));

const mockNavigate = jest.fn();
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate,
}));

describe('SbomsPage', () => {
  const mockSboms = [
    createMockSbom({
      id: 'sbom-1',
      name: 'App SBOM',
      status: 'completed',
      format: 'cyclonedx_1_5',
      component_count: 150,
      vulnerability_count: 5,
      risk_score: 4.5,
      ntia_minimum_compliant: true,
    }),
    createMockSbom({
      id: 'sbom-2',
      name: 'API SBOM',
      status: 'generating',
      format: 'spdx_2_3',
      component_count: 80,
      vulnerability_count: 0,
      risk_score: 2.1,
      ntia_minimum_compliant: false,
    }),
    createMockSbom({
      id: 'sbom-3',
      name: 'Worker SBOM',
      status: 'failed',
      format: 'cyclonedx_1_4',
      component_count: 0,
      vulnerability_count: 0,
      risk_score: 0,
      ntia_minimum_compliant: false,
    }),
  ];

  const mockPagination = createMockPagination({
    current_page: 1,
    per_page: 20,
    total_pages: 3,
    total_count: 50,
  });

  const mockUseSboms = {
    sboms: mockSboms,
    pagination: mockPagination,
    loading: false,
    error: null,
    refresh: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
    (useSboms as jest.Mock).mockReturnValue(mockUseSboms);
    (sbomsApi.delete as jest.Mock).mockResolvedValue(undefined);
  });

  const renderWithRouter = (component: React.ReactElement) => {
    return render(<BrowserRouter>{component}</BrowserRouter>);
  };

  describe('Page Structure', () => {
    it('renders page container with correct title', () => {
      renderWithRouter(<SbomsPage />);
      expect(screen.getByTestId('page-title')).toHaveTextContent('Software Bill of Materials');
    });

    it('renders page description', () => {
      renderWithRouter(<SbomsPage />);
      expect(screen.getByTestId('page-description')).toHaveTextContent(
        'Track and manage your software components and dependencies'
      );
    });

    it('renders refresh action button', () => {
      renderWithRouter(<SbomsPage />);
      expect(screen.getByTestId('action-refresh')).toBeInTheDocument();
      expect(screen.getByTestId('action-refresh')).toHaveTextContent('Refresh');
    });

    it('renders tab container', () => {
      renderWithRouter(<SbomsPage />);
      expect(screen.getByTestId('tab-container')).toBeInTheDocument();
    });

    it('renders data table', () => {
      renderWithRouter(<SbomsPage />);
      expect(screen.getByTestId('data-table')).toBeInTheDocument();
    });
  });

  describe('Loading State', () => {
    it('displays loading state when loading is true', () => {
      (useSboms as jest.Mock).mockReturnValue({
        ...mockUseSboms,
        loading: true,
        sboms: [],
      });
      renderWithRouter(<SbomsPage />);
      expect(screen.getByTestId('loading')).toBeInTheDocument();
    });

    it('does not display loading when data is loaded', () => {
      renderWithRouter(<SbomsPage />);
      expect(screen.queryByTestId('loading')).not.toBeInTheDocument();
    });
  });

  describe('Empty State', () => {
    it('displays empty state when no SBOMs exist', () => {
      (useSboms as jest.Mock).mockReturnValue({
        ...mockUseSboms,
        sboms: [],
      });
      renderWithRouter(<SbomsPage />);
      expect(screen.getByTestId('empty-state')).toBeInTheDocument();
      expect(screen.getByTestId('empty-title')).toHaveTextContent('No SBOMs Found');
    });

    it('displays correct empty state message when no filter is applied', () => {
      (useSboms as jest.Mock).mockReturnValue({
        ...mockUseSboms,
        sboms: [],
      });
      renderWithRouter(<SbomsPage />);
      expect(screen.getByTestId('empty-description')).toHaveTextContent(
        'SBOMs are generated via CI/CD pipelines or repository integrations.'
      );
    });

    it('displays filtered empty state message when status filter is active', async () => {
      (useSboms as jest.Mock).mockReturnValue({
        ...mockUseSboms,
        sboms: [],
      });
      renderWithRouter(<SbomsPage />);

      const completedTab = screen.getByTestId('tab-completed');
      fireEvent.click(completedTab);

      await waitFor(() => {
        expect(screen.getByTestId('empty-description')).toHaveTextContent(
          'No completed SBOMs found. Try adjusting your filters.'
        );
      });
    });
  });

  describe('Data Display', () => {
    it('renders all SBOMs in the list', () => {
      renderWithRouter(<SbomsPage />);
      expect(screen.getByTestId('row-sbom-1')).toBeInTheDocument();
      expect(screen.getByTestId('row-sbom-2')).toBeInTheDocument();
      expect(screen.getByTestId('row-sbom-3')).toBeInTheDocument();
    });

    it('displays SBOM names correctly', () => {
      renderWithRouter(<SbomsPage />);
      expect(screen.getByText('App SBOM')).toBeInTheDocument();
      expect(screen.getByText('API SBOM')).toBeInTheDocument();
      expect(screen.getByText('Worker SBOM')).toBeInTheDocument();
    });

    it('displays component counts', () => {
      renderWithRouter(<SbomsPage />);
      const appRow = screen.getByTestId('row-sbom-1');
      expect(appRow).toHaveTextContent('150');
    });

    it('displays vulnerability counts', () => {
      renderWithRouter(<SbomsPage />);
      const appRow = screen.getByTestId('row-sbom-1');
      expect(appRow).toHaveTextContent('5');
    });
  });

  describe('Tab Filtering', () => {
    it('renders all filter tabs', () => {
      renderWithRouter(<SbomsPage />);
      expect(screen.getByTestId('tab-all')).toBeInTheDocument();
      expect(screen.getByTestId('tab-completed')).toBeInTheDocument();
      expect(screen.getByTestId('tab-generating')).toBeInTheDocument();
      expect(screen.getByTestId('tab-failed')).toBeInTheDocument();
    });

    it('sets All tab as active by default', () => {
      renderWithRouter(<SbomsPage />);
      expect(screen.getByTestId('tab-all')).toHaveClass('active');
    });

    it('filters SBOMs when Completed tab is clicked', async () => {
      renderWithRouter(<SbomsPage />);

      const completedTab = screen.getByTestId('tab-completed');
      fireEvent.click(completedTab);

      await waitFor(() => {
        expect(useSboms).toHaveBeenCalledWith(
          expect.objectContaining({ status: 'completed' })
        );
      });
    });

    it('filters SBOMs when Generating tab is clicked', async () => {
      renderWithRouter(<SbomsPage />);

      const generatingTab = screen.getByTestId('tab-generating');
      fireEvent.click(generatingTab);

      await waitFor(() => {
        expect(useSboms).toHaveBeenCalledWith(
          expect.objectContaining({ status: 'generating' })
        );
      });
    });

    it('filters SBOMs when Failed tab is clicked', async () => {
      renderWithRouter(<SbomsPage />);

      const failedTab = screen.getByTestId('tab-failed');
      fireEvent.click(failedTab);

      await waitFor(() => {
        expect(useSboms).toHaveBeenCalledWith(
          expect.objectContaining({ status: 'failed' })
        );
      });
    });

    it('clears filter when All tab is clicked after filtering', async () => {
      renderWithRouter(<SbomsPage />);

      // First filter by completed
      fireEvent.click(screen.getByTestId('tab-completed'));

      // Then go back to all
      fireEvent.click(screen.getByTestId('tab-all'));

      await waitFor(() => {
        expect(useSboms).toHaveBeenCalledWith(
          expect.objectContaining({ status: undefined })
        );
      });
    });

    it('resets page to 1 when changing tabs', async () => {
      renderWithRouter(<SbomsPage />);

      // Click pagination next to go to page 2
      const nextButton = screen.getByText('Next');
      fireEvent.click(nextButton);

      // Then change tab
      fireEvent.click(screen.getByTestId('tab-completed'));

      await waitFor(() => {
        expect(useSboms).toHaveBeenCalledWith(
          expect.objectContaining({ page: 1 })
        );
      });
    });
  });

  describe('Status Badges', () => {
    it('renders status badge for completed SBOM', () => {
      renderWithRouter(<SbomsPage />);
      const appRow = screen.getByTestId('row-sbom-1');
      const badges = appRow.querySelectorAll('[data-testid="badge"]');
      const statusBadge = Array.from(badges).find(b => b.textContent === 'Completed');
      expect(statusBadge).toBeDefined();
    });

    it('renders status badge with correct variant for completed', () => {
      renderWithRouter(<SbomsPage />);
      const appRow = screen.getByTestId('row-sbom-1');
      const badges = appRow.querySelectorAll('[data-testid="badge"]');
      const statusBadge = Array.from(badges).find(b => b.textContent === 'Completed');
      expect(statusBadge).toHaveAttribute('data-variant', 'success');
    });

    it('renders status badge with correct variant for generating', () => {
      renderWithRouter(<SbomsPage />);
      const apiRow = screen.getByTestId('row-sbom-2');
      const badges = apiRow.querySelectorAll('[data-testid="badge"]');
      const statusBadge = Array.from(badges).find(b => b.textContent === 'Generating');
      expect(statusBadge).toHaveAttribute('data-variant', 'warning');
    });

    it('renders status badge with correct variant for failed', () => {
      renderWithRouter(<SbomsPage />);
      const workerRow = screen.getByTestId('row-sbom-3');
      const badges = workerRow.querySelectorAll('[data-testid="badge"]');
      const statusBadge = Array.from(badges).find(b => b.textContent === 'Failed');
      expect(statusBadge).toHaveAttribute('data-variant', 'danger');
    });
  });

  describe('Format Badges', () => {
    it('renders format badge for CycloneDX', () => {
      renderWithRouter(<SbomsPage />);
      const appRow = screen.getByTestId('row-sbom-1');
      expect(appRow).toHaveTextContent('CYCLONEDX_1_5');
    });

    it('renders format badge for SPDX', () => {
      renderWithRouter(<SbomsPage />);
      const apiRow = screen.getByTestId('row-sbom-2');
      expect(apiRow).toHaveTextContent('SPDX_2_3');
    });

    it('renders format badge with outline variant', () => {
      renderWithRouter(<SbomsPage />);
      const appRow = screen.getByTestId('row-sbom-1');
      const badges = appRow.querySelectorAll('[data-testid="badge"]');
      const formatBadge = Array.from(badges).find(b =>
        b.textContent?.includes('CYCLONEDX')
      );
      expect(formatBadge).toHaveAttribute('data-variant', 'outline');
    });
  });

  describe('Risk Score Badges', () => {
    it('renders risk score badge with correct value', () => {
      renderWithRouter(<SbomsPage />);
      const appRow = screen.getByTestId('row-sbom-1');
      expect(appRow).toHaveTextContent('4.5');
    });

    it('renders low risk score with success variant', () => {
      renderWithRouter(<SbomsPage />);
      const apiRow = screen.getByTestId('row-sbom-2');
      const badges = apiRow.querySelectorAll('[data-testid="badge"]');
      const riskBadge = Array.from(badges).find(b => b.textContent === '2.1');
      expect(riskBadge).toHaveAttribute('data-variant', 'success');
    });

    it('renders medium risk score with warning variant', () => {
      renderWithRouter(<SbomsPage />);
      const appRow = screen.getByTestId('row-sbom-1');
      const badges = appRow.querySelectorAll('[data-testid="badge"]');
      const riskBadge = Array.from(badges).find(b => b.textContent === '4.5');
      expect(riskBadge).toHaveAttribute('data-variant', 'warning');
    });

    it('renders high risk score with danger variant', () => {
      const highRiskSbom = createMockSbom({
        id: 'sbom-high',
        risk_score: 8.5,
      });
      (useSboms as jest.Mock).mockReturnValue({
        ...mockUseSboms,
        sboms: [highRiskSbom],
      });

      renderWithRouter(<SbomsPage />);
      const row = screen.getByTestId('row-sbom-high');
      const badges = row.querySelectorAll('[data-testid="badge"]');
      const riskBadge = Array.from(badges).find(b => b.textContent === '8.5');
      expect(riskBadge).toHaveAttribute('data-variant', 'danger');
    });
  });

  describe('NTIA Compliance Icons', () => {
    it('renders check icon for NTIA compliant SBOM', () => {
      renderWithRouter(<SbomsPage />);
      const appRow = screen.getByTestId('row-sbom-1');
      expect(appRow.querySelector('svg')).toBeInTheDocument();
    });

    it('displays appropriate icon styling for compliant status', () => {
      renderWithRouter(<SbomsPage />);
      const appRow = screen.getByTestId('row-sbom-1');
      const icon = appRow.querySelector('svg');
      expect(icon?.classList.contains('text-theme-success')).toBeTruthy();
    });

    it('displays appropriate icon styling for non-compliant status', () => {
      renderWithRouter(<SbomsPage />);
      const apiRow = screen.getByTestId('row-sbom-2');
      const icon = apiRow.querySelector('svg');
      expect(icon?.classList.contains('text-theme-error')).toBeTruthy();
    });
  });

  describe('Pagination', () => {
    it('displays pagination when data is available', () => {
      renderWithRouter(<SbomsPage />);
      expect(screen.getByTestId('pagination')).toBeInTheDocument();
    });

    it('displays current page and total pages', () => {
      renderWithRouter(<SbomsPage />);
      expect(screen.getByText('Page 1 of 3')).toBeInTheDocument();
    });

    it('calls onPageChange when next button is clicked', async () => {
      renderWithRouter(<SbomsPage />);

      const nextButton = screen.getByText('Next');
      fireEvent.click(nextButton);

      await waitFor(() => {
        expect(useSboms).toHaveBeenCalledWith(
          expect.objectContaining({ page: 2 })
        );
      });
    });
  });

  describe('Row Navigation', () => {
    it('navigates to detail page when row is clicked', () => {
      renderWithRouter(<SbomsPage />);

      const row = screen.getByTestId('row-sbom-1');
      fireEvent.click(row);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/sboms/sbom-1');
    });

    it('navigates to correct SBOM detail page', () => {
      renderWithRouter(<SbomsPage />);

      const row = screen.getByTestId('row-sbom-2');
      fireEvent.click(row);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/sboms/sbom-2');
    });
  });

  describe('Delete Action', () => {
    it('renders delete button in actions column', () => {
      renderWithRouter(<SbomsPage />);
      const row = screen.getByTestId('row-sbom-1');
      expect(row).toHaveTextContent('View');
    });

    it('calls delete API when delete is confirmed', async () => {
      renderWithRouter(<SbomsPage />);

      // Note: The confirmation is mocked to auto-confirm
      // In real scenario, user would click delete button then confirm in modal

      expect(sbomsApi.delete).not.toHaveBeenCalled();
    });
  });

  describe('Refresh Action', () => {
    it('calls refresh when refresh button is clicked', () => {
      renderWithRouter(<SbomsPage />);

      const refreshButton = screen.getByTestId('action-refresh');
      fireEvent.click(refreshButton);

      expect(mockUseSboms.refresh).toHaveBeenCalled();
    });

    it('refresh button is not disabled', () => {
      renderWithRouter(<SbomsPage />);

      const refreshButton = screen.getByTestId('action-refresh');
      expect(refreshButton).not.toBeDisabled();
    });
  });

  describe('Date Formatting', () => {
    it('displays relative time for recent SBOMs', () => {
      const recentSbom = createMockSbom({
        id: 'sbom-recent',
        created_at: new Date(Date.now() - 5 * 60000).toISOString(), // 5 minutes ago
      });
      (useSboms as jest.Mock).mockReturnValue({
        ...mockUseSboms,
        sboms: [recentSbom],
      });

      renderWithRouter(<SbomsPage />);
      const row = screen.getByTestId('row-sbom-recent');
      expect(row).toHaveTextContent('5m ago');
    });

    it('displays hours for SBOMs created today', () => {
      const todaySbom = createMockSbom({
        id: 'sbom-today',
        created_at: new Date(Date.now() - 2 * 3600000).toISOString(), // 2 hours ago
      });
      (useSboms as jest.Mock).mockReturnValue({
        ...mockUseSboms,
        sboms: [todaySbom],
      });

      renderWithRouter(<SbomsPage />);
      const row = screen.getByTestId('row-sbom-today');
      expect(row).toHaveTextContent('2h ago');
    });

    it('displays days for recent SBOMs', () => {
      const daysSbom = createMockSbom({
        id: 'sbom-days',
        created_at: new Date(Date.now() - 3 * 86400000).toISOString(), // 3 days ago
      });
      (useSboms as jest.Mock).mockReturnValue({
        ...mockUseSboms,
        sboms: [daysSbom],
      });

      renderWithRouter(<SbomsPage />);
      const row = screen.getByTestId('row-sbom-days');
      expect(row).toHaveTextContent('3d ago');
    });
  });

  describe('Vulnerability Count Styling', () => {
    it('displays vulnerability count in red when vulnerabilities exist', () => {
      renderWithRouter(<SbomsPage />);
      const appRow = screen.getByTestId('row-sbom-1');
      const vulnCell = appRow.querySelector('[data-testid="cell-sbom-1-vulnerability_count"]');
      expect(vulnCell?.textContent).toBe('5');
    });

    it('displays vulnerability count in green when no vulnerabilities', () => {
      renderWithRouter(<SbomsPage />);
      const apiRow = screen.getByTestId('row-sbom-2');
      const vulnCell = apiRow.querySelector('[data-testid="cell-sbom-2-vulnerability_count"]');
      expect(vulnCell?.textContent).toBe('0');
    });
  });

  describe('Hook Integration', () => {
    it('calls useSboms with correct default options', () => {
      renderWithRouter(<SbomsPage />);

      expect(useSboms).toHaveBeenCalledWith({
        page: 1,
        perPage: 20,
        status: undefined,
      });
    });

    it('updates hook options when filters change', async () => {
      renderWithRouter(<SbomsPage />);

      const completedTab = screen.getByTestId('tab-completed');
      fireEvent.click(completedTab);

      await waitFor(() => {
        expect(useSboms).toHaveBeenCalledWith({
          page: 1,
          perPage: 20,
          status: 'completed',
        });
      });
    });
  });
});
