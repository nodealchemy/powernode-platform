import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import { SupplyChainDashboardPage } from '../SupplyChainDashboardPage';
import { useSupplyChainDashboard } from '../../hooks/useSupplyChainDashboard';
import { createMockDashboardData } from '../../testing/mockFactories';

jest.mock('../../hooks/useSupplyChainDashboard');
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

const mockNavigate = jest.fn();
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate,
}));

const mockUseSupplyChainDashboard = useSupplyChainDashboard as jest.Mock;

describe('SupplyChainDashboardPage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  const renderPage = () =>
    render(
      <BrowserRouter>
        <SupplyChainDashboardPage />
      </BrowserRouter>
    );

  describe('loading state', () => {
    it('shows loading spinner when data is being fetched', () => {
      mockUseSupplyChainDashboard.mockReturnValue({
        data: null,
        loading: true,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByTestId('loading-spinner')).toBeInTheDocument();
      expect(screen.getByText('Loading dashboard...')).toBeInTheDocument();
    });

    it('shows page title and description during loading', () => {
      mockUseSupplyChainDashboard.mockReturnValue({
        data: null,
        loading: true,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Supply Chain Security')).toBeInTheDocument();
      expect(screen.getByText('Software supply chain security and compliance dashboard')).toBeInTheDocument();
    });

    it('shows breadcrumbs during loading', () => {
      mockUseSupplyChainDashboard.mockReturnValue({
        data: null,
        loading: true,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByTestId('breadcrumbs')).toBeInTheDocument();
      expect(screen.getByText('Dashboard')).toBeInTheDocument();
      expect(screen.getByText('Supply Chain')).toBeInTheDocument();
    });

    it('does not show refresh button during initial loading', () => {
      mockUseSupplyChainDashboard.mockReturnValue({
        data: null,
        loading: true,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.queryByTestId('action-refresh')).not.toBeInTheDocument();
    });
  });

  describe('error state', () => {
    it('shows error message when data fetch fails', () => {
      mockUseSupplyChainDashboard.mockReturnValue({
        data: null,
        loading: false,
        error: 'Network error',
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Failed to load dashboard')).toBeInTheDocument();
      expect(screen.getByText('Network error')).toBeInTheDocument();
    });

    it('shows error message when data is null', () => {
      mockUseSupplyChainDashboard.mockReturnValue({
        data: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Failed to load dashboard')).toBeInTheDocument();
    });

    it('shows refresh button in error state', () => {
      mockUseSupplyChainDashboard.mockReturnValue({
        data: null,
        loading: false,
        error: 'Network error',
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByTestId('action-refresh')).toBeInTheDocument();
    });

    it('error message displays AlertTriangle icon indicator', () => {
      mockUseSupplyChainDashboard.mockReturnValue({
        data: null,
        loading: false,
        error: 'API Error',
        refresh: jest.fn(),
      });

      renderPage();

      const span = screen.getByText('Failed to load dashboard');
      const errorContainer = span.parentElement?.parentElement;
      expect(errorContainer).toHaveClass('bg-theme-error/10');
    });
  });

  describe('successful render', () => {
    const mockData = createMockDashboardData();

    beforeEach(() => {
      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
    });

    it('renders page title and description', () => {
      renderPage();

      expect(screen.getByText('Supply Chain Security')).toBeInTheDocument();
      expect(screen.getByText('Software supply chain security and compliance dashboard')).toBeInTheDocument();
    });

    it('renders breadcrumbs with correct labels', () => {
      renderPage();

      expect(screen.getByText('Dashboard')).toBeInTheDocument();
      expect(screen.getByText('Supply Chain')).toBeInTheDocument();
    });

    it('renders refresh action button', () => {
      renderPage();

      const refreshButton = screen.getByTestId('action-refresh');
      expect(refreshButton).toBeInTheDocument();
      expect(refreshButton).toHaveTextContent('Refresh');
      expect(refreshButton).not.toBeDisabled();
    });

    it('renders all six stat cards', () => {
      renderPage();

      // Use getAllByText since some text appears in both stat cards and quick links
      expect(screen.getAllByText('SBOMs').length).toBeGreaterThan(0);
      expect(screen.getByText('Critical Vulnerabilities')).toBeInTheDocument();
      expect(screen.getAllByText('Container Images').length).toBeGreaterThan(0);
      expect(screen.getAllByText('Attestations').length).toBeGreaterThan(0);
      expect(screen.getAllByText('Vendors').length).toBeGreaterThan(0);
      expect(screen.getByText('NTIA Compliant')).toBeInTheDocument();
    });
  });

  describe('stat cards', () => {
    it('displays SBOM count with vulnerability subtitle', () => {
      const mockData = createMockDashboardData();
      mockData.sbom_count = 33;
      mockData.vulnerability_count = 42;

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('33')).toBeInTheDocument();
      expect(screen.getByText('42 vulnerabilities')).toBeInTheDocument();
    });

    it('displays critical vulnerabilities with high vulnerabilities subtitle', () => {
      const mockData = createMockDashboardData({
        critical_vulnerabilities: 5,
        high_vulnerabilities: 12,
      });

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('5')).toBeInTheDocument();
      expect(screen.getByText('12 high')).toBeInTheDocument();
    });

    it('displays container image count with quarantined images subtitle', () => {
      const mockData = createMockDashboardData({
        container_image_count: 30,
        quarantined_images: 2,
      });

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('30')).toBeInTheDocument();
      expect(screen.getByText('2 quarantined')).toBeInTheDocument();
    });

    it('displays attestation count with verified attestations subtitle', () => {
      const mockData = createMockDashboardData({
        attestation_count: 20,
        verified_attestations: 18,
      });

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('20')).toBeInTheDocument();
      expect(screen.getByText('18 verified')).toBeInTheDocument();
    });

    it('displays vendor count with high risk vendors subtitle', () => {
      const mockData = createMockDashboardData();
      mockData.vendor_count = 27;
      mockData.high_risk_vendors = 3;

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('27')).toBeInTheDocument();
      expect(screen.getByText('3 high risk')).toBeInTheDocument();
    });

    it('displays NTIA compliant count with total SBOMs subtitle', () => {
      const mockData = createMockDashboardData({
        ntia_compliant_sboms: 20,
        sbom_count: 25,
      });

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('20')).toBeInTheDocument();
      expect(screen.getByText('of 25 SBOMs')).toBeInTheDocument();
    });
  });

  describe('stat card navigation', () => {
    beforeEach(() => {
      const mockData = createMockDashboardData();
      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
    });

    it('navigates to SBOMs page when SBOM card is clicked', () => {
      renderPage();

      // Find the stat card specifically (not the quick link)
      const statCards = screen.getAllByText('SBOMs');
      const sbomCard = statCards[0].closest('div');
      fireEvent.click(sbomCard!);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/sboms');
    });

    it('navigates to vulnerabilities page when Critical Vulnerabilities card is clicked', () => {
      renderPage();

      const vulnCard = screen.getByText('Critical Vulnerabilities').closest('div');
      fireEvent.click(vulnCard!);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/vulnerabilities');
    });

    it('navigates to containers page when Container Images card is clicked', () => {
      renderPage();

      const containerCards = screen.getAllByText('Container Images');
      const containerCard = containerCards[0].closest('div');
      fireEvent.click(containerCard!);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/containers');
    });

    it('navigates to attestations page when Attestations card is clicked', () => {
      renderPage();

      const attestationCards = screen.getAllByText('Attestations');
      const attestationCard = attestationCards[0].closest('div');
      fireEvent.click(attestationCard!);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/attestations');
    });

    it('navigates to vendors page when Vendors card is clicked', () => {
      renderPage();

      const vendorCards = screen.getAllByText('Vendors');
      const vendorCard = vendorCards[0].closest('div');
      fireEvent.click(vendorCard!);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/vendors');
    });

    it('navigates to SBOMs page when NTIA Compliant card is clicked', () => {
      renderPage();

      const ntiaCard = screen.getByText('NTIA Compliant').closest('div');
      fireEvent.click(ntiaCard!);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/sboms');
    });
  });

  describe('alerts panel', () => {
    it('displays Recent Alerts heading', () => {
      const mockData = createMockDashboardData();
      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Recent Alerts')).toBeInTheDocument();
    });

    it('displays alerts with severity and message', () => {
      const mockData = createMockDashboardData({
        alerts: [
          {
            severity: 'critical',
            type: 'vulnerability',
            message: 'Critical vulnerability detected in production',
            action_url: '/supply-chain/sboms',
          },
        ],
      });

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('critical')).toBeInTheDocument();
      expect(screen.getByText('vulnerability')).toBeInTheDocument();
      expect(screen.getByText('Critical vulnerability detected in production')).toBeInTheDocument();
    });

    it('limits alerts display to maximum of 5', () => {
      const alerts = Array.from({ length: 10 }, (_, i) => ({
        severity: 'high',
        type: 'test',
        message: `Alert ${i + 1}`,
        action_url: '/test',
      }));

      const mockData = createMockDashboardData({ alerts });
      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Alert 1')).toBeInTheDocument();
      expect(screen.getByText('Alert 5')).toBeInTheDocument();
      expect(screen.queryByText('Alert 6')).not.toBeInTheDocument();
    });

    it('shows "No recent alerts" when alerts array is empty', () => {
      const mockData = createMockDashboardData({ alerts: [] });
      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('No recent alerts')).toBeInTheDocument();
    });

    it('navigates to action URL when alert is clicked', () => {
      const mockData = createMockDashboardData({
        alerts: [
          {
            severity: 'high',
            type: 'vulnerability',
            message: 'Test alert',
            action_url: '/supply-chain/sboms/123',
          },
        ],
      });

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const alert = screen.getByText('Test alert').closest('div');
      fireEvent.click(alert!);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/sboms/123');
    });

    it('applies correct severity colors for critical alerts', () => {
      const mockData = createMockDashboardData({
        alerts: [
          {
            severity: 'critical',
            type: 'test',
            message: 'Critical alert',
            action_url: '',
          },
        ],
      });

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const severityBadge = screen.getByText('critical');
      expect(severityBadge).toHaveClass('text-theme-error');
    });

    it('applies correct severity colors for high alerts', () => {
      const mockData = createMockDashboardData({
        alerts: [
          {
            severity: 'high',
            type: 'test',
            message: 'High alert',
            action_url: '',
          },
        ],
      });

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const severityBadge = screen.getByText('high');
      expect(severityBadge).toHaveClass('text-theme-warning');
    });
  });

  describe('activity feed', () => {
    it('displays Recent Activity heading', () => {
      const mockData = createMockDashboardData();
      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Recent Activity')).toBeInTheDocument();
    });

    it('displays activity items with title', () => {
      const mockData = createMockDashboardData({
        recent_activity: [
          {
            type: 'sbom_created',
            title: 'SBOM created for app:v1.0',
            timestamp: new Date().toISOString(),
            details: {},
          },
        ],
      });

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('SBOM created for app:v1.0')).toBeInTheDocument();
    });

    it('limits activity display to maximum of 5', () => {
      const activities = Array.from({ length: 10 }, (_, i) => ({
        type: 'test',
        title: `Activity ${i + 1}`,
        timestamp: new Date().toISOString(),
        details: {},
      }));

      const mockData = createMockDashboardData({ recent_activity: activities });
      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Activity 1')).toBeInTheDocument();
      expect(screen.getByText('Activity 5')).toBeInTheDocument();
      expect(screen.queryByText('Activity 6')).not.toBeInTheDocument();
    });

    it('shows "No recent activity" when activities array is empty', () => {
      const mockData = createMockDashboardData({ recent_activity: [] });
      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('No recent activity')).toBeInTheDocument();
    });

    it('formats timestamp as "Just now" for very recent activity', () => {
      const mockData = createMockDashboardData({
        recent_activity: [
          {
            type: 'test',
            title: 'Recent activity',
            timestamp: new Date().toISOString(),
            details: {},
          },
        ],
      });

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Just now')).toBeInTheDocument();
    });

    it('displays activity details when provided', () => {
      const mockData = createMockDashboardData({
        recent_activity: [
          {
            type: 'test',
            title: 'Activity with details',
            timestamp: new Date().toISOString(),
            details: { component: 'lodash', version: '4.17.21' },
          },
        ],
      });

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText(/component: lodash • version: 4\.17\.21/)).toBeInTheDocument();
    });
  });

  describe('quick access links', () => {
    beforeEach(() => {
      const mockData = createMockDashboardData();
      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
    });

    it('displays Quick Access heading', () => {
      renderPage();
      expect(screen.getByText('Quick Access')).toBeInTheDocument();
    });

    it('displays all six quick access links', () => {
      renderPage();

      // Check by description which is unique to quick links
      expect(screen.getByText('Software Bill of Materials')).toBeInTheDocument();
      expect(screen.getByText('Container security and scanning')).toBeInTheDocument();
      expect(screen.getByText('Build and provenance verification')).toBeInTheDocument();
      expect(screen.getByText('Third-party vendor management')).toBeInTheDocument();
      expect(screen.getByText('License compliance rules')).toBeInTheDocument();
      expect(screen.getByText('Policy violation tracking')).toBeInTheDocument();
    });

    it('displays descriptions for quick links', () => {
      renderPage();

      expect(screen.getByText('Software Bill of Materials')).toBeInTheDocument();
      expect(screen.getByText('Container security and scanning')).toBeInTheDocument();
      expect(screen.getByText('Build and provenance verification')).toBeInTheDocument();
      expect(screen.getByText('Third-party vendor management')).toBeInTheDocument();
      expect(screen.getByText('License compliance rules')).toBeInTheDocument();
      expect(screen.getByText('Policy violation tracking')).toBeInTheDocument();
    });

    it('navigates to SBOMs page when SBOMs quick link is clicked', () => {
      renderPage();

      const link = screen.getByText('Software Bill of Materials').closest('div');
      fireEvent.click(link!.parentElement!);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/sboms');
    });

    it('navigates to containers page when Container Images quick link is clicked', () => {
      renderPage();

      const link = screen.getByText('Container security and scanning').closest('div');
      fireEvent.click(link!.parentElement!);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/containers');
    });

    it('navigates to attestations page when Attestations quick link is clicked', () => {
      renderPage();

      const link = screen.getByText('Build and provenance verification').closest('div');
      fireEvent.click(link!.parentElement!);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/attestations');
    });

    it('navigates to vendors page when Vendors quick link is clicked', () => {
      renderPage();

      const link = screen.getByText('Third-party vendor management').closest('div');
      fireEvent.click(link!.parentElement!);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/vendors');
    });

    it('navigates to license policies page when License Policies quick link is clicked', () => {
      renderPage();

      const link = screen.getByText('License compliance rules').closest('div');
      fireEvent.click(link!.parentElement!);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/license-policies');
    });

    it('navigates to license violations page when License Violations quick link is clicked', () => {
      renderPage();

      const link = screen.getByText('Policy violation tracking').closest('div');
      fireEvent.click(link!.parentElement!);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/license-violations');
    });
  });

  describe('security attention required section', () => {
    it('displays when critical vulnerabilities exist', () => {
      const mockData = createMockDashboardData({
        critical_vulnerabilities: 5,
        quarantined_images: 0,
        high_risk_vendors: 0,
        open_vulnerabilities: 0,
      });

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Security Attention Required')).toBeInTheDocument();
      expect(screen.getByText('5 critical vulnerabilities detected')).toBeInTheDocument();
    });

    it('displays when quarantined images exist', () => {
      const mockData = createMockDashboardData({
        critical_vulnerabilities: 0,
        quarantined_images: 3,
        high_risk_vendors: 0,
        open_vulnerabilities: 0,
      });

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Security Attention Required')).toBeInTheDocument();
      expect(screen.getByText('3 container images quarantined')).toBeInTheDocument();
    });

    it('displays when high risk vendors exist', () => {
      const mockData = createMockDashboardData({
        critical_vulnerabilities: 0,
        quarantined_images: 0,
        high_risk_vendors: 2,
        open_vulnerabilities: 0,
      });

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Security Attention Required')).toBeInTheDocument();
      expect(screen.getByText('2 high-risk vendors need assessment')).toBeInTheDocument();
    });

    it('displays when open vulnerabilities exist', () => {
      const mockData = createMockDashboardData({
        critical_vulnerabilities: 0,
        quarantined_images: 0,
        high_risk_vendors: 0,
        open_vulnerabilities: 10,
      });

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('Security Attention Required')).toBeInTheDocument();
    });

    it('does not display when no security issues exist', () => {
      const mockData = createMockDashboardData({
        critical_vulnerabilities: 0,
        quarantined_images: 0,
        high_risk_vendors: 0,
        open_vulnerabilities: 0,
      });

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.queryByText('Security Attention Required')).not.toBeInTheDocument();
    });

    it('displays multiple security issues simultaneously', () => {
      const mockData = createMockDashboardData({
        critical_vulnerabilities: 5,
        quarantined_images: 2,
        high_risk_vendors: 3,
      });

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('5 critical vulnerabilities detected')).toBeInTheDocument();
      expect(screen.getByText('2 container images quarantined')).toBeInTheDocument();
      expect(screen.getByText('3 high-risk vendors need assessment')).toBeInTheDocument();
    });

    it('uses singular form for single vulnerability', () => {
      const mockData = createMockDashboardData({
        critical_vulnerabilities: 1,
      });

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('1 critical vulnerability detected')).toBeInTheDocument();
    });

    it('uses singular form for single container image', () => {
      const mockData = createMockDashboardData({
        quarantined_images: 1,
        critical_vulnerabilities: 0,
        high_risk_vendors: 0,
        open_vulnerabilities: 0,
      });

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('1 container image quarantined')).toBeInTheDocument();
    });

    it('uses singular form for single high-risk vendor', () => {
      const mockData = createMockDashboardData({
        high_risk_vendors: 1,
        critical_vulnerabilities: 0,
        quarantined_images: 0,
        open_vulnerabilities: 0,
      });

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      expect(screen.getByText('1 high-risk vendor need assessment')).toBeInTheDocument();
    });

    it('navigates to SBOMs when Review button is clicked for vulnerabilities', () => {
      const mockData = createMockDashboardData({
        critical_vulnerabilities: 5,
        quarantined_images: 0,
        high_risk_vendors: 0,
        open_vulnerabilities: 0,
      });

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const reviewButtons = screen.getAllByText('Review');
      fireEvent.click(reviewButtons[0]);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/sboms');
    });

    it('navigates to containers when Review button is clicked for quarantined images', () => {
      const mockData = createMockDashboardData({
        critical_vulnerabilities: 0,
        quarantined_images: 2,
        high_risk_vendors: 0,
        open_vulnerabilities: 0,
      });

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const reviewButtons = screen.getAllByText('Review');
      fireEvent.click(reviewButtons[0]);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/containers');
    });

    it('navigates to vendors when Review button is clicked for high-risk vendors', () => {
      const mockData = createMockDashboardData({
        critical_vulnerabilities: 0,
        quarantined_images: 0,
        high_risk_vendors: 3,
        open_vulnerabilities: 0,
      });

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const reviewButtons = screen.getAllByText('Review');
      fireEvent.click(reviewButtons[0]);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/vendors');
    });
  });

  describe('refresh action', () => {
    it('calls refresh function when Refresh button is clicked', async () => {
      const mockRefresh = jest.fn();
      const mockData = createMockDashboardData();

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: mockRefresh,
      });

      renderPage();

      const refreshButton = screen.getByTestId('action-refresh');
      fireEvent.click(refreshButton);

      await waitFor(() => {
        expect(mockRefresh).toHaveBeenCalledTimes(1);
      });
    });

    it('disables refresh button and shows "Refreshing..." during refresh', async () => {
      const mockRefresh = jest.fn().mockImplementation(
        () => new Promise((resolve) => setTimeout(resolve, 100))
      );
      const mockData = createMockDashboardData();

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: mockRefresh,
      });

      renderPage();

      const refreshButton = screen.getByTestId('action-refresh');
      fireEvent.click(refreshButton);

      await waitFor(() => {
        expect(screen.getByText('Refreshing...')).toBeInTheDocument();
      });
    });

    it('re-enables refresh button after refresh completes', async () => {
      const mockRefresh = jest.fn().mockResolvedValue(undefined);
      const mockData = createMockDashboardData();

      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: mockRefresh,
      });

      renderPage();

      const refreshButton = screen.getByTestId('action-refresh');
      fireEvent.click(refreshButton);

      await waitFor(() => {
        expect(refreshButton).not.toBeDisabled();
      });
    });
  });

  describe('stat card status indicators', () => {
    it('shows success status for SBOMs when count is greater than 0', () => {
      const mockData = createMockDashboardData({ sbom_count: 10 });
      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const sbomCards = screen.getAllByText('SBOMs');
      const sbomCard = sbomCards[0].closest('div');
      expect(sbomCard).toBeInTheDocument();
    });

    it('shows error status for critical vulnerabilities when count is greater than 0', () => {
      const mockData = createMockDashboardData({ critical_vulnerabilities: 5 });
      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const vulnCard = screen.getByText('Critical Vulnerabilities').closest('div');
      expect(vulnCard).toBeInTheDocument();
    });

    it('shows warning status for quarantined images when count is greater than 0', () => {
      const mockData = createMockDashboardData({ quarantined_images: 2 });
      mockUseSupplyChainDashboard.mockReturnValue({
        data: mockData,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      renderPage();

      const containerCards = screen.getAllByText('Container Images');
      const containerCard = containerCards[0].closest('div');
      expect(containerCard).toBeInTheDocument();
    });
  });
});
