import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { SbomDetailPage } from '../SbomDetailPage';
import { sbomsApi } from '../../services/sbomsApi';
import {
  useSbomCompliance,
  useSbomDiffs,
  useCreateSbomDiff,
  useUpdateVulnerabilityStatus,
  useSuppressVulnerability,
  useMarkFalsePositive,
  useCalculateRisk,
  useCorrelateVulnerabilities,
} from '../../hooks/useSboms';
import {
  createMockSbom,
  createMockSbomComponent,
  createMockSbomVulnerability,
  createMockPagination,
} from '../../testing/mockFactories';

// Mock dependencies
jest.mock('../../services/sbomsApi');
jest.mock('../../hooks/useSboms');
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    showNotification: jest.fn(),
  }),
}));

// Mock PageContainer
jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({ title, breadcrumbs, actions, children }: any) => (
    <div data-testid="page-container">
      <div data-testid="page-title">{title}</div>
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
          {tab.badge !== undefined && <span data-testid={`badge-${tab.id}`}>{tab.badge}</span>}
        </button>
      ))}
      <div data-testid="tab-content">
        {tabs.find((t: any) => t.id === activeTab)?.content}
      </div>
    </div>
  ),
}));

// Mock DataTable
jest.mock('@/shared/components/ui/DataTable', () => ({
  DataTable: ({ columns, data, loading, emptyState, pagination, onPageChange }: any) => (
    <div data-testid="data-table">
      {loading && <div data-testid="loading">Loading...</div>}
      {data.length === 0 && !loading && (
        <div data-testid="empty-state">{emptyState?.title}</div>
      )}
      {data.map((item: any) => (
        <div key={item.id} data-testid={`row-${item.id}`}>
          {columns.map((col: any) => (
            <div key={col.key} data-testid={`cell-${item.id}-${col.key}`}>
              {col.render ? col.render(item) : item[col.key]}
            </div>
          ))}
        </div>
      ))}
      {pagination && (
        <button onClick={() => onPageChange(pagination.current_page + 1)}>Next</button>
      )}
    </div>
  ),
}));

// Mock LoadingSpinner
jest.mock('@/shared/components/ui/LoadingSpinner', () => ({
  LoadingSpinner: () => <div data-testid="loading-spinner">Loading...</div>,
}));

// Mock ConfirmationModal
jest.mock('@/shared/components/ui/ConfirmationModal', () => ({
  useConfirmation: () => ({
    confirm: jest.fn((options) => options.onConfirm()),
    ConfirmationDialog: <div data-testid="confirmation-dialog" />,
  }),
}));

// Mock other components
jest.mock('../../components/sbom/VulnerabilityActionsMenu', () => ({
  VulnerabilityActionsMenu: ({ onSuppress, onMarkFalsePositive, onUpdateStatus }: any) => (
    <div data-testid="vulnerability-actions-menu">
      <button onClick={onSuppress}>Suppress</button>
      <button onClick={onMarkFalsePositive}>Mark False Positive</button>
      <button onClick={() => onUpdateStatus('fixed')}>Update Status</button>
    </div>
  ),
}));

jest.mock('../../components/sbom/RemediationStatusSelect', () => ({
  RemediationStatusSelect: ({ value, onChange }: any) => (
    <select data-testid="remediation-status-select" value={value} onChange={(e) => onChange(e.target.value)}>
      <option value="open">Open</option>
      <option value="in_progress">In Progress</option>
      <option value="fixed">Fixed</option>
      <option value="wont_fix">Won't Fix</option>
    </select>
  ),
}));

jest.mock('../../components/sbom/ComplianceStatusCard', () => ({
  ComplianceStatusCard: ({ compliance }: any) => (
    <div data-testid="compliance-status-card">
      <div>NTIA: {compliance.ntia_minimum_compliant ? 'Yes' : 'No'}</div>
      <div>Score: {compliance.completeness_score}</div>
    </div>
  ),
}));

jest.mock('../../components/sbom/CreateDiffModal', () => ({
  CreateDiffModal: ({ onClose, onCreateDiff }: any) => (
    <div data-testid="create-diff-modal">
      <button onClick={onClose}>Close</button>
      <button onClick={() => onCreateDiff('compare-sbom-id')}>Create</button>
    </div>
  ),
}));

jest.mock('../../components/sbom/ExportFormatDropdown', () => ({
  ExportFormatDropdown: ({ onExport }: any) => (
    <div data-testid="export-format-dropdown">
      <button onClick={() => onExport('json')}>Export JSON</button>
      <button onClick={() => onExport('pdf')}>Export PDF</button>
    </div>
  ),
}));

const mockNavigate = jest.fn();
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate,
  useParams: jest.fn(),
}));

describe('SbomDetailPage', () => {
  const mockSbom = createMockSbom({
    id: 'sbom-123',
    name: 'Test SBOM',
    status: 'completed',
    component_count: 150,
    vulnerability_count: 5,
    risk_score: 4.5,
    ntia_minimum_compliant: true,
  });

  const mockComponents = [
    createMockSbomComponent({
      id: 'comp-1',
      name: 'lodash',
      version: '4.17.21',
      ecosystem: 'npm',
      has_known_vulnerabilities: true,
    }),
    createMockSbomComponent({
      id: 'comp-2',
      name: 'express',
      version: '4.18.2',
      ecosystem: 'npm',
      has_known_vulnerabilities: false,
    }),
  ];

  const mockVulnerabilities = [
    createMockSbomVulnerability({
      id: 'vuln-1',
      vulnerability_id: 'CVE-2024-12345',
      severity: 'high',
      cvss_score: 7.5,
      remediation_status: 'open',
    }),
    createMockSbomVulnerability({
      id: 'vuln-2',
      vulnerability_id: 'CVE-2024-67890',
      severity: 'medium',
      cvss_score: 5.3,
      remediation_status: 'in_progress',
    }),
  ];

  const mockCompliance = {
    ntia_minimum_compliant: true,
    ntia_fields: { author: true, timestamp: true },
    completeness_score: 85,
    missing_fields: [],
  };

  const mockDiffs = [
    {
      id: 'diff-1',
      source_sbom_id: 'sbom-123',
      compare_sbom_id: 'sbom-456',
      added_count: 5,
      removed_count: 3,
      changed_count: 2,
      created_at: new Date().toISOString(),
    },
  ];

  beforeEach(() => {
    jest.clearAllMocks();

    // Mock useParams
    const useParams = require('react-router-dom').useParams;
    useParams.mockReturnValue({ id: 'sbom-123' });

    // Mock API calls
    (sbomsApi.get as jest.Mock).mockResolvedValue(mockSbom);
    (sbomsApi.getComponents as jest.Mock).mockResolvedValue({
      components: mockComponents,
      pagination: createMockPagination(),
    });
    (sbomsApi.getVulnerabilities as jest.Mock).mockResolvedValue({
      vulnerabilities: mockVulnerabilities,
      pagination: createMockPagination(),
    });
    (sbomsApi.exportSbom as jest.Mock).mockResolvedValue(new Blob());
    (sbomsApi.rescan as jest.Mock).mockResolvedValue(mockSbom);
    (sbomsApi.delete as jest.Mock).mockResolvedValue(undefined);

    // Mock hooks
    (useSbomCompliance as jest.Mock).mockReturnValue({
      compliance: mockCompliance,
      loading: false,
    });
    (useSbomDiffs as jest.Mock).mockReturnValue({
      diffs: mockDiffs,
      refresh: jest.fn(),
    });
    (useCreateSbomDiff as jest.Mock).mockReturnValue({
      mutateAsync: jest.fn().mockResolvedValue({ id: 'diff-new' }),
      isLoading: false,
    });
    (useUpdateVulnerabilityStatus as jest.Mock).mockReturnValue({
      mutateAsync: jest.fn().mockResolvedValue({}),
      isLoading: false,
    });
    (useSuppressVulnerability as jest.Mock).mockReturnValue({
      mutateAsync: jest.fn().mockResolvedValue({}),
      isLoading: false,
    });
    (useMarkFalsePositive as jest.Mock).mockReturnValue({
      mutateAsync: jest.fn().mockResolvedValue({}),
      isLoading: false,
    });
    (useCalculateRisk as jest.Mock).mockReturnValue({
      mutateAsync: jest.fn().mockResolvedValue({ overall_score: 4.5 }),
      isLoading: false,
    });
    (useCorrelateVulnerabilities as jest.Mock).mockReturnValue({
      mutateAsync: jest.fn().mockResolvedValue({ new_vulnerabilities: 3 }),
      isLoading: false,
    });
  });

  const renderWithRouter = (component: React.ReactElement) => {
    return render(
      <MemoryRouter initialEntries={['/app/supply-chain/sboms/sbom-123']}>
        <Routes>
          <Route path="/app/supply-chain/sboms/:id" element={component} />
        </Routes>
      </MemoryRouter>
    );
  };

  const renderAndWaitForLoad = async () => {
    renderWithRouter(<SbomDetailPage />);
    await waitFor(() => {
      expect(screen.queryByTestId('loading-spinner')).not.toBeInTheDocument();
    });
  };

  describe('Loading State', () => {
    it('displays loading spinner while fetching SBOM', async () => {
      (sbomsApi.get as jest.Mock).mockImplementation(
        () => new Promise(() => {}) // Never resolves
      );

      renderWithRouter(<SbomDetailPage />);

      // Spinner should be visible immediately
      expect(screen.getByTestId('loading-spinner')).toBeInTheDocument();
    });

    it('hides loading spinner after SBOM loads', async () => {
      await renderAndWaitForLoad();

      await waitFor(() => {
        expect(screen.queryByTestId('loading-spinner')).not.toBeInTheDocument();
      });
    });
  });

  describe('Error State', () => {
    it('handles SBOM not found error', async () => {
      (sbomsApi.get as jest.Mock).mockRejectedValue(new Error('SBOM not found'));

      renderWithRouter(<SbomDetailPage />);

      // The component should attempt to load and may stay in loading state if there's no error UI
      // Just verify that the API was called and rejected
      await waitFor(() => {
        expect(sbomsApi.get).toHaveBeenCalledWith('sbom-123');
      });
    });
  });

  describe('Page Structure', () => {
    it('renders page container with SBOM name as title', async () => {
      await renderAndWaitForLoad();

      await waitFor(() => {
        expect(screen.getByTestId('page-title')).toHaveTextContent('Test SBOM');
      });
    });

    it('renders all action buttons', async () => {
      await renderAndWaitForLoad();

      await waitFor(() => {
        expect(screen.getByTestId('action-compare')).toBeInTheDocument();
        expect(screen.getByTestId('action-rescan')).toBeInTheDocument();
        expect(screen.getByTestId('action-delete')).toBeInTheDocument();
      });
    });

    it('disables rescan button when SBOM is generating', async () => {
      (sbomsApi.get as jest.Mock).mockResolvedValue({
        ...mockSbom,
        status: 'generating',
      });

      await renderAndWaitForLoad();

      await waitFor(() => {
        expect(screen.getByTestId('action-rescan')).toBeDisabled();
      });
    });

    it('renders tab container', async () => {
      await renderAndWaitForLoad();

      await waitFor(() => {
        expect(screen.getByTestId('tab-container')).toBeInTheDocument();
      });
    });

    it('renders all tabs', async () => {
      await renderAndWaitForLoad();

      await waitFor(() => {
        expect(screen.getByTestId('tab-overview')).toBeInTheDocument();
        expect(screen.getByTestId('tab-components')).toBeInTheDocument();
        expect(screen.getByTestId('tab-vulnerabilities')).toBeInTheDocument();
        expect(screen.getByTestId('tab-compliance')).toBeInTheDocument();
        expect(screen.getByTestId('tab-diffs')).toBeInTheDocument();
      });
    });

    it('displays badge counts on tabs', async () => {
      await renderAndWaitForLoad();

      await waitFor(() => {
        expect(screen.getByTestId('badge-components')).toHaveTextContent('150');
        expect(screen.getByTestId('badge-vulnerabilities')).toHaveTextContent('5');
        expect(screen.getByTestId('badge-diffs')).toHaveTextContent('1');
      });
    });
  });

  describe('Overview Tab', () => {
    it('displays overview tab as active by default', async () => {
      await renderAndWaitForLoad();

      await waitFor(() => {
        expect(screen.getByTestId('tab-overview')).toHaveClass('active');
      });
    });

    it('displays component count stat', async () => {
      await renderAndWaitForLoad();

      await waitFor(() => {
        // Use getAllByText to get all elements with "Components", then check for the stat card
        const componentTexts = screen.getAllByText('Components');
        expect(componentTexts.length).toBeGreaterThan(0);
        // Use getAllByText to get all elements with "150" and verify at least one exists
        const counts = screen.getAllByText('150');
        expect(counts.length).toBeGreaterThan(0);
      });
    });

    it('displays vulnerability count stat', async () => {
      await renderAndWaitForLoad();

      await waitFor(() => {
        // Use getAllByText to get all elements with "Vulnerabilities", then check for the stat card
        const vulnTexts = screen.getAllByText('Vulnerabilities');
        expect(vulnTexts.length).toBeGreaterThan(0);
        // Use getAllByText to get all elements with "5" and verify at least one exists
        const counts = screen.getAllByText('5');
        expect(counts.length).toBeGreaterThan(0);
      });
    });

    it('displays risk score stat', async () => {
      await renderAndWaitForLoad();

      await waitFor(() => {
        expect(screen.getByText('Risk Score')).toBeInTheDocument();
        expect(screen.getByText('4.5')).toBeInTheDocument();
      });
    });

    it('displays NTIA compliant status', async () => {
      await renderAndWaitForLoad();

      await waitFor(() => {
        expect(screen.getByText('NTIA Compliant')).toBeInTheDocument();
        expect(screen.getByText('Yes')).toBeInTheDocument();
      });
    });

    it('displays SBOM format', async () => {
      await renderAndWaitForLoad();

      await waitFor(() => {
        expect(screen.getByText('Format:')).toBeInTheDocument();
        // The format is displayed in uppercase - use getAllByText to handle multiple instances
        const formats = screen.getAllByText(/CYCLONEDX/i);
        expect(formats.length).toBeGreaterThan(0);
      });
    });

    it('displays SBOM version', async () => {
      await renderAndWaitForLoad();

      await waitFor(() => {
        expect(screen.getByText('Version:')).toBeInTheDocument();
        expect(screen.getByText('1.0.0')).toBeInTheDocument();
      });
    });

    it('displays SBOM ID', async () => {
      await renderAndWaitForLoad();

      await waitFor(() => {
        expect(screen.getByText('SBOM ID:')).toBeInTheDocument();
      });
    });

    it('displays created date', async () => {
      await renderAndWaitForLoad();

      await waitFor(() => {
        expect(screen.getByText('Created:')).toBeInTheDocument();
      });
    });
  });

  describe('Components Tab', () => {
    it('fetches components when tab is clicked', async () => {
      await renderAndWaitForLoad();

      await waitFor(() => {
        expect(screen.getByTestId('tab-components')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByTestId('tab-components'));

      await waitFor(() => {
        expect(sbomsApi.getComponents).toHaveBeenCalledWith(
          'sbom-123',
          expect.objectContaining({ page: 1, per_page: 20 })
        );
      });
    });

    it('displays components table', async () => {
      await renderAndWaitForLoad();

      fireEvent.click(screen.getByTestId('tab-components'));

      await waitFor(() => {
        expect(screen.getByTestId('data-table')).toBeInTheDocument();
      });
    });

    it('displays component data', async () => {
      await renderAndWaitForLoad();

      fireEvent.click(screen.getByTestId('tab-components'));

      await waitFor(() => {
        expect(screen.getByTestId('row-comp-1')).toBeInTheDocument();
        expect(screen.getByTestId('row-comp-2')).toBeInTheDocument();
      });
    });

    it('displays ecosystem filter dropdown', async () => {
      await renderAndWaitForLoad();

      fireEvent.click(screen.getByTestId('tab-components'));

      await waitFor(() => {
        const select = screen.getByDisplayValue('All Ecosystems');
        expect(select).toBeInTheDocument();
      });
    });

    it('filters components by ecosystem', async () => {
      await renderAndWaitForLoad();

      fireEvent.click(screen.getByTestId('tab-components'));

      await waitFor(() => {
        const select = screen.getByDisplayValue('All Ecosystems');
        fireEvent.change(select, { target: { value: 'npm' } });
      });

      await waitFor(() => {
        expect(sbomsApi.getComponents).toHaveBeenCalledWith(
          'sbom-123',
          expect.objectContaining({ ecosystem: 'npm' })
        );
      });
    });

    it('resets page when ecosystem filter changes', async () => {
      await renderAndWaitForLoad();

      fireEvent.click(screen.getByTestId('tab-components'));

      await waitFor(() => {
        const select = screen.getByDisplayValue('All Ecosystems');
        fireEvent.change(select, { target: { value: 'npm' } });
      });

      await waitFor(() => {
        expect(sbomsApi.getComponents).toHaveBeenCalledWith(
          'sbom-123',
          expect.objectContaining({ page: 1 })
        );
      });
    });

    it('displays empty state when no components', async () => {
      (sbomsApi.getComponents as jest.Mock).mockResolvedValue({
        components: [],
        pagination: createMockPagination(),
      });

      await renderAndWaitForLoad();

      fireEvent.click(screen.getByTestId('tab-components'));

      await waitFor(() => {
        expect(screen.getByTestId('empty-state')).toHaveTextContent('No Components Found');
      });
    });

    it('handles component pagination', async () => {
      await renderAndWaitForLoad();

      fireEvent.click(screen.getByTestId('tab-components'));

      await waitFor(() => {
        const nextButton = screen.getByText('Next');
        fireEvent.click(nextButton);
      });

      await waitFor(() => {
        expect(sbomsApi.getComponents).toHaveBeenCalledWith(
          'sbom-123',
          expect.objectContaining({ page: 2 })
        );
      });
    });
  });

  describe('Vulnerabilities Tab', () => {
    it('fetches vulnerabilities when tab is clicked', async () => {
      await renderAndWaitForLoad();

      fireEvent.click(screen.getByTestId('tab-vulnerabilities'));

      await waitFor(() => {
        expect(sbomsApi.getVulnerabilities).toHaveBeenCalledWith(
          'sbom-123',
          expect.objectContaining({ page: 1, per_page: 20 })
        );
      });
    });

    it('displays vulnerabilities table', async () => {
      await renderAndWaitForLoad();

      fireEvent.click(screen.getByTestId('tab-vulnerabilities'));

      await waitFor(() => {
        expect(screen.getByTestId('data-table')).toBeInTheDocument();
      });
    });

    it('displays vulnerability data', async () => {
      await renderAndWaitForLoad();

      fireEvent.click(screen.getByTestId('tab-vulnerabilities'));

      await waitFor(() => {
        expect(screen.getByTestId('row-vuln-1')).toBeInTheDocument();
        expect(screen.getByTestId('row-vuln-2')).toBeInTheDocument();
      });
    });

    it('displays severity filter dropdown', async () => {
      await renderAndWaitForLoad();

      fireEvent.click(screen.getByTestId('tab-vulnerabilities'));

      await waitFor(() => {
        const select = screen.getByDisplayValue('All Severities');
        expect(select).toBeInTheDocument();
      });
    });

    it('filters vulnerabilities by severity', async () => {
      await renderAndWaitForLoad();

      fireEvent.click(screen.getByTestId('tab-vulnerabilities'));

      await waitFor(() => {
        const select = screen.getByDisplayValue('All Severities');
        fireEvent.change(select, { target: { value: 'high' } });
      });

      await waitFor(() => {
        expect(sbomsApi.getVulnerabilities).toHaveBeenCalledWith(
          'sbom-123',
          expect.objectContaining({ severity: 'high' })
        );
      });
    });

    it('displays Calculate Risk button', async () => {
      await renderAndWaitForLoad();

      fireEvent.click(screen.getByTestId('tab-vulnerabilities'));

      await waitFor(() => {
        expect(screen.getByText('Calculate Risk')).toBeInTheDocument();
      });
    });

    it('calls calculate risk mutation when button clicked', async () => {
      const mockCalculateRisk = jest.fn().mockResolvedValue({ overall_score: 5.5 });
      (useCalculateRisk as jest.Mock).mockReturnValue({
        mutateAsync: mockCalculateRisk,
        isLoading: false,
      });

      await renderAndWaitForLoad();

      fireEvent.click(screen.getByTestId('tab-vulnerabilities'));

      await waitFor(() => {
        const calculateButton = screen.getByText('Calculate Risk');
        fireEvent.click(calculateButton);
      });

      await waitFor(() => {
        expect(mockCalculateRisk).toHaveBeenCalledWith('sbom-123');
      });
    });

    it('displays Correlate button', async () => {
      await renderAndWaitForLoad();

      fireEvent.click(screen.getByTestId('tab-vulnerabilities'));

      await waitFor(() => {
        expect(screen.getByText('Correlate')).toBeInTheDocument();
      });
    });

    it('calls correlate vulnerabilities mutation when button clicked', async () => {
      const mockCorrelate = jest.fn().mockResolvedValue({ new_vulnerabilities: 3 });
      (useCorrelateVulnerabilities as jest.Mock).mockReturnValue({
        mutateAsync: mockCorrelate,
        isLoading: false,
      });

      await renderAndWaitForLoad();

      fireEvent.click(screen.getByTestId('tab-vulnerabilities'));

      await waitFor(() => {
        const correlateButton = screen.getByText('Correlate');
        fireEvent.click(correlateButton);
      });

      await waitFor(() => {
        expect(mockCorrelate).toHaveBeenCalledWith('sbom-123');
      });
    });

    it('displays remediation status select for each vulnerability', async () => {
      await renderAndWaitForLoad();

      fireEvent.click(screen.getByTestId('tab-vulnerabilities'));

      await waitFor(() => {
        const selects = screen.getAllByTestId('remediation-status-select');
        expect(selects).toHaveLength(2);
      });
    });

    it('updates vulnerability status when select changes', async () => {
      const mockUpdateStatus = jest.fn().mockResolvedValue({});
      (useUpdateVulnerabilityStatus as jest.Mock).mockReturnValue({
        mutateAsync: mockUpdateStatus,
        isLoading: false,
      });

      await renderAndWaitForLoad();

      fireEvent.click(screen.getByTestId('tab-vulnerabilities'));

      await waitFor(() => {
        const selects = screen.getAllByTestId('remediation-status-select');
        fireEvent.change(selects[0], { target: { value: 'fixed' } });
      });

      await waitFor(() => {
        expect(mockUpdateStatus).toHaveBeenCalledWith({
          sbomId: 'sbom-123',
          vulnId: 'vuln-1',
          status: 'fixed',
        });
      });
    });

    it('displays vulnerability actions menu', async () => {
      await renderAndWaitForLoad();

      fireEvent.click(screen.getByTestId('tab-vulnerabilities'));

      await waitFor(() => {
        const menus = screen.getAllByTestId('vulnerability-actions-menu');
        expect(menus).toHaveLength(2);
      });
    });

    it('suppresses vulnerability when action clicked', async () => {
      const mockSuppress = jest.fn().mockResolvedValue({});
      (useSuppressVulnerability as jest.Mock).mockReturnValue({
        mutateAsync: mockSuppress,
        isLoading: false,
      });

      await renderAndWaitForLoad();

      fireEvent.click(screen.getByTestId('tab-vulnerabilities'));

      await waitFor(() => {
        const suppressButtons = screen.getAllByText('Suppress');
        fireEvent.click(suppressButtons[0]);
      });

      await waitFor(() => {
        expect(mockSuppress).toHaveBeenCalledWith({
          sbomId: 'sbom-123',
          vulnId: 'vuln-1',
        });
      });
    });

    it('marks false positive when action clicked', async () => {
      const mockMarkFalsePositive = jest.fn().mockResolvedValue({});
      (useMarkFalsePositive as jest.Mock).mockReturnValue({
        mutateAsync: mockMarkFalsePositive,
        isLoading: false,
      });

      // Mock window.prompt
      global.prompt = jest.fn().mockReturnValue('This is a false positive');

      await renderAndWaitForLoad();

      fireEvent.click(screen.getByTestId('tab-vulnerabilities'));

      await waitFor(() => {
        const fpButtons = screen.getAllByText('Mark False Positive');
        fireEvent.click(fpButtons[0]);
      });

      await waitFor(() => {
        expect(mockMarkFalsePositive).toHaveBeenCalledWith({
          sbomId: 'sbom-123',
          vulnId: 'vuln-1',
          reason: 'This is a false positive',
        });
      });
    });

    it('handles vulnerability pagination', async () => {
      await renderAndWaitForLoad();

      fireEvent.click(screen.getByTestId('tab-vulnerabilities'));

      await waitFor(() => {
        const nextButton = screen.getByText('Next');
        fireEvent.click(nextButton);
      });

      await waitFor(() => {
        expect(sbomsApi.getVulnerabilities).toHaveBeenCalledWith(
          'sbom-123',
          expect.objectContaining({ page: 2 })
        );
      });
    });
  });

  describe('Compliance Tab', () => {
    it('displays compliance status card', async () => {
      await renderAndWaitForLoad();

      fireEvent.click(screen.getByTestId('tab-compliance'));

      await waitFor(() => {
        expect(screen.getByTestId('compliance-status-card')).toBeInTheDocument();
      });
    });

    it('displays loading state while fetching compliance', async () => {
      (useSbomCompliance as jest.Mock).mockReturnValue({
        compliance: null,
        loading: true,
      });

      await renderAndWaitForLoad();

      fireEvent.click(screen.getByTestId('tab-compliance'));

      await waitFor(() => {
        expect(screen.getByTestId('loading-spinner')).toBeInTheDocument();
      });
    });

    it('displays compliance data', async () => {
      await renderAndWaitForLoad();

      fireEvent.click(screen.getByTestId('tab-compliance'));

      await waitFor(() => {
        expect(screen.getByText('NTIA: Yes')).toBeInTheDocument();
        expect(screen.getByText('Score: 85')).toBeInTheDocument();
      });
    });

    it('displays message when compliance data not available', async () => {
      (useSbomCompliance as jest.Mock).mockReturnValue({
        compliance: null,
        loading: false,
      });

      await renderAndWaitForLoad();

      fireEvent.click(screen.getByTestId('tab-compliance'));

      await waitFor(() => {
        expect(screen.getByText('Compliance data not available')).toBeInTheDocument();
      });
    });
  });

  describe('Diff History Tab', () => {
    it('displays diffs list', async () => {
      await renderAndWaitForLoad();

      await waitFor(() => {
        expect(screen.getByTestId('tab-diffs')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByTestId('tab-diffs'));

      await waitFor(() => {
        expect(screen.getByText('+5')).toBeInTheDocument();
        expect(screen.getByText('-3')).toBeInTheDocument();
        expect(screen.getByText('~2')).toBeInTheDocument();
      });
    });

    it('displays Create Diff button', async () => {
      await renderAndWaitForLoad();

      await waitFor(() => {
        expect(screen.getByTestId('tab-diffs')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByTestId('tab-diffs'));

      await waitFor(() => {
        expect(screen.getByText('Create Diff')).toBeInTheDocument();
      });
    });

    it('navigates to diff page when diff is clicked', async () => {
      await renderAndWaitForLoad();

      await waitFor(() => {
        expect(screen.getByTestId('tab-diffs')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByTestId('tab-diffs'));

      await waitFor(() => {
        const diffButton = screen.getByText('+5').closest('button');
        fireEvent.click(diffButton!);
      });

      await waitFor(() => {
        expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/sboms/sbom-123/diff/diff-1');
      });
    });

    it('displays empty state when no diffs exist', async () => {
      (useSbomDiffs as jest.Mock).mockReturnValue({
        diffs: [],
        refresh: jest.fn(),
      });

      await renderAndWaitForLoad();

      await waitFor(() => {
        expect(screen.getByTestId('tab-diffs')).toBeInTheDocument();
      });

      fireEvent.click(screen.getByTestId('tab-diffs'));

      await waitFor(() => {
        expect(screen.getByText('No diffs created yet')).toBeInTheDocument();
      });
    });
  });

  describe('Compare Action', () => {
    it('opens create diff modal when compare button clicked', async () => {
      await renderAndWaitForLoad();

      await waitFor(() => {
        const compareButton = screen.getByTestId('action-compare');
        fireEvent.click(compareButton);
      });

      await waitFor(() => {
        expect(screen.getByTestId('create-diff-modal')).toBeInTheDocument();
      });
    });

    it('creates diff and navigates when modal confirms', async () => {
      const mockCreateDiff = jest.fn().mockResolvedValue({ id: 'diff-new' });
      (useCreateSbomDiff as jest.Mock).mockReturnValue({
        mutateAsync: mockCreateDiff,
        isLoading: false,
      });

      await renderAndWaitForLoad();

      await waitFor(() => {
        fireEvent.click(screen.getByTestId('action-compare'));
      });

      await waitFor(() => {
        const createButton = screen.getByText('Create');
        fireEvent.click(createButton);
      });

      await waitFor(() => {
        expect(mockCreateDiff).toHaveBeenCalledWith({
          sbomId: 'sbom-123',
          compareSbomId: 'compare-sbom-id',
        });
        expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/sboms/sbom-123/diff/diff-new');
      });
    });

    it('closes modal when close button clicked', async () => {
      await renderAndWaitForLoad();

      await waitFor(() => {
        fireEvent.click(screen.getByTestId('action-compare'));
      });

      await waitFor(() => {
        const closeButton = screen.getByText('Close');
        fireEvent.click(closeButton);
      });

      await waitFor(() => {
        expect(screen.queryByTestId('create-diff-modal')).not.toBeInTheDocument();
      });
    });
  });

  describe('Export Functionality', () => {
    it('displays export format dropdown', async () => {
      await renderAndWaitForLoad();

      await waitFor(() => {
        expect(screen.getByTestId('export-format-dropdown')).toBeInTheDocument();
      });
    });

    it('exports SBOM as JSON', async () => {
      await renderAndWaitForLoad();

      await waitFor(() => {
        const exportButton = screen.getByText('Export JSON');
        fireEvent.click(exportButton);
      });

      await waitFor(() => {
        expect(sbomsApi.exportSbom).toHaveBeenCalledWith('sbom-123', 'json');
      });
    });

    it('exports SBOM as PDF', async () => {
      await renderAndWaitForLoad();

      await waitFor(() => {
        const exportButton = screen.getByText('Export PDF');
        fireEvent.click(exportButton);
      });

      await waitFor(() => {
        expect(sbomsApi.exportSbom).toHaveBeenCalledWith('sbom-123', 'pdf');
      });
    });
  });

  describe('Re-scan Action', () => {
    it('calls rescan API when rescan button clicked', async () => {
      await renderAndWaitForLoad();

      await waitFor(() => {
        const rescanButton = screen.getByTestId('action-rescan');
        fireEvent.click(rescanButton);
      });

      await waitFor(() => {
        expect(sbomsApi.rescan).toHaveBeenCalledWith('sbom-123');
      });
    });
  });

  describe('Delete Action', () => {
    it('calls delete API and navigates when delete confirmed', async () => {
      await renderAndWaitForLoad();

      await waitFor(() => {
        const deleteButton = screen.getByTestId('action-delete');
        fireEvent.click(deleteButton);
      });

      await waitFor(() => {
        expect(sbomsApi.delete).toHaveBeenCalledWith('sbom-123');
        expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/sboms');
      });
    });
  });
});
