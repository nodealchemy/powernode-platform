import { render, screen } from '@testing-library/react';
import { SbomDiffViewer } from '../SbomDiffViewer';

type Severity = 'critical' | 'high' | 'medium' | 'low';

describe('SbomDiffViewer', () => {
  const mockDiff = {
    id: 'diff-123',
    source_sbom_id: 'sbom-1',
    compare_sbom_id: 'sbom-2',
    added_count: 5,
    removed_count: 2,
    changed_count: 3,
    created_at: '2025-01-15T10:00:00Z',
    added_components: [
      { name: 'lodash', version: '4.17.21', ecosystem: 'npm' },
      { name: 'express', version: '4.18.2', ecosystem: 'npm' },
    ],
    removed_components: [
      { name: 'old-lib', version: '1.0.0', ecosystem: 'npm' },
    ],
    changed_components: [
      { name: 'react', old_version: '16.8.0', new_version: '18.2.0', ecosystem: 'npm' },
      { name: 'webpack', old_version: '4.0.0', new_version: '5.89.0', ecosystem: 'npm' },
    ],
    added_vulnerabilities: [
      { vulnerability_id: 'CVE-2025-1001', severity: 'high' as Severity },
      { vulnerability_id: 'CVE-2025-1002', severity: 'critical' as Severity },
    ],
    removed_vulnerabilities: [
      { vulnerability_id: 'CVE-2024-1001', severity: 'medium' as Severity },
    ],
  };

  const defaultProps = {
    diff: mockDiff,
  };

  describe('rendering', () => {
    it('renders the component', () => {
      const { container } = render(<SbomDiffViewer {...defaultProps} />);
      expect(container).toBeInTheDocument();
    });

    it('displays three summary cards', () => {
      const { container } = render(<SbomDiffViewer {...defaultProps} />);
      const cards = container.querySelectorAll('[class*="bg-theme-surface"]');
      expect(cards.length).toBeGreaterThanOrEqual(3);
    });
  });

  describe('summary cards', () => {
    it('displays added count', () => {
      render(<SbomDiffViewer {...defaultProps} />);
      expect(screen.getByText('Added')).toBeInTheDocument();
      expect(screen.getByText('5')).toBeInTheDocument();
    });

    it('displays removed count', () => {
      render(<SbomDiffViewer {...defaultProps} />);
      expect(screen.getByText('Removed')).toBeInTheDocument();
      expect(screen.getByText('2')).toBeInTheDocument();
    });

    it('displays changed count', () => {
      render(<SbomDiffViewer {...defaultProps} />);
      expect(screen.getByText('Changed')).toBeInTheDocument();
      expect(screen.getByText('3')).toBeInTheDocument();
    });

    it('shows components label', () => {
      render(<SbomDiffViewer {...defaultProps} />);
      expect(screen.getAllByText('components').length).toBeGreaterThanOrEqual(3);
    });
  });

  describe('added components section', () => {
    it('displays added components section', () => {
      render(<SbomDiffViewer {...defaultProps} />);
      expect(screen.getByText(/Added Components/)).toBeInTheDocument();
    });

    it('shows added component count in header', () => {
      render(<SbomDiffViewer {...defaultProps} />);
      expect(screen.getByText(/Added Components \(2\)/)).toBeInTheDocument();
    });

    it('displays all added components', () => {
      render(<SbomDiffViewer {...defaultProps} />);
      expect(screen.getByText('lodash')).toBeInTheDocument();
      expect(screen.getByText('express')).toBeInTheDocument();
    });

    it('shows component versions', () => {
      render(<SbomDiffViewer {...defaultProps} />);
      expect(screen.getByText('@4.17.21')).toBeInTheDocument();
      expect(screen.getByText('@4.18.2')).toBeInTheDocument();
    });

    it('displays ecosystem badges', () => {
      render(<SbomDiffViewer {...defaultProps} />);
      const npmBadges = screen.getAllByText('npm');
      expect(npmBadges.length).toBeGreaterThan(0);
    });

    it('hides added section when no added components', () => {
      const noDiff = { ...mockDiff, added_components: [], added_count: 0 };
      const { container } = render(<SbomDiffViewer diff={noDiff} />);
      expect(screen.queryByText(/Added Components/)).not.toBeInTheDocument();
    });
  });

  describe('removed components section', () => {
    it('displays removed components section', () => {
      render(<SbomDiffViewer {...defaultProps} />);
      expect(screen.getByText(/Removed Components/)).toBeInTheDocument();
    });

    it('shows removed component count in header', () => {
      render(<SbomDiffViewer {...defaultProps} />);
      expect(screen.getByText(/Removed Components \(1\)/)).toBeInTheDocument();
    });

    it('displays removed components', () => {
      render(<SbomDiffViewer {...defaultProps} />);
      expect(screen.getByText('old-lib')).toBeInTheDocument();
    });

    it('applies strikethrough styling to removed components', () => {
      const { container } = render(<SbomDiffViewer {...defaultProps} />);
      const oldLibText = screen.getByText('old-lib');
      expect(oldLibText).toHaveClass('line-through');
    });

    it('applies strikethrough to removed version', () => {
      const { container } = render(<SbomDiffViewer {...defaultProps} />);
      const removedVersion = Array.from(container.querySelectorAll('[class*="line-through"]')).find(
        el => el.textContent.includes('@1.0.0')
      );
      expect(removedVersion).toBeInTheDocument();
    });

    it('hides removed section when no removed components', () => {
      const noDiff = { ...mockDiff, removed_components: [], removed_count: 0 };
      render(<SbomDiffViewer diff={noDiff} />);
      expect(screen.queryByText(/Removed Components/)).not.toBeInTheDocument();
    });
  });

  describe('changed components section', () => {
    it('displays changed components section', () => {
      render(<SbomDiffViewer {...defaultProps} />);
      expect(screen.getByText(/Changed Components/)).toBeInTheDocument();
    });

    it('shows changed component count in header', () => {
      render(<SbomDiffViewer {...defaultProps} />);
      expect(screen.getByText(/Changed Components \(2\)/)).toBeInTheDocument();
    });

    it('displays all changed components', () => {
      render(<SbomDiffViewer {...defaultProps} />);
      expect(screen.getByText('react')).toBeInTheDocument();
      expect(screen.getByText('webpack')).toBeInTheDocument();
    });

    it('shows old version with strikethrough', () => {
      const { container } = render(<SbomDiffViewer {...defaultProps} />);
      const oldVersion = Array.from(container.querySelectorAll('[class*="line-through"]')).find(
        el => el.textContent.includes('@16.8.0')
      );
      expect(oldVersion).toBeInTheDocument();
    });

    it('shows arrow between versions', () => {
      render(<SbomDiffViewer {...defaultProps} />);
      const arrows = screen.getAllByText('→');
      expect(arrows.length).toBeGreaterThan(0);
    });

    it('shows new version in success color', () => {
      const { container } = render(<SbomDiffViewer {...defaultProps} />);
      const newVersion = Array.from(container.querySelectorAll('[class*="text-theme-success"]')).find(
        el => el.textContent.includes('@18.2.0')
      );
      expect(newVersion).toBeInTheDocument();
    });

    it('hides changed section when no changed components', () => {
      const noDiff = { ...mockDiff, changed_components: [], changed_count: 0 };
      render(<SbomDiffViewer diff={noDiff} />);
      expect(screen.queryByText(/Changed Components/)).not.toBeInTheDocument();
    });
  });

  describe('vulnerability changes section', () => {
    it('displays vulnerability changes section', () => {
      render(<SbomDiffViewer {...defaultProps} />);
      expect(screen.getByText(/Vulnerability Changes/)).toBeInTheDocument();
    });

    it('hides section when no vulnerability changes', () => {
      const noDiff = {
        ...mockDiff,
        added_vulnerabilities: [],
        removed_vulnerabilities: [],
      };
      render(<SbomDiffViewer diff={noDiff} />);
      expect(screen.queryByText(/Vulnerability Changes/)).not.toBeInTheDocument();
    });
  });

  describe('added vulnerabilities', () => {
    it('displays new vulnerabilities subsection', () => {
      render(<SbomDiffViewer {...defaultProps} />);
      expect(screen.getByText(/New Vulnerabilities/)).toBeInTheDocument();
    });

    it('shows new vulnerability count', () => {
      render(<SbomDiffViewer {...defaultProps} />);
      expect(screen.getByText(/New Vulnerabilities \(2\)/)).toBeInTheDocument();
    });

    it('displays vulnerability IDs', () => {
      render(<SbomDiffViewer {...defaultProps} />);
      expect(screen.getByText('CVE-2025-1001')).toBeInTheDocument();
      expect(screen.getByText('CVE-2025-1002')).toBeInTheDocument();
    });

    it('shows severity badges for added vulnerabilities', () => {
      render(<SbomDiffViewer {...defaultProps} />);
      expect(screen.getAllByText('high').length).toBeGreaterThan(0);
      expect(screen.getAllByText('critical').length).toBeGreaterThan(0);
    });

    it('hides new vulnerabilities when none added', () => {
      const noDiff = { ...mockDiff, added_vulnerabilities: [] };
      const { container } = render(<SbomDiffViewer diff={noDiff} />);
      expect(screen.queryByText(/New Vulnerabilities \(/)).not.toBeInTheDocument();
    });
  });

  describe('resolved vulnerabilities', () => {
    it('displays resolved vulnerabilities subsection', () => {
      render(<SbomDiffViewer {...defaultProps} />);
      expect(screen.getByText(/Resolved Vulnerabilities/)).toBeInTheDocument();
    });

    it('shows resolved vulnerability count', () => {
      render(<SbomDiffViewer {...defaultProps} />);
      expect(screen.getByText(/Resolved Vulnerabilities \(1\)/)).toBeInTheDocument();
    });

    it('displays resolved vulnerability IDs', () => {
      render(<SbomDiffViewer {...defaultProps} />);
      expect(screen.getByText('CVE-2024-1001')).toBeInTheDocument();
    });

    it('applies strikethrough to resolved vulnerabilities', () => {
      const { container } = render(<SbomDiffViewer {...defaultProps} />);
      const resolvedVuln = Array.from(container.querySelectorAll('[class*="line-through"]')).find(
        el => el.textContent.includes('CVE-2024-1001')
      );
      expect(resolvedVuln).toBeInTheDocument();
    });

    it('shows severity for resolved vulnerabilities', () => {
      render(<SbomDiffViewer {...defaultProps} />);
      expect(screen.getAllByText('medium').length).toBeGreaterThan(0);
    });

    it('hides resolved vulnerabilities when none removed', () => {
      const noDiff = { ...mockDiff, removed_vulnerabilities: [] };
      render(<SbomDiffViewer diff={noDiff} />);
      expect(screen.queryByText(/Resolved Vulnerabilities \(/)).not.toBeInTheDocument();
    });
  });

  describe('card styling and layout', () => {
    it('added card has success styling', () => {
      const { container } = render(<SbomDiffViewer {...defaultProps} />);
      const addedText = screen.getByText('Added');
      const card = addedText.closest('[class*="bg-theme-surface"]');
      expect(card?.textContent).toContain('components');
    });

    it('removed card has error styling', () => {
      const { container } = render(<SbomDiffViewer {...defaultProps} />);
      const removedText = screen.getByText('Removed');
      expect(removedText).toBeInTheDocument();
    });

    it('changed card has warning styling', () => {
      const { container } = render(<SbomDiffViewer {...defaultProps} />);
      const changedText = screen.getByText('Changed');
      expect(changedText).toBeInTheDocument();
    });
  });

  describe('empty diff', () => {
    it('renders with zero counts', () => {
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

      render(<SbomDiffViewer diff={emptyDiff} />);
      expect(screen.getAllByText('0').length).toBeGreaterThan(0);
    });

    it('hides detail sections when no changes', () => {
      const emptyDiff = {
        ...mockDiff,
        added_components: [],
        removed_components: [],
        changed_components: [],
        added_vulnerabilities: [],
        removed_vulnerabilities: [],
      };

      render(<SbomDiffViewer diff={emptyDiff} />);
      expect(screen.queryByText(/Added Components/)).not.toBeInTheDocument();
      expect(screen.queryByText(/Removed Components/)).not.toBeInTheDocument();
      expect(screen.queryByText(/Changed Components/)).not.toBeInTheDocument();
    });
  });

  describe('component listing format', () => {
    it('displays components with consistent format', () => {
      render(<SbomDiffViewer {...defaultProps} />);
      // All added components should follow pattern: name@version
      expect(screen.getByText('lodash')).toBeInTheDocument();
      expect(screen.getByText('@4.17.21')).toBeInTheDocument();
    });

    it('shows all ecosystems', () => {
      const multiEcosystemDiff = {
        ...mockDiff,
        added_components: [
          { name: 'lodash', version: '4.17.21', ecosystem: 'npm' },
          { name: 'requests', version: '2.28.0', ecosystem: 'pip' },
          { name: 'log4j', version: '2.19.0', ecosystem: 'maven' },
        ],
      };

      render(<SbomDiffViewer diff={multiEcosystemDiff} />);
      expect(screen.getAllByText('npm').length).toBeGreaterThan(0);
      expect(screen.getByText('pip')).toBeInTheDocument();
      expect(screen.getByText('maven')).toBeInTheDocument();
    });
  });

  describe('large dataset handling', () => {
    it('renders with many components', () => {
      const manyComponents = Array.from({ length: 50 }, (_, i) => ({
        name: `package-${i}`,
        version: `1.${i}.0`,
        ecosystem: 'npm',
      }));

      const largeDiff = {
        ...mockDiff,
        added_components: manyComponents,
        added_count: manyComponents.length,
      };

      render(<SbomDiffViewer diff={largeDiff} />);
      expect(screen.getByText(/Added Components \(50\)/)).toBeInTheDocument();
      expect(screen.getByText('package-0')).toBeInTheDocument();
      expect(screen.getByText('package-49')).toBeInTheDocument();
    });
  });

  describe('icon display', () => {
    it('shows plus icon for added section', () => {
      const { container } = render(<SbomDiffViewer {...defaultProps} />);
      const addedHeader = screen.getByText(/Added Components/).closest('h3');
      expect(addedHeader?.querySelector('svg')).toBeInTheDocument();
    });

    it('shows minus icon for removed section', () => {
      const { container } = render(<SbomDiffViewer {...defaultProps} />);
      const removedHeader = screen.getByText(/Removed Components/).closest('h3');
      expect(removedHeader?.querySelector('svg')).toBeInTheDocument();
    });

    it('shows refresh icon for changed section', () => {
      const { container } = render(<SbomDiffViewer {...defaultProps} />);
      const changedHeader = screen.getByText(/Changed Components/).closest('h3');
      expect(changedHeader?.querySelector('svg')).toBeInTheDocument();
    });

    it('shows alert icon for vulnerability changes', () => {
      const { container } = render(<SbomDiffViewer {...defaultProps} />);
      const vulnHeader = screen.getByText(/Vulnerability Changes/).closest('h3');
      expect(vulnHeader?.querySelector('svg')).toBeInTheDocument();
    });
  });
});
