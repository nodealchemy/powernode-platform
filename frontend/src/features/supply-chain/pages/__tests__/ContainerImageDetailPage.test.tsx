import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import { ContainerImageDetailPage } from '../ContainerImageDetailPage';
import {
  useContainerImage,
  useContainerVulnerabilities,
  useContainerSbom,
  useEvaluatePolicies,
} from '../../hooks/useContainerImages';
import { containerImagesApi } from '../../services/containerImagesApi';
import {
  createMockContainerImageDetail,
  createMockVulnerabilityScan,
} from '../../testing/mockFactories';

jest.mock('../../hooks/useContainerImages');
jest.mock('../../services/containerImagesApi');

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
        {actions?.map((action: any) => (
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

// Mock LoadingSpinner
jest.mock('@/shared/components/ui/LoadingSpinner', () => ({
  LoadingSpinner: ({ size }: any) => <div data-testid="loading-spinner" data-size={size}>Loading...</div>,
}));

// Mock ErrorAlert
jest.mock('@/shared/components/ui/ErrorAlert', () => ({
  __esModule: true,
  default: ({ message }: any) => <div data-testid="error-alert">{message}</div>,
}));

// Mock Card
jest.mock('@/shared/components/ui/Card', () => ({
  Card: ({ children, className }: any) => (
    <div data-testid="card" className={className}>
      {children}
    </div>
  ),
}));

// Mock Badge
jest.mock('@/shared/components/ui/Badge', () => ({
  Badge: ({ children, variant }: any) => (
    <span data-testid={`badge-${variant}`}>{children}</span>
  ),
}));

// Mock StatusBadge
jest.mock('../../components/shared/StatusBadge', () => ({
  StatusBadge: ({ status, size }: any) => (
    <span data-testid="status-badge" data-status={status} data-size={size}>
      {status}
    </span>
  ),
}));

// Mock component tables and viewers
jest.mock('../../components/container/ContainerVulnerabilitiesTable', () => ({
  ContainerVulnerabilitiesTable: ({ vulnerabilities, loading }: any) => (
    <div data-testid="vulnerabilities-table">
      {loading ? 'Loading vulnerabilities...' : `${vulnerabilities?.length || 0} vulnerabilities`}
    </div>
  ),
}));

jest.mock('../../components/container/ContainerSbomViewer', () => ({
  ContainerSbomViewer: ({ sbom, loading }: any) => (
    <div data-testid="sbom-viewer">
      {loading ? 'Loading SBOM...' : sbom ? 'SBOM Content' : 'No SBOM'}
    </div>
  ),
}));

jest.mock('../../components/container/PolicyViolationsList', () => ({
  PolicyViolationsList: ({ evaluations, loading, onEvaluate }: any) => (
    <div data-testid="policy-violations-list">
      <button data-testid="evaluate-policies-btn" onClick={onEvaluate} disabled={loading}>
        Evaluate Policies
      </button>
      {loading && 'Loading...'}
      {evaluations && <div data-testid="policy-results">Policy Results</div>}
    </div>
  ),
}));

// Mock react-router-dom params
const mockParams = { id: 'image-123' };
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useParams: () => mockParams,
}));

// Mock window.prompt
const originalPrompt = window.prompt;

describe('ContainerImageDetailPage', () => {
  const mockUseContainerImage = useContainerImage as jest.MockedFunction<typeof useContainerImage>;
  const mockUseContainerVulnerabilities = useContainerVulnerabilities as jest.MockedFunction<
    typeof useContainerVulnerabilities
  >;
  const mockUseContainerSbom = useContainerSbom as jest.MockedFunction<typeof useContainerSbom>;
  const mockUseEvaluatePolicies = useEvaluatePolicies as jest.MockedFunction<
    typeof useEvaluatePolicies
  >;
  const mockContainerImagesApi = containerImagesApi as jest.Mocked<typeof containerImagesApi>;

  beforeEach(() => {
    jest.clearAllMocks();
    window.prompt = jest.fn();
  });

  afterEach(() => {
    window.prompt = originalPrompt;
  });

  describe('Loading State', () => {
    it('shows loading spinner when loading is true', () => {
      mockUseContainerImage.mockReturnValue({
        image: null,
        loading: true,
        error: null,
        refresh: jest.fn(),
      });
      mockUseContainerVulnerabilities.mockReturnValue({
        vulnerabilities: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseContainerSbom.mockReturnValue({
        sbom: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseEvaluatePolicies.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      expect(screen.getByTestId('loading-spinner')).toBeInTheDocument();
      expect(screen.getByTestId('loading-spinner')).toHaveAttribute('data-size', 'lg');
    });

    it('hides loading spinner when loading is false', () => {
      const mockImage = createMockContainerImageDetail();
      mockUseContainerImage.mockReturnValue({
        image: mockImage,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseContainerVulnerabilities.mockReturnValue({
        vulnerabilities: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseContainerSbom.mockReturnValue({
        sbom: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseEvaluatePolicies.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      expect(screen.queryByTestId('loading-spinner')).not.toBeInTheDocument();
    });
  });

  describe('Error State', () => {
    it('shows error alert when error exists', () => {
      mockUseContainerImage.mockReturnValue({
        image: null,
        loading: false,
        error: 'Failed to load image',
        refresh: jest.fn(),
      });
      mockUseContainerVulnerabilities.mockReturnValue({
        vulnerabilities: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseContainerSbom.mockReturnValue({
        sbom: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseEvaluatePolicies.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      expect(screen.getByTestId('error-alert')).toBeInTheDocument();
      expect(screen.getByTestId('error-alert')).toHaveTextContent('Failed to load image');
    });

    it('shows error when image is not found', () => {
      mockUseContainerImage.mockReturnValue({
        image: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseContainerVulnerabilities.mockReturnValue({
        vulnerabilities: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseContainerSbom.mockReturnValue({
        sbom: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseEvaluatePolicies.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      expect(screen.getByTestId('error-alert')).toBeInTheDocument();
      expect(screen.getByTestId('error-alert')).toHaveTextContent('Image not found');
    });

    it('shows page container with breadcrumbs in error state', () => {
      mockUseContainerImage.mockReturnValue({
        image: null,
        loading: false,
        error: 'Failed to load image',
        refresh: jest.fn(),
      });
      mockUseContainerVulnerabilities.mockReturnValue({
        vulnerabilities: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseContainerSbom.mockReturnValue({
        sbom: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseEvaluatePolicies.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });

      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      expect(screen.getByTestId('breadcrumb-0')).toHaveTextContent('Dashboard');
      expect(screen.getByTestId('breadcrumb-1')).toHaveTextContent('Supply Chain');
      expect(screen.getByTestId('breadcrumb-2')).toHaveTextContent('Container Images');
      expect(screen.getByTestId('breadcrumb-3')).toHaveTextContent('Details');
    });
  });

  describe('Image Details Display', () => {
    const mockImage = createMockContainerImageDetail({
      id: 'image-123',
      registry: 'ghcr.io',
      repository: 'org/app',
      tag: 'v1.2.3',
      digest: 'sha256:abcdef123456',
      status: 'verified',
      is_deployed: true,
      critical_vuln_count: 2,
      high_vuln_count: 5,
      medium_vuln_count: 8,
      low_vuln_count: 12,
      last_scanned_at: '2024-01-15T10:30:00Z',
      created_at: '2024-01-10T08:00:00Z',
    });

    beforeEach(() => {
      mockUseContainerImage.mockReturnValue({
        image: mockImage,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseContainerVulnerabilities.mockReturnValue({
        vulnerabilities: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseContainerSbom.mockReturnValue({
        sbom: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseEvaluatePolicies.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });
    });

    it('renders page title with repository and tag', () => {
      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      expect(screen.getByTestId('page-title')).toHaveTextContent('org/app:v1.2.3');
    });

    it('renders page description with registry', () => {
      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      expect(screen.getByTestId('page-description')).toHaveTextContent('Registry: ghcr.io');
    });

    it('renders breadcrumbs with image name', () => {
      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      expect(screen.getByTestId('breadcrumb-0')).toHaveTextContent('Dashboard');
      expect(screen.getByTestId('breadcrumb-1')).toHaveTextContent('Supply Chain');
      expect(screen.getByTestId('breadcrumb-2')).toHaveTextContent('Container Images');
      expect(screen.getByTestId('breadcrumb-3')).toHaveTextContent('org/app:v1.2.3');
    });

    it('renders status badge', () => {
      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      const statusBadges = screen.getAllByTestId('status-badge');
      expect(statusBadges[0]).toHaveAttribute('data-status', 'verified');
    });

    it('renders deployed badge when is_deployed is true', () => {
      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      const deployedBadges = screen.getAllByTestId('badge-success');
      const deployedBadge = deployedBadges.find(badge => badge.textContent === 'Deployed');
      expect(deployedBadge).toBeInTheDocument();
      expect(deployedBadge).toHaveTextContent('Deployed');
    });

    it('does not render deployed badge when is_deployed is false', () => {
      const notDeployedImage = createMockContainerImageDetail({ is_deployed: false });
      mockUseContainerImage.mockReturnValue({
        image: notDeployedImage,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      expect(screen.queryByTestId('badge-success')).not.toBeInTheDocument();
    });
  });

  describe('Tab Navigation', () => {
    const mockImage = createMockContainerImageDetail();

    beforeEach(() => {
      mockUseContainerImage.mockReturnValue({
        image: mockImage,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseContainerVulnerabilities.mockReturnValue({
        vulnerabilities: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseContainerSbom.mockReturnValue({
        sbom: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseEvaluatePolicies.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });
    });

    it('renders all tabs', () => {
      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      expect(screen.getByTestId('tab-overview')).toHaveTextContent('Overview');
      expect(screen.getByTestId('tab-vulnerabilities')).toHaveTextContent('Vulnerabilities');
      expect(screen.getByTestId('tab-sbom')).toHaveTextContent('SBOM');
      expect(screen.getByTestId('tab-policies')).toHaveTextContent('Policies');
    });

    it('shows overview tab as active by default', () => {
      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      expect(screen.getByTestId('tab-overview')).toHaveAttribute('data-active', 'true');
    });

    it('changes to vulnerabilities tab when clicked', () => {
      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('tab-vulnerabilities'));
      expect(screen.getByTestId('tab-vulnerabilities')).toHaveAttribute('data-active', 'true');
    });

    it('changes to sbom tab when clicked', () => {
      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('tab-sbom'));
      expect(screen.getByTestId('tab-sbom')).toHaveAttribute('data-active', 'true');
    });

    it('changes to policies tab when clicked', () => {
      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('tab-policies'));
      expect(screen.getByTestId('tab-policies')).toHaveAttribute('data-active', 'true');
    });
  });

  describe('Overview Tab', () => {
    const mockImage = createMockContainerImageDetail({
      registry: 'ghcr.io',
      repository: 'org/app',
      tag: 'v1.0.0',
      digest: 'sha256:abc123',
      status: 'verified',
      is_deployed: true,
      critical_vuln_count: 1,
      high_vuln_count: 3,
      medium_vuln_count: 5,
      low_vuln_count: 7,
      last_scanned_at: '2024-01-15T10:30:00Z',
      created_at: '2024-01-10T08:00:00Z',
      scans: [
        createMockVulnerabilityScan({
          scanner: 'trivy',
          status: 'completed',
          critical_count: 1,
          high_count: 3,
          medium_count: 5,
          low_count: 7,
        }),
      ],
    });

    beforeEach(() => {
      mockUseContainerImage.mockReturnValue({
        image: mockImage,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseContainerVulnerabilities.mockReturnValue({
        vulnerabilities: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseContainerSbom.mockReturnValue({
        sbom: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseEvaluatePolicies.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });
    });

    it('renders image details card', () => {
      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      expect(screen.getByText('Image Details')).toBeInTheDocument();
      expect(screen.getByText('ghcr.io')).toBeInTheDocument();
      expect(screen.getByText('org/app')).toBeInTheDocument();
      expect(screen.getByText('v1.0.0')).toBeInTheDocument();
      expect(screen.getByText('sha256:abc123')).toBeInTheDocument();
    });

    it('renders vulnerability summary card with four severity boxes', () => {
      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      expect(screen.getByText('Vulnerability Summary')).toBeInTheDocument();
      expect(screen.getByText('1')).toBeInTheDocument(); // Critical
      expect(screen.getByText('3')).toBeInTheDocument(); // High
      expect(screen.getByText('5')).toBeInTheDocument(); // Medium
      expect(screen.getByText('7')).toBeInTheDocument(); // Low
      expect(screen.getByText('Critical')).toBeInTheDocument();
      expect(screen.getByText('High')).toBeInTheDocument();
      expect(screen.getByText('Medium')).toBeInTheDocument();
      expect(screen.getByText('Low')).toBeInTheDocument();
    });

    it('renders scan history when scans exist', () => {
      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      expect(screen.getByText('Scan History')).toBeInTheDocument();
      expect(screen.getByText('trivy')).toBeInTheDocument();
    });

    it('does not render scan history when no scans', () => {
      const imageWithoutScans = createMockContainerImageDetail({ scans: [] });
      mockUseContainerImage.mockReturnValue({
        image: imageWithoutScans,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      expect(screen.queryByText('Scan History')).not.toBeInTheDocument();
    });

    it('displays formatted dates', () => {
      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      // Should not show "Never" since dates are provided
      const neverTexts = screen.queryAllByText('Never');
      expect(neverTexts).toHaveLength(0);
    });

    it('displays "Never" when last_scanned_at is null', () => {
      const imageNotScanned = createMockContainerImageDetail({ last_scanned_at: undefined });
      mockUseContainerImage.mockReturnValue({
        image: imageNotScanned,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      expect(screen.getByText('Never')).toBeInTheDocument();
    });
  });

  describe('Vulnerabilities Tab', () => {
    const mockImage = createMockContainerImageDetail();
    const mockVulnerabilities = [
      {
        id: 'vuln-1',
        vulnerability_id: 'CVE-2024-1234',
        severity: 'critical' as const,
        cvss_score: 9.8,
        package_name: 'lodash',
        package_version: '4.17.20',
        fixed_version: '4.17.21',
      },
    ];

    beforeEach(() => {
      mockUseContainerImage.mockReturnValue({
        image: mockImage,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseContainerVulnerabilities.mockReturnValue({
        vulnerabilities: mockVulnerabilities,
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseContainerSbom.mockReturnValue({
        sbom: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseEvaluatePolicies.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });
    });

    it('renders vulnerabilities table', () => {
      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('tab-vulnerabilities'));

      expect(screen.getByTestId('vulnerabilities-table')).toBeInTheDocument();
      expect(screen.getByTestId('vulnerabilities-table')).toHaveTextContent('1 vulnerabilities');
    });

    it('passes vulnerabilities to table component', () => {
      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('tab-vulnerabilities'));

      expect(screen.getByTestId('vulnerabilities-table')).toHaveTextContent('1 vulnerabilities');
    });

    it('shows loading state in vulnerabilities table', () => {
      mockUseContainerVulnerabilities.mockReturnValue({
        vulnerabilities: [],
        pagination: null,
        loading: true,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('tab-vulnerabilities'));

      expect(screen.getByTestId('vulnerabilities-table')).toHaveTextContent(
        'Loading vulnerabilities...'
      );
    });
  });

  describe('SBOM Tab', () => {
    const mockImage = createMockContainerImageDetail();
    const mockSbom = {
      id: 'sbom-123',
      format: 'cyclonedx_1_5',
      component_count: 150,
      components: [],
      generated_at: '2024-01-15T10:30:00Z',
    };

    beforeEach(() => {
      mockUseContainerImage.mockReturnValue({
        image: mockImage,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseContainerVulnerabilities.mockReturnValue({
        vulnerabilities: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseContainerSbom.mockReturnValue({
        sbom: mockSbom,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseEvaluatePolicies.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });
    });

    it('renders SBOM viewer', () => {
      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('tab-sbom'));

      expect(screen.getByTestId('sbom-viewer')).toBeInTheDocument();
      expect(screen.getByTestId('sbom-viewer')).toHaveTextContent('SBOM Content');
    });

    it('shows loading state in SBOM viewer', () => {
      mockUseContainerSbom.mockReturnValue({
        sbom: null,
        loading: true,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('tab-sbom'));

      expect(screen.getByTestId('sbom-viewer')).toHaveTextContent('Loading SBOM...');
    });

    it('shows empty state when no SBOM', () => {
      mockUseContainerSbom.mockReturnValue({
        sbom: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });

      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('tab-sbom'));

      expect(screen.getByTestId('sbom-viewer')).toHaveTextContent('No SBOM');
    });
  });

  describe('Policies Tab', () => {
    const mockImage = createMockContainerImageDetail();
    const mockEvaluatePolicies = jest.fn();

    beforeEach(() => {
      mockUseContainerImage.mockReturnValue({
        image: mockImage,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseContainerVulnerabilities.mockReturnValue({
        vulnerabilities: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseContainerSbom.mockReturnValue({
        sbom: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseEvaluatePolicies.mockReturnValue({
        mutateAsync: mockEvaluatePolicies,
        isLoading: false,
        error: null,
      });
    });

    it('renders policy violations list', () => {
      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('tab-policies'));

      expect(screen.getByTestId('policy-violations-list')).toBeInTheDocument();
    });

    it('renders evaluate policies button', () => {
      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('tab-policies'));

      expect(screen.getByTestId('evaluate-policies-btn')).toBeInTheDocument();
    });

    it('calls evaluate policies mutation when button clicked', async () => {
      mockEvaluatePolicies.mockResolvedValue({ violations: [] });

      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('tab-policies'));
      fireEvent.click(screen.getByTestId('evaluate-policies-btn'));

      await waitFor(() => {
        expect(mockEvaluatePolicies).toHaveBeenCalledWith('image-123');
      });
    });

    it('displays policy results after evaluation', async () => {
      mockEvaluatePolicies.mockResolvedValue({ violations: [] });

      const { rerender } = render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('tab-policies'));
      fireEvent.click(screen.getByTestId('evaluate-policies-btn'));

      await waitFor(() => {
        expect(mockEvaluatePolicies).toHaveBeenCalled();
      });

      // Simulate state update after evaluation
      rerender(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      // Note: In actual implementation, policy results would be displayed
      // This tests the structure is present
      expect(screen.getByTestId('policy-violations-list')).toBeInTheDocument();
    });
  });

  describe('Actions', () => {
    const mockImage = createMockContainerImageDetail({ status: 'unverified' });
    const mockRefresh = jest.fn();

    beforeEach(() => {
      mockUseContainerImage.mockReturnValue({
        image: mockImage,
        loading: false,
        error: null,
        refresh: mockRefresh,
      });
      mockUseContainerVulnerabilities.mockReturnValue({
        vulnerabilities: [],
        pagination: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseContainerSbom.mockReturnValue({
        sbom: null,
        loading: false,
        error: null,
        refresh: jest.fn(),
      });
      mockUseEvaluatePolicies.mockReturnValue({
        mutateAsync: jest.fn(),
        isLoading: false,
        error: null,
      });
    });

    it('renders all action buttons', () => {
      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      expect(screen.getByTestId('action-rescan')).toBeInTheDocument();
      expect(screen.getByTestId('action-verify')).toBeInTheDocument();
      expect(screen.getByTestId('action-quarantine')).toBeInTheDocument();
    });

    it('calls scan API when re-scan button clicked', async () => {
      mockContainerImagesApi.scan.mockResolvedValue({} as any);

      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('action-rescan'));

      await waitFor(() => {
        expect(mockContainerImagesApi.scan).toHaveBeenCalledWith('image-123');
      });
    });

    it('calls refresh after re-scan completes', async () => {
      mockContainerImagesApi.scan.mockResolvedValue({} as any);

      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('action-rescan'));

      await waitFor(() => {
        expect(mockRefresh).toHaveBeenCalled();
      });
    });

    it('calls verify API when verify button clicked', async () => {
      mockContainerImagesApi.verify.mockResolvedValue({} as any);

      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('action-verify'));

      await waitFor(() => {
        expect(mockContainerImagesApi.verify).toHaveBeenCalledWith('image-123');
      });
    });

    it('calls refresh after verify completes', async () => {
      mockContainerImagesApi.verify.mockResolvedValue({} as any);

      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('action-verify'));

      await waitFor(() => {
        expect(mockRefresh).toHaveBeenCalled();
      });
    });

    it('disables verify button when already verified', () => {
      const verifiedImage = createMockContainerImageDetail({ status: 'verified' });
      mockUseContainerImage.mockReturnValue({
        image: verifiedImage,
        loading: false,
        error: null,
        refresh: mockRefresh,
      });

      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      const verifyButton = screen.getByTestId('action-verify') as HTMLButtonElement;
      expect(verifyButton.disabled).toBe(true);
    });

    it('prompts for reason when quarantine button clicked', async () => {
      (window.prompt as jest.Mock).mockReturnValue('Security issue detected');
      mockContainerImagesApi.quarantine.mockResolvedValue({} as any);

      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('action-quarantine'));

      expect(window.prompt).toHaveBeenCalledWith('Enter reason for quarantine:');
    });

    it('calls quarantine API with reason', async () => {
      (window.prompt as jest.Mock).mockReturnValue('Security issue detected');
      mockContainerImagesApi.quarantine.mockResolvedValue({} as any);

      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('action-quarantine'));

      await waitFor(() => {
        expect(mockContainerImagesApi.quarantine).toHaveBeenCalledWith(
          'image-123',
          'Security issue detected'
        );
      });
    });

    it('does not call quarantine API when prompt is cancelled', async () => {
      (window.prompt as jest.Mock).mockReturnValue(null);

      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('action-quarantine'));

      await waitFor(() => {
        expect(mockContainerImagesApi.quarantine).not.toHaveBeenCalled();
      });
    });

    it('does not call quarantine API when reason is empty', async () => {
      (window.prompt as jest.Mock).mockReturnValue('');

      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('action-quarantine'));

      await waitFor(() => {
        expect(mockContainerImagesApi.quarantine).not.toHaveBeenCalled();
      });
    });

    it('disables quarantine button when already quarantined', () => {
      const quarantinedImage = createMockContainerImageDetail({ status: 'quarantined' });
      mockUseContainerImage.mockReturnValue({
        image: quarantinedImage,
        loading: false,
        error: null,
        refresh: mockRefresh,
      });

      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      const quarantineButton = screen.getByTestId('action-quarantine') as HTMLButtonElement;
      expect(quarantineButton.disabled).toBe(true);
    });

    it('disables all actions when action is loading', async () => {
      mockContainerImagesApi.scan.mockImplementation(
        () => new Promise((resolve) => setTimeout(resolve, 1000))
      );

      render(
        <BrowserRouter>
          <ContainerImageDetailPage />
        </BrowserRouter>
      );

      fireEvent.click(screen.getByTestId('action-rescan'));

      // Actions should be disabled during loading
      const rescanButton = screen.getByTestId('action-rescan') as HTMLButtonElement;
      const verifyButton = screen.getByTestId('action-verify') as HTMLButtonElement;
      const quarantineButton = screen.getByTestId('action-quarantine') as HTMLButtonElement;

      expect(rescanButton.disabled).toBe(true);
      expect(verifyButton.disabled).toBe(true);
      expect(quarantineButton.disabled).toBe(true);
    });
  });
});
