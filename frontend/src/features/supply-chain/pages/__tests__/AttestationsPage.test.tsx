import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { BrowserRouter, useNavigate } from 'react-router-dom';
import { AttestationsPage } from '../AttestationsPage';
import { useAttestations } from '../../hooks/useAttestations';
import {
  createMockAttestation,
  createMockPagination,
} from '../../testing/mockFactories';

// Mock dependencies
jest.mock('../../hooks/useAttestations');
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: jest.fn(),
}));
jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({ children, title, description, breadcrumbs, actions }: any) => (
    <div data-testid="page-container">
      <h1>{title}</h1>
      <p>{description}</p>
      {breadcrumbs && (
        <nav data-testid="breadcrumbs">
          {breadcrumbs.map((crumb: any, i: number) => (
            <span key={i}>{crumb.label}</span>
          ))}
        </nav>
      )}
      {actions && (
        <div data-testid="page-actions">
          {actions.map((action: any) => (
            <button
              key={action.id}
              data-testid={`action-${action.id}`}
              onClick={action.onClick}
              disabled={action.disabled}
            >
              {action.label}
            </button>
          ))}
        </div>
      )}
      {children}
    </div>
  ),
}));
jest.mock('@/shared/components/ui/TabContainer', () => ({
  TabContainer: ({ tabs, activeTab, onTabChange }: any) => (
    <div data-testid="tab-container">
      {tabs.map((t: any) => (
        <button
          key={t.id}
          data-testid={`tab-${t.id}`}
          onClick={() => onTabChange(t.id)}
          className={activeTab === t.id ? 'active' : ''}
        >
          {t.label}
        </button>
      ))}
    </div>
  ),
}));
jest.mock('@/shared/components/ui/DataTable', () => ({
  DataTable: ({ columns, data, loading, pagination, onPageChange, onRowClick, emptyState }: any) => (
    <div data-testid="data-table">
      {loading ? (
        <div>Loading table...</div>
      ) : data.length === 0 ? (
        <div data-testid="empty-state">
          <div>{emptyState.title}</div>
          <div>{emptyState.description}</div>
        </div>
      ) : (
        <>
          <table>
            <thead>
              <tr>
                {columns.map((col: any) => (
                  <th key={col.key}>{col.header}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {data.map((item: any, idx: number) => (
                <tr
                  key={item.id}
                  data-testid={`row-${idx}`}
                  onClick={() => onRowClick && onRowClick(item)}
                  style={{ cursor: 'pointer' }}
                >
                  {columns.map((col: any) => (
                    <td key={col.key} data-testid={`cell-${col.key}-${idx}`}>
                      {col.render ? col.render(item) : item[col.key]}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
          {pagination && (
            <div data-testid="pagination">
              <button
                data-testid="prev-page"
                onClick={() => onPageChange(pagination.current_page - 1)}
                disabled={pagination.current_page === 1}
              >
                Previous
              </button>
              <span>
                Page {pagination.current_page} of {pagination.total_pages}
              </span>
              <button
                data-testid="next-page"
                onClick={() => onPageChange(pagination.current_page + 1)}
                disabled={pagination.current_page === pagination.total_pages}
              >
                Next
              </button>
            </div>
          )}
        </>
      )}
    </div>
  ),
}));
jest.mock('@/shared/components/ui/LoadingSpinner', () => ({
  LoadingSpinner: ({ size }: any) => (
    <div data-testid="loading-spinner" data-size={size}>
      Loading...
    </div>
  ),
}));
jest.mock('@/shared/components/ui/ErrorAlert', () => ({
  __esModule: true,
  default: ({ message }: any) => <div data-testid="error-alert">{message}</div>,
}));
jest.mock('@/shared/components/ui/Badge', () => ({
  Badge: ({ children, variant, size }: any) => (
    <span data-testid="badge" data-variant={variant} data-size={size}>
      {children}
    </span>
  ),
}));
jest.mock('../../components/shared/StatusBadge', () => ({
  StatusBadge: ({ status, size }: any) => (
    <span data-testid="status-badge" data-status={status} data-size={size}>
      {status}
    </span>
  ),
}));
jest.mock('lucide-react', () => ({
  FileSignature: ({ className }: { className?: string }) => (
    <span data-testid="file-signature-icon" className={className} />
  ),
  Check: ({ className }: { className?: string }) => (
    <span data-testid="check-icon" className={className}>✓</span>
  ),
  X: ({ className }: { className?: string }) => (
    <span data-testid="x-icon" className={className}>✗</span>
  ),
}));

const mockUseAttestations = useAttestations as jest.MockedFunction<typeof useAttestations>;
const mockNavigate = jest.fn();

describe('AttestationsPage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    (useNavigate as jest.Mock).mockReturnValue(mockNavigate);
  });

  const renderPage = () => {
    return render(
      <BrowserRouter>
        <AttestationsPage />
      </BrowserRouter>
    );
  };

  describe('Loading State', () => {
    it('shows loading spinner when data is loading', () => {
      mockUseAttestations.mockReturnValue({
        attestations: [],
        pagination: null,
        loading: true,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByTestId('loading-spinner')).toBeInTheDocument();
      expect(screen.getByTestId('loading-spinner')).toHaveAttribute('data-size', 'lg');
    });

    it('does not show data table during loading', () => {
      mockUseAttestations.mockReturnValue({
        attestations: [],
        pagination: null,
        loading: true,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.queryByTestId('data-table')).not.toBeInTheDocument();
    });
  });

  describe('Error State', () => {
    it('shows error alert when there is an error', () => {
      const errorMessage = 'Failed to load attestations';
      mockUseAttestations.mockReturnValue({
        attestations: [],
        pagination: null,
        loading: false,
        error: errorMessage,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByTestId('error-alert')).toBeInTheDocument();
      expect(screen.getByTestId('error-alert')).toHaveTextContent(errorMessage);
    });

    it('still shows data table when there is an error', () => {
      mockUseAttestations.mockReturnValue({
        attestations: [],
        pagination: null,
        loading: false,
        error: 'Some error',
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByTestId('data-table')).toBeInTheDocument();
    });
  });

  describe('Empty State', () => {
    it('shows empty state message when no attestations exist', () => {
      mockUseAttestations.mockReturnValue({
        attestations: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByTestId('empty-state')).toBeInTheDocument();
      expect(screen.getByText('No attestations found')).toBeInTheDocument();
    });

    it('shows CI/CD message in empty state for all attestations tab', () => {
      mockUseAttestations.mockReturnValue({
        attestations: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText(/Attestations are generated automatically via CI\/CD pipelines/)).toBeInTheDocument();
    });
  });

  describe('Page Layout', () => {
    it('renders page container with correct title', () => {
      mockUseAttestations.mockReturnValue({
        attestations: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByRole('heading', { name: 'Attestations' })).toBeInTheDocument();
    });

    it('renders page container with correct description', () => {
      mockUseAttestations.mockReturnValue({
        attestations: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Manage cryptographic attestations for supply chain artifacts')).toBeInTheDocument();
    });

    it('renders breadcrumbs correctly', () => {
      mockUseAttestations.mockReturnValue({
        attestations: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const breadcrumbs = screen.getByTestId('breadcrumbs');
      expect(breadcrumbs).toHaveTextContent('Dashboard');
      expect(breadcrumbs).toHaveTextContent('Supply Chain');
      expect(breadcrumbs).toHaveTextContent('Attestations');
    });
  });

  describe('Attestations List', () => {
    it('renders attestations list with data', () => {
      const attestations = [
        createMockAttestation({ id: 'att-1', subject_name: 'app:v1.0' }),
        createMockAttestation({ id: 'att-2', subject_name: 'app:v2.0' }),
      ];

      mockUseAttestations.mockReturnValue({
        attestations,
        pagination: createMockPagination(),
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByTestId('data-table')).toBeInTheDocument();
      expect(screen.getByTestId('row-0')).toBeInTheDocument();
      expect(screen.getByTestId('row-1')).toBeInTheDocument();
    });

    it('renders correct number of attestations', () => {
      const attestations = [
        createMockAttestation({ id: 'att-1' }),
        createMockAttestation({ id: 'att-2' }),
        createMockAttestation({ id: 'att-3' }),
      ];

      mockUseAttestations.mockReturnValue({
        attestations,
        pagination: createMockPagination({ total_count: 3 }),
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const rows = screen.getAllByTestId(/^row-\d+$/);
      expect(rows).toHaveLength(3);
    });
  });

  describe('Subject Column', () => {
    it('shows attestation subject name', () => {
      const attestations = [
        createMockAttestation({ subject_name: 'myapp:latest' }),
      ];

      mockUseAttestations.mockReturnValue({
        attestations,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('myapp:latest')).toBeInTheDocument();
    });

    it('shows truncated digest', () => {
      const attestations = [
        createMockAttestation({
          subject_digest: 'sha256:1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        }),
      ];

      mockUseAttestations.mockReturnValue({
        attestations,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText(/1234567890ab\.\.\./)).toBeInTheDocument();
    });

    it('truncates digest to first 12 characters', () => {
      const attestations = [
        createMockAttestation({
          subject_digest: 'sha256:abcdefghijklmnopqrstuvwxyz',
        }),
      ];

      mockUseAttestations.mockReturnValue({
        attestations,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText(/abcdefghijkl\.\.\./)).toBeInTheDocument();
    });
  });

  describe('Type Column', () => {
    it('shows SLSA Provenance label for slsa_provenance type', () => {
      const attestations = [
        createMockAttestation({ attestation_type: 'slsa_provenance' }),
      ];

      mockUseAttestations.mockReturnValue({
        attestations,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const cell = screen.getByTestId('cell-type-0');
      expect(cell).toHaveTextContent('SLSA Provenance');
    });

    it('shows SBOM label for sbom type', () => {
      const attestations = [
        createMockAttestation({ attestation_type: 'sbom' }),
      ];

      mockUseAttestations.mockReturnValue({
        attestations,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const cell = screen.getByTestId('cell-type-0');
      expect(cell).toHaveTextContent('SBOM');
    });

    it('shows Vulnerability Scan label for vulnerability_scan type', () => {
      const attestations = [
        createMockAttestation({ attestation_type: 'vulnerability_scan' }),
      ];

      mockUseAttestations.mockReturnValue({
        attestations,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const cell = screen.getByTestId('cell-type-0');
      expect(cell).toHaveTextContent('Vulnerability Scan');
    });

    it('shows Custom label for custom type', () => {
      const attestations = [
        createMockAttestation({ attestation_type: 'custom' }),
      ];

      mockUseAttestations.mockReturnValue({
        attestations,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const cell = screen.getByTestId('cell-type-0');
      expect(cell).toHaveTextContent('Custom');
    });
  });

  describe('SLSA Level Column', () => {
    it('shows Level 1 badge with secondary variant', () => {
      const attestations = [
        createMockAttestation({ slsa_level: 1 }),
      ];

      mockUseAttestations.mockReturnValue({
        attestations,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const badge = screen.getByText('Level 1');
      expect(badge).toHaveAttribute('data-variant', 'secondary');
    });

    it('shows Level 2 badge with warning variant', () => {
      const attestations = [
        createMockAttestation({ slsa_level: 2 }),
      ];

      mockUseAttestations.mockReturnValue({
        attestations,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const badge = screen.getByText('Level 2');
      expect(badge).toHaveAttribute('data-variant', 'warning');
    });

    it('shows Level 3 badge with success variant', () => {
      const attestations = [
        createMockAttestation({ slsa_level: 3 }),
      ];

      mockUseAttestations.mockReturnValue({
        attestations,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const badge = screen.getByText('Level 3');
      expect(badge).toHaveAttribute('data-variant', 'success');
    });

    it('shows dash for null SLSA level', () => {
      const attestations = [
        createMockAttestation({ slsa_level: null }),
      ];

      mockUseAttestations.mockReturnValue({
        attestations,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('-')).toBeInTheDocument();
    });
  });

  describe('Signed Column', () => {
    it('shows check icon when attestation is signed', () => {
      const attestations = [
        createMockAttestation({ signed: true }),
      ];

      mockUseAttestations.mockReturnValue({
        attestations,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const cell = screen.getByTestId('cell-signed-0');
      expect(cell.querySelector('[data-testid="check-icon"]')).toBeInTheDocument();
    });

    it('shows X icon when attestation is not signed', () => {
      const attestations = [
        createMockAttestation({ signed: false }),
      ];

      mockUseAttestations.mockReturnValue({
        attestations,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const cell = screen.getByTestId('cell-signed-0');
      expect(cell.querySelector('[data-testid="x-icon"]')).toBeInTheDocument();
    });
  });

  describe('Verified Column', () => {
    it('shows StatusBadge with verification status', () => {
      const attestations = [
        createMockAttestation({ verification_status: 'verified' }),
      ];

      mockUseAttestations.mockReturnValue({
        attestations,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const statusBadge = screen.getByTestId('status-badge');
      expect(statusBadge).toHaveAttribute('data-status', 'verified');
    });

    it('passes size prop to StatusBadge', () => {
      const attestations = [
        createMockAttestation({ verification_status: 'unverified' }),
      ];

      mockUseAttestations.mockReturnValue({
        attestations,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const statusBadge = screen.getByTestId('status-badge');
      expect(statusBadge).toHaveAttribute('data-size', 'sm');
    });
  });

  describe('Rekor Column', () => {
    it('shows check icon when logged to Rekor', () => {
      const attestations = [
        createMockAttestation({ rekor_logged: true }),
      ];

      mockUseAttestations.mockReturnValue({
        attestations,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const cell = screen.getByTestId('cell-rekor-0');
      expect(cell.querySelector('[data-testid="check-icon"]')).toBeInTheDocument();
    });

    it('shows X icon when not logged to Rekor', () => {
      const attestations = [
        createMockAttestation({ rekor_logged: false }),
      ];

      mockUseAttestations.mockReturnValue({
        attestations,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const cell = screen.getByTestId('cell-rekor-0');
      expect(cell.querySelector('[data-testid="x-icon"]')).toBeInTheDocument();
    });
  });

  describe('Created Column', () => {
    it('shows formatted creation date', () => {
      const attestations = [
        createMockAttestation({
          created_at: '2024-01-15T10:30:00Z',
        }),
      ];

      mockUseAttestations.mockReturnValue({
        attestations,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const cell = screen.getByTestId('cell-created-0');
      expect(cell).toBeInTheDocument();
      expect(cell.textContent).not.toBe('');
    });
  });

  describe('Tab Navigation', () => {
    it('renders all tab buttons', () => {
      mockUseAttestations.mockReturnValue({
        attestations: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByTestId('tab-all')).toBeInTheDocument();
      expect(screen.getByTestId('tab-slsa_provenance')).toBeInTheDocument();
      expect(screen.getByTestId('tab-sbom')).toBeInTheDocument();
      expect(screen.getByTestId('tab-custom')).toBeInTheDocument();
    });

    it('shows All Attestations tab as active by default', () => {
      mockUseAttestations.mockReturnValue({
        attestations: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByTestId('tab-all')).toHaveClass('active');
    });

    it('filters by slsa_provenance when SLSA Provenance tab is clicked', async () => {
      const mockRefresh = jest.fn();
      mockUseAttestations.mockReturnValue({
        attestations: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: mockRefresh,
      });

      renderPage();

      fireEvent.click(screen.getByTestId('tab-slsa_provenance'));

      await waitFor(() => {
        const lastCall = mockUseAttestations.mock.calls[mockUseAttestations.mock.calls.length - 1];
        expect(lastCall?.[0]?.attestationType).toBe('slsa_provenance');
      });
    });

    it('filters by sbom when SBOM tab is clicked', async () => {
      mockUseAttestations.mockReturnValue({
        attestations: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      fireEvent.click(screen.getByTestId('tab-sbom'));

      await waitFor(() => {
        const lastCall = mockUseAttestations.mock.calls[mockUseAttestations.mock.calls.length - 1];
        expect(lastCall?.[0]?.attestationType).toBe('sbom');
      });
    });

    it('filters by custom when Custom tab is clicked', async () => {
      mockUseAttestations.mockReturnValue({
        attestations: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      fireEvent.click(screen.getByTestId('tab-custom'));

      await waitFor(() => {
        const lastCall = mockUseAttestations.mock.calls[mockUseAttestations.mock.calls.length - 1];
        expect(lastCall?.[0]?.attestationType).toBe('custom');
      });
    });

    it('shows all attestations when All tab is clicked', async () => {
      mockUseAttestations.mockReturnValue({
        attestations: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      // Click another tab first
      fireEvent.click(screen.getByTestId('tab-sbom'));

      // Then click All tab
      fireEvent.click(screen.getByTestId('tab-all'));

      await waitFor(() => {
        const lastCall = mockUseAttestations.mock.calls[mockUseAttestations.mock.calls.length - 1];
        expect(lastCall?.[0]?.attestationType).toBeUndefined();
      });
    });
  });

  describe('Pagination', () => {
    it('renders pagination controls when data is paginated', () => {
      mockUseAttestations.mockReturnValue({
        attestations: [createMockAttestation()],
        pagination: createMockPagination({ total_pages: 5 }),
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByTestId('pagination')).toBeInTheDocument();
    });

    it('shows current page number', () => {
      mockUseAttestations.mockReturnValue({
        attestations: [createMockAttestation()],
        pagination: createMockPagination({ current_page: 2, total_pages: 5 }),
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText(/Page 2 of 5/)).toBeInTheDocument();
    });

    it('handles next page click', async () => {
      mockUseAttestations.mockReturnValue({
        attestations: [createMockAttestation()],
        pagination: createMockPagination({ current_page: 1, total_pages: 5 }),
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      fireEvent.click(screen.getByTestId('next-page'));

      await waitFor(() => {
        const lastCall = mockUseAttestations.mock.calls[mockUseAttestations.mock.calls.length - 1];
        expect(lastCall?.[0]?.page).toBe(2);
      });
    });

    it('handles previous page click', async () => {
      mockUseAttestations.mockReturnValue({
        attestations: [createMockAttestation()],
        pagination: createMockPagination({ current_page: 2, total_pages: 5 }),
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      fireEvent.click(screen.getByTestId('prev-page'));

      await waitFor(() => {
        const lastCall = mockUseAttestations.mock.calls[mockUseAttestations.mock.calls.length - 1];
        expect(lastCall?.[0]?.page).toBe(1);
      });
    });
  });

  describe('Row Click Navigation', () => {
    it('navigates to detail page when row is clicked', () => {
      const attestations = [
        createMockAttestation({ id: 'att-123' }),
      ];

      mockUseAttestations.mockReturnValue({
        attestations,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      fireEvent.click(screen.getByTestId('row-0'));

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/attestations/att-123');
    });

    it('navigates to correct detail page for each attestation', () => {
      const attestations = [
        createMockAttestation({ id: 'att-1' }),
        createMockAttestation({ id: 'att-2' }),
      ];

      mockUseAttestations.mockReturnValue({
        attestations,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      fireEvent.click(screen.getByTestId('row-1'));

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/attestations/att-2');
    });
  });

  describe('Tab Container', () => {
    it('renders TabContainer with correct variant', () => {
      mockUseAttestations.mockReturnValue({
        attestations: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByTestId('tab-container')).toBeInTheDocument();
    });

    it('updates active tab on tab change', async () => {
      mockUseAttestations.mockReturnValue({
        attestations: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      fireEvent.click(screen.getByTestId('tab-slsa_provenance'));

      await waitFor(() => {
        expect(screen.getByTestId('tab-slsa_provenance')).toHaveClass('active');
      });
    });
  });

  describe('Tab Change Resets Page', () => {
    it('resets to page 1 when switching tabs', async () => {
      mockUseAttestations.mockReturnValue({
        attestations: [createMockAttestation()],
        pagination: createMockPagination({ current_page: 3, total_pages: 5 }),
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      // Click next page to go to page 4
      fireEvent.click(screen.getByTestId('next-page'));

      // Switch tabs
      fireEvent.click(screen.getByTestId('tab-sbom'));

      await waitFor(() => {
        const lastCall = mockUseAttestations.mock.calls[mockUseAttestations.mock.calls.length - 1];
        expect(lastCall?.[0]?.page).toBe(1);
      });
    });
  });

  describe('Empty State per Tab', () => {
    it('shows specific empty message for SLSA Provenance tab', () => {
      mockUseAttestations.mockReturnValue({
        attestations: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      fireEvent.click(screen.getByTestId('tab-slsa_provenance'));

      expect(screen.getByText('No SLSA Provenance attestations found.')).toBeInTheDocument();
    });

    it('shows specific empty message for SBOM tab', () => {
      mockUseAttestations.mockReturnValue({
        attestations: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      fireEvent.click(screen.getByTestId('tab-sbom'));

      expect(screen.getByText('No SBOM attestations found.')).toBeInTheDocument();
    });

    it('shows specific empty message for Custom tab', () => {
      mockUseAttestations.mockReturnValue({
        attestations: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      fireEvent.click(screen.getByTestId('tab-custom'));

      expect(screen.getByText('No Custom attestations found.')).toBeInTheDocument();
    });
  });

  describe('Hook Integration', () => {
    it('calls useAttestations with correct default parameters', () => {
      mockUseAttestations.mockReturnValue({
        attestations: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(mockUseAttestations).toHaveBeenCalledWith({
        page: 1,
        perPage: 20,
        attestationType: undefined,
      });
    });

    it('passes perPage parameter to hook', () => {
      mockUseAttestations.mockReturnValue({
        attestations: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const lastCall = mockUseAttestations.mock.calls[mockUseAttestations.mock.calls.length - 1];
      expect(lastCall?.[0]?.perPage).toBe(20);
    });
  });

  describe('Refresh functionality', () => {
    it('shows Refresh button in page actions', () => {
      mockUseAttestations.mockReturnValue({
        attestations: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      renderPage();
      expect(screen.getByTestId('action-refresh')).toBeInTheDocument();
      expect(screen.getByText('Refresh')).toBeInTheDocument();
    });

    it('calls refresh when Refresh button is clicked', async () => {
      const mockRefresh = jest.fn();
      mockUseAttestations.mockReturnValue({
        attestations: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: mockRefresh,
      });
      renderPage();
      const refreshButton = screen.getByTestId('action-refresh');
      fireEvent.click(refreshButton);
      await waitFor(() => {
        expect(mockRefresh).toHaveBeenCalled();
      });
    });

    it('disables Refresh button while loading', () => {
      mockUseAttestations.mockReturnValue({
        attestations: [],
        pagination: null,
        loading: true,
        error: null,
        refresh: jest.fn(),
      });
      renderPage();
      const refreshButton = screen.getByTestId('action-refresh');
      expect(refreshButton).toBeDisabled();
    });
  });
});
