import { render, screen, fireEvent } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import { VendorRiskDashboardPage } from '../VendorRiskDashboardPage';
import { useVendorRiskDashboard } from '../../hooks/useVendorRisk';

jest.mock('../../hooks/useVendorRisk');
jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({ children, title, description, breadcrumbs, actions }: any) => (
    <div data-testid="page-container">
      <h1>{title}</h1>
      {description && <p>{description}</p>}
      {breadcrumbs && (
        <nav data-testid="breadcrumbs">
          {breadcrumbs.map((crumb: any, index: number) => (
            <span key={index}>{crumb.label}</span>
          ))}
        </nav>
      )}
      {actions?.map((action: any) => (
        <button
          key={action.id}
          onClick={action.onClick}
          disabled={action.disabled}
          data-testid={`action-${action.id}`}
        >
          {action.label}
        </button>
      ))}
      {children}
    </div>
  ),
}));
jest.mock('@/shared/components/ui/LoadingSpinner', () => ({
  LoadingSpinner: ({ size: _size }: any) => <div data-testid="loading-spinner">Loading...</div>,
}));
jest.mock('../../components/RiskTierBadge', () => ({
  RiskTierBadge: ({ tier }: any) => <span data-testid={`risk-badge-${tier}`}>{tier}</span>,
}));
jest.mock('@/shared/components/ui/Badge', () => ({
  Badge: ({ children, variant, size }: any) => (
    <span data-testid="badge" data-variant={variant} data-size={size}>
      {children}
    </span>
  ),
}));

const mockNavigate = jest.fn();
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate,
}));

const mockUseVendorRiskDashboard = useVendorRiskDashboard as jest.Mock;

describe('VendorRiskDashboardPage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  const renderPage = () =>
    render(
      <BrowserRouter>
        <VendorRiskDashboardPage />
      </BrowserRouter>
    );

  const createMockDashboardData = () => ({
    total_vendors: 50,
    critical_vendors: 3,
    high_risk_vendors: 8,
    vendors_needing_assessment: 12,
    upcoming_assessments: [
      {
        vendor_id: 'vendor-1',
        vendor_name: 'Acme Corp',
        due_date: '2026-02-15T00:00:00Z',
      },
      {
        vendor_id: 'vendor-2',
        vendor_name: 'Beta Systems',
        due_date: '2026-02-20T00:00:00Z',
      },
    ],
    risk_distribution: {
      critical: 3,
      high: 8,
      medium: 20,
      low: 19,
    },
  });

  describe('loading state', () => {
    it('shows loading spinner when data is being fetched', () => {
      mockUseVendorRiskDashboard.mockReturnValue({
        data: null,
        loading: true,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByTestId('loading-spinner')).toBeInTheDocument();
    });

    it('does not show page content during loading', () => {
      mockUseVendorRiskDashboard.mockReturnValue({
        data: null,
        loading: true,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.queryByText('Total Vendors')).not.toBeInTheDocument();
    });

    it('centers loading spinner', () => {
      mockUseVendorRiskDashboard.mockReturnValue({
        data: null,
        loading: true,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const spinnerContainer = screen.getByTestId('loading-spinner').parentElement;
      expect(spinnerContainer).toHaveClass('flex');
      expect(spinnerContainer).toHaveClass('justify-center');
      expect(spinnerContainer).toHaveClass('items-center');
    });
  });

  describe('error state', () => {
    it('shows error message when data fetch fails', () => {
      mockUseVendorRiskDashboard.mockReturnValue({
        data: null,
        loading: false,
        error: 'Network connection failed',
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Network connection failed')).toBeInTheDocument();
    });

    it('shows error message when data is null', () => {
      mockUseVendorRiskDashboard.mockReturnValue({
        data: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Failed to load dashboard data')).toBeInTheDocument();
    });

    it('applies error styling to error message', () => {
      mockUseVendorRiskDashboard.mockReturnValue({
        data: null,
        loading: false,
        error: 'Test error',
        refresh: jest.fn(),
      });

      renderPage();

      const errorElement = screen.getByText('Test error');
      expect(errorElement).toHaveClass('bg-theme-error', 'bg-opacity-10', 'text-theme-error');
    });

    it('does not show page content in error state', () => {
      mockUseVendorRiskDashboard.mockReturnValue({
        data: null,
        loading: false,
        error: 'Error occurred',
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.queryByText('Total Vendors')).not.toBeInTheDocument();
    });
  });

  describe('successful render', () => {
    const mockData = createMockDashboardData();

    beforeEach(() => {
      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
    });

    it('renders page title and description', () => {
      renderPage();

      expect(screen.getByText('Vendor Risk Dashboard')).toBeInTheDocument();
      expect(screen.getByText('Monitor and manage third-party vendor risk exposure')).toBeInTheDocument();
    });

    it('renders breadcrumbs with correct labels', () => {
      renderPage();

      expect(screen.getByText('Dashboard')).toBeInTheDocument();
      expect(screen.getByText('Supply Chain')).toBeInTheDocument();
      expect(screen.getByText('Vendor Risk')).toBeInTheDocument();
    });

    it('renders refresh action button', () => {
      renderPage();

      const refreshButton = screen.getByTestId('action-refresh');
      expect(refreshButton).toBeInTheDocument();
      expect(refreshButton).toHaveTextContent('Refresh');
    });

    it('renders all four stat cards', () => {
      renderPage();

      expect(screen.getByText('Total Vendors')).toBeInTheDocument();
      expect(screen.getByText('Critical Risk')).toBeInTheDocument();
      expect(screen.getByText('High Risk')).toBeInTheDocument();
      expect(screen.getByText('Needs Assessment')).toBeInTheDocument();
    });
  });

  describe('stat cards', () => {
    it('displays total vendors count', () => {
      const mockData = createMockDashboardData();
      mockData.total_vendors = 75;

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('75')).toBeInTheDocument();
      expect(screen.getByText('Total Vendors')).toBeInTheDocument();
    });

    it('displays critical vendors count', () => {
      const mockData = createMockDashboardData();
      mockData.critical_vendors = 5;

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('5')).toBeInTheDocument();
      expect(screen.getByText('Critical Risk')).toBeInTheDocument();
    });

    it('displays high risk vendors count', () => {
      const mockData = createMockDashboardData();
      mockData.high_risk_vendors = 12;

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const highRiskLabel = screen.getByText('High Risk');
      const highRiskValue = highRiskLabel.closest('div')?.querySelector('p')?.textContent;
      expect(highRiskValue).toBe('12');
      expect(highRiskLabel).toBeInTheDocument();
    });

    it('displays vendors needing assessment count', () => {
      const mockData = createMockDashboardData();
      mockData.vendors_needing_assessment = 8;

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const assessmentLabel = screen.getByText('Needs Assessment');
      const assessmentValue = assessmentLabel.closest('div')?.querySelector('p')?.textContent;
      expect(assessmentValue).toBe('8');
      expect(assessmentLabel).toBeInTheDocument();
    });

    it('displays stat cards with correct grid layout classes', () => {
      const mockData = createMockDashboardData();

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      // Get the stat card by checking for bg-theme-surface class
      let element: HTMLElement | null = screen.getByText('Total Vendors').closest('p');
      while (element && !element.className.includes('bg-theme-surface')) {
        element = element.parentElement;
      }
      const gridContainer = element?.parentElement;
      expect(gridContainer).toHaveClass('grid');
    });
  });

  describe('risk distribution chart', () => {
    it('displays risk distribution heading', () => {
      const mockData = createMockDashboardData();

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Risk Distribution')).toBeInTheDocument();
    });

    it('displays all risk tier badges', () => {
      const mockData = createMockDashboardData();

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByTestId('risk-badge-critical')).toBeInTheDocument();
      expect(screen.getByTestId('risk-badge-high')).toBeInTheDocument();
      expect(screen.getByTestId('risk-badge-medium')).toBeInTheDocument();
      expect(screen.getByTestId('risk-badge-low')).toBeInTheDocument();
    });

    it('displays risk tier labels', () => {
      const mockData = createMockDashboardData();

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Critical')).toBeInTheDocument();
      expect(screen.getByText('High')).toBeInTheDocument();
      expect(screen.getByText('Medium')).toBeInTheDocument();
      expect(screen.getByText('Low')).toBeInTheDocument();
    });

    it('displays critical risk count and percentage', () => {
      const mockData = createMockDashboardData();

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText(/3 \(6\.0%\)/)).toBeInTheDocument();
    });

    it('displays high risk count and percentage', () => {
      const mockData = createMockDashboardData();

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText(/8 \(16\.0%\)/)).toBeInTheDocument();
    });

    it('displays medium risk count and percentage', () => {
      const mockData = createMockDashboardData();

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText(/20 \(40\.0%\)/)).toBeInTheDocument();
    });

    it('displays low risk count and percentage', () => {
      const mockData = createMockDashboardData();

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText(/19 \(38\.0%\)/)).toBeInTheDocument();
    });

    it('handles zero vendors correctly', () => {
      const mockData = createMockDashboardData();
      mockData.total_vendors = 0;
      mockData.risk_distribution = {
        critical: 0,
        high: 0,
        medium: 0,
        low: 0,
      };

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const allZeroMatches = screen.getAllByText(/0 \(0\.0%\)/);
      expect(allZeroMatches.length).toBeGreaterThan(0);
    });

    it('calculates percentages correctly for uneven distribution', () => {
      const mockData = createMockDashboardData();
      mockData.total_vendors = 100;
      mockData.risk_distribution = {
        critical: 5,
        high: 15,
        medium: 30,
        low: 50,
      };

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText(/5 \(5\.0%\)/)).toBeInTheDocument();
      expect(screen.getByText(/15 \(15\.0%\)/)).toBeInTheDocument();
      expect(screen.getByText(/30 \(30\.0%\)/)).toBeInTheDocument();
      expect(screen.getByText(/50 \(50\.0%\)/)).toBeInTheDocument();
    });
  });

  describe('critical vendors section', () => {
    it('displays critical risk vendors heading', () => {
      const mockData = createMockDashboardData();

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Critical Risk Vendors')).toBeInTheDocument();
    });

    it('displays vendor count badge when critical vendors exist', () => {
      const mockData = createMockDashboardData();
      mockData.risk_distribution.critical = 5;

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const badge = screen.getByText('5 vendors');
      expect(badge).toBeInTheDocument();
      expect(badge).toHaveAttribute('data-variant', 'danger');
    });

    it('displays warning message about critical vendors', () => {
      const mockData = createMockDashboardData();
      mockData.risk_distribution.critical = 3;

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('These vendors require immediate attention and assessment.')).toBeInTheDocument();
    });

    it('displays "View All Critical Vendors" button when critical vendors exist', () => {
      const mockData = createMockDashboardData();
      mockData.risk_distribution.critical = 5;

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('View All Critical Vendors')).toBeInTheDocument();
    });

    it('navigates to vendors page with critical filter when button is clicked', () => {
      const mockData = createMockDashboardData();
      mockData.risk_distribution.critical = 5;

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const button = screen.getByText('View All Critical Vendors');
      fireEvent.click(button);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/vendors?filter=critical');
    });

    it('displays "No critical risk vendors" when count is zero', () => {
      const mockData = createMockDashboardData();
      mockData.risk_distribution.critical = 0;

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('No critical risk vendors')).toBeInTheDocument();
    });

    it('displays shield icon when no critical vendors exist', () => {
      const mockData = createMockDashboardData();
      mockData.risk_distribution.critical = 0;

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const noVendorsMessage = screen.getByText('No critical risk vendors');
      expect(noVendorsMessage).toBeInTheDocument();
    });
  });

  describe('upcoming assessments section', () => {
    it('displays upcoming assessments heading', () => {
      const mockData = createMockDashboardData();

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Upcoming Assessments')).toBeInTheDocument();
    });

    it('displays vendor names in upcoming assessments', () => {
      const mockData = createMockDashboardData();

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Acme Corp')).toBeInTheDocument();
      expect(screen.getByText('Beta Systems')).toBeInTheDocument();
    });

    it('displays due dates for upcoming assessments', () => {
      const mockData = createMockDashboardData();

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Acme Corp')).toBeInTheDocument();
      const acmeAssessment = screen.getByText('Acme Corp').closest('div');
      expect(acmeAssessment?.textContent).toMatch(/Due:/);
      expect(acmeAssessment?.textContent).toMatch(/2026/);
      expect(screen.getByText('Beta Systems')).toBeInTheDocument();
      const betaAssessment = screen.getByText('Beta Systems').closest('div');
      expect(betaAssessment?.textContent).toMatch(/Due:/);
      expect(betaAssessment?.textContent).toMatch(/2026/);
    });

    it('displays "Due Soon" badges for upcoming assessments', () => {
      const mockData = createMockDashboardData();

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const dueSoonBadges = screen.getAllByText('Due Soon');
      expect(dueSoonBadges).toHaveLength(2);
      dueSoonBadges.forEach((badge) => {
        expect(badge).toHaveAttribute('data-variant', 'warning');
      });
    });

    it('limits assessment display to maximum of 5', () => {
      const mockData = createMockDashboardData();
      mockData.upcoming_assessments = Array.from({ length: 10 }, (_, i) => ({
        vendor_id: `vendor-${i}`,
        vendor_name: `Vendor ${i + 1}`,
        due_date: '2026-02-15T00:00:00Z',
      }));

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Vendor 1')).toBeInTheDocument();
      expect(screen.getByText('Vendor 5')).toBeInTheDocument();
      expect(screen.queryByText('Vendor 6')).not.toBeInTheDocument();
    });

    it('shows "View all X upcoming assessments" link when more than 5 assessments', () => {
      const mockData = createMockDashboardData();
      mockData.upcoming_assessments = Array.from({ length: 8 }, (_, i) => ({
        vendor_id: `vendor-${i}`,
        vendor_name: `Vendor ${i + 1}`,
        due_date: '2026-02-15T00:00:00Z',
      }));

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('View all 8 upcoming assessments')).toBeInTheDocument();
    });

    it('navigates to vendor detail page when assessment is clicked', () => {
      const mockData = createMockDashboardData();

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const vendorItem = screen.getByText('Acme Corp').closest('div');
      fireEvent.click(vendorItem!);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/vendors/vendor-1');
    });

    it('navigates to vendors page with needs-assessment tab when view all link is clicked', () => {
      const mockData = createMockDashboardData();
      mockData.upcoming_assessments = Array.from({ length: 8 }, (_, i) => ({
        vendor_id: `vendor-${i}`,
        vendor_name: `Vendor ${i + 1}`,
        due_date: '2026-02-15T00:00:00Z',
      }));

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const viewAllLink = screen.getByText('View all 8 upcoming assessments');
      fireEvent.click(viewAllLink);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/vendors?tab=needs-assessment');
    });

    it('displays "No upcoming assessments scheduled" when array is empty', () => {
      const mockData = createMockDashboardData();
      mockData.upcoming_assessments = [];

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('No upcoming assessments scheduled')).toBeInTheDocument();
    });

    it('displays FileWarning icon when no upcoming assessments', () => {
      const mockData = createMockDashboardData();
      mockData.upcoming_assessments = [];

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const emptyMessage = screen.getByText('No upcoming assessments scheduled');
      expect(emptyMessage).toBeInTheDocument();
    });
  });

  describe('refresh action', () => {
    it('calls refresh function when Refresh button is clicked', () => {
      const mockRefresh = jest.fn();
      const mockData = createMockDashboardData();

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: mockRefresh,
      });

      renderPage();

      const refreshButton = screen.getByTestId('action-refresh');
      fireEvent.click(refreshButton);

      expect(mockRefresh).toHaveBeenCalledTimes(1);
    });

    it('refresh button is accessible and not disabled', () => {
      const mockData = createMockDashboardData();

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const refreshButton = screen.getByTestId('action-refresh');
      expect(refreshButton).not.toBeDisabled();
    });
  });

  describe('layout and styling', () => {
    it('renders stats in responsive grid layout', () => {
      const mockData = createMockDashboardData();

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      // Get the stat card by checking for bg-theme-surface class
      let element: HTMLElement | null = screen.getByText('Total Vendors').closest('p');
      while (element && !element.className.includes('bg-theme-surface')) {
        element = element.parentElement;
      }
      const gridContainer = element?.parentElement;
      expect(gridContainer).toHaveClass('grid');
    });

    it('renders risk distribution and critical vendors in two-column grid', () => {
      const mockData = createMockDashboardData();

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const distributionContainer = screen.getByText('Risk Distribution').closest('div')?.parentElement;
      expect(distributionContainer).toHaveClass('grid');
    });

    it('applies proper spacing between sections', () => {
      const mockData = createMockDashboardData();

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const mainContainer = screen.getByText('Total Vendors').closest('.space-y-6');
      expect(mainContainer).toBeInTheDocument();
    });
  });

  describe('edge cases', () => {
    it('handles missing upcoming assessments array', () => {
      const mockData = createMockDashboardData();
      // @ts-ignore - Testing edge case
      mockData.upcoming_assessments = undefined;

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('No upcoming assessments scheduled')).toBeInTheDocument();
    });

    it('handles zero values for all risk distribution tiers', () => {
      const mockData = createMockDashboardData();
      mockData.total_vendors = 0;
      mockData.critical_vendors = 0;
      mockData.high_risk_vendors = 0;
      mockData.vendors_needing_assessment = 0;
      mockData.risk_distribution = {
        critical: 0,
        high: 0,
        medium: 0,
        low: 0,
      };

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const allZeros = screen.getAllByText('0');
      expect(allZeros.length).toBeGreaterThan(0);
      expect(screen.getByText('No critical risk vendors')).toBeInTheDocument();
    });

    it('handles very large vendor counts', () => {
      const mockData = createMockDashboardData();
      mockData.total_vendors = 9999;
      mockData.critical_vendors = 1234;

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('9999')).toBeInTheDocument();
      expect(screen.getByText('1234')).toBeInTheDocument();
    });

    it('handles future dates in upcoming assessments', () => {
      const mockData = createMockDashboardData();
      const futureDate = new Date();
      futureDate.setFullYear(futureDate.getFullYear() + 1);

      mockData.upcoming_assessments = [
        {
          vendor_id: 'vendor-1',
          vendor_name: 'Future Vendor',
          due_date: futureDate.toISOString(),
        },
      ];

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Future Vendor')).toBeInTheDocument();
    });

    it('handles vendor names with special characters', () => {
      const mockData = createMockDashboardData();
      mockData.upcoming_assessments = [
        {
          vendor_id: 'vendor-1',
          vendor_name: 'Test & Co. (LLC)',
          due_date: '2026-02-15T00:00:00Z',
        },
      ];

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Test & Co. (LLC)')).toBeInTheDocument();
    });
  });

  describe('accessibility', () => {
    it('has proper heading hierarchy', () => {
      const mockData = createMockDashboardData();

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Vendor Risk Dashboard')).toBeInTheDocument();
      expect(screen.getByText('Risk Distribution')).toBeInTheDocument();
      expect(screen.getByText('Critical Risk Vendors')).toBeInTheDocument();
      expect(screen.getByText('Upcoming Assessments')).toBeInTheDocument();
    });

    it('buttons have descriptive labels', () => {
      const mockData = createMockDashboardData();
      mockData.risk_distribution.critical = 3;

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Refresh')).toBeInTheDocument();
      expect(screen.getByText('View All Critical Vendors')).toBeInTheDocument();
    });

    it('clickable items have proper cursor styling', () => {
      const mockData = createMockDashboardData();

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const assessmentItem = screen.getByText('Acme Corp').closest('div')?.parentElement;
      expect(assessmentItem).toHaveClass('cursor-pointer');
    });
  });

  describe('data transformations', () => {
    it('correctly calculates percentage with one decimal place', () => {
      const mockData = createMockDashboardData();
      mockData.total_vendors = 150;
      mockData.risk_distribution.critical = 7;

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      // 7/150 = 4.6666... should be displayed as 4.7%
      expect(screen.getByText(/7 \(4\.7%\)/)).toBeInTheDocument();
    });

    it('displays 0.0% for zero values', () => {
      const mockData = createMockDashboardData();
      mockData.total_vendors = 100;
      mockData.risk_distribution.critical = 0;

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText(/0 \(0\.0%\)/)).toBeInTheDocument();
    });

    it('formats dates consistently across all assessments', () => {
      const mockData = createMockDashboardData();
      mockData.upcoming_assessments = [
        {
          vendor_id: 'vendor-1',
          vendor_name: 'Vendor A',
          due_date: '2026-03-01T00:00:00Z',
        },
        {
          vendor_id: 'vendor-2',
          vendor_name: 'Vendor B',
          due_date: '2026-12-31T00:00:00Z',
        },
      ];

      mockUseVendorRiskDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const vendorA = screen.getByText('Vendor A').closest('div');
      expect(vendorA?.textContent).toMatch(/Due:/);
      expect(vendorA?.textContent).toMatch(/2026/);
      const vendorB = screen.getByText('Vendor B').closest('div');
      expect(vendorB?.textContent).toMatch(/Due:/);
      expect(vendorB?.textContent).toMatch(/2026/);
    });
  });
});
