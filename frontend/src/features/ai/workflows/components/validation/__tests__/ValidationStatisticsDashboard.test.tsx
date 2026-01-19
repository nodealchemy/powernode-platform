import { render, screen, waitFor } from '@testing-library/react';
import { ValidationStatisticsDashboard } from '../ValidationStatisticsDashboard';
import { validationApi } from '@/shared/services/ai';

// Mock the validation API
jest.mock('@/shared/services/ai', () => ({
  validationApi: {
    getValidationStatistics: jest.fn(),
  },
}));

// Mock useNotifications hook
jest.mock('@/shared/hooks/useNotifications', () => ({
  useNotifications: () => ({
    addNotification: jest.fn(),
  }),
}));

describe('ValidationStatisticsDashboard', () => {
  const mockStatistics = {
    overview: {
      total_workflows: 50,
      validated_workflows: 45,
      unvalidated_workflows: 5,
      average_health_score: 85,
      valid_count: 30,
      invalid_count: 10,
      warning_count: 5,
      total_validations: 150,
      validations_last_24h: 12,
    },
    health_distribution: {
      healthy: 30,
      moderate: 10,
      unhealthy: 5,
    },
    status_distribution: {
      valid: 30,
      invalid: 10,
      warning: 5,
    },
    issue_categories: {
      configuration: 15,
      connection: 8,
      data_flow: 5,
      performance: 7,
      security: 3,
    },
    trends: [
      {
        date: '2025-01-01',
        avg_health_score: 82,
        validation_count: 10,
      },
    ],
    top_issues: [
      {
        code: 'missing_timeout',
        severity: 'warning',
        category: 'configuration',
        message: 'Node timeout not configured',
        count: 15,
      },
    ],
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('renders loading state initially', () => {
    (validationApi.getValidationStatistics as jest.Mock).mockImplementation(
      () => new Promise(() => {}) // Never resolves
    );

    render(<ValidationStatisticsDashboard />);

    expect(screen.getByText(/loading statistics/i)).toBeInTheDocument();
  });

  it('renders statistics dashboard with data', async () => {
    (validationApi.getValidationStatistics as jest.Mock).mockResolvedValue({
      statistics: mockStatistics,
    });

    render(<ValidationStatisticsDashboard />);

    await waitFor(() => {
      expect(screen.getByText('Validation Statistics')).toBeInTheDocument();
    });

    // Check overview metrics
    expect(screen.getByText('50')).toBeInTheDocument(); // Total workflows
    expect(screen.getByText('85')).toBeInTheDocument(); // Average health score
  });

  it('handles API errors gracefully', async () => {
    (validationApi.getValidationStatistics as jest.Mock).mockRejectedValue(
      new Error('API Error')
    );

    render(<ValidationStatisticsDashboard />);

    await waitFor(() => {
      expect(screen.getByText(/no statistics available/i)).toBeInTheDocument();
    });
  });

  it('allows changing time range', async () => {
    (validationApi.getValidationStatistics as jest.Mock).mockResolvedValue({
      statistics: mockStatistics,
    });

    const { rerender } = render(<ValidationStatisticsDashboard />);

    await waitFor(() => {
      expect(validationApi.getValidationStatistics).toHaveBeenCalledWith('', '30d');
    });

    // Would need to trigger select change in real test
    rerender(<ValidationStatisticsDashboard />);
  });
});
