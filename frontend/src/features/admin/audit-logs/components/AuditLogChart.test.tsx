import { render, screen } from '@testing-library/react';
import { AuditLogChart, TimeSeriesData, BarData, PieData } from './AuditLogChart';

describe('AuditLogChart', () => {
  const defaultTimeRange = {
    label: 'Last 7 days',
    value: '7d',
    days: 7
  };

  const mockLineData: TimeSeriesData[] = [
    { x: '2025-01-01', y: 100 },
    { x: '2025-01-02', y: 150 },
    { x: '2025-01-03', y: 120 },
    { x: '2025-01-04', y: 180 },
    { x: '2025-01-05', y: 90 }
  ];

  const mockBarData: BarData[] = [
    { label: 'Create', value: 45 },
    { label: 'Update', value: 30 },
    { label: 'Delete', value: 15 },
    { label: 'Login', value: 50 }
  ];

  const mockPieData: PieData[] = [
    { label: 'API Requests', value: 40 },
    { label: 'User Actions', value: 30 },
    { label: 'System Events', value: 20 },
    { label: 'Admin Actions', value: 10 }
  ];

  const defaultProps = {
    title: 'Security Events',
    type: 'line' as const,
    data: mockLineData,
    timeRange: defaultTimeRange
  };

  describe('basic display', () => {
    it('shows chart title', () => {
      render(<AuditLogChart {...defaultProps} />);

      expect(screen.getByText('Security Events')).toBeInTheDocument();
    });

    it('shows time range label', () => {
      render(<AuditLogChart {...defaultProps} />);

      expect(screen.getByText('Last 7 days')).toBeInTheDocument();
    });

    it('hides time range label when not provided', () => {
      render(<AuditLogChart title="Test" type="line" data={mockLineData} />);

      expect(screen.queryByText('Last 7 days')).not.toBeInTheDocument();
    });

    it('shows Total Events summary', () => {
      render(<AuditLogChart {...defaultProps} />);

      expect(screen.getByText('Total Events')).toBeInTheDocument();
    });

    it('calculates total from time series data', () => {
      render(<AuditLogChart {...defaultProps} />);

      // Sum of mockLineData y values: 100 + 150 + 120 + 180 + 90 = 640
      expect(screen.getByText('640')).toBeInTheDocument();
    });

    it('calculates total from bar data', () => {
      render(<AuditLogChart title="Test" type="bar" data={mockBarData} />);

      // Sum of mockBarData values: 45 + 30 + 15 + 50 = 140
      expect(screen.getByText('140')).toBeInTheDocument();
    });

    it('calculates total from pie data', () => {
      render(<AuditLogChart title="Test" type="pie" data={mockPieData} />);

      // Sum of mockPieData values: 40 + 30 + 20 + 10 = 100
      expect(screen.getByText('100')).toBeInTheDocument();
    });
  });

  describe('loading state', () => {
    it('shows loading skeleton when loading', () => {
      const { container } = render(<AuditLogChart {...defaultProps} loading={true} />);

      expect(container.querySelector('.animate-pulse')).toBeInTheDocument();
    });

    it('hides chart content when loading', () => {
      render(<AuditLogChart {...defaultProps} loading={true} />);

      expect(screen.queryByText('Security Events')).not.toBeInTheDocument();
    });
  });

  describe('empty state', () => {
    it('shows no data message when data is empty', () => {
      render(<AuditLogChart title="Test" type="line" data={[]} />);

      expect(screen.getByText('No data available')).toBeInTheDocument();
    });

    it('shows zero total when data is empty', () => {
      render(<AuditLogChart title="Test" type="line" data={[]} />);

      expect(screen.getByText('0')).toBeInTheDocument();
    });
  });

  describe('line chart', () => {
    it('renders SVG for line chart', () => {
      const { container } = render(<AuditLogChart {...defaultProps} type="line" />);

      expect(container.querySelector('svg')).toBeInTheDocument();
    });

    it('renders polyline for line chart', () => {
      const { container } = render(<AuditLogChart {...defaultProps} type="line" />);

      expect(container.querySelector('polyline')).toBeInTheDocument();
    });

    it('renders circle points for line chart', () => {
      const { container } = render(<AuditLogChart {...defaultProps} type="line" />);

      expect(container.querySelectorAll('circle').length).toBe(mockLineData.length);
    });

    it('renders grid lines for line chart', () => {
      const { container } = render(<AuditLogChart {...defaultProps} type="line" />);

      expect(container.querySelectorAll('line').length).toBeGreaterThan(0);
    });

    it('renders polygon area fill for line chart', () => {
      const { container } = render(<AuditLogChart {...defaultProps} type="line" />);

      expect(container.querySelector('polygon')).toBeInTheDocument();
    });
  });

  describe('bar chart', () => {
    it('renders bar chart with bars', () => {
      const { container } = render(<AuditLogChart title="Test" type="bar" data={mockBarData} />);

      expect(container.querySelector('.rounded-t')).toBeInTheDocument();
    });

    it('shows bar values', () => {
      render(<AuditLogChart title="Test" type="bar" data={mockBarData} />);

      expect(screen.getByText('45')).toBeInTheDocument();
      expect(screen.getByText('30')).toBeInTheDocument();
      expect(screen.getByText('15')).toBeInTheDocument();
      expect(screen.getByText('50')).toBeInTheDocument();
    });

    it('shows truncated bar labels', () => {
      render(<AuditLogChart title="Test" type="bar" data={mockBarData} />);

      expect(screen.getByText('Cre')).toBeInTheDocument(); // Create
      expect(screen.getByText('Upd')).toBeInTheDocument(); // Update
      expect(screen.getByText('Del')).toBeInTheDocument(); // Delete
      expect(screen.getByText('Log')).toBeInTheDocument(); // Login
    });
  });

  describe('pie chart', () => {
    it('renders SVG for pie chart', () => {
      const { container } = render(<AuditLogChart title="Test" type="pie" data={mockPieData} />);

      expect(container.querySelector('svg')).toBeInTheDocument();
    });

    it('renders path elements for pie segments', () => {
      const { container } = render(<AuditLogChart title="Test" type="pie" data={mockPieData} />);

      // At least mockPieData.length paths (may have more from icons)
      expect(container.querySelectorAll('path').length).toBeGreaterThanOrEqual(mockPieData.length);
    });

    it('shows pie chart legend', () => {
      render(<AuditLogChart title="Test" type="pie" data={mockPieData} />);

      expect(screen.getByText('API Requests')).toBeInTheDocument();
      expect(screen.getByText('User Actions')).toBeInTheDocument();
      expect(screen.getByText('System Events')).toBeInTheDocument();
      expect(screen.getByText('Admin Actions')).toBeInTheDocument();
    });

    it('shows legend values in parentheses', () => {
      render(<AuditLogChart title="Test" type="pie" data={mockPieData} />);

      expect(screen.getByText('(40)')).toBeInTheDocument();
      expect(screen.getByText('(30)')).toBeInTheDocument();
      expect(screen.getByText('(20)')).toBeInTheDocument();
      expect(screen.getByText('(10)')).toBeInTheDocument();
    });
  });

  describe('doughnut chart', () => {
    it('renders SVG for doughnut chart', () => {
      const { container } = render(<AuditLogChart title="Test" type="doughnut" data={mockPieData} />);

      expect(container.querySelector('svg')).toBeInTheDocument();
    });

    it('renders path elements for doughnut segments', () => {
      const { container } = render(<AuditLogChart title="Test" type="doughnut" data={mockPieData} />);

      // At least mockPieData.length paths (may have more from icons)
      expect(container.querySelectorAll('path').length).toBeGreaterThanOrEqual(mockPieData.length);
    });
  });

  describe('custom height', () => {
    it('applies default height of 300', () => {
      const { container } = render(<AuditLogChart {...defaultProps} />);

      const chartContainer = container.querySelector('[style*="height"]');
      expect(chartContainer).toHaveStyle({ height: '300px' });
    });

    it('applies custom height', () => {
      const { container } = render(<AuditLogChart {...defaultProps} height={400} />);

      const chartContainer = container.querySelector('[style*="height"]');
      expect(chartContainer).toHaveStyle({ height: '400px' });
    });
  });

  describe('chart icons', () => {
    it('shows TrendingUp icon for line chart', () => {
      const { container } = render(<AuditLogChart {...defaultProps} type="line" />);

      expect(container.querySelector('.lucide-trending-up')).toBeInTheDocument();
    });

    it('shows icon for bar chart', () => {
      const { container } = render(<AuditLogChart title="Test" type="bar" data={mockBarData} />);

      const svg = container.querySelector('svg[class*="lucide"]');
      expect(svg).toBeInTheDocument();
    });

    it('shows icon for pie chart', () => {
      const { container } = render(<AuditLogChart title="Test" type="pie" data={mockPieData} />);

      const svgs = container.querySelectorAll('svg[class*="lucide"]');
      expect(svgs.length).toBeGreaterThan(0);
    });
  });

  describe('styling', () => {
    it('has theme background', () => {
      const { container } = render(<AuditLogChart {...defaultProps} />);

      expect(container.querySelector('.bg-theme-background')).toBeInTheDocument();
    });

    it('has border styling', () => {
      const { container } = render(<AuditLogChart {...defaultProps} />);

      expect(container.querySelector('.border-theme')).toBeInTheDocument();
    });

    it('has rounded corners', () => {
      const { container } = render(<AuditLogChart {...defaultProps} />);

      expect(container.querySelector('.rounded-lg')).toBeInTheDocument();
    });
  });

  describe('data variations', () => {
    it('handles single data point', () => {
      render(<AuditLogChart title="Test" type="line" data={[{ x: '2025-01-01', y: 100 }]} />);

      expect(screen.getByText('100')).toBeInTheDocument();
    });

    it('handles large values', () => {
      const largeData: TimeSeriesData[] = [
        { x: '2025-01-01', y: 1000000 },
        { x: '2025-01-02', y: 2000000 }
      ];
      render(<AuditLogChart title="Test" type="line" data={largeData} />);

      expect(screen.getByText('3,000,000')).toBeInTheDocument();
    });

    it('handles zero values', () => {
      const zeroData: BarData[] = [
        { label: 'Test', value: 0 }
      ];
      render(<AuditLogChart title="Test" type="bar" data={zeroData} />);

      // Zero appears multiple times (in bar label and total events)
      const zeroElements = screen.getAllByText('0');
      expect(zeroElements.length).toBeGreaterThan(0);
    });
  });
});
