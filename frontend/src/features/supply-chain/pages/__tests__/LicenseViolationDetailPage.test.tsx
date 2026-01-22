import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import { BreadcrumbProvider } from '@/shared/hooks/BreadcrumbContext';
import { LicenseViolationDetailPage } from '../LicenseViolationDetailPage';
import {
  useLicenseViolation,
  useResolveViolation,
  useGrantViolationException,
  useRequestException,
} from '../../hooks/useLicenseCompliance';
import { createMockLicenseViolation } from '../../testing/mockFactories';

jest.mock('../../hooks/useLicenseCompliance');
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ showNotification: jest.fn() }),
}));

const mockNavigate = jest.fn();
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate,
  useParams: () => ({ id: 'viol-123' }),
}));

// Mock window.prompt
global.prompt = jest.fn();

const mockUseLicenseViolation = useLicenseViolation as jest.MockedFunction<typeof useLicenseViolation>;
const mockUseResolveViolation = useResolveViolation as jest.MockedFunction<typeof useResolveViolation>;
const mockUseGrantViolationException = useGrantViolationException as jest.MockedFunction<typeof useGrantViolationException>;
const mockUseRequestException = useRequestException as jest.MockedFunction<typeof useRequestException>;

describe('LicenseViolationDetailPage', () => {
  const mockViolation = createMockLicenseViolation({
    id: 'viol-123',
    component_name: 'copyleft-lib',
    component_version: '1.2.3',
    license_name: 'GPL-3.0',
    license_spdx_id: 'GPL-3.0-only',
    violation_type: 'denied',
    severity: 'high',
    status: 'open',
    resolution_note: undefined,
    resolved_at: undefined,
    created_at: '2025-01-15T10:00:00Z',
  });

  const defaultMockData = {
    data: mockViolation,
    isLoading: false,
    error: null,
    refetch: jest.fn(),
  };

  const mockResolveMutation = {
    mutateAsync: jest.fn(),
    isLoading: false,
    error: null,
  };

  const mockGrantExceptionMutation = {
    mutateAsync: jest.fn(),
    isLoading: false,
    error: null,
  };

  const mockRequestExceptionMutation = {
    mutateAsync: jest.fn(),
    isLoading: false,
    error: null,
  };

  beforeEach(() => {
    jest.clearAllMocks();
    mockUseLicenseViolation.mockReturnValue(defaultMockData);
    mockUseResolveViolation.mockReturnValue(mockResolveMutation);
    mockUseGrantViolationException.mockReturnValue(mockGrantExceptionMutation);
    mockUseRequestException.mockReturnValue(mockRequestExceptionMutation);
    (global.prompt as jest.Mock).mockReturnValue('Test note');
  });

  const renderComponent = () => {
    return render(
      <BreadcrumbProvider>
        <BrowserRouter>
          <LicenseViolationDetailPage />
        </BrowserRouter>
      </BreadcrumbProvider>
    );
  };

  describe('loading state', () => {
    it('shows loading spinner when loading', () => {
      mockUseLicenseViolation.mockReturnValue({
        ...defaultMockData,
        isLoading: true,
      });
      const { container } = renderComponent();
      expect(container.querySelector('.animate-spin')).toBeInTheDocument();
    });

    it('does not show content while loading', () => {
      mockUseLicenseViolation.mockReturnValue({
        ...defaultMockData,
        isLoading: true,
      });
      renderComponent();
      expect(screen.queryByText('copyleft-lib@1.2.3')).not.toBeInTheDocument();
    });
  });

  describe('error state', () => {
    it('shows error message when violation fails to load', () => {
      mockUseLicenseViolation.mockReturnValue({
        ...defaultMockData,
        data: null,
        error: 'Failed to load violation',
      });
      renderComponent();
      expect(screen.getByText('Failed to load violation')).toBeInTheDocument();
    });

    it('shows error when violation is null', () => {
      mockUseLicenseViolation.mockReturnValue({
        ...defaultMockData,
        data: null,
      });
      renderComponent();
      expect(screen.getByText('Violation not found')).toBeInTheDocument();
    });
  });

  describe('page header', () => {
    it('renders component name and version as title', () => {
      renderComponent();
      const titleElement = screen.getByRole('heading', { level: 1 });
      expect(titleElement).toHaveTextContent('copyleft-lib@1.2.3');
    });

    it('renders description', () => {
      renderComponent();
      expect(screen.getByText('License compliance violation details')).toBeInTheDocument();
    });

    it('renders breadcrumbs', () => {
      renderComponent();
      const breadcrumb = screen.getByRole('navigation', { name: /breadcrumb/i });
      expect(breadcrumb).toBeInTheDocument();
      expect(breadcrumb).toHaveTextContent('Supply Chain');
      expect(breadcrumb).toHaveTextContent('License Violations');
    });

    it('renders Back to Violations action', () => {
      renderComponent();
      expect(screen.getByText('Back to Violations')).toBeInTheDocument();
    });
  });

  describe('back action', () => {
    it('navigates to violations list when Back clicked', () => {
      renderComponent();
      const backButton = screen.getByText('Back to Violations');

      fireEvent.click(backButton);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/licenses/violations');
    });
  });

  describe('status badges and icons', () => {
    it('displays warning badge for open status', () => {
      renderComponent();
      expect(screen.getByText('open')).toBeInTheDocument();
    });

    it('displays success badge for resolved status', () => {
      mockUseLicenseViolation.mockReturnValue({
        ...defaultMockData,
        data: { ...mockViolation, status: 'resolved' },
      });
      renderComponent();
      expect(screen.getByText('resolved')).toBeInTheDocument();
    });

    it('displays info badge for exception granted status', () => {
      mockUseLicenseViolation.mockReturnValue({
        ...defaultMockData,
        data: { ...mockViolation, status: 'exception_granted' },
      });
      renderComponent();
      expect(screen.getByText('Exception Granted')).toBeInTheDocument();
    });

    it('displays severity badge', () => {
      const { container } = renderComponent();
      // SeverityBadge component should be rendered
      const badges = container.querySelectorAll('[class*="badge"]');
      expect(badges.length).toBeGreaterThan(0);
    });

    it('shows error icon for open status', () => {
      const { container } = renderComponent();
      expect(container.querySelector('svg.text-theme-error')).toBeInTheDocument();
    });

    it('shows success icon for resolved status', () => {
      mockUseLicenseViolation.mockReturnValue({
        ...defaultMockData,
        data: { ...mockViolation, status: 'resolved', resolved_at: '2025-01-20T10:00:00Z' },
      });
      const { container } = renderComponent();
      expect(container.querySelector('svg.text-theme-success')).toBeInTheDocument();
    });
  });

  describe('violation details', () => {
    it('displays component name', () => {
      renderComponent();
      expect(screen.getByText('Component')).toBeInTheDocument();
      expect(screen.getByText('copyleft-lib')).toBeInTheDocument();
    });

    it('displays component version', () => {
      renderComponent();
      expect(screen.getByText('Version')).toBeInTheDocument();
      expect(screen.getByText('1.2.3')).toBeInTheDocument();
    });

    it('displays license name', () => {
      renderComponent();
      expect(screen.getByText('License')).toBeInTheDocument();
      // Match the exact license name to avoid matching SPDX ID
      expect(screen.getByText('GPL-3.0')).toBeInTheDocument();
    });

    it('displays SPDX ID when available', () => {
      renderComponent();
      expect(screen.getByText(/GPL-3.0-only/)).toBeInTheDocument();
    });

    it('displays violation type badge', () => {
      renderComponent();
      expect(screen.getByText('Violation Type')).toBeInTheDocument();
      expect(screen.getByText('Denied License')).toBeInTheDocument();
    });

    it('displays detected date', () => {
      renderComponent();
      expect(screen.getByText('Detected')).toBeInTheDocument();
    });

    it('displays resolved date when resolved', () => {
      mockUseLicenseViolation.mockReturnValue({
        ...defaultMockData,
        data: { ...mockViolation, status: 'resolved', resolved_at: '2025-01-20T10:00:00Z' },
      });
      renderComponent();
      // Look for the Resolved label in the violation details section, not status/activity
      const violationDetailsSection = screen.getByText('Violation Details').closest('div');
      expect(violationDetailsSection).toHaveTextContent('Resolved');
    });

    it('does not display resolved date when not resolved', () => {
      renderComponent();
      const resolvedLabels = screen.queryAllByText('Resolved');
      // Should only appear in breadcrumbs or status, not as a date label
      expect(resolvedLabels.length).toBeLessThan(2);
    });
  });

  describe('resolution note', () => {
    it('displays resolution note when available', () => {
      mockUseLicenseViolation.mockReturnValue({
        ...defaultMockData,
        data: { ...mockViolation, resolution_note: 'Fixed by updating dependency' },
      });
      renderComponent();
      expect(screen.getByText('Resolution Note')).toBeInTheDocument();
      expect(screen.getByText('Fixed by updating dependency')).toBeInTheDocument();
    });

    it('does not display resolution note section when not available', () => {
      renderComponent();
      expect(screen.queryByText('Resolution Note')).not.toBeInTheDocument();
    });

    it('styles resolution note with success theme', () => {
      mockUseLicenseViolation.mockReturnValue({
        ...defaultMockData,
        data: { ...mockViolation, resolution_note: 'Fixed by updating dependency' },
      });
      const { container } = renderComponent();
      // Find the resolution note container by looking for the specific background color
      const noteContainer = container.querySelector('div[class*="bg-theme-success"]');
      expect(noteContainer).toBeInTheDocument();
      expect(noteContainer).toHaveTextContent('Resolution Note');
    });
  });

  describe('actions section - open violations', () => {
    it('displays Actions section for open violations', () => {
      renderComponent();
      expect(screen.getByText('Actions')).toBeInTheDocument();
    });

    it('displays Mark as Resolved button', () => {
      renderComponent();
      expect(screen.getByText('Mark as Resolved')).toBeInTheDocument();
    });

    it('displays Grant Exception button', () => {
      renderComponent();
      expect(screen.getByText('Grant Exception')).toBeInTheDocument();
    });

    it('displays Request Exception button', () => {
      renderComponent();
      expect(screen.getByText('Request Exception')).toBeInTheDocument();
    });

    it('does not display Actions section for resolved violations', () => {
      mockUseLicenseViolation.mockReturnValue({
        ...defaultMockData,
        data: { ...mockViolation, status: 'resolved', resolved_at: '2025-01-20T10:00:00Z' },
      });
      renderComponent();
      expect(screen.queryByText('Mark as Resolved')).not.toBeInTheDocument();
    });
  });

  describe('resolve action', () => {
    it('prompts for note when Mark as Resolved clicked', async () => {
      renderComponent();
      const resolveButton = screen.getByText('Mark as Resolved');

      fireEvent.click(resolveButton);

      expect(global.prompt).toHaveBeenCalledWith('Enter resolution note (optional):');
    });

    it('calls resolve mutation with note', async () => {
      mockResolveMutation.mutateAsync.mockResolvedValue({});
      (global.prompt as jest.Mock).mockReturnValue('Fixed the issue');
      renderComponent();
      const resolveButton = screen.getByText('Mark as Resolved');

      fireEvent.click(resolveButton);

      await waitFor(() => {
        expect(mockResolveMutation.mutateAsync).toHaveBeenCalledWith({
          id: 'viol-123',
          note: 'Fixed the issue',
        });
      });
    });

    it('calls resolve mutation without note when empty', async () => {
      mockResolveMutation.mutateAsync.mockResolvedValue({});
      (global.prompt as jest.Mock).mockReturnValue('');
      renderComponent();
      const resolveButton = screen.getByText('Mark as Resolved');

      fireEvent.click(resolveButton);

      await waitFor(() => {
        expect(mockResolveMutation.mutateAsync).toHaveBeenCalledWith({
          id: 'viol-123',
          note: undefined,
        });
      });
    });

    it('does not call mutation when prompt cancelled', async () => {
      (global.prompt as jest.Mock).mockReturnValue(null);
      renderComponent();
      const resolveButton = screen.getByText('Mark as Resolved');

      fireEvent.click(resolveButton);

      await waitFor(() => {
        expect(mockResolveMutation.mutateAsync).not.toHaveBeenCalled();
      });
    });

    it('refetches violation after successful resolve', async () => {
      mockResolveMutation.mutateAsync.mockResolvedValue({});
      renderComponent();
      const resolveButton = screen.getByText('Mark as Resolved');

      fireEvent.click(resolveButton);

      await waitFor(() => {
        expect(defaultMockData.refetch).toHaveBeenCalled();
      });
    });

    it('disables button while resolving', () => {
      mockUseResolveViolation.mockReturnValue({
        ...mockResolveMutation,
        isLoading: true,
      });
      renderComponent();
      const resolveButton = screen.getByText('Resolving...');

      expect(resolveButton).toBeDisabled();
    });
  });

  describe('grant exception action', () => {
    it('prompts for justification when Grant Exception clicked', async () => {
      renderComponent();
      const grantButton = screen.getByText('Grant Exception');

      fireEvent.click(grantButton);

      expect(global.prompt).toHaveBeenCalledWith('Enter exception justification (required):');
    });

    it('calls grant exception mutation with justification', async () => {
      mockGrantExceptionMutation.mutateAsync.mockResolvedValue({});
      (global.prompt as jest.Mock).mockReturnValue('Business requirement');
      renderComponent();
      const grantButton = screen.getByText('Grant Exception');

      fireEvent.click(grantButton);

      await waitFor(() => {
        expect(mockGrantExceptionMutation.mutateAsync).toHaveBeenCalledWith({
          id: 'viol-123',
          note: 'Business requirement',
        });
      });
    });

    it('does not call mutation when justification empty', async () => {
      (global.prompt as jest.Mock).mockReturnValue('');
      renderComponent();
      const grantButton = screen.getByText('Grant Exception');

      fireEvent.click(grantButton);

      await waitFor(() => {
        expect(mockGrantExceptionMutation.mutateAsync).not.toHaveBeenCalled();
      });
    });

    it('refetches violation after successful grant', async () => {
      mockGrantExceptionMutation.mutateAsync.mockResolvedValue({});
      renderComponent();
      const grantButton = screen.getByText('Grant Exception');

      fireEvent.click(grantButton);

      await waitFor(() => {
        expect(defaultMockData.refetch).toHaveBeenCalled();
      });
    });

    it('disables button while granting', () => {
      mockUseGrantViolationException.mockReturnValue({
        ...mockGrantExceptionMutation,
        isLoading: true,
      });
      renderComponent();
      const grantButton = screen.getByText('Granting...');

      expect(grantButton).toBeDisabled();
    });
  });

  describe('request exception action', () => {
    it('opens modal when Request Exception clicked', () => {
      renderComponent();
      // Get the first Request Exception button (from the Actions section)
      const requestButtons = screen.getAllByText('Request Exception');
      const requestButton = requestButtons[0];

      fireEvent.click(requestButton);

      // Modal should be visible with the textarea
      expect(screen.getByPlaceholderText('Explain why an exception should be granted...')).toBeInTheDocument();
    });

    it('renders justification textarea in modal', () => {
      renderComponent();
      const requestButton = screen.getByText('Request Exception');

      fireEvent.click(requestButton);

      const textarea = screen.getByPlaceholderText('Explain why an exception should be granted...');
      expect(textarea).toBeInTheDocument();
    });

    it('renders Cancel and Submit buttons in modal', () => {
      renderComponent();
      const requestButton = screen.getByText('Request Exception');

      fireEvent.click(requestButton);

      expect(screen.getByText('Cancel')).toBeInTheDocument();
      expect(screen.getByText('Submit Request')).toBeInTheDocument();
    });

    it('allows entering justification', () => {
      renderComponent();
      const requestButton = screen.getByText('Request Exception');
      fireEvent.click(requestButton);

      const textarea = screen.getByPlaceholderText('Explain why an exception should be granted...') as HTMLTextAreaElement;
      fireEvent.change(textarea, { target: { value: 'Need this for legacy support' } });

      expect(textarea.value).toBe('Need this for legacy support');
    });

    it('disables submit when justification empty', () => {
      renderComponent();
      const requestButton = screen.getByText('Request Exception');
      fireEvent.click(requestButton);

      const submitButton = screen.getByText('Submit Request');
      expect(submitButton).toBeDisabled();
    });

    it('enables submit when justification provided', () => {
      renderComponent();
      const requestButton = screen.getByText('Request Exception');
      fireEvent.click(requestButton);

      const textarea = screen.getByPlaceholderText('Explain why an exception should be granted...');
      fireEvent.change(textarea, { target: { value: 'Need this for legacy support' } });

      const submitButton = screen.getByText('Submit Request');
      expect(submitButton).not.toBeDisabled();
    });

    it('calls request exception mutation when submitted', async () => {
      mockRequestExceptionMutation.mutateAsync.mockResolvedValue({});
      renderComponent();
      const requestButton = screen.getByText('Request Exception');
      fireEvent.click(requestButton);

      const textarea = screen.getByPlaceholderText('Explain why an exception should be granted...');
      fireEvent.change(textarea, { target: { value: 'Need this for legacy support' } });

      const submitButton = screen.getByText('Submit Request');
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(mockRequestExceptionMutation.mutateAsync).toHaveBeenCalledWith({
          id: 'viol-123',
          justification: 'Need this for legacy support',
        });
      });
    });

    it('closes modal after successful request', async () => {
      mockRequestExceptionMutation.mutateAsync.mockResolvedValue({});
      renderComponent();
      const requestButton = screen.getByText('Request Exception');
      fireEvent.click(requestButton);

      const textarea = screen.getByPlaceholderText('Explain why an exception should be granted...');
      fireEvent.change(textarea, { target: { value: 'Need this' } });

      const submitButton = screen.getByText('Submit Request');
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(screen.queryByPlaceholderText('Explain why an exception should be granted...')).not.toBeInTheDocument();
      });
    });

    it('closes modal when Cancel clicked', () => {
      renderComponent();
      const requestButton = screen.getByText('Request Exception');
      fireEvent.click(requestButton);

      const cancelButton = screen.getAllByText('Cancel')[0];
      fireEvent.click(cancelButton);

      expect(screen.queryByPlaceholderText('Explain why an exception should be granted...')).not.toBeInTheDocument();
    });

    it('closes modal when backdrop clicked', () => {
      const { container } = renderComponent();
      const requestButton = screen.getByText('Request Exception');
      fireEvent.click(requestButton);

      const backdrop = container.querySelector('.bg-black\\/50');
      fireEvent.click(backdrop!);

      expect(screen.queryByPlaceholderText('Explain why an exception should be granted...')).not.toBeInTheDocument();
    });

    it('clears justification after submission', async () => {
      mockRequestExceptionMutation.mutateAsync.mockResolvedValue({});
      renderComponent();
      const requestButtons = screen.getAllByText('Request Exception');
      fireEvent.click(requestButtons[0]);

      const textarea = screen.getByPlaceholderText('Explain why an exception should be granted...');
      fireEvent.change(textarea, { target: { value: 'Need this' } });

      const submitButton = screen.getByText('Submit Request');
      fireEvent.click(submitButton);

      await waitFor(() => {
        expect(mockRequestExceptionMutation.mutateAsync).toHaveBeenCalled();
      });

      // Open modal again - get the button from the Actions section again
      await waitFor(() => {
        expect(screen.queryByPlaceholderText('Explain why an exception should be granted...')).not.toBeInTheDocument();
      });

      const newRequestButtons = screen.getAllByText('Request Exception');
      fireEvent.click(newRequestButtons[0]);

      const newTextarea = screen.getByPlaceholderText('Explain why an exception should be granted...') as HTMLTextAreaElement;
      expect(newTextarea.value).toBe('');
    });

    it('shows loading state while submitting', () => {
      mockUseRequestException.mockReturnValue({
        ...mockRequestExceptionMutation,
        isLoading: true,
      });
      renderComponent();
      const requestButton = screen.getByText('Request Exception');
      fireEvent.click(requestButton);

      const textarea = screen.getByPlaceholderText('Explain why an exception should be granted...');
      fireEvent.change(textarea, { target: { value: 'Need this' } });

      expect(screen.getByText('Submitting...')).toBeInTheDocument();
    });
  });

  describe('activity history', () => {
    it('displays Activity History section', () => {
      renderComponent();
      expect(screen.getByText('Activity History')).toBeInTheDocument();
    });

    it('shows violation detected event', () => {
      renderComponent();
      expect(screen.getByText('Violation Detected')).toBeInTheDocument();
    });

    it('shows resolved event when violation is resolved', () => {
      mockUseLicenseViolation.mockReturnValue({
        ...defaultMockData,
        data: { ...mockViolation, status: 'resolved', resolved_at: '2025-01-20T10:00:00Z' },
      });
      renderComponent();
      const resolvedEvents = screen.getAllByText('Resolved');
      expect(resolvedEvents.length).toBeGreaterThan(0);
    });

    it('shows exception granted event when exception granted', () => {
      mockUseLicenseViolation.mockReturnValue({
        ...defaultMockData,
        data: { ...mockViolation, status: 'exception_granted', resolved_at: '2025-01-20T10:00:00Z' },
      });
      renderComponent();
      // Look for "Exception Granted" in the activity history section
      const activityHistory = screen.getByText('Activity History').closest('div');
      expect(activityHistory).toHaveTextContent('Exception Granted');
    });

    it('does not show resolved event for open violations', () => {
      renderComponent();
      const activitySection = screen.getByText('Activity History').closest('div');
      const resolvedInActivity = activitySection?.textContent?.match(/Resolved/g);
      expect(resolvedInActivity?.length || 0).toBe(0);
    });
  });

  describe('violation type badges', () => {
    it('shows Denied License badge for denied type', () => {
      renderComponent();
      expect(screen.getByText('Denied License')).toBeInTheDocument();
    });

    it('shows Copyleft Contamination badge for copyleft type', () => {
      mockUseLicenseViolation.mockReturnValue({
        ...defaultMockData,
        data: { ...mockViolation, violation_type: 'copyleft_contamination' },
      });
      renderComponent();
      expect(screen.getByText('Copyleft Contamination')).toBeInTheDocument();
    });

    it('shows Incompatible License badge for incompatible type', () => {
      mockUseLicenseViolation.mockReturnValue({
        ...defaultMockData,
        data: { ...mockViolation, violation_type: 'incompatible' },
      });
      renderComponent();
      expect(screen.getByText('Incompatible License')).toBeInTheDocument();
    });

    it('shows Unknown License badge for unknown_license type', () => {
      mockUseLicenseViolation.mockReturnValue({
        ...defaultMockData,
        data: { ...mockViolation, violation_type: 'unknown_license' },
      });
      renderComponent();
      expect(screen.getByText('Unknown License')).toBeInTheDocument();
    });
  });

  describe('date formatting', () => {
    it('formats dates correctly', () => {
      const { container } = renderComponent();
      const dateElements = container.querySelectorAll('p.text-theme-primary');
      expect(dateElements.length).toBeGreaterThan(0);
    });
  });
});
