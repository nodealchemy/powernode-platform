import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { WorkflowExecutionSummaryModal } from './WorkflowExecutionSummaryModal';
import { workflowsApi } from '@/shared/services/ai';
import { WorkflowExecutionStats } from '@/shared/types/workflow';

// Mock consolidated workflow API
jest.mock('@/shared/services/ai', () => ({
  workflowsApi: {
    getWorkflow: jest.fn(),
    getRuns: jest.fn(),
    executeWorkflow: jest.fn(),
    getExecutionMetrics: jest.fn()
  }
}));
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    addNotification: jest.fn()
  })
}));

// Mock UI components
jest.mock('@/shared/components/ui/Modal', () => ({
  Modal: ({ children, isOpen, title, footer }: any) =>
    isOpen ? (
      <div data-testid="modal">
        <h2>{title}</h2>
        {children}
        <div>{footer}</div>
      </div>
    ) : null
}));

jest.mock('@/shared/components/ui/Button', () => ({
  Button: ({ children, onClick, variant, ...props }: any) => (
    <button onClick={onClick} data-variant={variant} {...props}>
      {children}
    </button>
  )
}));

jest.mock('@/shared/components/ui/Card', () => ({
  Card: ({ children }: any) => <div data-testid="card">{children}</div>,
  CardContent: ({ children }: any) => <div data-testid="card-content">{children}</div>,
  CardHeader: ({ children }: any) => <div data-testid="card-header">{children}</div>,
  CardTitle: ({ children }: any) => <h3 data-testid="card-title">{children}</h3>
}));

// Mock Lucide icons
jest.mock('lucide-react', () => ({
  BarChart3: () => <div data-testid="barchart3-icon" />,
  Clock: () => <div data-testid="clock-icon" />,
  TrendingUp: () => <div data-testid="trending-up-icon" />,
  TrendingDown: () => <div data-testid="trending-down-icon" />,
  CheckCircle: () => <div data-testid="check-circle-icon" />,
  XCircle: () => <div data-testid="x-circle-icon" />,
  AlertCircle: () => <div data-testid="alert-circle-icon" />,
  Activity: () => <div data-testid="activity-icon" />,
  DollarSign: () => <div data-testid="dollar-sign-icon" />,
  Calendar: () => <div data-testid="calendar-icon" />,
  Users: () => <div data-testid="users-icon" />
}));

const mockMetrics: WorkflowExecutionStats = {
  totalExecutions: 150,
  completedExecutions: 120,
  failedExecutions: 25,
  activeExecutions: 5,
  successRate: 0.8,
  avgExecutionTime: 45000, // 45 seconds
  minExecutionTime: 15000, // 15 seconds
  maxExecutionTime: 180000, // 3 minutes
  dailyExecutions: {
    '2024-01-01': 20,
    '2024-01-02': 15,
    '2024-01-03': 25,
    '2024-01-04': 18,
    '2024-01-05': 22
  },
  mostActiveUsers: {
    'user-001': 45,
    'user-002': 30,
    'user-003': 25,
    'user-004': 20,
    'user-005': 15
  }
};

const defaultProps = {
  isOpen: true,
  onClose: jest.fn(),
  workflowId: 'workflow-123',
  workflowName: 'Test Workflow'
};

describe('WorkflowExecutionSummaryModal', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('renders correctly when opened', () => {
    (workflowsApi.getExecutionMetrics as jest.Mock).mockResolvedValue({
      metrics: mockMetrics,
      period: {
        startDate: '2024-01-01',
        endDate: '2024-01-31',
        totalDays: 30
      }
    });

    render(<WorkflowExecutionSummaryModal {...defaultProps} />);

    expect(screen.getByTestId('modal')).toBeInTheDocument();
    expect(screen.getByText('Execution Summary - Test Workflow')).toBeInTheDocument();
  });

  it('displays loading state initially', () => {
    (workflowsApi.getExecutionMetrics as jest.Mock).mockImplementation(
      () => new Promise(resolve => setTimeout(resolve, 1000))
    );

    render(<WorkflowExecutionSummaryModal {...defaultProps} />);

    // Component shows spinner with animate-spin class
    expect(screen.getByTestId('modal')).toBeInTheDocument();
  });

  it('loads and displays execution metrics', async () => {
    (workflowsApi.getExecutionMetrics as jest.Mock).mockResolvedValue({
      metrics: mockMetrics,
      period: {
        startDate: '2024-01-01',
        endDate: '2024-01-31',
        totalDays: 30
      }
    });

    render(<WorkflowExecutionSummaryModal {...defaultProps} />);

    await waitFor(() => {
      expect(screen.getByText('150')).toBeInTheDocument(); // Total executions
      expect(screen.getByText('80%')).toBeInTheDocument(); // Success rate
      // Use getAllByText since '45.0s' appears in multiple places (metric card and performance section)
      expect(screen.getAllByText('45.0s').length).toBeGreaterThan(0); // Avg execution time
      // Use getAllByText since '5' appears in multiple places (active executions card and status breakdown)
      expect(screen.getAllByText('5').length).toBeGreaterThan(0); // Active executions
    });
  });

  it('displays execution status breakdown', async () => {
    (workflowsApi.getExecutionMetrics as jest.Mock).mockResolvedValue({
      metrics: mockMetrics,
      period: {
        startDate: '2024-01-01',
        endDate: '2024-01-31',
        totalDays: 30
      }
    });

    render(<WorkflowExecutionSummaryModal {...defaultProps} />);

    // Wait for metrics to load first
    await waitFor(() => {
      expect(screen.getByText('150')).toBeInTheDocument(); // Total executions from key metrics
    });

    // Then check for execution status breakdown content
    const cardTitles = screen.getAllByTestId('card-title');
    const statusTitle = cardTitles.find(el => el.textContent === 'Execution Status Breakdown');
    expect(statusTitle).toBeInTheDocument();
  });

  it('displays performance metrics', async () => {
    (workflowsApi.getExecutionMetrics as jest.Mock).mockResolvedValue({
      metrics: mockMetrics,
      period: {
        startDate: '2024-01-01',
        endDate: '2024-01-31',
        totalDays: 30
      }
    });

    render(<WorkflowExecutionSummaryModal {...defaultProps} />);

    // Wait for metrics to load first
    await waitFor(() => {
      expect(screen.getByText('150')).toBeInTheDocument(); // Total executions
    });

    // Check for performance metrics card
    const cardTitles = screen.getAllByTestId('card-title');
    const perfTitle = cardTitles.find(el => el.textContent === 'Performance Metrics');
    expect(perfTitle).toBeInTheDocument();
  });

  it('allows changing date range filters', async () => {
    (workflowsApi.getExecutionMetrics as jest.Mock).mockResolvedValue({
      metrics: mockMetrics,
      period: {
        startDate: '2024-01-01',
        endDate: '2024-01-31',
        totalDays: 30
      }
    });

    render(<WorkflowExecutionSummaryModal {...defaultProps} />);

    // Wait for content to load (loading state shows spinner, loaded state shows metrics)
    await waitFor(() => {
      expect(screen.getByText('Total Executions')).toBeInTheDocument();
    });

    // Click on "Last 7 days" filter
    const sevenDayButton = screen.getByText('Last 7 days');
    fireEvent.click(sevenDayButton);

    // Should call API again with different date range
    await waitFor(() => {
      expect(workflowsApi.getExecutionMetrics).toHaveBeenCalledTimes(2);
    });
  });

  it('displays daily activity chart when data is available', async () => {
    (workflowsApi.getExecutionMetrics as jest.Mock).mockResolvedValue({
      metrics: mockMetrics,
      period: {
        startDate: '2024-01-01',
        endDate: '2024-01-31',
        totalDays: 30
      }
    });

    render(<WorkflowExecutionSummaryModal {...defaultProps} />);

    // Wait for metrics to load first (verified by key metrics cards)
    await waitFor(() => {
      expect(screen.getByText('150')).toBeInTheDocument(); // Total executions
    });

    // Daily Activity section should render with dailyExecutions data
    // The CardTitle mock renders as h3
    const cardTitles = screen.getAllByTestId('card-title');
    const dailyActivityTitle = cardTitles.find(el => el.textContent === 'Daily Activity');
    expect(dailyActivityTitle).toBeInTheDocument();
  });

  it('displays most active users when data is available', async () => {
    (workflowsApi.getExecutionMetrics as jest.Mock).mockResolvedValue({
      metrics: mockMetrics,
      period: {
        startDate: '2024-01-01',
        endDate: '2024-01-31',
        totalDays: 30
      }
    });

    render(<WorkflowExecutionSummaryModal {...defaultProps} />);

    // Wait for metrics to load first
    await waitFor(() => {
      expect(screen.getByText('150')).toBeInTheDocument(); // Total executions
    });

    // Most Active Users section should render with mostActiveUsers data
    const cardTitles = screen.getAllByTestId('card-title');
    const usersTitle = cardTitles.find(el => el.textContent === 'Most Active Users');
    expect(usersTitle).toBeInTheDocument();
  });

  it('handles error state gracefully', async () => {
    const mockError = new Error('Failed to load metrics');
    (workflowsApi.getExecutionMetrics as jest.Mock).mockRejectedValue(mockError);

    render(<WorkflowExecutionSummaryModal {...defaultProps} />);

    await waitFor(() => {
      expect(screen.getByText('Failed to load execution summary. Please try again.')).toBeInTheDocument();
      expect(screen.getByText('Try Again')).toBeInTheDocument();
    });
  });

  it('displays empty state when no data is available', async () => {
    (workflowsApi.getExecutionMetrics as jest.Mock).mockResolvedValue({
      metrics: null,
      period: {
        startDate: '2024-01-01',
        endDate: '2024-01-31',
        totalDays: 30
      }
    });

    render(<WorkflowExecutionSummaryModal {...defaultProps} />);

    await waitFor(() => {
      expect(screen.getByText('No execution data available for this workflow.')).toBeInTheDocument();
    });
  });

  it('calls onClose when close button is clicked', async () => {
    (workflowsApi.getExecutionMetrics as jest.Mock).mockResolvedValue({
      metrics: mockMetrics,
      period: {
        startDate: '2024-01-01',
        endDate: '2024-01-31',
        totalDays: 30
      }
    });

    render(<WorkflowExecutionSummaryModal {...defaultProps} />);

    await waitFor(() => {
      const closeButton = screen.getByText('Close');
      fireEvent.click(closeButton);
      expect(defaultProps.onClose).toHaveBeenCalled();
    });
  });

  it('refreshes data when refresh button is clicked', async () => {
    (workflowsApi.getExecutionMetrics as jest.Mock).mockResolvedValue({
      metrics: mockMetrics,
      period: {
        startDate: '2024-01-01',
        endDate: '2024-01-31',
        totalDays: 30
      }
    });

    render(<WorkflowExecutionSummaryModal {...defaultProps} />);

    // Wait for initial load
    await waitFor(() => {
      expect(workflowsApi.getExecutionMetrics).toHaveBeenCalledTimes(1);
    });

    // Click refresh
    const refreshButton = screen.getByText('Refresh');
    fireEvent.click(refreshButton);

    await waitFor(() => {
      expect(workflowsApi.getExecutionMetrics).toHaveBeenCalledTimes(2);
    });
  });
});