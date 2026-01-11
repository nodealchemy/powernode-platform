import { render, screen } from '@testing-library/react';
import { CohortChart } from './CohortChart';

describe('CohortChart', () => {
  const mockData = [
    {
      cohort_date: '2024-01',
      cohort_size: 150,
      retention_rates: [
        { month: 0, retention_rate: 1.0, retained_customers: 150 },
        { month: 1, retention_rate: 0.85, retained_customers: 128 },
        { month: 2, retention_rate: 0.75, retained_customers: 113 },
        { month: 3, retention_rate: 0.68, retained_customers: 102 },
        { month: 4, retention_rate: 0.62, retained_customers: 93 },
        { month: 5, retention_rate: 0.58, retained_customers: 87 },
        { month: 6, retention_rate: 0.55, retained_customers: 83 }
      ]
    },
    {
      cohort_date: '2024-02',
      cohort_size: 200,
      retention_rates: [
        { month: 0, retention_rate: 1.0, retained_customers: 200 },
        { month: 1, retention_rate: 0.88, retained_customers: 176 },
        { month: 2, retention_rate: 0.78, retained_customers: 156 },
        { month: 3, retention_rate: 0.72, retained_customers: 144 },
        { month: 4, retention_rate: 0.65, retained_customers: 130 },
        { month: 5, retention_rate: 0.60, retained_customers: 120 },
        { month: 6, retention_rate: 0.56, retained_customers: 112 }
      ]
    },
    {
      cohort_date: '2024-03',
      cohort_size: 180,
      retention_rates: [
        { month: 0, retention_rate: 1.0, retained_customers: 180 },
        { month: 1, retention_rate: 0.90, retained_customers: 162 },
        { month: 2, retention_rate: 0.82, retained_customers: 148 },
        { month: 3, retention_rate: 0.76, retained_customers: 137 }
      ]
    }
  ];

  const mockSummary = {
    total_cohorts: 3,
    average_first_month_retention: 87.67,
    average_six_month_retention: 55.5
  };

  const defaultProps = {
    data: mockData,
    title: 'Customer Retention Cohorts'
  };

  describe('empty state', () => {
    it('shows empty state when no data', () => {
      render(<CohortChart data={[]} title="Empty Cohorts" />);

      expect(screen.getByText('No Cohort Data Available')).toBeInTheDocument();
    });

    it('shows helpful message in empty state', () => {
      render(<CohortChart data={[]} title="Empty Cohorts" />);

      expect(screen.getByText(/Cohort analysis will appear here/)).toBeInTheDocument();
    });

    it('shows title in empty state', () => {
      render(<CohortChart data={[]} title="Empty Cohorts" />);

      expect(screen.getByText('Empty Cohorts')).toBeInTheDocument();
    });
  });

  describe('summary section', () => {
    it('shows Cohort Summary when summary provided', () => {
      render(<CohortChart {...defaultProps} summary={mockSummary} />);

      expect(screen.getByText('Cohort Summary')).toBeInTheDocument();
    });

    it('shows total cohorts count', () => {
      render(<CohortChart {...defaultProps} summary={mockSummary} />);

      expect(screen.getByText('Total Cohorts')).toBeInTheDocument();
      expect(screen.getByText('3')).toBeInTheDocument();
    });

    it('shows average 1st month retention', () => {
      render(<CohortChart {...defaultProps} summary={mockSummary} />);

      expect(screen.getByText('Avg 1st Month Retention')).toBeInTheDocument();
      // 88% appears multiple times (summary + table), use getAllByText
      expect(screen.getAllByText('88%').length).toBeGreaterThan(0);
    });

    it('shows average 6th month retention', () => {
      render(<CohortChart {...defaultProps} summary={mockSummary} />);

      expect(screen.getByText('Avg 6th Month Retention')).toBeInTheDocument();
      // 56% appears multiple times (summary + table), use getAllByText
      expect(screen.getAllByText('56%').length).toBeGreaterThan(0);
    });

    it('hides summary when not provided', () => {
      render(<CohortChart {...defaultProps} />);

      expect(screen.queryByText('Cohort Summary')).not.toBeInTheDocument();
    });
  });

  describe('retention analysis table', () => {
    it('shows Cohort Retention Analysis section', () => {
      render(<CohortChart {...defaultProps} />);

      expect(screen.getByText('Cohort Retention Analysis')).toBeInTheDocument();
    });

    it('shows Cohort column header', () => {
      render(<CohortChart {...defaultProps} />);

      expect(screen.getByText('Cohort')).toBeInTheDocument();
    });

    it('shows Size column header', () => {
      render(<CohortChart {...defaultProps} />);

      expect(screen.getByText('Size')).toBeInTheDocument();
    });

    it('shows month column headers', () => {
      render(<CohortChart {...defaultProps} />);

      // Month labels appear in both table headers and X-axis
      expect(screen.getAllByText('M0').length).toBeGreaterThan(0);
      expect(screen.getAllByText('M1').length).toBeGreaterThan(0);
      expect(screen.getAllByText('M2').length).toBeGreaterThan(0);
    });

    it('shows cohort dates formatted', () => {
      render(<CohortChart {...defaultProps} />);

      // Dates appear in table and legend
      expect(screen.getAllByText('Jan 2024').length).toBeGreaterThan(0);
      expect(screen.getAllByText('Feb 2024').length).toBeGreaterThan(0);
      expect(screen.getAllByText('Mar 2024').length).toBeGreaterThan(0);
    });

    it('shows cohort sizes', () => {
      render(<CohortChart {...defaultProps} />);

      expect(screen.getByText('150')).toBeInTheDocument();
      expect(screen.getByText('200')).toBeInTheDocument();
      expect(screen.getByText('180')).toBeInTheDocument();
    });

    it('shows retention percentages', () => {
      render(<CohortChart {...defaultProps} />);

      // M0 is always 100% (3 in table + 1 in Y-axis)
      expect(screen.getAllByText('100%').length).toBeGreaterThanOrEqual(3);
      // First cohort M1 is 85%
      expect(screen.getAllByText('85%').length).toBeGreaterThan(0);
    });
  });

  describe('retention legend', () => {
    it('shows Retention Rate label', () => {
      render(<CohortChart {...defaultProps} />);

      expect(screen.getByText('Retention Rate:')).toBeInTheDocument();
    });

    it('shows 0-20% range', () => {
      render(<CohortChart {...defaultProps} />);

      expect(screen.getByText('0-20%')).toBeInTheDocument();
    });

    it('shows 20-40% range', () => {
      render(<CohortChart {...defaultProps} />);

      expect(screen.getByText('20-40%')).toBeInTheDocument();
    });

    it('shows 60-80% range', () => {
      render(<CohortChart {...defaultProps} />);

      expect(screen.getByText('60-80%')).toBeInTheDocument();
    });

    it('shows 80%+ range', () => {
      render(<CohortChart {...defaultProps} />);

      expect(screen.getByText('80%+')).toBeInTheDocument();
    });
  });

  describe('retention curves', () => {
    it('shows Retention Curves section', () => {
      render(<CohortChart {...defaultProps} />);

      expect(screen.getByText('Retention Curves')).toBeInTheDocument();
    });

    it('renders SVG for curves', () => {
      const { container } = render(<CohortChart {...defaultProps} />);

      // Should have SVGs for the curves visualization
      const svgs = container.querySelectorAll('svg');
      expect(svgs.length).toBeGreaterThan(0);
    });

    it('renders path elements for curve lines', () => {
      const { container } = render(<CohortChart {...defaultProps} />);

      const paths = container.querySelectorAll('path');
      expect(paths.length).toBeGreaterThan(0);
    });

    it('renders circle elements for data points', () => {
      const { container } = render(<CohortChart {...defaultProps} />);

      const circles = container.querySelectorAll('circle');
      expect(circles.length).toBeGreaterThan(0);
    });

    it('shows Y-axis percentage labels', () => {
      render(<CohortChart {...defaultProps} />);

      expect(screen.getAllByText('0%').length).toBeGreaterThan(0);
      expect(screen.getAllByText('20%').length).toBeGreaterThan(0);
      expect(screen.getAllByText('40%').length).toBeGreaterThan(0);
      expect(screen.getAllByText('60%').length).toBeGreaterThan(0);
      expect(screen.getAllByText('80%').length).toBeGreaterThan(0);
    });

    it('shows legend with cohort dates', () => {
      render(<CohortChart {...defaultProps} />);

      // Multiple instances of these dates may appear
      expect(screen.getAllByText('Jan 2024').length).toBeGreaterThan(0);
      expect(screen.getAllByText('Feb 2024').length).toBeGreaterThan(0);
      expect(screen.getAllByText('Mar 2024').length).toBeGreaterThan(0);
    });
  });

  describe('cohort performance insights', () => {
    it('shows Cohort Performance Insights section', () => {
      render(<CohortChart {...defaultProps} />);

      expect(screen.getByText('Cohort Performance Insights')).toBeInTheDocument();
    });

    it('shows Best Performing Cohort card', () => {
      render(<CohortChart {...defaultProps} />);

      expect(screen.getByText(/Best Performing Cohort/)).toBeInTheDocument();
    });

    it('shows Largest Cohort card', () => {
      render(<CohortChart {...defaultProps} />);

      expect(screen.getByText(/Largest Cohort/)).toBeInTheDocument();
    });

    it('shows Retention Trend card', () => {
      render(<CohortChart {...defaultProps} />);

      expect(screen.getByText(/Retention Trend/)).toBeInTheDocument();
    });

    it('identifies Feb 2024 as largest cohort', () => {
      render(<CohortChart {...defaultProps} />);

      // Feb 2024 has 200 customers - largest
      const largestCard = screen.getByText(/Largest Cohort/).parentElement;
      expect(largestCard?.textContent).toContain('200');
    });
  });

  describe('retention color coding', () => {
    it('applies success color for high retention (80%+)', () => {
      const { container } = render(<CohortChart {...defaultProps} />);

      // 100% cells should have success color
      expect(container.querySelector('.bg-theme-success')).toBeInTheDocument();
    });

    it('applies info color for good retention (60-80%)', () => {
      const { container } = render(<CohortChart {...defaultProps} />);

      expect(container.querySelector('.bg-theme-info')).toBeInTheDocument();
    });

    it('applies warning color for fair retention (40-60%)', () => {
      const { container } = render(<CohortChart {...defaultProps} />);

      // 55% retention should show warning color
      expect(container.querySelector('.bg-theme-warning')).toBeInTheDocument();
    });
  });

  describe('missing data handling', () => {
    it('shows dash for missing retention data', () => {
      render(<CohortChart {...defaultProps} />);

      // Mar 2024 only has 4 months of data, so M4+ should show dash
      expect(screen.getAllByText('-').length).toBeGreaterThan(0);
    });
  });

  describe('tooltip information', () => {
    it('cells have title attribute with details', () => {
      const { container } = render(<CohortChart {...defaultProps} />);

      // Retention cells should have title showing percentage and customer count
      const retentionCells = container.querySelectorAll('[title*="customers"]');
      expect(retentionCells.length).toBeGreaterThan(0);
    });
  });

  describe('styling', () => {
    it('has card styling', () => {
      const { container } = render(<CohortChart {...defaultProps} />);

      expect(container.querySelector('.card-theme')).toBeInTheDocument();
    });

    it('has rounded corners', () => {
      const { container } = render(<CohortChart {...defaultProps} />);

      expect(container.querySelector('.rounded-lg')).toBeInTheDocument();
    });

    it('has shadow styling', () => {
      const { container } = render(<CohortChart {...defaultProps} />);

      expect(container.querySelector('.shadow-sm')).toBeInTheDocument();
    });
  });

  describe('responsive design', () => {
    it('has responsive grid for summary', () => {
      const { container } = render(<CohortChart {...defaultProps} summary={mockSummary} />);

      expect(container.querySelector('.md\\:grid-cols-3')).toBeInTheDocument();
    });

    it('has responsive grid for insights', () => {
      const { container } = render(<CohortChart {...defaultProps} />);

      expect(container.querySelector('.lg\\:grid-cols-3')).toBeInTheDocument();
    });

    it('table has horizontal scroll', () => {
      const { container } = render(<CohortChart {...defaultProps} />);

      expect(container.querySelector('.overflow-x-auto')).toBeInTheDocument();
    });
  });
});
