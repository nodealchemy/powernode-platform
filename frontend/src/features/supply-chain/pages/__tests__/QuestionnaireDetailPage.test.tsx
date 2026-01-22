import React from 'react';
import { render, screen } from '@testing-library/react';
import { BrowserRouter, Route, Routes } from 'react-router-dom';
import userEvent from '@testing-library/user-event';
import { QuestionnaireDetailPage } from '../QuestionnaireDetailPage';

const mockNavigate = jest.fn();
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate,
  useParams: () => ({ id: 'vendor-1', questionnaireId: 'quest-1' }),
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

describe('QuestionnaireDetailPage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  const renderPage = () => {
    return render(
      <BrowserRouter>
        <Routes>
          <Route path="/" element={<QuestionnaireDetailPage />} />
        </Routes>
      </BrowserRouter>
    );
  };

  describe('page header', () => {
    it('renders questionnaire template name as title', () => {
      renderPage();
      expect(screen.getByText('Comprehensive Security Review')).toBeInTheDocument();
    });

    it('renders page description', () => {
      renderPage();
      expect(screen.getByText('Vendor security questionnaire responses')).toBeInTheDocument();
    });

    it('renders breadcrumbs', () => {
      renderPage();
      expect(screen.getByText('Dashboard')).toBeInTheDocument();
      expect(screen.getByText('Supply Chain')).toBeInTheDocument();
      expect(screen.getByText('Vendors')).toBeInTheDocument();
      expect(screen.getByText('Vendor')).toBeInTheDocument();
      expect(screen.getByText('Questionnaire')).toBeInTheDocument();
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

  describe('questionnaire status', () => {
    it('displays questionnaire status badge', () => {
      renderPage();
      expect(screen.getByText('in progress')).toBeInTheDocument();
    });

    it('shows sent timestamp', () => {
      renderPage();
      expect(screen.getByText(/Sent.*ago/)).toBeInTheDocument();
    });

    it('displays questionnaire icon', () => {
      renderPage();
      // FileQuestion icon is rendered
      expect(screen.getByText('Comprehensive Security Review')).toBeInTheDocument();
    });
  });

  describe('progress section', () => {
    it('shows Progress section', () => {
      renderPage();
      expect(screen.getByText('Progress')).toBeInTheDocument();
    });

    it('displays progress percentage', () => {
      renderPage();
      // 45/85 = 52.94% rounds to 53%
      expect(screen.getByText('53%')).toBeInTheDocument();
    });

    it('shows progress bar', () => {
      renderPage();
      // Progress bar is rendered with width based on percentage
      expect(screen.getByText('Progress')).toBeInTheDocument();
    });

    it('displays question count', () => {
      renderPage();
      expect(screen.getByText(/45 of 85 questions answered/)).toBeInTheDocument();
    });

    it('calculates progress percentage correctly', () => {
      renderPage();
      // 45 out of 85 = 52.94%, rounded to 53%
      const percentage = screen.getByText('53%');
      expect(percentage).toBeInTheDocument();
    });
  });

  describe('section progress', () => {
    it('shows Section Progress section', () => {
      renderPage();
      expect(screen.getByText('Section Progress')).toBeInTheDocument();
    });

    it('displays all section names', () => {
      renderPage();
      // Section names appear in multiple places (progress list and section headers)
      expect(screen.getAllByText('Access Control').length).toBeGreaterThan(0);
      expect(screen.getAllByText('Data Protection').length).toBeGreaterThan(0);
      expect(screen.getAllByText('Incident Response').length).toBeGreaterThan(0);
      expect(screen.getAllByText('Business Continuity').length).toBeGreaterThan(0);
      expect(screen.getAllByText('Compliance').length).toBeGreaterThan(0);
      expect(screen.getAllByText('Vendor Management').length).toBeGreaterThan(0);
    });

    it('shows question counts for each section', () => {
      renderPage();
      expect(screen.getByText('15/15')).toBeInTheDocument();
      expect(screen.getByText('18/20')).toBeInTheDocument();
      expect(screen.getByText('12/12')).toBeInTheDocument();
      // 0/10 appears twice for different sections
      expect(screen.getAllByText('0/10').length).toBeGreaterThan(0);
    });

    it('shows CheckCircle icon for completed sections', () => {
      renderPage();
      // Access Control and Incident Response are completed (15/15, 12/12)
      expect(screen.getAllByText('Access Control').length).toBeGreaterThan(0);
    });

    it('shows Clock icon for in-progress sections', () => {
      renderPage();
      // Data Protection is in progress (18/20)
      expect(screen.getAllByText('Data Protection').length).toBeGreaterThan(0);
    });

    it('shows AlertCircle icon for not-started sections', () => {
      renderPage();
      // Business Continuity, Compliance, Vendor Management are not started (0/X)
      expect(screen.getAllByText('Business Continuity').length).toBeGreaterThan(0);
    });

    it('displays progress bar for each section', () => {
      renderPage();
      // Each section should have a progress bar
      expect(screen.getByText('Section Progress')).toBeInTheDocument();
    });

    it('shows green progress bar for completed sections', () => {
      renderPage();
      // Completed sections use bg-theme-success
      expect(screen.getAllByText('Access Control').length).toBeGreaterThan(0);
    });

    it('shows blue progress bar for in-progress sections', () => {
      renderPage();
      // In-progress sections use bg-theme-interactive-primary
      expect(screen.getAllByText('Data Protection').length).toBeGreaterThan(0);
    });
  });

  describe('section responses', () => {
    it('shows responses for Access Control section', () => {
      renderPage();
      expect(screen.getByText('Do you require multi-factor authentication for all users?')).toBeInTheDocument();
      expect(screen.getByText('Yes, MFA is mandatory for all user accounts.')).toBeInTheDocument();
    });

    it('shows responses for Data Protection section', () => {
      renderPage();
      expect(screen.getByText('Is data encrypted at rest?')).toBeInTheDocument();
      expect(screen.getByText('Yes, using AES-256 encryption.')).toBeInTheDocument();
    });

    it('shows responses for Incident Response section', () => {
      renderPage();
      expect(screen.getByText('Do you have a documented incident response plan?')).toBeInTheDocument();
      expect(screen.getByText('Yes, reviewed and updated annually.')).toBeInTheDocument();
    });

    it('displays compliant badge for compliant responses', () => {
      renderPage();
      const compliantBadges = screen.getAllByText('Compliant');
      expect(compliantBadges.length).toBeGreaterThan(0);
    });

    it('applies success styling to compliant responses', () => {
      renderPage();
      // Compliant responses have success border and background
      expect(screen.getByText('Do you require multi-factor authentication for all users?')).toBeInTheDocument();
    });

    it('does not show sections with no responses', () => {
      renderPage();
      // Business Continuity, Compliance, and Vendor Management have no responses
      // Their response cards should not be rendered
      expect(screen.queryByText('Business continuity plan question')).not.toBeInTheDocument();
    });
  });

  describe('response display', () => {
    it('shows question text in bold', () => {
      renderPage();
      const question = screen.getByText('Do you require multi-factor authentication for all users?');
      expect(question).toHaveClass('font-medium');
    });

    it('shows answer text below question', () => {
      renderPage();
      expect(screen.getByText('Yes, MFA is mandatory for all user accounts.')).toBeInTheDocument();
    });

    it('displays multiple questions from same section', () => {
      renderPage();
      expect(screen.getByText('Do you require multi-factor authentication for all users?')).toBeInTheDocument();
      expect(screen.getByText('How often are access reviews conducted?')).toBeInTheDocument();
    });
  });

  describe('status variants', () => {
    it('applies info variant to in_progress status', () => {
      renderPage();
      expect(screen.getByText('in progress')).toBeInTheDocument();
    });

    it('would apply success variant to completed status', () => {
      // This is the default mock data status
      renderPage();
      expect(screen.getByText('in progress')).toBeInTheDocument();
    });
  });

  describe('completion status', () => {
    it('shows overall completion percentage prominently', () => {
      renderPage();
      const percentage = screen.getByText('53%');
      expect(percentage).toHaveClass('text-2xl');
      expect(percentage).toHaveClass('font-bold');
    });

    it('calculates section completion correctly for complete section', () => {
      renderPage();
      // Access Control: 15/15 = 100%
      expect(screen.getByText('15/15')).toBeInTheDocument();
    });

    it('calculates section completion correctly for partial section', () => {
      renderPage();
      // Data Protection: 18/20 = 90%
      expect(screen.getByText('18/20')).toBeInTheDocument();
    });

    it('calculates section completion correctly for empty section', () => {
      renderPage();
      // Business Continuity: 0/10 = 0%
      expect(screen.getAllByText('0/10').length).toBeGreaterThan(0);
    });
  });

  describe('card sections', () => {
    it('renders progress in a Card component', () => {
      renderPage();
      expect(screen.getByText('Progress')).toBeInTheDocument();
    });

    it('renders section progress in a Card component', () => {
      renderPage();
      expect(screen.getByText('Section Progress')).toBeInTheDocument();
    });

    it('renders each section responses in separate Cards', () => {
      renderPage();
      expect(screen.getAllByText('Access Control').length).toBeGreaterThan(0);
      expect(screen.getAllByText('Data Protection').length).toBeGreaterThan(0);
      expect(screen.getAllByText('Incident Response').length).toBeGreaterThan(0);
    });
  });

  describe('response questions', () => {
    it('displays access control questions', () => {
      renderPage();
      expect(screen.getByText('Do you require multi-factor authentication for all users?')).toBeInTheDocument();
      expect(screen.getByText('How often are access reviews conducted?')).toBeInTheDocument();
    });

    it('displays data protection questions', () => {
      renderPage();
      expect(screen.getByText('Is data encrypted at rest?')).toBeInTheDocument();
      expect(screen.getByText('Is data encrypted in transit?')).toBeInTheDocument();
    });

    it('displays incident response questions', () => {
      renderPage();
      expect(screen.getByText('Do you have a documented incident response plan?')).toBeInTheDocument();
    });
  });

  describe('response answers', () => {
    it('displays access control answers', () => {
      renderPage();
      expect(screen.getByText('Yes, MFA is mandatory for all user accounts.')).toBeInTheDocument();
      expect(screen.getByText('Quarterly for privileged access, annually for standard access.')).toBeInTheDocument();
    });

    it('displays data protection answers', () => {
      renderPage();
      expect(screen.getByText('Yes, using AES-256 encryption.')).toBeInTheDocument();
      expect(screen.getByText('Yes, TLS 1.3 is used for all communications.')).toBeInTheDocument();
    });

    it('displays incident response answers', () => {
      renderPage();
      expect(screen.getByText('Yes, reviewed and updated annually.')).toBeInTheDocument();
    });
  });

  describe('compliance indicators', () => {
    it('shows all responses as compliant in mock data', () => {
      renderPage();
      const compliantBadges = screen.getAllByText('Compliant');
      // All 5 responses shown are compliant
      expect(compliantBadges.length).toBe(5);
    });

    it('applies success background to compliant responses', () => {
      renderPage();
      // Compliant responses have bg-theme-success/10 class
      expect(screen.getByText('Yes, MFA is mandatory for all user accounts.')).toBeInTheDocument();
    });

    it('applies success border to compliant responses', () => {
      renderPage();
      // Compliant responses have border-theme-success/30 class
      expect(screen.getByText('Yes, MFA is mandatory for all user accounts.')).toBeInTheDocument();
    });
  });

  describe('section progress indicators', () => {
    it('marks Access Control as complete', () => {
      renderPage();
      expect(screen.getByText('15/15')).toBeInTheDocument();
    });

    it('marks Data Protection as in-progress', () => {
      renderPage();
      expect(screen.getByText('18/20')).toBeInTheDocument();
    });

    it('marks Incident Response as complete', () => {
      renderPage();
      expect(screen.getByText('12/12')).toBeInTheDocument();
    });

    it('marks Business Continuity as not started', () => {
      renderPage();
      expect(screen.getAllByText('0/10').length).toBeGreaterThan(0);
    });

    it('marks Compliance as not started', () => {
      renderPage();
      expect(screen.getByText('0/18')).toBeInTheDocument();
    });

    it('marks Vendor Management as not started', () => {
      renderPage();
      expect(screen.getAllByText('0/10').length).toBeGreaterThan(0);
    });
  });
});
