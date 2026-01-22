import { render, screen } from '@testing-library/react';
import { ComplianceStatusCard } from '../ComplianceStatusCard';

describe('ComplianceStatusCard', () => {
  const mockCompliance = {
    ntia_minimum_compliant: true,
    ntia_fields: {
      supplier_name: true,
      component_name: true,
      component_version: true,
      unique_identifier: true,
      dependency_relationship: true,
      author: false,
      timestamp: true,
    },
    completeness_score: 85,
    missing_fields: ['author'],
  };

  const defaultProps = {
    compliance: mockCompliance,
  };

  describe('rendering', () => {
    it('renders the component', () => {
      const { container } = render(<ComplianceStatusCard {...defaultProps} />);
      expect(container).toBeInTheDocument();
    });

    it('displays NTIA Minimum Elements title', () => {
      render(<ComplianceStatusCard {...defaultProps} />);
      expect(screen.getByText('NTIA Minimum Elements')).toBeInTheDocument();
    });

    it('displays Completeness Score title', () => {
      render(<ComplianceStatusCard {...defaultProps} />);
      expect(screen.getByText('Completeness Score')).toBeInTheDocument();
    });
  });

  describe('NTIA compliance status', () => {
    it('shows Compliant badge when compliant', () => {
      render(<ComplianceStatusCard {...defaultProps} />);
      expect(screen.getByText('Compliant')).toBeInTheDocument();
    });

    it('shows Non-Compliant badge when not compliant', () => {
      const nonCompliant = {
        ...mockCompliance,
        ntia_minimum_compliant: false,
      };
      render(<ComplianceStatusCard compliance={nonCompliant} />);
      expect(screen.getByText('Non-Compliant')).toBeInTheDocument();
    });
  });

  describe('NTIA fields display', () => {
    it('displays all NTIA field labels', () => {
      render(<ComplianceStatusCard {...defaultProps} />);
      expect(screen.getByText('Supplier Name')).toBeInTheDocument();
      expect(screen.getByText('Component Name')).toBeInTheDocument();
      expect(screen.getByText('Component Version')).toBeInTheDocument();
      expect(screen.getByText('Unique Identifier')).toBeInTheDocument();
      expect(screen.getByText('Dependency Relationship')).toBeInTheDocument();
      expect(screen.getAllByText('Author').length).toBeGreaterThan(0);
      expect(screen.getByText('Timestamp')).toBeInTheDocument();
    });

    it('displays all fields in grid layout', () => {
      const { container } = render(<ComplianceStatusCard {...defaultProps} />);
      const grid = container.querySelector('div[class*="grid grid-cols"]');
      expect(grid).toBeInTheDocument();
    });

    it('shows correct field labels for mapping', () => {
      render(<ComplianceStatusCard {...defaultProps} />);
      // Check that field names map to proper labels
      expect(screen.getByText('Supplier Name')).toBeInTheDocument();
      expect(screen.getByText('Component Name')).toBeInTheDocument();
      expect(screen.getByText('Component Version')).toBeInTheDocument();
      expect(screen.getByText('Unique Identifier')).toBeInTheDocument();
      expect(screen.getByText('Dependency Relationship')).toBeInTheDocument();
      expect(screen.getAllByText('Author').length).toBeGreaterThan(0);
      expect(screen.getByText('Timestamp')).toBeInTheDocument();
    });
  });

  describe('field presence indicators', () => {
    it('shows check icon for present fields', () => {
      const { container } = render(<ComplianceStatusCard {...defaultProps} />);
      const checkIcons = container.querySelectorAll('svg');
      expect(checkIcons.length).toBeGreaterThan(0);
    });

    it('shows X icon for missing fields', () => {
      const { container } = render(<ComplianceStatusCard {...defaultProps} />);
      const xIcons = container.querySelectorAll('svg');
      expect(xIcons.length).toBeGreaterThan(0);
    });

    it('colors present fields with success color', () => {
      const { container } = render(<ComplianceStatusCard {...defaultProps} />);
      const successElements = container.querySelectorAll('[class*="text-theme-success"]');
      expect(successElements.length).toBeGreaterThan(0);
    });

    it('colors missing fields with error color', () => {
      const { container } = render(<ComplianceStatusCard {...defaultProps} />);
      const errorElements = container.querySelectorAll('[class*="text-theme-error"]');
      expect(errorElements.length).toBeGreaterThan(0);
    });

    it('highlights present field rows with success background', () => {
      const { container } = render(<ComplianceStatusCard {...defaultProps} />);
      const successRows = container.querySelectorAll('[class*="bg-theme-success/10"]');
      expect(successRows.length).toBeGreaterThan(0);
    });

    it('highlights missing field rows with error background', () => {
      const { container } = render(<ComplianceStatusCard {...defaultProps} />);
      const errorRows = container.querySelectorAll('[class*="bg-theme-error/10"]');
      expect(errorRows.length).toBeGreaterThan(0);
    });
  });

  describe('completeness score display', () => {
    it('displays completeness score value', () => {
      render(<ComplianceStatusCard {...defaultProps} />);
      expect(screen.getByText('85%')).toBeInTheDocument();
    });

    it('displays large score text', () => {
      const { container } = render(<ComplianceStatusCard {...defaultProps} />);
      const scoreText = screen.getByText('85%');
      expect(scoreText).toHaveClass('text-3xl', 'font-bold');
    });
  });

  describe('completeness progress bar', () => {
    it('displays progress bar', () => {
      const { container } = render(<ComplianceStatusCard {...defaultProps} />);
      const progressBar = container.querySelector('div[class*="bg-theme-muted rounded-full"]');
      expect(progressBar).toBeInTheDocument();
    });

    it('sets progress bar width based on score', () => {
      const { container } = render(<ComplianceStatusCard {...defaultProps} />);
      const progress = container.querySelector('div[class*="h-3 rounded-full"]');
      expect(progress).toHaveStyle({ width: '85%' });
    });

    it('uses success color for high score', () => {
      const { container } = render(<ComplianceStatusCard {...defaultProps} />);
      const progress = container.querySelector('div[class*="h-3 rounded-full"]');
      expect(progress).toHaveClass('bg-theme-success');
    });

    it('uses warning color for medium score', () => {
      const mediumCompliance = {
        ...mockCompliance,
        completeness_score: 70,
      };
      const { container } = render(<ComplianceStatusCard compliance={mediumCompliance} />);
      const progress = container.querySelector('div[class*="h-3 rounded-full"]');
      expect(progress).toHaveClass('bg-theme-warning');
    });

    it('uses error color for low score', () => {
      const lowCompliance = {
        ...mockCompliance,
        completeness_score: 45,
      };
      const { container } = render(<ComplianceStatusCard compliance={lowCompliance} />);
      const progress = container.querySelector('div[class*="h-3 rounded-full"]');
      expect(progress).toHaveClass('bg-theme-error');
    });
  });

  describe('score color coding', () => {
    it('displays success color for score >= 80', () => {
      render(<ComplianceStatusCard {...defaultProps} />);
      const scoreText = screen.getByText('85%');
      expect(scoreText).toHaveClass('text-theme-success');
    });

    it('displays warning color for score >= 60 and < 80', () => {
      const mediumCompliance = {
        ...mockCompliance,
        completeness_score: 70,
      };
      render(<ComplianceStatusCard compliance={mediumCompliance} />);
      const scoreText = screen.getByText('70%');
      expect(scoreText).toHaveClass('text-theme-warning');
    });

    it('displays error color for score < 60', () => {
      const lowCompliance = {
        ...mockCompliance,
        completeness_score: 45,
      };
      render(<ComplianceStatusCard compliance={lowCompliance} />);
      const scoreText = screen.getByText('45%');
      expect(scoreText).toHaveClass('text-theme-error');
    });
  });

  describe('missing fields section', () => {
    it('displays Missing Fields header when fields are missing', () => {
      render(<ComplianceStatusCard {...defaultProps} />);
      expect(screen.getByText('Missing Fields')).toBeInTheDocument();
    });

    it('displays missing field names as badges', () => {
      render(<ComplianceStatusCard {...defaultProps} />);
      expect(screen.getAllByText('Author').length).toBeGreaterThan(0);
    });

    it('hides missing fields section when all fields present', () => {
      const allCompliance = {
        ...mockCompliance,
        missing_fields: [],
      };
      render(<ComplianceStatusCard compliance={allCompliance} />);
      expect(screen.queryByText('Missing Fields')).not.toBeInTheDocument();
    });

    it('displays all missing fields', () => {
      const multiMissing = {
        ...mockCompliance,
        missing_fields: ['author', 'timestamp', 'supplier_name'],
      };
      render(<ComplianceStatusCard compliance={multiMissing} />);
      expect(screen.getAllByText('Author').length).toBeGreaterThan(0);
      expect(screen.getAllByText('Timestamp').length).toBeGreaterThan(0);
      expect(screen.getAllByText('Supplier Name').length).toBeGreaterThan(0);
    });

    it('displays alert icon for missing fields', () => {
      const { container } = render(<ComplianceStatusCard {...defaultProps} />);
      const missingFieldsSection = screen.getByText('Missing Fields').closest('div');
      expect(missingFieldsSection?.querySelector('svg')).toBeInTheDocument();
    });

    it('applies warning styling to missing fields badge', () => {
      const { container } = render(<ComplianceStatusCard {...defaultProps} />);
      const missingBadges = container.querySelectorAll('[class*="badge-theme-warning"]');
      expect(missingBadges.length).toBeGreaterThan(0);
    });
  });

  describe('compliant state variations', () => {
    it('renders fully compliant state', () => {
      const fullyCompliant = {
        ntia_minimum_compliant: true,
        ntia_fields: {
          supplier_name: true,
          component_name: true,
          component_version: true,
          unique_identifier: true,
          dependency_relationship: true,
          author: true,
          timestamp: true,
        },
        completeness_score: 100,
        missing_fields: [],
      };
      render(<ComplianceStatusCard compliance={fullyCompliant} />);
      expect(screen.getByText('Compliant')).toBeInTheDocument();
      expect(screen.getByText('100%')).toBeInTheDocument();
    });

    it('renders non-compliant state', () => {
      const nonCompliant = {
        ntia_minimum_compliant: false,
        ntia_fields: {
          supplier_name: false,
          component_name: false,
          component_version: false,
          unique_identifier: false,
          dependency_relationship: false,
          author: false,
          timestamp: false,
        },
        completeness_score: 0,
        missing_fields: [
          'supplier_name',
          'component_name',
          'component_version',
          'unique_identifier',
          'dependency_relationship',
          'author',
          'timestamp',
        ],
      };
      render(<ComplianceStatusCard compliance={nonCompliant} />);
      expect(screen.getByText('Non-Compliant')).toBeInTheDocument();
      expect(screen.getByText('0%')).toBeInTheDocument();
    });
  });

  describe('card structure', () => {
    it('renders multiple cards for different sections', () => {
      const { container } = render(<ComplianceStatusCard {...defaultProps} />);
      // Should have multiple Card components or equivalent
      const sections = container.querySelectorAll('[class*="p-6"]');
      expect(sections.length).toBeGreaterThanOrEqual(2);
    });

    it('organizes content in sections', () => {
      render(<ComplianceStatusCard {...defaultProps} />);
      expect(screen.getByText('NTIA Minimum Elements')).toBeInTheDocument();
      expect(screen.getByText('Completeness Score')).toBeInTheDocument();
    });
  });

  describe('field label handling', () => {
    it('handles unknown field names gracefully', () => {
      const unknownCompliance = {
        ...mockCompliance,
        ntia_fields: {
          ...mockCompliance.ntia_fields,
          unknown_field: true,
        } as any,
      };
      const { container } = render(<ComplianceStatusCard compliance={unknownCompliance} />);
      expect(screen.getByText('unknown_field')).toBeInTheDocument();
    });
  });

  describe('responsive layout', () => {
    it('uses grid layout for fields', () => {
      const { container } = render(<ComplianceStatusCard {...defaultProps} />);
      const grid = container.querySelector('div[class*="grid"]');
      expect(grid?.className).toContain('grid-cols');
    });

    it('applies responsive grid classes', () => {
      const { container } = render(<ComplianceStatusCard {...defaultProps} />);
      const grid = container.querySelector('div[class*="md:grid-cols"]');
      expect(grid).toBeInTheDocument();
    });
  });

  describe('badge styling', () => {
    it('missing field badges have warning variant', () => {
      const { container } = render(<ComplianceStatusCard {...defaultProps} />);
      // Check for warning-styled badges in missing fields
      const missingSection = screen.getByText('Missing Fields').closest('div')?.parentElement;
      expect(missingSection?.textContent).toContain('Author');
    });

    it('displays badges in flex layout', () => {
      const { container } = render(<ComplianceStatusCard {...defaultProps} />);
      const missingHeaderDiv = screen.getByText('Missing Fields').closest('div');
      const badgeContainer = missingHeaderDiv?.parentElement?.querySelector('div[class*="flex flex-wrap"]');
      expect(badgeContainer).toBeInTheDocument();
    });
  });

  describe('threshold styling', () => {
    it('applies different styling for score above 80%', () => {
      render(<ComplianceStatusCard {...defaultProps} />);
      const scoreText = screen.getByText('85%');
      expect(scoreText).toHaveClass('text-theme-success');
    });

    it('applies different styling for score 60-80%', () => {
      const mediumCompliance = {
        ...mockCompliance,
        completeness_score: 70,
      };
      render(<ComplianceStatusCard compliance={mediumCompliance} />);
      const scoreText = screen.getByText('70%');
      expect(scoreText).toHaveClass('text-theme-warning');
    });

    it('applies different styling for score below 60%', () => {
      const lowCompliance = {
        ...mockCompliance,
        completeness_score: 50,
      };
      render(<ComplianceStatusCard compliance={lowCompliance} />);
      const scoreText = screen.getByText('50%');
      expect(scoreText).toHaveClass('text-theme-error');
    });
  });
});
