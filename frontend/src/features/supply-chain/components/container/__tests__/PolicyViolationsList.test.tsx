import { render, screen, fireEvent } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { PolicyViolationsList } from '../PolicyViolationsList';

// Mock Card component
jest.mock('@/shared/components/ui/Card', () => ({
  Card: ({ children, className }: any) => <div data-testid="card" className={className}>{children}</div>,
}));

// Mock Badge component
jest.mock('@/shared/components/ui/Badge', () => ({
  Badge: ({ children, variant, size }: any) => (
    <span data-testid={`badge-${variant}`} data-size={size}>
      {children}
    </span>
  ),
}));

// Mock LoadingSpinner component
jest.mock('@/shared/components/ui/LoadingSpinner', () => ({
  LoadingSpinner: ({ size }: any) => <div data-testid="loading-spinner" data-size={size}>Loading...</div>,
}));

// Mock icons
jest.mock('lucide-react', () => ({
  Shield: () => <span data-testid="shield-icon">🛡️</span>,
  CheckCircle: () => <span data-testid="check-circle-icon">✓</span>,
  XCircle: () => <span data-testid="x-circle-icon">✗</span>,
  AlertTriangle: () => <span data-testid="alert-triangle-icon">⚠️</span>,
}));

describe('PolicyViolationsList', () => {
  const mockEvaluations = [
    {
      policy_id: 'policy-1',
      policy_name: 'Production Security Policy',
      policy_type: 'security',
      enforcement_level: 'block',
      passed: true,
      violations: [],
      evaluated_at: new Date().toISOString(),
    },
    {
      policy_id: 'policy-2',
      policy_name: 'Vulnerability Threshold Policy',
      policy_type: 'vulnerability',
      enforcement_level: 'warn',
      passed: false,
      violations: [
        {
          rule: 'max_critical_vulnerabilities',
          message: 'Found 2 critical vulnerabilities, allowed max: 0',
          severity: 'critical' as const,
        },
        {
          rule: 'max_high_vulnerabilities',
          message: 'Found 5 high vulnerabilities, allowed max: 2',
          severity: 'high' as const,
        },
      ],
      evaluated_at: new Date().toISOString(),
    },
    {
      policy_id: 'policy-3',
      policy_name: 'License Compliance Policy',
      policy_type: 'license',
      enforcement_level: 'block',
      passed: false,
      violations: [
        {
          rule: 'no_copyleft',
          message: 'GPL licensed component detected',
          severity: 'high' as const,
        },
      ],
      evaluated_at: new Date().toISOString(),
    },
    {
      policy_id: 'policy-4',
      policy_name: 'Image Provenance Policy',
      policy_type: 'provenance',
      enforcement_level: 'warn',
      passed: true,
      violations: [],
      evaluated_at: new Date().toISOString(),
    },
  ];

  describe('Loading State', () => {
    it('shows loading spinner when loading is true', () => {
      render(
        <PolicyViolationsList evaluations={null} loading={true} />
      );

      expect(screen.getByTestId('loading-spinner')).toBeInTheDocument();
      expect(screen.getByTestId('loading-spinner')).toHaveAttribute('data-size', 'lg');
    });

    it('hides content when loading', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={true} />
      );

      expect(screen.queryByText('Production Security Policy')).not.toBeInTheDocument();
    });

    it('shows card wrapper during loading', () => {
      render(
        <PolicyViolationsList evaluations={null} loading={true} />
      );

      expect(screen.getByTestId('card')).toBeInTheDocument();
    });
  });

  describe('Error State', () => {
    it('displays error message when error is provided', () => {
      const errorMessage = 'Failed to evaluate policies';
      render(
        <PolicyViolationsList evaluations={null} loading={false} error={errorMessage} />
      );

      expect(screen.getByText(errorMessage)).toBeInTheDocument();
    });

    it('shows error in red color', () => {
      render(
        <PolicyViolationsList evaluations={null} loading={false} error="Test error" />
      );

      const errorElement = screen.getByText('Test error');
      expect(errorElement).toHaveClass('text-theme-error');
    });

    it('hides policy content when error occurs', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} error="Error loading policies" />
      );

      expect(screen.queryByText('Production Security Policy')).not.toBeInTheDocument();
    });
  });

  describe('Empty State', () => {
    it('shows empty state when evaluations is null', () => {
      render(
        <PolicyViolationsList evaluations={null} loading={false} />
      );

      expect(screen.getByText('No policy evaluations available')).toBeInTheDocument();
      expect(screen.getByTestId('shield-icon')).toBeInTheDocument();
    });

    it('shows empty state when evaluations is empty array', () => {
      render(
        <PolicyViolationsList evaluations={[]} loading={false} />
      );

      expect(screen.getByText('No policy evaluations available')).toBeInTheDocument();
    });

    it('shows muted text color for empty state', () => {
      render(
        <PolicyViolationsList evaluations={null} loading={false} />
      );

      const emptyText = screen.getByText('No policy evaluations available');
      expect(emptyText.parentElement).toHaveClass('text-theme-muted');
    });

    it('shows evaluate button in empty state when onEvaluate provided', () => {
      const mockOnEvaluate = jest.fn();
      render(
        <PolicyViolationsList evaluations={null} loading={false} onEvaluate={mockOnEvaluate} />
      );

      const evaluateButton = screen.getByText('Evaluate Policies');
      expect(evaluateButton).toBeInTheDocument();
    });

    it('calls onEvaluate when button clicked in empty state', async () => {
      const mockOnEvaluate = jest.fn();
      const user = userEvent.setup();
      render(
        <PolicyViolationsList evaluations={null} loading={false} onEvaluate={mockOnEvaluate} />
      );

      const evaluateButton = screen.getByText('Evaluate Policies');
      await user.click(evaluateButton);

      expect(mockOnEvaluate).toHaveBeenCalled();
    });
  });

  describe('Summary Statistics', () => {
    it('displays correct passed count', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      expect(screen.getByText('passed')).toBeInTheDocument();
      const passedSpan = screen.getByText('passed').querySelector('.text-theme-success');
      expect(passedSpan?.textContent).toContain('2');
    });

    it('displays correct failed count', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      expect(screen.getByText('failed')).toBeInTheDocument();
      const failedSpan = screen.getByText('failed').querySelector('.text-theme-error');
      expect(failedSpan?.textContent).toContain('2');
    });

    it('shows check circle icon for passed summary', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      const checkIcons = screen.getAllByTestId('check-circle-icon');
      expect(checkIcons.length).toBeGreaterThan(0);
    });

    it('shows x circle icon for failed summary', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      const xIcons = screen.getAllByTestId('x-circle-icon');
      expect(xIcons.length).toBeGreaterThan(0);
    });

    it('displays success color for passed count', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      // The passed count should have success styling
      const successElements = document.querySelectorAll('.text-theme-success');
      expect(successElements.length).toBeGreaterThan(0);
    });

    it('displays error color for failed count', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      // The failed count should have error styling
      const errorElements = document.querySelectorAll('.text-theme-error');
      expect(errorElements.length).toBeGreaterThan(0);
    });
  });

  describe('Policy Evaluation Cards', () => {
    it('renders one card per evaluation', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      const cards = screen.getAllByTestId('card');
      // One card for summary + one for each evaluation
      expect(cards.length).toBeGreaterThanOrEqual(mockEvaluations.length);
    });

    it('displays policy name', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      expect(screen.getByText('Production Security Policy')).toBeInTheDocument();
      expect(screen.getByText('Vulnerability Threshold Policy')).toBeInTheDocument();
      expect(screen.getByText('License Compliance Policy')).toBeInTheDocument();
    });

    it('shows passed policies with check circle icon', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      // Find the policy name and verify it has a check circle nearby
      const passedPolicy = screen.getByText('Production Security Policy');
      const card = passedPolicy.closest('[data-testid="card"]');
      expect(card?.querySelector('[data-testid="check-circle-icon"]')).toBeInTheDocument();
    });

    it('shows failed policies with x circle icon', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      const failedPolicy = screen.getByText('Vulnerability Threshold Policy');
      const card = failedPolicy.closest('[data-testid="card"]');
      expect(card?.querySelector('[data-testid="x-circle-icon"]')).toBeInTheDocument();
    });

    it('displays policy type badge', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      expect(screen.getByText('security')).toBeInTheDocument();
      expect(screen.getByText('vulnerability')).toBeInTheDocument();
      expect(screen.getByText('license')).toBeInTheDocument();
      expect(screen.getByText('provenance')).toBeInTheDocument();
    });

    it('displays enforcement level badge', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      expect(screen.getAllByText('block')).toHaveLength(2);
      expect(screen.getAllByText('warn')).toHaveLength(2);
    });

    it('shows danger badge for block enforcement level', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      const blockBadges = screen.getAllByTestId('badge-danger').filter(
        (badge) => badge.textContent === 'block'
      );
      expect(blockBadges.length).toBeGreaterThan(0);
    });

    it('shows warning badge for warn enforcement level', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      const warnBadges = screen.getAllByTestId('badge-warning').filter(
        (badge) => badge.textContent === 'warn'
      );
      expect(warnBadges.length).toBeGreaterThan(0);
    });

    it('displays pass/fail badge on policy card', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      expect(screen.getAllByText('Passed').length).toBe(2);
      expect(screen.getAllByText('Failed').length).toBe(2);
    });

    it('shows success badge variant for passed policies', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      const successBadges = screen.getAllByTestId('badge-success');
      expect(successBadges.length).toBeGreaterThan(0);
    });

    it('shows danger badge variant for failed policies', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      const dangerBadges = screen.getAllByTestId('badge-danger');
      expect(dangerBadges.length).toBeGreaterThan(0);
    });
  });

  describe('Policy Violations Display', () => {
    it('shows violations section when violations exist', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      expect(screen.getAllByText(/^Violations \(/)).toHaveLength(2);
    });

    it('hides violations section for policies without violations', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      const violationSections = screen.getAllByText(/^Violations \(/);
      expect(violationSections).toHaveLength(2);
    });

    it('displays violation count in header', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      expect(screen.getByText('Violations (2)')).toBeInTheDocument();
      expect(screen.getByText('Violations (1)')).toBeInTheDocument();
    });

    it('renders violation rule name', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      expect(screen.getByText('max_critical_vulnerabilities')).toBeInTheDocument();
      expect(screen.getByText('max_high_vulnerabilities')).toBeInTheDocument();
      expect(screen.getByText('no_copyleft')).toBeInTheDocument();
    });

    it('renders violation message', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      expect(screen.getByText('Found 2 critical vulnerabilities, allowed max: 0')).toBeInTheDocument();
      expect(screen.getByText('GPL licensed component detected')).toBeInTheDocument();
    });

    it('displays violation severity badge', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      expect(screen.getByText('critical')).toBeInTheDocument();
      expect(screen.getAllByText('high').length).toBeGreaterThan(0);
    });
  });

  describe('Violation Severity Styling', () => {
    it('applies critical severity styling', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      const criticalViolation = document.querySelector('.bg-theme-error\\/10');
      expect(criticalViolation).toBeInTheDocument();
    });

    it('applies high severity styling', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      const highViolations = document.querySelectorAll('.bg-theme-error\\/10');
      expect(highViolations.length).toBeGreaterThan(0);
    });

    it('applies correct text color for severity', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      const violationWithText = document.querySelector('.text-theme-error');
      expect(violationWithText).toBeInTheDocument();
    });
  });

  describe('Timestamp Display', () => {
    it('displays evaluated timestamp for each policy', () => {
      const specificDate = new Date('2024-01-15T10:30:00Z');
      const evaluationWithDate = {
        ...mockEvaluations[0],
        evaluated_at: specificDate.toISOString(),
      };

      render(
        <PolicyViolationsList evaluations={[evaluationWithDate]} loading={false} />
      );

      // The timestamp should be displayed (exact format depends on locale)
      expect(screen.getByText(/Evaluated:/)).toBeInTheDocument();
    });
  });

  describe('Alert Icon Display', () => {
    it('shows alert icon in violations header', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      const alertIcons = screen.getAllByTestId('alert-triangle-icon');
      expect(alertIcons.length).toBeGreaterThan(0);
    });
  });

  describe('Multiple Evaluations', () => {
    it('renders all evaluations', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      mockEvaluations.forEach((evaluation) => {
        expect(screen.getByText(evaluation.policy_name)).toBeInTheDocument();
      });
    });

    it('correctly shows mix of passed and failed policies', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      const passedBadges = screen.getAllByTestId('badge-success');
      const failedBadges = screen.getAllByTestId('badge-danger');

      expect(passedBadges.length).toBeGreaterThan(0);
      expect(failedBadges.length).toBeGreaterThan(0);
    });
  });

  describe('Policy Violations with Multiple Severities', () => {
    it('displays violations with different severity levels', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      // Vulnerability policy has both critical and high severity violations
      const vulnerabilityPolicy = mockEvaluations[1];
      expect(vulnerabilityPolicy.violations).toHaveLength(2);

      expect(screen.getByText('critical')).toBeInTheDocument();
      expect(screen.getAllByText('high').length).toBeGreaterThan(0);
    });
  });

  describe('Policies Without Violations', () => {
    it('shows passed policy without violation section', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      const productionPolicy = screen.getByText('Production Security Policy');
      const card = productionPolicy.closest('[data-testid="card"]');
      expect(card?.textContent).not.toContain('Violations');
    });
  });

  describe('Text Content and Labels', () => {
    it('displays all policy names correctly', () => {
      render(
        <PolicyViolationsList evaluations={mockEvaluations} loading={false} />
      );

      expect(screen.getByText('Production Security Policy')).toBeInTheDocument();
      expect(screen.getByText('Vulnerability Threshold Policy')).toBeInTheDocument();
      expect(screen.getByText('License Compliance Policy')).toBeInTheDocument();
      expect(screen.getByText('Image Provenance Policy')).toBeInTheDocument();
    });
  });
});
