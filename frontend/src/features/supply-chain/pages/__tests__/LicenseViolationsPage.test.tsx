import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import { BreadcrumbProvider } from '@/shared/hooks/BreadcrumbContext';
import { LicenseViolationsPage } from '../LicenseViolationsPage';
import {
  useLicenseViolations,
  useResolveViolation,
  useGrantViolationException,
} from '../../hooks/useLicenseCompliance';
import { createMockLicenseViolation, createMockPagination } from '../../testing/mockFactories';

jest.mock('../../hooks/useLicenseCompliance');

const mockNavigate = jest.fn();
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate,
}));

// Mock window.prompt and window.alert
global.prompt = jest.fn();
global.alert = jest.fn();

const mockUseLicenseViolations = useLicenseViolations as jest.MockedFunction<typeof useLicenseViolations>;
const mockUseResolveViolation = useResolveViolation as jest.MockedFunction<typeof useResolveViolation>;
const mockUseGrantViolationException = useGrantViolationException as jest.MockedFunction<typeof useGrantViolationException>;

describe('LicenseViolationsPage', () => {
  const mockViolations = [
    createMockLicenseViolation({
      id: 'viol-1',
      component_name: 'copyleft-lib',
      component_version: '1.2.3',
      license_name: 'GPL-3.0',
      license_spdx_id: 'GPL-3.0-only',
      violation_type: 'denied',
      severity: 'high',
      status: 'open',
      created_at: '2025-01-15T10:00:00Z',
    }),
    createMockLicenseViolation({
      id: 'viol-2',
      component_name: 'another-lib',
      component_version: '2.0.0',
      license_name: 'AGPL-3.0',
      license_spdx_id: 'AGPL-3.0-only',
      violation_type: 'copyleft_contamination',
      severity: 'critical',
      status: 'open',
      created_at: '2025-01-20T12:00:00Z',
    }),
    createMockLicenseViolation({
      id: 'viol-3',
      component_name: 'unknown-lib',
      component_version: '1.0.0',
      license_name: 'Unknown',
      license_spdx_id: undefined,
      violation_type: 'unknown_license',
      severity: 'medium',
      status: 'open',
      created_at: '2025-01-18T08:00:00Z',
    }),
  ];

  const mockPagination = createMockPagination({
    current_page: 1,
    per_page: 25,
    total_pages: 1,
    total_count: 3,
  });

  const defaultMockData = {
    data: { violations: mockViolations, pagination: mockPagination },
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

  beforeEach(() => {
    jest.clearAllMocks();
    mockUseLicenseViolations.mockReturnValue(defaultMockData);
    mockUseResolveViolation.mockReturnValue(mockResolveMutation);
    mockUseGrantViolationException.mockReturnValue(mockGrantExceptionMutation);
    (global.prompt as jest.Mock).mockReturnValue('Test note');
    (global.alert as jest.Mock).mockImplementation(() => {});
  });

  const renderComponent = () => {
    return render(
      <BreadcrumbProvider>
        <BrowserRouter>
          <LicenseViolationsPage />
        </BrowserRouter>
      </BreadcrumbProvider>
    );
  };

  describe('page rendering', () => {
    it('renders page title', () => {
      renderComponent();
      expect(screen.getByRole('heading', { name: 'License Violations' })).toBeInTheDocument();
    });

    it('renders page description', () => {
      renderComponent();
      expect(screen.getByText('Monitor and manage license compliance violations')).toBeInTheDocument();
    });

    it('renders breadcrumbs', () => {
      const { container } = renderComponent();
      const breadcrumb = container.querySelector('nav[aria-label="Breadcrumb"]');
      expect(breadcrumb).toBeInTheDocument();
      expect(breadcrumb?.querySelector('[title="Dashboard"]')).toBeInTheDocument();
      expect(screen.getByText('Supply Chain')).toBeInTheDocument();
      expect(screen.getAllByText('License Violations')[0]).toBeInTheDocument();
    });
  });

  describe('loading state', () => {
    it('shows loading spinner when loading', () => {
      mockUseLicenseViolations.mockReturnValue({
        ...defaultMockData,
        isLoading: true,
      });
      const { container } = renderComponent();
      expect(container.querySelector('.animate-spin')).toBeInTheDocument();
    });

    it('does not show data while loading', () => {
      mockUseLicenseViolations.mockReturnValue({
        ...defaultMockData,
        isLoading: true,
      });
      renderComponent();
      expect(screen.queryByText('copyleft-lib')).not.toBeInTheDocument();
    });
  });

  describe('tab navigation', () => {
    it('renders all tabs', () => {
      renderComponent();
      expect(screen.getAllByText('Open')[0]).toBeInTheDocument();
      expect(screen.getByText('Resolved')).toBeInTheDocument();
      expect(screen.getByText('Exception Granted')).toBeInTheDocument();
    });

    it('Open tab is active by default', () => {
      renderComponent();
      const openTab = screen.getAllByText('Open')[0].closest('button');
      expect(openTab).toHaveClass('border-theme-interactive-primary');
    });

    it('changes active tab when clicked', () => {
      renderComponent();
      const resolvedTab = screen.getByText('Resolved');

      fireEvent.click(resolvedTab);

      expect(resolvedTab.closest('button')).toHaveClass('border-theme-interactive-primary');
    });

    it('resets page to 1 when changing tabs', () => {
      renderComponent();
      const resolvedTab = screen.getByText('Resolved');

      fireEvent.click(resolvedTab);

      expect(mockUseLicenseViolations).toHaveBeenCalledWith(
        expect.objectContaining({
          page: 1,
          status: 'resolved',
        })
      );
    });

    it('calls hook with correct status for Open tab', () => {
      renderComponent();
      expect(mockUseLicenseViolations).toHaveBeenCalledWith(
        expect.objectContaining({
          status: 'open',
        })
      );
    });

    it('calls hook with correct status for Resolved tab', () => {
      renderComponent();
      const resolvedTab = screen.getByText('Resolved');
      fireEvent.click(resolvedTab);

      expect(mockUseLicenseViolations).toHaveBeenCalledWith(
        expect.objectContaining({
          status: 'resolved',
        })
      );
    });

    it('calls hook with correct status for Exception Granted tab', () => {
      renderComponent();
      const exceptionTab = screen.getByText('Exception Granted');
      fireEvent.click(exceptionTab);

      expect(mockUseLicenseViolations).toHaveBeenCalledWith(
        expect.objectContaining({
          status: 'exception_granted',
        })
      );
    });
  });

  describe('empty states', () => {
    it('shows empty state for Open tab', () => {
      mockUseLicenseViolations.mockReturnValue({
        ...defaultMockData,
        data: { violations: [], pagination: null },
      });
      renderComponent();
      expect(screen.getByText('No open violations')).toBeInTheDocument();
      expect(screen.getByText('There are no open license violations')).toBeInTheDocument();
    });

    it('shows empty state for Resolved tab', () => {
      mockUseLicenseViolations.mockReturnValue({
        ...defaultMockData,
        data: { violations: [], pagination: null },
      });
      renderComponent();
      const resolvedTab = screen.getByText('Resolved');
      fireEvent.click(resolvedTab);

      waitFor(() => {
        expect(screen.getByText('No resolved violations')).toBeInTheDocument();
      });
    });

    it('shows empty state for Exception Granted tab', () => {
      mockUseLicenseViolations.mockReturnValue({
        ...defaultMockData,
        data: { violations: [], pagination: null },
      });
      renderComponent();
      const exceptionTab = screen.getByText('Exception Granted');
      fireEvent.click(exceptionTab);

      waitFor(() => {
        expect(screen.getByText('No exception granted violations')).toBeInTheDocument();
      });
    });
  });

  describe('violations list rendering', () => {
    it('renders all violations', () => {
      renderComponent();
      expect(screen.getByText('copyleft-lib')).toBeInTheDocument();
      expect(screen.getByText('another-lib')).toBeInTheDocument();
      expect(screen.getByText('unknown-lib')).toBeInTheDocument();
    });

    it('renders table headers', () => {
      renderComponent();
      expect(screen.getByText('Component')).toBeInTheDocument();
      expect(screen.getByText('License')).toBeInTheDocument();
      expect(screen.getByText('Type')).toBeInTheDocument();
      expect(screen.getByText('Severity')).toBeInTheDocument();
      expect(screen.getByText('Status')).toBeInTheDocument();
      expect(screen.getByText('Created')).toBeInTheDocument();
      expect(screen.getByText('Actions')).toBeInTheDocument();
    });
  });

  describe('component column', () => {
    it('displays component name', () => {
      renderComponent();
      expect(screen.getByText('copyleft-lib')).toBeInTheDocument();
    });

    it('displays component version', () => {
      renderComponent();
      expect(screen.getByText('1.2.3')).toBeInTheDocument();
    });

    it('applies correct styling', () => {
      renderComponent();
      const nameElement = screen.getByText('copyleft-lib');
      expect(nameElement).toHaveClass('font-medium', 'text-theme-primary');
    });
  });

  describe('license column', () => {
    it('displays license name', () => {
      renderComponent();
      expect(screen.getByText('GPL-3.0')).toBeInTheDocument();
    });

    it('displays SPDX ID when available', () => {
      renderComponent();
      expect(screen.getByText('GPL-3.0-only')).toBeInTheDocument();
    });

    it('does not show SPDX ID when not available', () => {
      renderComponent();
      const unknownLicenseElements = screen.getAllByText('Unknown');
      const unknownLicense = unknownLicenseElements.find(el => el.closest('td'));
      expect(unknownLicense?.nextElementSibling).toBeFalsy();
    });
  });

  describe('type column', () => {
    it('shows denied badge with danger variant', () => {
      renderComponent();
      const badgeText = screen.getAllByText('Denied')[0];
      const badgeElement = badgeText.closest('span[class*="badge-theme"]');
      expect(badgeElement).toHaveClass('badge-theme-danger');
    });

    it('shows copyleft badge with warning variant', () => {
      renderComponent();
      const badgeText = screen.getAllByText('Copyleft')[0];
      const badgeElement = badgeText.closest('span[class*="badge-theme"]');
      expect(badgeElement).toHaveClass('badge-theme-warning');
    });

    it('shows unknown badge with info variant', () => {
      renderComponent();
      const badgeTexts = screen.getAllByText('Unknown');
      // Find the badge that is in a table cell (td or similar), not the license name
      const badgeText = badgeTexts.find(el => {
        const badgeEl = el.closest('span[class*="badge-theme"]');
        return badgeEl !== null;
      });
      const badgeElement = badgeText?.closest('span[class*="badge-theme"]');
      expect(badgeElement).toHaveClass('badge-theme-info');
    });
  });

  describe('severity column', () => {
    it('renders SeverityBadge component', () => {
      const { container } = renderComponent();
      const severityBadges = container.querySelectorAll('[class*="badge-theme"]');
      expect(severityBadges.length).toBeGreaterThan(0);
    });
  });

  describe('status column', () => {
    it('shows open status badge with warning variant', () => {
      renderComponent();
      const badges = screen.getAllByText('Open');
      const statusBadgeText = badges.find(el => el.closest('span[class*="badge-theme"]'));
      const badgeElement = statusBadgeText?.closest('span[class*="badge-theme"]');
      expect(badgeElement).toHaveClass('badge-theme-warning');
    });
  });

  describe('created column', () => {
    it('displays formatted date', () => {
      renderComponent();
      expect(screen.getByText('1/15/2025')).toBeInTheDocument();
    });
  });

  describe('actions column - open violations', () => {
    it('renders View button for each violation', () => {
      const { container } = renderComponent();
      const viewButtons = container.querySelectorAll('button[title="View Details"]');
      expect(viewButtons.length).toBe(mockViolations.length);
    });

    it('renders Resolve button for open violations', () => {
      renderComponent();
      const resolveButtons = screen.getAllByText('Resolve');
      expect(resolveButtons.length).toBe(mockViolations.length);
    });

    it('renders Exception button for open violations', () => {
      renderComponent();
      const exceptionButtons = screen.getAllByText('Exception');
      expect(exceptionButtons.length).toBe(mockViolations.length);
    });
  });

  describe('view action', () => {
    it('navigates to detail page when View clicked', () => {
      const { container } = renderComponent();
      const viewButtons = container.querySelectorAll('button[title="View Details"]');

      fireEvent.click(viewButtons[0]);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/licenses/violations/viol-1');
    });
  });

  describe('resolve action', () => {
    it('prompts for note when Resolve clicked', async () => {
      renderComponent();
      const resolveButtons = screen.getAllByText('Resolve');

      fireEvent.click(resolveButtons[0]);

      expect(global.prompt).toHaveBeenCalledWith('Enter resolution note (optional):');
    });

    it('calls resolve mutation with note', async () => {
      mockResolveMutation.mutateAsync.mockResolvedValue({});
      (global.prompt as jest.Mock).mockReturnValue('Fixed the issue');
      renderComponent();
      const resolveButtons = screen.getAllByText('Resolve');

      fireEvent.click(resolveButtons[0]);

      await waitFor(() => {
        expect(mockResolveMutation.mutateAsync).toHaveBeenCalledWith({
          id: 'viol-1',
          note: 'Fixed the issue',
        });
      });
    });

    it('calls resolve mutation without note when empty', async () => {
      mockResolveMutation.mutateAsync.mockResolvedValue({});
      (global.prompt as jest.Mock).mockReturnValue('');
      renderComponent();
      const resolveButtons = screen.getAllByText('Resolve');

      fireEvent.click(resolveButtons[0]);

      await waitFor(() => {
        expect(mockResolveMutation.mutateAsync).toHaveBeenCalledWith({
          id: 'viol-1',
          note: undefined,
        });
      });
    });

    it('does not call mutation when prompt cancelled', async () => {
      (global.prompt as jest.Mock).mockReturnValue(null);
      renderComponent();
      const resolveButtons = screen.getAllByText('Resolve');

      fireEvent.click(resolveButtons[0]);

      await waitFor(() => {
        expect(mockResolveMutation.mutateAsync).not.toHaveBeenCalled();
      });
    });
  });

  describe('grant exception action', () => {
    it('prompts for justification when Exception clicked', async () => {
      renderComponent();
      const exceptionButtons = screen.getAllByText('Exception');

      fireEvent.click(exceptionButtons[0]);

      expect(global.prompt).toHaveBeenCalledWith('Enter exception justification (required):');
    });

    it('calls grant exception mutation with justification', async () => {
      mockGrantExceptionMutation.mutateAsync.mockResolvedValue({});
      (global.prompt as jest.Mock).mockReturnValue('Business requirement');
      renderComponent();
      const exceptionButtons = screen.getAllByText('Exception');

      fireEvent.click(exceptionButtons[0]);

      await waitFor(() => {
        expect(mockGrantExceptionMutation.mutateAsync).toHaveBeenCalledWith({
          id: 'viol-1',
          note: 'Business requirement',
        });
      });
    });

    it('shows alert when justification is empty', async () => {
      (global.prompt as jest.Mock).mockReturnValue('');
      renderComponent();
      const exceptionButtons = screen.getAllByText('Exception');

      fireEvent.click(exceptionButtons[0]);

      await waitFor(() => {
        expect(global.alert).toHaveBeenCalledWith('Exception justification is required');
      });
    });

    it('shows alert when justification is whitespace only', async () => {
      (global.prompt as jest.Mock).mockReturnValue('   ');
      renderComponent();
      const exceptionButtons = screen.getAllByText('Exception');

      fireEvent.click(exceptionButtons[0]);

      await waitFor(() => {
        expect(global.alert).toHaveBeenCalledWith('Exception justification is required');
      });
    });

    it('does not call mutation when justification empty', async () => {
      (global.prompt as jest.Mock).mockReturnValue('');
      renderComponent();
      const exceptionButtons = screen.getAllByText('Exception');

      fireEvent.click(exceptionButtons[0]);

      await waitFor(() => {
        expect(mockGrantExceptionMutation.mutateAsync).not.toHaveBeenCalled();
      });
    });

    it('does not call mutation when prompt cancelled', async () => {
      (global.prompt as jest.Mock).mockReturnValue(null);
      renderComponent();
      const exceptionButtons = screen.getAllByText('Exception');

      fireEvent.click(exceptionButtons[0]);

      await waitFor(() => {
        expect(mockGrantExceptionMutation.mutateAsync).not.toHaveBeenCalled();
      });
    });

    it('does not show alert when prompt cancelled', async () => {
      (global.prompt as jest.Mock).mockReturnValue(null);
      renderComponent();
      const exceptionButtons = screen.getAllByText('Exception');

      fireEvent.click(exceptionButtons[0]);

      await waitFor(() => {
        expect(global.alert).not.toHaveBeenCalled();
      });
    });
  });

  describe('resolved violations display', () => {
    it('shows resolved date for resolved violations', () => {
      mockUseLicenseViolations.mockReturnValue({
        ...defaultMockData,
        data: {
          violations: [
            createMockLicenseViolation({
              id: 'viol-1',
              status: 'resolved',
              resolved_at: '2025-01-21T10:00:00Z',
            }),
          ],
          pagination: mockPagination,
        },
      });
      renderComponent();
      expect(screen.getByText('1/21/2025')).toBeInTheDocument();
    });

    it('does not show Resolve button for resolved violations', () => {
      mockUseLicenseViolations.mockReturnValue({
        ...defaultMockData,
        data: {
          violations: [
            createMockLicenseViolation({
              id: 'viol-1',
              status: 'resolved',
              resolved_at: '2025-01-21T10:00:00Z',
            }),
          ],
          pagination: mockPagination,
        },
      });
      renderComponent();
      expect(screen.queryByText('Resolve')).not.toBeInTheDocument();
    });

    it('does not show Exception button for resolved violations', () => {
      mockUseLicenseViolations.mockReturnValue({
        ...defaultMockData,
        data: {
          violations: [
            createMockLicenseViolation({
              id: 'viol-1',
              status: 'resolved',
              resolved_at: '2025-01-21T10:00:00Z',
            }),
          ],
          pagination: mockPagination,
        },
      });
      renderComponent();
      expect(screen.queryByText('Exception')).not.toBeInTheDocument();
    });
  });

  describe('pagination', () => {
    it('displays pagination when available', () => {
      renderComponent();
      expect(screen.getByText(/Page \d+ of \d+/)).toBeInTheDocument();
    });

    it('does not display pagination when not available', () => {
      mockUseLicenseViolations.mockReturnValue({
        ...defaultMockData,
        data: { violations: mockViolations, pagination: null },
      });
      renderComponent();
      expect(screen.queryByText(/Page \d+ of \d+/)).not.toBeInTheDocument();
    });

    it('calls hook with correct page parameter', () => {
      renderComponent();
      expect(mockUseLicenseViolations).toHaveBeenCalledWith({
        page: 1,
        per_page: 25,
        status: 'open',
      });
    });
  });

  describe('error handling', () => {
    it('handles resolve error gracefully', async () => {
      mockResolveMutation.mutateAsync.mockImplementation(() =>
        Promise.reject(new Error('Resolve failed')).catch(() => {
          // Error expected
        })
      );
      (global.prompt as jest.Mock).mockReturnValue('Test note');
      renderComponent();
      const resolveButtons = screen.getAllByText('Resolve');

      fireEvent.click(resolveButtons[0]);

      await waitFor(() => {
        expect(mockResolveMutation.mutateAsync).toHaveBeenCalled();
      });
    });

    it('handles grant exception error gracefully', async () => {
      mockGrantExceptionMutation.mutateAsync.mockImplementation(() =>
        Promise.reject(new Error('Grant failed')).catch(() => {
          // Error expected
        })
      );
      (global.prompt as jest.Mock).mockReturnValue('Test justification');
      renderComponent();
      const exceptionButtons = screen.getAllByText('Exception');

      fireEvent.click(exceptionButtons[0]);

      await waitFor(() => {
        expect(mockGrantExceptionMutation.mutateAsync).toHaveBeenCalled();
      });
    });
  });

  describe('tab icons', () => {
    it('renders AlertTriangle icon for Open tab', () => {
      const { container } = renderComponent();
      const openTab = screen.getAllByText('Open')[0].closest('button');
      expect(openTab?.querySelector('svg')).toBeInTheDocument();
    });

    it('renders CheckCircle2 icon for Resolved tab', () => {
      const { container } = renderComponent();
      const resolvedTab = screen.getByText('Resolved').closest('button');
      expect(resolvedTab?.querySelector('svg')).toBeInTheDocument();
    });

    it('renders ShieldAlert icon for Exception Granted tab', () => {
      const { container } = renderComponent();
      const exceptionTab = screen.getByText('Exception Granted').closest('button');
      expect(exceptionTab?.querySelector('svg')).toBeInTheDocument();
    });
  });

  describe('Refresh functionality', () => {
    it('shows Refresh button in page actions', () => {
      renderComponent();
      expect(screen.getByText('Refresh')).toBeInTheDocument();
    });

    it('calls refetch when Refresh button is clicked', async () => {
      const mockRefetch = jest.fn();
      mockUseLicenseViolations.mockReturnValue({
        ...defaultMockData,
        refetch: mockRefetch,
      });
      renderComponent();
      const refreshButton = screen.getByText('Refresh');
      fireEvent.click(refreshButton);
      await waitFor(() => {
        expect(mockRefetch).toHaveBeenCalled();
      });
    });

    it('disables Refresh button while loading', () => {
      mockUseLicenseViolations.mockReturnValue({
        ...defaultMockData,
        isLoading: true,
      });
      renderComponent();
      const refreshButton = screen.getByText('Refresh');
      expect(refreshButton).toBeDisabled();
    });
  });
});
