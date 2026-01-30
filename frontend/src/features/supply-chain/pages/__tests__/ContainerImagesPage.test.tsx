import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { BrowserRouter, MemoryRouter } from 'react-router-dom';
import { ContainerImagesPage } from '../ContainerImagesPage';
import { useContainerImages } from '../../hooks/useContainerImages';
import { createMockContainerImage, createMockPagination } from '../../testing/mockFactories';

jest.mock('../../hooks/useContainerImages');

// Mock PageContainer
jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({ children, title, description, breadcrumbs, actions }: any) => (
    <div data-testid="page-container">
      <h1 data-testid="page-title">{title}</h1>
      <p data-testid="page-description">{description}</p>
      <div data-testid="breadcrumbs">
        {breadcrumbs?.map((bc: any, i: number) => (
          <span key={i} data-testid={`breadcrumb-${i}`}>
            {bc.label}
          </span>
        ))}
      </div>
      <div data-testid="page-actions">
        {actions?.map((action: any, i: number) => (
          <button key={i} onClick={action.onClick}>
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
      {tabs.map((t: any) => (
        <button
          key={t.id}
          data-testid={`tab-${t.id}`}
          data-active={activeTab === t.id}
          onClick={() => onTabChange(t.id)}
        >
          {t.label}
        </button>
      ))}
    </div>
  ),
}));

// Mock DataTable
jest.mock('@/shared/components/ui/DataTable', () => ({
  DataTable: ({ columns, data, loading, pagination, onPageChange, onRowClick, emptyState }: any) => (
    <div data-testid="data-table">
      {!loading && data.length === 0 && (
        <div data-testid="empty-state">
          <span data-testid="empty-icon">{emptyState?.icon?.name}</span>
          <span data-testid="empty-title">{emptyState?.title}</span>
          <span data-testid="empty-description">{emptyState?.description}</span>
        </div>
      )}
      {!loading && data.length > 0 && (
        <div data-testid="table-body">
          {data.map((item: any, i: number) => (
            <div
              key={i}
              data-testid={`row-${i}`}
              onClick={() => onRowClick?.(item)}
              style={{ cursor: 'pointer' }}
            >
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
            data-testid="page-prev"
            onClick={() => onPageChange?.(pagination.current_page - 1)}
          >
            Previous
          </button>
          <span data-testid="page-info">
            Page {pagination.current_page} of {pagination.total_pages}
          </span>
          <button
            data-testid="page-next"
            onClick={() => onPageChange?.(pagination.current_page + 1)}
          >
            Next
          </button>
        </div>
      )}
    </div>
  ),
}));

// Mock LoadingSpinner
jest.mock('@/shared/components/ui/LoadingSpinner', () => ({
  LoadingSpinner: ({ size }: any) => <div data-testid="loading-spinner" data-size={size}>Loading...</div>,
}));

// Mock ErrorAlert
jest.mock('@/shared/components/ui/ErrorAlert', () => ({
  __esModule: true,
  default: ({ message }: any) => <div data-testid="error-alert">{message}</div>,
}));

// Mock StatusBadge
jest.mock('../../components/shared/StatusBadge', () => ({
  StatusBadge: ({ status, size }: any) => (
    <span data-testid="status-badge" data-status={status} data-size={size}>
      {status}
    </span>
  ),
}));

// Mock react-router-dom navigation
const mockNavigate = jest.fn();
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate,
}));

describe('ContainerImagesPage', () => {
  const mockUseContainerImages = useContainerImages as jest.MockedFunction<typeof useContainerImages>;

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('Loading State', () => {
    it('shows loading spinner when loading is true', () => {
      mockUseContainerImages.mockReturnValue({
        images: [],
        pagination: null,
        loading: true,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      expect(screen.getByTestId('loading-spinner')).toBeInTheDocument();
      expect(screen.queryByTestId('table-body')).not.toBeInTheDocument();
    });

    it('shows loading spinner with large size', () => {
      mockUseContainerImages.mockReturnValue({
        images: [],
        pagination: null,
        loading: true,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      const spinner = screen.getByTestId('loading-spinner');
      expect(spinner).toHaveAttribute('data-size', 'lg');
    });

    it('hides loading spinner when loading is false', () => {
      mockUseContainerImages.mockReturnValue({
        images: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      expect(screen.queryByTestId('loading-spinner')).not.toBeInTheDocument();
    });
  });

  describe('Error State', () => {
    it('shows error alert when error exists', () => {
      mockUseContainerImages.mockReturnValue({
        images: [],
        pagination: null,
        loading: false,
        error: 'Failed to fetch container images',
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      expect(screen.getByTestId('error-alert')).toBeInTheDocument();
      expect(screen.getByTestId('error-alert')).toHaveTextContent('Failed to fetch container images');
    });

    it('hides error alert when no error', () => {
      mockUseContainerImages.mockReturnValue({
        images: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      expect(screen.queryByTestId('error-alert')).not.toBeInTheDocument();
    });
  });

  describe('Empty State', () => {
    it('shows empty state when no images', () => {
      mockUseContainerImages.mockReturnValue({
        images: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      expect(screen.getByTestId('empty-state')).toBeInTheDocument();
      expect(screen.getByTestId('empty-title')).toHaveTextContent('No container images found');
    });

    it('shows generic empty description for "all" tab', () => {
      mockUseContainerImages.mockReturnValue({
        images: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      expect(screen.getByTestId('empty-description')).toHaveTextContent(
        'Container images are discovered via registry integrations.'
      );
    });

    it('shows tab-specific empty description for filtered tabs', () => {
      mockUseContainerImages.mockReturnValue({
        images: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      const { rerender } = render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      // Switch to verified tab
      fireEvent.click(screen.getByTestId('tab-verified'));

      // Need to update mock return value after tab change
      mockUseContainerImages.mockReturnValue({
        images: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      rerender(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      expect(screen.getByTestId('empty-description')).toHaveTextContent(
        'No verified container images found.'
      );
    });
  });

  describe('Container Images List', () => {
    const mockImages = [
      createMockContainerImage({
        id: 'image-1',
        registry: 'ghcr.io',
        repository: 'org/app',
        tag: 'latest',
        digest: 'sha256:' + 'a'.repeat(64),
        status: 'verified',
        critical_vuln_count: 0,
        high_vuln_count: 2,
        medium_vuln_count: 5,
        low_vuln_count: 10,
        is_deployed: true,
        last_scanned_at: '2024-01-15T10:30:00Z',
      }),
      createMockContainerImage({
        id: 'image-2',
        registry: 'docker.io',
        repository: 'library/nginx',
        tag: 'v1.0.0',
        digest: 'sha256:' + 'b'.repeat(64),
        status: 'unverified',
        critical_vuln_count: 1,
        high_vuln_count: 0,
        medium_vuln_count: 0,
        low_vuln_count: 0,
        is_deployed: false,
        last_scanned_at: null,
      }),
    ];

    it('renders container images list', () => {
      mockUseContainerImages.mockReturnValue({
        images: mockImages,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      expect(screen.getByTestId('table-body')).toBeInTheDocument();
      expect(screen.getByTestId('row-0')).toBeInTheDocument();
      expect(screen.getByTestId('row-1')).toBeInTheDocument();
    });

    it('displays registry and repository in image column', () => {
      mockUseContainerImages.mockReturnValue({
        images: mockImages,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      expect(screen.getByText('ghcr.io/org/app')).toBeInTheDocument();
      expect(screen.getByText('docker.io/library/nginx')).toBeInTheDocument();
    });

    it('displays tag in image column', () => {
      mockUseContainerImages.mockReturnValue({
        images: mockImages,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      expect(screen.getByText('latest')).toBeInTheDocument();
      expect(screen.getByText('v1.0.0')).toBeInTheDocument();
    });

    it('truncates digest to first 12 characters', () => {
      mockUseContainerImages.mockReturnValue({
        images: mockImages,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      // Digest should be truncated: sha256:aaa... -> aaa...
      expect(screen.getByText('aaaaaaaaaaaa...')).toBeInTheDocument();
      expect(screen.getByText('bbbbbbbbbbbb...')).toBeInTheDocument();
    });

    it('displays vulnerability counts', () => {
      mockUseContainerImages.mockReturnValue({
        images: mockImages,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      // Check first image
      const firstImageCells = screen.getByTestId('row-0');
      expect(firstImageCells).toBeInTheDocument();
      expect(screen.getByTestId('cell-0-critical')).toHaveTextContent('0');
      expect(screen.getByTestId('cell-0-high')).toHaveTextContent('2');
      expect(screen.getByTestId('cell-0-medium')).toHaveTextContent('5');
      expect(screen.getByTestId('cell-0-low')).toHaveTextContent('10');
    });

    it('displays status badge', () => {
      mockUseContainerImages.mockReturnValue({
        images: mockImages,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      const statusBadges = screen.getAllByTestId('status-badge');
      expect(statusBadges).toHaveLength(2);
      expect(statusBadges[0]).toHaveAttribute('data-status', 'verified');
      expect(statusBadges[1]).toHaveAttribute('data-status', 'unverified');
    });

    it('displays "Yes" when is_deployed is true', () => {
      mockUseContainerImages.mockReturnValue({
        images: mockImages,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      expect(screen.getByTestId('cell-0-deployed')).toHaveTextContent('Yes');
    });

    it('displays "No" when is_deployed is false', () => {
      mockUseContainerImages.mockReturnValue({
        images: mockImages,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      expect(screen.getByTestId('cell-1-deployed')).toHaveTextContent('No');
    });

    it('displays formatted last scanned date', () => {
      mockUseContainerImages.mockReturnValue({
        images: mockImages,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      // Should format the date
      const lastScannedCell = screen.getByTestId('cell-0-last_scanned');
      expect(lastScannedCell).toBeInTheDocument();
      expect(lastScannedCell).not.toHaveTextContent('Never');
    });

    it('displays "Never" when last_scanned_at is null', () => {
      mockUseContainerImages.mockReturnValue({
        images: mockImages,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      expect(screen.getByTestId('cell-1-last_scanned')).toHaveTextContent('Never');
    });
  });

  describe('Vulnerability Count Colors', () => {
    const mockImage = createMockContainerImage({
      critical_vuln_count: 3,
      high_vuln_count: 5,
      medium_vuln_count: 7,
      low_vuln_count: 2,
    });

    it('applies error color to critical count when non-zero', () => {
      mockUseContainerImages.mockReturnValue({
        images: [mockImage],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      const criticalCell = screen.getByTestId('cell-0-critical');
      const criticalSpan = criticalCell.querySelector('span');
      expect(criticalSpan).toHaveClass('text-theme-error', 'font-semibold');
    });

    it('applies warning color to high count when non-zero', () => {
      mockUseContainerImages.mockReturnValue({
        images: [mockImage],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      const highCell = screen.getByTestId('cell-0-high');
      const highSpan = highCell.querySelector('span');
      expect(highSpan).toHaveClass('text-theme-warning', 'font-medium');
    });

    it('applies info color to medium count when non-zero', () => {
      mockUseContainerImages.mockReturnValue({
        images: [mockImage],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      const mediumCell = screen.getByTestId('cell-0-medium');
      const mediumSpan = mediumCell.querySelector('span');
      expect(mediumSpan).toHaveClass('text-theme-info');
    });

    it('applies success color to low count when non-zero', () => {
      mockUseContainerImages.mockReturnValue({
        images: [mockImage],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      const lowCell = screen.getByTestId('cell-0-low');
      const lowSpan = lowCell.querySelector('span');
      expect(lowSpan).toHaveClass('text-theme-success');
    });

    it('applies muted color to zero counts', () => {
      const zeroImage = createMockContainerImage({
        critical_vuln_count: 0,
        high_vuln_count: 0,
        medium_vuln_count: 0,
        low_vuln_count: 0,
      });

      mockUseContainerImages.mockReturnValue({
        images: [zeroImage],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      const criticalSpan = screen.getByTestId('cell-0-critical').querySelector('span');
      expect(criticalSpan).toHaveClass('text-theme-muted');
    });
  });

  describe('Tab Navigation', () => {
    it('renders all tabs', () => {
      mockUseContainerImages.mockReturnValue({
        images: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      expect(screen.getByTestId('tab-all')).toHaveTextContent('All Images');
      expect(screen.getByTestId('tab-verified')).toHaveTextContent('Verified');
      expect(screen.getByTestId('tab-unverified')).toHaveTextContent('Unverified');
      expect(screen.getByTestId('tab-quarantined')).toHaveTextContent('Quarantined');
    });

    it('shows "all" tab as active by default', () => {
      mockUseContainerImages.mockReturnValue({
        images: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      expect(screen.getByTestId('tab-all')).toHaveAttribute('data-active', 'true');
    });

    it('changes active tab when clicked', () => {
      mockUseContainerImages.mockReturnValue({
        images: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('tab-verified'));
      expect(screen.getByTestId('tab-verified')).toHaveAttribute('data-active', 'true');
    });

    it('filters by status undefined when "all" tab is active', () => {
      mockUseContainerImages.mockReturnValue({
        images: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      expect(mockUseContainerImages).toHaveBeenCalledWith({
        page: 1,
        perPage: 20,
        status: undefined,
      });
    });

    it('filters by status "verified" when verified tab is active', () => {
      mockUseContainerImages.mockReturnValue({
        images: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      const { rerender } = render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('tab-verified'));

      rerender(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      expect(mockUseContainerImages).toHaveBeenLastCalledWith({
        page: 1,
        perPage: 20,
        status: 'verified',
      });
    });

    it('filters by status "unverified" when unverified tab is active', () => {
      mockUseContainerImages.mockReturnValue({
        images: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      const { rerender } = render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('tab-unverified'));

      rerender(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      expect(mockUseContainerImages).toHaveBeenLastCalledWith({
        page: 1,
        perPage: 20,
        status: 'unverified',
      });
    });

    it('filters by status "quarantined" when quarantined tab is active', () => {
      mockUseContainerImages.mockReturnValue({
        images: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      const { rerender } = render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('tab-quarantined'));

      rerender(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      expect(mockUseContainerImages).toHaveBeenLastCalledWith({
        page: 1,
        perPage: 20,
        status: 'quarantined',
      });
    });

    it('resets to page 1 when changing tabs', () => {
      const pagination = createMockPagination({ current_page: 3 });
      mockUseContainerImages.mockReturnValue({
        images: [],
        pagination,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      const { rerender } = render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('tab-verified'));

      rerender(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      expect(mockUseContainerImages).toHaveBeenLastCalledWith({
        page: 1,
        perPage: 20,
        status: 'verified',
      });
    });
  });

  describe('Pagination', () => {
    const mockImages = [createMockContainerImage()];
    const mockPagination = createMockPagination({
      current_page: 1,
      total_pages: 5,
      total_count: 100,
    });

    it('renders pagination when pagination data exists', () => {
      mockUseContainerImages.mockReturnValue({
        images: mockImages,
        pagination: mockPagination,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      expect(screen.getByTestId('pagination')).toBeInTheDocument();
      expect(screen.getByTestId('page-info')).toHaveTextContent('Page 1 of 5');
    });

    it('calls hook with updated page when next page clicked', () => {
      mockUseContainerImages.mockReturnValue({
        images: mockImages,
        pagination: mockPagination,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      const { rerender } = render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('page-next'));

      rerender(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      expect(mockUseContainerImages).toHaveBeenLastCalledWith({
        page: 2,
        perPage: 20,
        status: undefined,
      });
    });

    it('calls hook with updated page when previous page clicked', () => {
      const page2Pagination = createMockPagination({ current_page: 2 });
      mockUseContainerImages.mockReturnValue({
        images: mockImages,
        pagination: page2Pagination,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      const { rerender } = render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('page-prev'));

      rerender(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      expect(mockUseContainerImages).toHaveBeenLastCalledWith({
        page: 1,
        perPage: 20,
        status: undefined,
      });
    });
  });

  describe('Row Click Navigation', () => {
    it('navigates to detail page when row is clicked', () => {
      const mockImages = [createMockContainerImage({ id: 'image-123' })];
      mockUseContainerImages.mockReturnValue({
        images: mockImages,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('row-0'));

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/container-images/image-123');
    });

    it('navigates with correct image id for different images', () => {
      const mockImages = [
        createMockContainerImage({ id: 'image-aaa' }),
        createMockContainerImage({ id: 'image-bbb' }),
      ];
      mockUseContainerImages.mockReturnValue({
        images: mockImages,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('row-1'));

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/container-images/image-bbb');
    });
  });

  describe('Page Container', () => {
    it('renders correct title', () => {
      mockUseContainerImages.mockReturnValue({
        images: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      expect(screen.getByTestId('page-title')).toHaveTextContent('Container Images');
    });

    it('renders correct description', () => {
      mockUseContainerImages.mockReturnValue({
        images: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      expect(screen.getByTestId('page-description')).toHaveTextContent(
        'Manage and monitor container images with vulnerability scanning and verification'
      );
    });

    it('renders breadcrumbs', () => {
      mockUseContainerImages.mockReturnValue({
        images: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      expect(screen.getByTestId('breadcrumb-0')).toHaveTextContent('Dashboard');
      expect(screen.getByTestId('breadcrumb-1')).toHaveTextContent('Supply Chain');
      expect(screen.getByTestId('breadcrumb-2')).toHaveTextContent('Container Images');
    });

    it('renders Refresh action', () => {
      mockUseContainerImages.mockReturnValue({
        images: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImagesPage />
        </BrowserRouter>
      );

      const actions = screen.getByTestId('page-actions');
      expect(actions).toHaveTextContent('Refresh');
    });
  });
});
