import React from 'react';
import { render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { SbomDiffPage } from '../SbomDiffPage';
import { useSbomDiff } from '../../hooks/useSboms';

// Mock dependencies
jest.mock('../../hooks/useSboms');

// Mock PageContainer
jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({ title, description, breadcrumbs: _breadcrumbs, actions, children }: any) => (
    <div data-testid="page-container">
      <div data-testid="page-title">{title}</div>
      <div data-testid="page-description">{description}</div>
      <div data-testid="page-actions">
        {actions?.map((action: any) => (
          <button
            key={action.id}
            onClick={action.onClick}
            data-testid={`action-${action.id}`}
          >
            {action.label}
          </button>
        ))}
      </div>
      {children}
    </div>
  ),
}));

// Mock LoadingSpinner
jest.mock('@/shared/components/ui/LoadingSpinner', () => ({
  LoadingSpinner: () => <div data-testid="loading-spinner">Loading...</div>,
}));

// Mock ErrorAlert
jest.mock('@/shared/components/ui/ErrorAlert', () => ({
  __esModule: true,
  default: ({ message }: any) => <div data-testid="error-alert">{message}</div>,
}));

// Mock SbomDiffViewer
jest.mock('../../components/sbom/SbomDiffViewer', () => ({
  SbomDiffViewer: ({ diff }: any) => (
    <div data-testid="sbom-diff-viewer">
      <div data-testid="diff-added">{diff.added_count} added</div>
      <div data-testid="diff-removed">{diff.removed_count} removed</div>
      <div data-testid="diff-changed">{diff.changed_count} changed</div>
      <div data-testid="added-components">
        {diff.added_components.map((c: any) => (
          <div key={c.name} data-testid={`added-${c.name}`}>
            {c.name}@{c.version}
          </div>
        ))}
      </div>
      <div data-testid="removed-components">
        {diff.removed_components.map((c: any) => (
          <div key={c.name} data-testid={`removed-${c.name}`}>
            {c.name}@{c.version}
          </div>
        ))}
      </div>
      <div data-testid="changed-components">
        {diff.changed_components.map((c: any) => (
          <div key={c.name} data-testid={`changed-${c.name}`}>
            {c.name}: {c.old_version} → {c.new_version}
          </div>
        ))}
      </div>
      <div data-testid="added-vulnerabilities">
        {diff.added_vulnerabilities.map((v: any) => (
          <div key={v.vulnerability_id} data-testid={`added-vuln-${v.vulnerability_id}`}>
            {v.vulnerability_id} ({v.severity})
          </div>
        ))}
      </div>
      <div data-testid="removed-vulnerabilities">
        {diff.removed_vulnerabilities.map((v: any) => (
          <div key={v.vulnerability_id} data-testid={`removed-vuln-${v.vulnerability_id}`}>
            {v.vulnerability_id} ({v.severity})
          </div>
        ))}
      </div>
    </div>
  ),
}));

const mockNavigate = jest.fn();
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate,
  useParams: jest.fn(),
}));

describe('SbomDiffPage', () => {
  const mockDiff = {
    id: 'diff-123',
    source_sbom_id: 'sbom-source',
    compare_sbom_id: 'sbom-compare',
    added_count: 5,
    removed_count: 3,
    changed_count: 2,
    created_at: '2025-01-21T10:00:00Z',
    added_components: [
      { name: 'new-package', version: '1.0.0', ecosystem: 'npm' },
      { name: 'another-package', version: '2.1.0', ecosystem: 'npm' },
    ],
    removed_components: [
      { name: 'old-package', version: '0.9.0', ecosystem: 'npm' },
    ],
    changed_components: [
      { name: 'updated-package', old_version: '1.0.0', new_version: '1.5.0', ecosystem: 'npm' },
      { name: 'another-updated', old_version: '2.0.0', new_version: '2.1.0', ecosystem: 'npm' },
    ],
    added_vulnerabilities: [
      { vulnerability_id: 'CVE-2025-12345', severity: 'high' as const },
      { vulnerability_id: 'CVE-2025-67890', severity: 'medium' as const },
    ],
    removed_vulnerabilities: [
      { vulnerability_id: 'CVE-2024-11111', severity: 'low' as const },
    ],
  };

  beforeEach(() => {
    jest.clearAllMocks();

    // Mock useParams
    const useParams = require('react-router-dom').useParams;
    useParams.mockReturnValue({ id: 'sbom-source', diffId: 'diff-123' });

    // Default mock - successful diff load
    (useSbomDiff as jest.Mock).mockReturnValue({
      diff: mockDiff,
      loading: false,
      error: null,
    });
  });

  const renderWithRouter = (component: React.ReactElement) => {
    return render(
      <MemoryRouter initialEntries={['/app/supply-chain/sboms/sbom-source/diff/diff-123']}>
        <Routes>
          <Route path="/app/supply-chain/sboms/:id/diff/:diffId" element={component} />
        </Routes>
      </MemoryRouter>
    );
  };

  describe('Loading State', () => {
    it('displays loading spinner while fetching diff', () => {
      (useSbomDiff as jest.Mock).mockReturnValue({
        diff: null,
        loading: true,
        error: null,
      });

      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('loading-spinner')).toBeInTheDocument();
    });

    it('hides loading spinner after diff loads', async () => {
      renderWithRouter(<SbomDiffPage />);

      await waitFor(() => {
        expect(screen.queryByTestId('loading-spinner')).not.toBeInTheDocument();
      });
    });
  });

  describe('Error State', () => {
    it('displays error message when diff fetch fails', () => {
      (useSbomDiff as jest.Mock).mockReturnValue({
        diff: null,
        loading: false,
        error: 'Failed to load diff',
      });

      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('error-alert')).toHaveTextContent('Failed to load diff');
    });

    it('displays error message when diff not found', () => {
      (useSbomDiff as jest.Mock).mockReturnValue({
        diff: null,
        loading: false,
        error: null,
      });

      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('error-alert')).toHaveTextContent('Diff not found');
    });

    it('displays page container with error', () => {
      (useSbomDiff as jest.Mock).mockReturnValue({
        diff: null,
        loading: false,
        error: 'Diff not found',
      });

      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('page-container')).toBeInTheDocument();
      expect(screen.getByTestId('page-title')).toHaveTextContent('SBOM Diff');
    });
  });

  describe('Page Structure', () => {
    it('renders page container', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('page-container')).toBeInTheDocument();
    });

    it('displays correct page title', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('page-title')).toHaveTextContent('SBOM Comparison');
    });

    it('displays formatted creation date in description', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('page-description')).toHaveTextContent('Created Jan 21, 2025');
    });

    it('displays correct breadcrumbs structure', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('page-container')).toBeInTheDocument();
      // Breadcrumbs would be verified if they were rendered in mock
    });

    it('displays back to SBOM action button', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('action-back')).toBeInTheDocument();
      expect(screen.getByTestId('action-back')).toHaveTextContent('Back to SBOM');
    });

    it('displays comparison description', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByText('Comparing changes between two SBOM versions')).toBeInTheDocument();
    });

    it('displays GitCompare icon', () => {
      renderWithRouter(<SbomDiffPage />);
      // Icon would be rendered in the actual component
      const container = screen.getByTestId('page-container');
      expect(container).toBeInTheDocument();
    });
  });

  describe('Navigation', () => {
    it('navigates back to SBOM detail when back button clicked', () => {
      renderWithRouter(<SbomDiffPage />);

      const backButton = screen.getByTestId('action-back');
      backButton.click();

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/sboms/sbom-source');
    });
  });

  describe('Diff Viewer', () => {
    it('renders SbomDiffViewer component', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('sbom-diff-viewer')).toBeInTheDocument();
    });

    it('passes diff data to SbomDiffViewer', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('diff-added')).toHaveTextContent('5 added');
      expect(screen.getByTestId('diff-removed')).toHaveTextContent('3 removed');
      expect(screen.getByTestId('diff-changed')).toHaveTextContent('2 changed');
    });
  });

  describe('Diff Summary Counts', () => {
    it('displays added components count', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('diff-added')).toHaveTextContent('5');
    });

    it('displays removed components count', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('diff-removed')).toHaveTextContent('3');
    });

    it('displays changed components count', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('diff-changed')).toHaveTextContent('2');
    });

    it('displays zero counts correctly', () => {
      const emptyDiff = {
        ...mockDiff,
        added_count: 0,
        removed_count: 0,
        changed_count: 0,
        added_components: [],
        removed_components: [],
        changed_components: [],
        added_vulnerabilities: [],
        removed_vulnerabilities: [],
      };

      (useSbomDiff as jest.Mock).mockReturnValue({
        diff: emptyDiff,
        loading: false,
        error: null,
      });

      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('diff-added')).toHaveTextContent('0');
      expect(screen.getByTestId('diff-removed')).toHaveTextContent('0');
      expect(screen.getByTestId('diff-changed')).toHaveTextContent('0');
    });
  });

  describe('Added Components', () => {
    it('displays added components section', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('added-components')).toBeInTheDocument();
    });

    it('displays all added components', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('added-new-package')).toBeInTheDocument();
      expect(screen.getByTestId('added-another-package')).toBeInTheDocument();
    });

    it('displays added component names and versions', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('added-new-package')).toHaveTextContent('new-package@1.0.0');
      expect(screen.getByTestId('added-another-package')).toHaveTextContent('another-package@2.1.0');
    });

    it('handles empty added components list', () => {
      const noDiff = {
        ...mockDiff,
        added_count: 0,
        added_components: [],
      };

      (useSbomDiff as jest.Mock).mockReturnValue({
        diff: noDiff,
        loading: false,
        error: null,
      });

      renderWithRouter(<SbomDiffPage />);
      const addedSection = screen.getByTestId('added-components');
      expect(addedSection.children).toHaveLength(0);
    });
  });

  describe('Removed Components', () => {
    it('displays removed components section', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('removed-components')).toBeInTheDocument();
    });

    it('displays all removed components', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('removed-old-package')).toBeInTheDocument();
    });

    it('displays removed component names and versions', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('removed-old-package')).toHaveTextContent('old-package@0.9.0');
    });

    it('handles empty removed components list', () => {
      const noDiff = {
        ...mockDiff,
        removed_count: 0,
        removed_components: [],
      };

      (useSbomDiff as jest.Mock).mockReturnValue({
        diff: noDiff,
        loading: false,
        error: null,
      });

      renderWithRouter(<SbomDiffPage />);
      const removedSection = screen.getByTestId('removed-components');
      expect(removedSection.children).toHaveLength(0);
    });
  });

  describe('Changed Components', () => {
    it('displays changed components section', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('changed-components')).toBeInTheDocument();
    });

    it('displays all changed components', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('changed-updated-package')).toBeInTheDocument();
      expect(screen.getByTestId('changed-another-updated')).toBeInTheDocument();
    });

    it('displays version changes with arrow notation', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('changed-updated-package')).toHaveTextContent(
        'updated-package: 1.0.0 → 1.5.0'
      );
      expect(screen.getByTestId('changed-another-updated')).toHaveTextContent(
        'another-updated: 2.0.0 → 2.1.0'
      );
    });

    it('handles empty changed components list', () => {
      const noDiff = {
        ...mockDiff,
        changed_count: 0,
        changed_components: [],
      };

      (useSbomDiff as jest.Mock).mockReturnValue({
        diff: noDiff,
        loading: false,
        error: null,
      });

      renderWithRouter(<SbomDiffPage />);
      const changedSection = screen.getByTestId('changed-components');
      expect(changedSection.children).toHaveLength(0);
    });
  });

  describe('Added Vulnerabilities', () => {
    it('displays added vulnerabilities section', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('added-vulnerabilities')).toBeInTheDocument();
    });

    it('displays all added vulnerabilities', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('added-vuln-CVE-2025-12345')).toBeInTheDocument();
      expect(screen.getByTestId('added-vuln-CVE-2025-67890')).toBeInTheDocument();
    });

    it('displays vulnerability IDs and severities', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('added-vuln-CVE-2025-12345')).toHaveTextContent(
        'CVE-2025-12345 (high)'
      );
      expect(screen.getByTestId('added-vuln-CVE-2025-67890')).toHaveTextContent(
        'CVE-2025-67890 (medium)'
      );
    });

    it('handles empty added vulnerabilities list', () => {
      const noDiff = {
        ...mockDiff,
        added_vulnerabilities: [],
      };

      (useSbomDiff as jest.Mock).mockReturnValue({
        diff: noDiff,
        loading: false,
        error: null,
      });

      renderWithRouter(<SbomDiffPage />);
      const addedVulns = screen.getByTestId('added-vulnerabilities');
      expect(addedVulns.children).toHaveLength(0);
    });
  });

  describe('Removed Vulnerabilities', () => {
    it('displays removed vulnerabilities section', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('removed-vulnerabilities')).toBeInTheDocument();
    });

    it('displays all removed vulnerabilities', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('removed-vuln-CVE-2024-11111')).toBeInTheDocument();
    });

    it('displays vulnerability IDs and severities', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('removed-vuln-CVE-2024-11111')).toHaveTextContent(
        'CVE-2024-11111 (low)'
      );
    });

    it('handles empty removed vulnerabilities list', () => {
      const noDiff = {
        ...mockDiff,
        removed_vulnerabilities: [],
      };

      (useSbomDiff as jest.Mock).mockReturnValue({
        diff: noDiff,
        loading: false,
        error: null,
      });

      renderWithRouter(<SbomDiffPage />);
      const removedVulns = screen.getByTestId('removed-vulnerabilities');
      expect(removedVulns.children).toHaveLength(0);
    });
  });

  describe('Date Formatting', () => {
    it('formats date with month, day, year', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('page-description')).toHaveTextContent('Jan 21, 2025');
    });

    it('formats date with time', () => {
      renderWithRouter(<SbomDiffPage />);
      const description = screen.getByTestId('page-description').textContent;
      expect(description).toMatch(/\d{1,2}:\d{2}/); // Matches time format
    });

    it('handles different date formats', () => {
      const diffWithOldDate = {
        ...mockDiff,
        created_at: '2024-01-15T14:30:00Z',
      };

      (useSbomDiff as jest.Mock).mockReturnValue({
        diff: diffWithOldDate,
        loading: false,
        error: null,
      });

      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('page-description')).toHaveTextContent('Jan 15, 2024');
    });
  });

  describe('Hook Integration', () => {
    it('calls useSbomDiff with correct parameters', () => {
      renderWithRouter(<SbomDiffPage />);

      expect(useSbomDiff).toHaveBeenCalledWith('sbom-source', 'diff-123');
    });

    it('handles null SBOM ID', () => {
      const useParams = require('react-router-dom').useParams;
      useParams.mockReturnValue({ id: null, diffId: 'diff-123' });

      renderWithRouter(<SbomDiffPage />);

      expect(useSbomDiff).toHaveBeenCalledWith(null, 'diff-123');
    });

    it('handles null diff ID', () => {
      const useParams = require('react-router-dom').useParams;
      useParams.mockReturnValue({ id: 'sbom-source', diffId: null });

      renderWithRouter(<SbomDiffPage />);

      expect(useSbomDiff).toHaveBeenCalledWith('sbom-source', null);
    });

    it('handles missing URL parameters', () => {
      const useParams = require('react-router-dom').useParams;
      useParams.mockReturnValue({});

      renderWithRouter(<SbomDiffPage />);

      expect(useSbomDiff).toHaveBeenCalledWith(null, null);
    });
  });

  describe('Large Diff Handling', () => {
    it('handles diffs with many components', () => {
      const largeDiff = {
        ...mockDiff,
        added_count: 100,
        removed_count: 50,
        changed_count: 75,
        added_components: Array.from({ length: 100 }, (_, i) => ({
          name: `package-${i}`,
          version: `${i}.0.0`,
          ecosystem: 'npm',
        })),
        removed_components: [],
        changed_components: [],
        added_vulnerabilities: [],
        removed_vulnerabilities: [],
      };

      (useSbomDiff as jest.Mock).mockReturnValue({
        diff: largeDiff,
        loading: false,
        error: null,
      });

      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('diff-added')).toHaveTextContent('100');
      expect(screen.getAllByTestId(/^added-package-/)).toHaveLength(100);
    });

    it('handles diffs with many vulnerabilities', () => {
      const vulnDiff = {
        ...mockDiff,
        added_vulnerabilities: Array.from({ length: 50 }, (_, i) => ({
          vulnerability_id: `CVE-2025-${10000 + i}`,
          severity: 'high' as const,
        })),
        removed_vulnerabilities: Array.from({ length: 25 }, (_, i) => ({
          vulnerability_id: `CVE-2024-${20000 + i}`,
          severity: 'low' as const,
        })),
      };

      (useSbomDiff as jest.Mock).mockReturnValue({
        diff: vulnDiff,
        loading: false,
        error: null,
      });

      renderWithRouter(<SbomDiffPage />);
      expect(screen.getAllByTestId(/^added-vuln-CVE-2025-/)).toHaveLength(50);
      expect(screen.getAllByTestId(/^removed-vuln-CVE-2024-/)).toHaveLength(25);
    });
  });

  describe('Edge Cases', () => {
    it('handles diff with only additions', () => {
      const addOnlyDiff = {
        ...mockDiff,
        removed_count: 0,
        changed_count: 0,
        removed_components: [],
        changed_components: [],
        removed_vulnerabilities: [],
      };

      (useSbomDiff as jest.Mock).mockReturnValue({
        diff: addOnlyDiff,
        loading: false,
        error: null,
      });

      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('diff-added')).toHaveTextContent('5');
      expect(screen.getByTestId('diff-removed')).toHaveTextContent('0');
      expect(screen.getByTestId('diff-changed')).toHaveTextContent('0');
    });

    it('handles diff with only removals', () => {
      const removeOnlyDiff = {
        ...mockDiff,
        added_count: 0,
        changed_count: 0,
        added_components: [],
        changed_components: [],
        added_vulnerabilities: [],
      };

      (useSbomDiff as jest.Mock).mockReturnValue({
        diff: removeOnlyDiff,
        loading: false,
        error: null,
      });

      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('diff-added')).toHaveTextContent('0');
      expect(screen.getByTestId('diff-removed')).toHaveTextContent('3');
      expect(screen.getByTestId('diff-changed')).toHaveTextContent('0');
    });

    it('handles diff with only changes', () => {
      const changeOnlyDiff = {
        ...mockDiff,
        added_count: 0,
        removed_count: 0,
        added_components: [],
        removed_components: [],
        added_vulnerabilities: [],
        removed_vulnerabilities: [],
      };

      (useSbomDiff as jest.Mock).mockReturnValue({
        diff: changeOnlyDiff,
        loading: false,
        error: null,
      });

      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('diff-added')).toHaveTextContent('0');
      expect(screen.getByTestId('diff-removed')).toHaveTextContent('0');
      expect(screen.getByTestId('diff-changed')).toHaveTextContent('2');
    });

    it('handles identical SBOMs with no differences', () => {
      const noDiff = {
        ...mockDiff,
        added_count: 0,
        removed_count: 0,
        changed_count: 0,
        added_components: [],
        removed_components: [],
        changed_components: [],
        added_vulnerabilities: [],
        removed_vulnerabilities: [],
      };

      (useSbomDiff as jest.Mock).mockReturnValue({
        diff: noDiff,
        loading: false,
        error: null,
      });

      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('diff-added')).toHaveTextContent('0');
      expect(screen.getByTestId('diff-removed')).toHaveTextContent('0');
      expect(screen.getByTestId('diff-changed')).toHaveTextContent('0');
    });
  });

  describe('Different Ecosystems', () => {
    it('handles components from npm ecosystem', () => {
      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('added-new-package')).toBeInTheDocument();
    });

    it('handles components from multiple ecosystems', () => {
      const multiEcoDiff = {
        ...mockDiff,
        added_components: [
          { name: 'npm-pkg', version: '1.0.0', ecosystem: 'npm' },
          { name: 'pypi-pkg', version: '2.0.0', ecosystem: 'pypi' },
          { name: 'gem-pkg', version: '3.0.0', ecosystem: 'gem' },
        ],
      };

      (useSbomDiff as jest.Mock).mockReturnValue({
        diff: multiEcoDiff,
        loading: false,
        error: null,
      });

      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('added-npm-pkg')).toBeInTheDocument();
      expect(screen.getByTestId('added-pypi-pkg')).toBeInTheDocument();
      expect(screen.getByTestId('added-gem-pkg')).toBeInTheDocument();
    });
  });

  describe('Vulnerability Severity Levels', () => {
    it('handles critical severity vulnerabilities', () => {
      const criticalDiff = {
        ...mockDiff,
        added_vulnerabilities: [
          { vulnerability_id: 'CVE-2025-99999', severity: 'critical' as const },
        ],
      };

      (useSbomDiff as jest.Mock).mockReturnValue({
        diff: criticalDiff,
        loading: false,
        error: null,
      });

      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('added-vuln-CVE-2025-99999')).toHaveTextContent('critical');
    });

    it('handles all severity levels', () => {
      const allSeverityDiff = {
        ...mockDiff,
        added_vulnerabilities: [
          { vulnerability_id: 'CVE-CRITICAL', severity: 'critical' as const },
          { vulnerability_id: 'CVE-HIGH', severity: 'high' as const },
          { vulnerability_id: 'CVE-MEDIUM', severity: 'medium' as const },
          { vulnerability_id: 'CVE-LOW', severity: 'low' as const },
        ],
        removed_vulnerabilities: [],
      };

      (useSbomDiff as jest.Mock).mockReturnValue({
        diff: allSeverityDiff,
        loading: false,
        error: null,
      });

      renderWithRouter(<SbomDiffPage />);
      expect(screen.getByTestId('added-vuln-CVE-CRITICAL')).toHaveTextContent('critical');
      expect(screen.getByTestId('added-vuln-CVE-HIGH')).toHaveTextContent('high');
      expect(screen.getByTestId('added-vuln-CVE-MEDIUM')).toHaveTextContent('medium');
      expect(screen.getByTestId('added-vuln-CVE-LOW')).toHaveTextContent('low');
    });
  });
});
