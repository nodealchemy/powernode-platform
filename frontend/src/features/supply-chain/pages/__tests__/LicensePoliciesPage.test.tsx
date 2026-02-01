import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { BrowserRouter } from 'react-router-dom';
import { BreadcrumbProvider } from '@/shared/hooks/BreadcrumbContext';
import { LicensePoliciesPage } from '../LicensePoliciesPage';
import { useLicensePolicies, useDeleteLicensePolicy, useToggleLicensePolicyActive } from '../../hooks/useLicenseCompliance';
import { createMockLicensePolicy, createMockPagination } from '../../testing/mockFactories';

jest.mock('../../hooks/useLicenseCompliance');
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({ showNotification: jest.fn() }),
}));
jest.mock('@/shared/components/ui/ConfirmationModal', () => ({
  useConfirmation: () => ({
    confirm: jest.fn(({ onConfirm }) => onConfirm()),
    ConfirmationDialog: null,
  }),
}));

// Mock PageContainer
jest.mock('@/shared/components/layout/PageContainer', () => ({
  PageContainer: ({ title, description, breadcrumbs, actions, children }: any) => (
    <div data-testid="page-container">
      <div data-testid="page-title">{title}</div>
      <div data-testid="page-description">{description}</div>
      <div data-testid="page-breadcrumbs">
        {breadcrumbs?.map((bc: any, i: number) => (
          <span key={i}>{bc.label}</span>
        ))}
      </div>
      <div data-testid="page-actions">
        {actions?.map((action: any) => (
          <button key={action.id} onClick={action.onClick} disabled={action.disabled}>
            {action.label}
          </button>
        ))}
      </div>
      {children}
    </div>
  ),
}));

// Mock DataTable
jest.mock('@/shared/components/ui/DataTable', () => ({
  DataTable: ({ columns, data, loading, onRowClick, emptyState, pagination, onPageChange: _onPageChange }: any) => (
    <div data-testid="data-table">
      {loading && <div className="animate-spin">Loading...</div>}
      {!loading && data.length === 0 && (
        <div data-testid="empty-state">
          <div>{emptyState?.title}</div>
          <div>{emptyState?.description}</div>
          {emptyState?.action && (
            <button onClick={emptyState.action.onClick}>{emptyState.action.label}</button>
          )}
        </div>
      )}
      {!loading && data.length > 0 && (
        <>
          <div className="table-header">
            {columns.map((col: any) => (
              <div key={col.key}>{col.header}</div>
            ))}
          </div>
          {data.map((item: any) => (
            <div key={item.id} onClick={() => onRowClick?.(item)} className="table-row">
              {columns.map((col: any) => (
                <div key={col.key}>{col.render ? col.render(item) : item[col.key]}</div>
              ))}
            </div>
          ))}
        </>
      )}
      {!loading && pagination && (
        <div role="navigation">
          <span>Page {pagination.current_page} of {pagination.total_pages}</span>
        </div>
      )}
    </div>
  ),
}));

// Mock Badge
jest.mock('@/shared/components/ui/Badge', () => ({
  Badge: ({ children, variant }: any) => (
    <span className={`badge-${variant}`}>{children}</span>
  ),
}));

const mockNavigate = jest.fn();
jest.mock('react-router-dom', () => ({
  ...jest.requireActual('react-router-dom'),
  useNavigate: () => mockNavigate,
}));

const mockUseLicensePolicies = useLicensePolicies as jest.MockedFunction<typeof useLicensePolicies>;
const mockUseDeleteLicensePolicy = useDeleteLicensePolicy as jest.MockedFunction<typeof useDeleteLicensePolicy>;
const mockUseToggleLicensePolicyActive = useToggleLicensePolicyActive as jest.MockedFunction<typeof useToggleLicensePolicyActive>;

describe('LicensePoliciesPage', () => {
  const mockPolicies = [
    createMockLicensePolicy({
      id: 'policy-1',
      name: 'Production Policy',
      policy_type: 'allowlist',
      enforcement_level: 'block',
      is_active: true,
      block_copyleft: true,
      block_strong_copyleft: false,
    }),
    createMockLicensePolicy({
      id: 'policy-2',
      name: 'Development Policy',
      policy_type: 'denylist',
      enforcement_level: 'warn',
      is_active: false,
      block_copyleft: false,
      block_strong_copyleft: true,
    }),
    createMockLicensePolicy({
      id: 'policy-3',
      name: 'Hybrid Policy',
      policy_type: 'hybrid',
      enforcement_level: 'log',
      is_active: true,
      block_copyleft: false,
      block_strong_copyleft: false,
    }),
  ];

  const mockPagination = createMockPagination({
    current_page: 1,
    per_page: 25,
    total_pages: 2,
    total_count: 3,
  });

  const defaultMockData = {
    data: { policies: mockPolicies, pagination: mockPagination },
    isLoading: false,
    error: null,
    refetch: jest.fn(),
  };

  const mockDeleteMutation = {
    mutateAsync: jest.fn(),
    isLoading: false,
    error: null,
  };

  const mockToggleMutation = {
    mutateAsync: jest.fn(),
    isLoading: false,
    error: null,
  };

  beforeEach(() => {
    jest.clearAllMocks();
    mockUseLicensePolicies.mockReturnValue(defaultMockData);
    mockUseDeleteLicensePolicy.mockReturnValue(mockDeleteMutation);
    mockUseToggleLicensePolicyActive.mockReturnValue(mockToggleMutation);
  });

  const renderComponent = () => {
    return render(
      <BreadcrumbProvider>
        <BrowserRouter>
          <LicensePoliciesPage />
        </BrowserRouter>
      </BreadcrumbProvider>
    );
  };

  describe('page rendering', () => {
    it('renders page title', () => {
      renderComponent();
      expect(screen.getByTestId('page-title')).toHaveTextContent('License Policies');
    });

    it('renders page description', () => {
      renderComponent();
      expect(screen.getByTestId('page-description')).toHaveTextContent('Manage license compliance policies and enforcement rules');
    });

    it('renders breadcrumbs', () => {
      renderComponent();
      const breadcrumbs = screen.getByTestId('page-breadcrumbs');
      expect(breadcrumbs).toHaveTextContent('Dashboard');
      expect(breadcrumbs).toHaveTextContent('Supply Chain');
      expect(breadcrumbs).toHaveTextContent('License Policies');
    });
  });

  describe('loading state', () => {
    it('shows loading spinner when loading', () => {
      mockUseLicensePolicies.mockReturnValue({
        ...defaultMockData,
        isLoading: true,
      });
      const { container } = renderComponent();
      expect(container.querySelector('.animate-spin')).toBeInTheDocument();
    });

    it('does not show data table while loading', () => {
      mockUseLicensePolicies.mockReturnValue({
        ...defaultMockData,
        isLoading: true,
      });
      renderComponent();
      expect(screen.queryByText('Production Policy')).not.toBeInTheDocument();
    });
  });

  describe('empty state', () => {
    it('shows empty state when no policies', () => {
      mockUseLicensePolicies.mockReturnValue({
        ...defaultMockData,
        data: { policies: [], pagination: null },
      });
      renderComponent();
      expect(screen.getByText('No license policies')).toBeInTheDocument();
      expect(screen.getByText('Create your first license policy to enforce compliance rules.')).toBeInTheDocument();
    });

    it('shows create action in empty state', () => {
      mockUseLicensePolicies.mockReturnValue({
        ...defaultMockData,
        data: { policies: [], pagination: null },
      });
      renderComponent();
      const createButtons = screen.getAllByText('Create Policy');
      expect(createButtons.length).toBeGreaterThan(0);
    });

    it('navigates to create page when empty state action clicked', () => {
      mockUseLicensePolicies.mockReturnValue({
        ...defaultMockData,
        data: { policies: [], pagination: null },
      });
      renderComponent();
      const createButtons = screen.getAllByText('Create Policy');
      fireEvent.click(createButtons[createButtons.length - 1]);
      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/licenses/policies/new');
    });
  });

  describe('policies list rendering', () => {
    it('renders all policies', () => {
      renderComponent();
      expect(screen.getByText('Production Policy')).toBeInTheDocument();
      expect(screen.getByText('Development Policy')).toBeInTheDocument();
      expect(screen.getByText('Hybrid Policy')).toBeInTheDocument();
    });

    it('renders table headers', () => {
      renderComponent();
      expect(screen.getByText('Name')).toBeInTheDocument();
      expect(screen.getByText('Type')).toBeInTheDocument();
      expect(screen.getByText('Enforcement')).toBeInTheDocument();
      expect(screen.getByText('Active')).toBeInTheDocument();
      expect(screen.getByText('Copyleft Rules')).toBeInTheDocument();
      expect(screen.getByText('Actions')).toBeInTheDocument();
    });
  });

  describe('name column', () => {
    it('displays policy name', () => {
      renderComponent();
      expect(screen.getByText('Production Policy')).toBeInTheDocument();
    });

    it('applies correct styling to name', () => {
      renderComponent();
      const nameElement = screen.getByText('Production Policy');
      expect(nameElement).toHaveClass('font-medium', 'text-theme-primary');
    });
  });

  describe('type column', () => {
    it('shows allowlist badge with correct variant', () => {
      renderComponent();
      const badges = screen.getAllByText('allowlist');
      expect(badges[0]).toBeInTheDocument();
      expect(badges[0].closest('span')).toHaveClass('badge-info');
    });

    it('shows denylist badge with correct variant', () => {
      renderComponent();
      const badges = screen.getAllByText('denylist');
      expect(badges[0]).toBeInTheDocument();
      expect(badges[0].closest('span')).toHaveClass('badge-warning');
    });

    it('shows hybrid badge with correct variant', () => {
      renderComponent();
      const badges = screen.getAllByText('hybrid');
      expect(badges[0]).toBeInTheDocument();
      expect(badges[0].closest('span')).toHaveClass('badge-primary');
    });
  });

  describe('enforcement column', () => {
    it('shows log badge with success variant', () => {
      renderComponent();
      const badges = screen.getAllByText('log');
      expect(badges[0]).toBeInTheDocument();
      expect(badges[0].closest('span')).toHaveClass('badge-success');
    });

    it('shows warn badge with warning variant', () => {
      renderComponent();
      const badges = screen.getAllByText('warn');
      expect(badges[0]).toBeInTheDocument();
      expect(badges[0].closest('span')).toHaveClass('badge-warning');
    });

    it('shows block badge with danger variant', () => {
      renderComponent();
      const badges = screen.getAllByText('block');
      expect(badges[0]).toBeInTheDocument();
      expect(badges[0].closest('span')).toHaveClass('badge-danger');
    });
  });

  describe('active toggle', () => {
    it('renders toggle switch for each policy', () => {
      const { container } = renderComponent();
      const toggles = container.querySelectorAll('input[type="checkbox"]');
      expect(toggles.length).toBeGreaterThanOrEqual(mockPolicies.length);
    });

    it('shows active state correctly', () => {
      const { container } = renderComponent();
      const toggles = container.querySelectorAll('input[type="checkbox"]');
      expect(toggles[0]).toBeChecked(); // Production Policy is active
      expect(toggles[1]).not.toBeChecked(); // Development Policy is inactive
    });

    it('calls toggle mutation when clicked', async () => {
      const { container } = renderComponent();
      const toggles = container.querySelectorAll('input[type="checkbox"]');

      fireEvent.click(toggles[0]);

      await waitFor(() => {
        expect(mockToggleMutation.mutateAsync).toHaveBeenCalledWith({
          id: 'policy-1',
          isActive: false,
        });
      });
    });

    it('refetches data after successful toggle', async () => {
      mockToggleMutation.mutateAsync.mockResolvedValue({});
      const { container } = renderComponent();
      const toggles = container.querySelectorAll('input[type="checkbox"]');

      fireEvent.click(toggles[0]);

      await waitFor(() => {
        expect(defaultMockData.refetch).toHaveBeenCalled();
      });
    });
  });

  describe('copyleft rules column', () => {
    it('shows Block Copyleft badge when block_copyleft is true', () => {
      renderComponent();
      expect(screen.getByText('Block Copyleft')).toBeInTheDocument();
    });

    it('shows Block Strong badge when block_strong_copyleft is true', () => {
      renderComponent();
      expect(screen.getByText('Block Strong')).toBeInTheDocument();
    });

    it('shows None when no copyleft rules', () => {
      renderComponent();
      expect(screen.getByText('None')).toBeInTheDocument();
    });

    it('applies correct badge variants', () => {
      renderComponent();
      const blockCopyleft = screen.getByText('Block Copyleft');
      const blockStrong = screen.getByText('Block Strong');

      expect(blockCopyleft.closest('span')).toHaveClass('badge-warning');
      expect(blockStrong.closest('span')).toHaveClass('badge-danger');
    });
  });

  describe('actions column', () => {
    it('renders View button for each policy', () => {
      const { container } = renderComponent();
      const viewButtons = container.querySelectorAll('button[title="View details"]');
      expect(viewButtons).toHaveLength(mockPolicies.length);
    });

    it('renders Edit button for each policy', () => {
      const { container } = renderComponent();
      const editButtons = container.querySelectorAll('button[title="Edit policy"]');
      expect(editButtons).toHaveLength(mockPolicies.length);
    });

    it('renders Delete button for each policy', () => {
      const { container } = renderComponent();
      const deleteButtons = container.querySelectorAll('button[title="Delete policy"]');
      expect(deleteButtons).toHaveLength(mockPolicies.length);
    });
  });

  describe('view action', () => {
    it('navigates to detail page when View clicked', () => {
      const { container } = renderComponent();
      const viewButtons = container.querySelectorAll('button[title="View details"]');

      fireEvent.click(viewButtons[0]);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/licenses/policies/policy-1');
    });

    it('stops event propagation when View clicked', () => {
      const { container } = renderComponent();
      const viewButtons = container.querySelectorAll('button[title="View details"]');

      const clickEvent = new MouseEvent('click', { bubbles: true });
      const stopPropagation = jest.spyOn(clickEvent, 'stopPropagation');

      viewButtons[0].dispatchEvent(clickEvent);

      expect(stopPropagation).toHaveBeenCalled();
    });
  });

  describe('edit action', () => {
    it('navigates to edit page when Edit clicked', () => {
      const { container } = renderComponent();
      const editButtons = container.querySelectorAll('button[title="Edit policy"]');

      fireEvent.click(editButtons[0]);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/licenses/policies/policy-1/edit');
    });

    it('stops event propagation when Edit clicked', () => {
      const { container } = renderComponent();
      const editButtons = container.querySelectorAll('button[title="Edit policy"]');

      const clickEvent = new MouseEvent('click', { bubbles: true });
      const stopPropagation = jest.spyOn(clickEvent, 'stopPropagation');

      editButtons[0].dispatchEvent(clickEvent);

      expect(stopPropagation).toHaveBeenCalled();
    });
  });

  describe('delete action', () => {
    it('triggers confirmation when Delete clicked', () => {
      const { container } = renderComponent();
      const deleteButtons = container.querySelectorAll('button[title="Delete policy"]');

      fireEvent.click(deleteButtons[0]);

      expect(mockDeleteMutation.mutateAsync).toHaveBeenCalledWith('policy-1');
    });

    it('calls delete mutation with correct policy ID', async () => {
      mockDeleteMutation.mutateAsync.mockResolvedValue({});
      const { container } = renderComponent();
      const deleteButtons = container.querySelectorAll('button[title="Delete policy"]');

      fireEvent.click(deleteButtons[0]);

      await waitFor(() => {
        expect(mockDeleteMutation.mutateAsync).toHaveBeenCalledWith('policy-1');
      });
    });

    it('refetches data after successful deletion', async () => {
      mockDeleteMutation.mutateAsync.mockResolvedValue({});
      const { container } = renderComponent();
      const deleteButtons = container.querySelectorAll('button[title="Delete policy"]');

      fireEvent.click(deleteButtons[0]);

      await waitFor(() => {
        expect(defaultMockData.refetch).toHaveBeenCalled();
      });
    });

    it('stops event propagation when Delete clicked', () => {
      const { container } = renderComponent();
      const deleteButtons = container.querySelectorAll('button[title="Delete policy"]');

      const clickEvent = new MouseEvent('click', { bubbles: true });
      const stopPropagation = jest.spyOn(clickEvent, 'stopPropagation');

      deleteButtons[0].dispatchEvent(clickEvent);

      expect(stopPropagation).toHaveBeenCalled();
    });
  });

  describe('row click', () => {
    it('navigates to detail page when row clicked', () => {
      renderComponent();
      const policyName = screen.getByText('Production Policy');

      fireEvent.click(policyName);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/licenses/policies/policy-1');
    });
  });

  describe('create policy action', () => {
    it('renders Create Policy button in actions', () => {
      renderComponent();
      const createButtons = screen.getAllByText('Create Policy');
      expect(createButtons.length).toBeGreaterThan(0);
    });

    it('navigates to create page when Create Policy clicked', () => {
      renderComponent();
      const createButtons = screen.getAllByText('Create Policy');

      fireEvent.click(createButtons[0]);

      expect(mockNavigate).toHaveBeenCalledWith('/app/supply-chain/licenses/policies/new');
    });
  });

  describe('pagination', () => {
    it('displays pagination when available', () => {
      const { container } = renderComponent();
      // Check for pagination elements
      expect(container.querySelector('[role="navigation"]')).toBeInTheDocument();
    });

    it('does not display pagination when not available', () => {
      mockUseLicensePolicies.mockReturnValue({
        ...defaultMockData,
        data: { policies: mockPolicies, pagination: null },
      });
      const { container } = renderComponent();
      expect(container.querySelector('[role="navigation"]')).not.toBeInTheDocument();
    });

    it('calls hook with correct page parameter', () => {
      renderComponent();
      expect(mockUseLicensePolicies).toHaveBeenCalledWith({
        page: 1,
        per_page: 25,
      });
    });
  });

  describe('error handling', () => {
    it('handles delete error gracefully', async () => {
      mockDeleteMutation.mutateAsync.mockRejectedValue(new Error('Delete failed'));
      const { container } = renderComponent();
      const deleteButtons = container.querySelectorAll('button[title="Delete policy"]');

      fireEvent.click(deleteButtons[0]);

      await waitFor(() => {
        expect(mockDeleteMutation.mutateAsync).toHaveBeenCalled();
      });
    });

    it('handles toggle error gracefully', async () => {
      mockToggleMutation.mutateAsync.mockRejectedValue(new Error('Toggle failed'));
      const { container } = renderComponent();
      const toggles = container.querySelectorAll('input[type="checkbox"]');

      fireEvent.click(toggles[0]);

      await waitFor(() => {
        expect(mockToggleMutation.mutateAsync).toHaveBeenCalled();
      });
    });
  });

  describe('accessibility', () => {
    it('has accessible button labels', () => {
      const { container } = renderComponent();
      expect(container.querySelector('button[title="View details"]')).toBeInTheDocument();
      expect(container.querySelector('button[title="Edit policy"]')).toBeInTheDocument();
      expect(container.querySelector('button[title="Delete policy"]')).toBeInTheDocument();
    });

    it('has accessible toggle switches', () => {
      const { container } = renderComponent();
      const hiddenCheckboxes = container.querySelectorAll('.sr-only');
      expect(hiddenCheckboxes.length).toBeGreaterThan(0);
    });
  });

  describe('Refresh functionality', () => {
    it('shows Refresh button in page actions', () => {
      renderComponent();
      expect(screen.getByText('Refresh')).toBeInTheDocument();
    });

    it('calls refetch when Refresh button is clicked', async () => {
      const mockRefetch = jest.fn();
      mockUseLicensePolicies.mockReturnValue({
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
      mockUseLicensePolicies.mockReturnValue({
        ...defaultMockData,
        isLoading: true,
      });
      renderComponent();
      const refreshButton = screen.getByText('Refresh');
      expect(refreshButton).toBeDisabled();
    });
  });
});
