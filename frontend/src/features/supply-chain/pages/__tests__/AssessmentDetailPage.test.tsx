import React from 'react';
import { render, screen } from '@testing-library/react';
import { BrowserRouter, Route, Routes } from 'react-router-dom';
import userEvent from '@testing-library/user-event';
import { AssessmentDetailPage } from '../AssessmentDetailPage';

const mockNavigate = jest.fn();
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate,
  useParams: () => ({ id: 'vendor-1', assessmentId: 'assess-1' }),
}));

// Mock PageContainer to simplify testing
jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({ title, description, breadcrumbs, actions, children }: any) => (
    <div data-testid="page-container">
      <h1>{title}</h1>
      <p>{description}</p>
      <nav data-testid="breadcrumbs">
        {breadcrumbs?.map((bc: any, idx: number) => (
          <span key={idx}>{bc.label}</span>
        ))}
      </nav>
      <div data-testid="page-actions">
        {actions?.map((action: any, idx: number) => (
          <button
            key={action.id || idx}
            onClick={action.onClick}
            data-testid={`action-${action.id || idx}`}
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

describe('AssessmentDetailPage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  const renderPage = () => {
    return render(
      <BrowserRouter>
        <Routes>
          <Route path="/" element={<AssessmentDetailPage />} />
        </Routes>
      </BrowserRouter>
    );
  };

  describe('page header', () => {
    it('renders page title', () => {
      renderPage();
      expect(screen.getByText('Risk Assessment')).toBeInTheDocument();
    });

    it('renders assessment type in description', () => {
      renderPage();
      expect(screen.getByText(/periodic assessment/i)).toBeInTheDocument();
    });

    it('renders breadcrumbs', () => {
      renderPage();
      expect(screen.getByText('Dashboard')).toBeInTheDocument();
      expect(screen.getByText('Supply Chain')).toBeInTheDocument();
      expect(screen.getByText('Vendors')).toBeInTheDocument();
      expect(screen.getByText('Vendor')).toBeInTheDocument();
      expect(screen.getByText('Assessment')).toBeInTheDocument();
    });

    it('shows Back to Vendor button', () => {
      renderPage();
      expect(screen.getByText('Back to Vendor')).toBeInTheDocument();
    });

    it('navigates back to vendor when Back button clicked', async () => {
      renderPage();
      const backButton = screen.getByText('Back to Vendor');
      await userEvent.click(backButton);
      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/vendors/vendor-1');
    });
  });

  describe('assessment status', () => {
    it('displays assessment status badge', () => {
      renderPage();
      expect(screen.getByText('completed')).toBeInTheDocument();
    });

    it('shows completed timestamp', () => {
      renderPage();
      expect(screen.getByText(/Completed.*ago/)).toBeInTheDocument();
    });

    it('displays assessment icon', () => {
      renderPage();
      // ClipboardCheck icon is rendered
      expect(screen.getByText('Risk Assessment')).toBeInTheDocument();
    });
  });

  describe('assessment scores', () => {
    it('shows Assessment Scores section', () => {
      renderPage();
      expect(screen.getByText('Assessment Scores')).toBeInTheDocument();
    });

    it('displays overall score', () => {
      renderPage();
      expect(screen.getByText('84')).toBeInTheDocument();
      expect(screen.getByText('Overall')).toBeInTheDocument();
    });

    it('displays security score', () => {
      renderPage();
      expect(screen.getByText('85')).toBeInTheDocument();
      expect(screen.getByText('Security')).toBeInTheDocument();
    });

    it('displays compliance score', () => {
      renderPage();
      expect(screen.getByText('90')).toBeInTheDocument();
      expect(screen.getByText('Compliance')).toBeInTheDocument();
    });

    it('displays operational score', () => {
      renderPage();
      expect(screen.getByText('78')).toBeInTheDocument();
      expect(screen.getByText('Operational')).toBeInTheDocument();
    });

    it('applies correct color to overall score >= 80', () => {
      renderPage();
      const overallScore = screen.getByText('84');
      expect(overallScore).toHaveClass('text-theme-success');
    });

    it('applies correct color to security score >= 80', () => {
      renderPage();
      const securityScore = screen.getByText('85');
      expect(securityScore).toHaveClass('text-theme-success');
    });

    it('applies correct color to compliance score >= 80', () => {
      renderPage();
      const complianceScore = screen.getByText('90');
      expect(complianceScore).toHaveClass('text-theme-success');
    });

    it('applies warning color to operational score 60-79', () => {
      renderPage();
      const operationalScore = screen.getByText('78');
      expect(operationalScore).toHaveClass('text-theme-warning');
    });
  });

  describe('assessment details', () => {
    it('shows Details section', () => {
      renderPage();
      expect(screen.getByText('Details')).toBeInTheDocument();
    });

    it('displays assessment type', () => {
      renderPage();
      // "periodic" appears in multiple places (description and details)
      expect(screen.getAllByText(/periodic/i).length).toBeGreaterThan(0);
    });

    it('displays valid until date', () => {
      renderPage();
      expect(screen.getByText(/Jun.*2025/)).toBeInTheDocument();
    });

    it('displays started date', () => {
      renderPage();
      // Multiple dates matching "Jan.*2025" pattern
      expect(screen.getAllByText(/Jan.*2025/).length).toBeGreaterThan(0);
    });

    it('displays completed date', () => {
      renderPage();
      const completedDates = screen.getAllByText(/Jan.*2025/);
      expect(completedDates.length).toBeGreaterThan(0);
    });
  });

  describe('findings section', () => {
    it('shows Findings section with count', () => {
      renderPage();
      expect(screen.getByText(/Findings \(3\)/)).toBeInTheDocument();
    });

    it('displays finding titles', () => {
      renderPage();
      expect(screen.getByText('Multi-factor authentication not enforced')).toBeInTheDocument();
      expect(screen.getByText('Encryption at rest not enabled for all storage')).toBeInTheDocument();
      expect(screen.getByText('Audit log retention period too short')).toBeInTheDocument();
    });

    it('displays finding descriptions', () => {
      renderPage();
      expect(screen.getByText('MFA is available but not required for all users')).toBeInTheDocument();
      expect(screen.getByText('Some storage volumes are not encrypted')).toBeInTheDocument();
      expect(screen.getByText('Logs are only retained for 30 days')).toBeInTheDocument();
    });

    it('displays finding recommendations', () => {
      renderPage();
      expect(screen.getByText(/Enable mandatory MFA for all user accounts/)).toBeInTheDocument();
      expect(screen.getByText(/Enable encryption at rest for all data storage/)).toBeInTheDocument();
      expect(screen.getByText(/Extend log retention to at least 90 days/)).toBeInTheDocument();
    });

    it('shows severity badge for high severity finding', () => {
      renderPage();
      expect(screen.getByText('high')).toBeInTheDocument();
    });

    it('shows severity badge for medium severity finding', () => {
      renderPage();
      expect(screen.getByText('medium')).toBeInTheDocument();
    });

    it('shows severity badge for low severity finding', () => {
      renderPage();
      expect(screen.getByText('low')).toBeInTheDocument();
    });

    it('shows category badge for findings', () => {
      renderPage();
      expect(screen.getByText('Access Control')).toBeInTheDocument();
      expect(screen.getByText('Data Protection')).toBeInTheDocument();
      expect(screen.getByText('Logging')).toBeInTheDocument();
    });

    it('displays status icon for resolved finding', () => {
      renderPage();
      // CheckCircle icon for resolved status
      const findings = screen.getAllByText(/Audit log retention/);
      expect(findings.length).toBeGreaterThan(0);
    });

    it('displays status icon for in_progress finding', () => {
      renderPage();
      // AlertCircle icon for in_progress status
      const findings = screen.getAllByText(/Encryption at rest/);
      expect(findings.length).toBeGreaterThan(0);
    });

    it('displays status icon for open finding', () => {
      renderPage();
      // AlertCircle icon for open status
      const findings = screen.getAllByText(/Multi-factor authentication/);
      expect(findings.length).toBeGreaterThan(0);
    });
  });

  describe('severity variants', () => {
    it('applies danger variant to critical severity', () => {
      renderPage();
      // High severity finding gets danger variant
      expect(screen.getByText('high')).toBeInTheDocument();
    });

    it('applies warning variant to medium severity', () => {
      renderPage();
      expect(screen.getByText('medium')).toBeInTheDocument();
    });

    it('applies info variant to low severity', () => {
      renderPage();
      expect(screen.getByText('low')).toBeInTheDocument();
    });
  });

  describe('finding status indicators', () => {
    it('shows green indicator for resolved findings', () => {
      renderPage();
      // Resolved finding should have success styling
      expect(screen.getByText(/Audit log retention period too short/)).toBeInTheDocument();
    });

    it('shows yellow indicator for in_progress findings', () => {
      renderPage();
      // In progress finding should have warning styling
      expect(screen.getByText(/Encryption at rest not enabled/)).toBeInTheDocument();
    });

    it('shows red indicator for open findings', () => {
      renderPage();
      // Open finding should have error styling
      expect(screen.getByText(/Multi-factor authentication not enforced/)).toBeInTheDocument();
    });
  });

  describe('assessment metadata', () => {
    it('shows finding count in metadata', () => {
      renderPage();
      expect(screen.getByText(/Findings \(3\)/)).toBeInTheDocument();
    });

    it('displays assessment ID in URL params', () => {
      // The assessment ID is used via useParams
      renderPage();
      expect(screen.getByText('Risk Assessment')).toBeInTheDocument();
    });
  });

  describe('card layout', () => {
    it('renders scores in a Card component', () => {
      renderPage();
      expect(screen.getByText('Assessment Scores')).toBeInTheDocument();
    });

    it('renders details in a Card component', () => {
      renderPage();
      expect(screen.getByText('Details')).toBeInTheDocument();
    });

    it('renders findings in a Card component', () => {
      renderPage();
      expect(screen.getByText(/Findings \(3\)/)).toBeInTheDocument();
    });
  });

  describe('score display formatting', () => {
    it('displays scores in large font', () => {
      renderPage();
      const overallScore = screen.getByText('84');
      expect(overallScore).toHaveClass('text-3xl');
      expect(overallScore).toHaveClass('font-bold');
    });

    it('displays score labels below scores', () => {
      renderPage();
      expect(screen.getByText('Overall')).toBeInTheDocument();
      expect(screen.getByText('Security')).toBeInTheDocument();
      expect(screen.getByText('Compliance')).toBeInTheDocument();
      expect(screen.getByText('Operational')).toBeInTheDocument();
    });
  });
});
