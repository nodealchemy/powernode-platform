import { render, screen } from '@testing-library/react';
import { AuditLogMetrics } from './AuditLogMetrics';
import { Activity } from 'lucide-react';

describe('AuditLogMetrics', () => {
  const defaultProps = {
    title: 'Total Events',
    value: 1234,
    icon: <Activity className="w-4 h-4" data-testid="icon" />,
    color: 'blue' as const
  };

  describe('basic display', () => {
    it('shows title', () => {
      render(<AuditLogMetrics {...defaultProps} />);

      expect(screen.getByText('Total Events')).toBeInTheDocument();
    });

    it('shows value', () => {
      render(<AuditLogMetrics {...defaultProps} />);

      expect(screen.getByText('1,234')).toBeInTheDocument();
    });

    it('shows icon', () => {
      render(<AuditLogMetrics {...defaultProps} />);

      expect(screen.getByTestId('icon')).toBeInTheDocument();
    });

    it('formats large numbers with commas', () => {
      render(<AuditLogMetrics {...defaultProps} value={1000000} />);

      expect(screen.getByText('1,000,000')).toBeInTheDocument();
    });
  });

  describe('loading state', () => {
    it('shows loading skeleton when loading', () => {
      const { container } = render(<AuditLogMetrics {...defaultProps} loading={true} />);

      expect(container.querySelector('.animate-pulse')).toBeInTheDocument();
    });

    it('hides value when loading', () => {
      render(<AuditLogMetrics {...defaultProps} loading={true} />);

      expect(screen.queryByText('1,234')).not.toBeInTheDocument();
    });

    it('hides title when loading', () => {
      render(<AuditLogMetrics {...defaultProps} loading={true} />);

      expect(screen.queryByText('Total Events')).not.toBeInTheDocument();
    });
  });

  describe('trend display', () => {
    it('shows positive trend text', () => {
      render(<AuditLogMetrics {...defaultProps} trend="+12% from last week" />);

      expect(screen.getByText('+12% from last week')).toBeInTheDocument();
    });

    it('shows negative trend text', () => {
      render(<AuditLogMetrics {...defaultProps} trend="-5% from last week" />);

      expect(screen.getByText('-5% from last week')).toBeInTheDocument();
    });

    it('shows neutral trend text', () => {
      render(<AuditLogMetrics {...defaultProps} trend="0% change" />);

      expect(screen.getByText('0% change')).toBeInTheDocument();
    });

    it('hides trend when not provided', () => {
      render(<AuditLogMetrics {...defaultProps} />);

      // No trend text should be present
      expect(screen.queryByText(/from last/)).not.toBeInTheDocument();
    });
  });

  describe('trend icons', () => {
    it('shows TrendingUp icon for positive trend', () => {
      const { container } = render(<AuditLogMetrics {...defaultProps} trend="+12%" />);

      const trendingUp = container.querySelector('.lucide-trending-up');
      expect(trendingUp).toBeInTheDocument();
    });

    it('shows TrendingDown icon for negative trend', () => {
      const { container } = render(<AuditLogMetrics {...defaultProps} trend="-5%" />);

      const trendingDown = container.querySelector('.lucide-trending-down');
      expect(trendingDown).toBeInTheDocument();
    });

    it('shows Minus icon for neutral trend', () => {
      const { container } = render(<AuditLogMetrics {...defaultProps} trend="0%" />);

      const minus = container.querySelector('.lucide-minus');
      expect(minus).toBeInTheDocument();
    });
  });

  describe('trend color logic', () => {
    it('shows success color for positive trend on non-red cards', () => {
      const { container } = render(
        <AuditLogMetrics {...defaultProps} color="blue" trend="+12%" />
      );

      const trendElement = container.querySelector('.text-theme-success');
      expect(trendElement).toBeInTheDocument();
    });

    it('shows error color for positive trend on red cards', () => {
      const { container } = render(
        <AuditLogMetrics {...defaultProps} color="red" trend="+12%" />
      );

      const trendElement = container.querySelector('.text-theme-error');
      expect(trendElement).toBeInTheDocument();
    });

    it('shows error color for negative trend on non-red cards', () => {
      const { container } = render(
        <AuditLogMetrics {...defaultProps} color="blue" trend="-5%" />
      );

      const trendElement = container.querySelector('.text-theme-error');
      expect(trendElement).toBeInTheDocument();
    });

    it('shows success color for negative trend on red cards', () => {
      const { container } = render(
        <AuditLogMetrics {...defaultProps} color="red" trend="-5%" />
      );

      const trendElement = container.querySelector('.text-theme-success');
      expect(trendElement).toBeInTheDocument();
    });
  });

  describe('color variants', () => {
    it('applies blue color classes', () => {
      const { container } = render(<AuditLogMetrics {...defaultProps} color="blue" />);

      expect(container.querySelector('.text-theme-link')).toBeInTheDocument();
      expect(container.querySelector('.bg-theme-link-background')).toBeInTheDocument();
    });

    it('applies green color classes', () => {
      const { container } = render(<AuditLogMetrics {...defaultProps} color="green" />);

      expect(container.querySelector('.text-theme-success')).toBeInTheDocument();
      expect(container.querySelector('.bg-theme-success-background')).toBeInTheDocument();
    });

    it('applies red color classes', () => {
      const { container } = render(<AuditLogMetrics {...defaultProps} color="red" />);

      expect(container.querySelector('.text-theme-error')).toBeInTheDocument();
      expect(container.querySelector('.bg-theme-error-background')).toBeInTheDocument();
    });

    it('applies yellow color classes', () => {
      const { container } = render(<AuditLogMetrics {...defaultProps} color="yellow" />);

      expect(container.querySelector('.text-theme-warning')).toBeInTheDocument();
      expect(container.querySelector('.bg-theme-warning-background')).toBeInTheDocument();
    });

    it('applies purple color classes', () => {
      const { container } = render(<AuditLogMetrics {...defaultProps} color="purple" />);

      expect(container.querySelector('.text-theme-info')).toBeInTheDocument();
      expect(container.querySelector('.bg-theme-info-background')).toBeInTheDocument();
    });
  });

  describe('card styling', () => {
    it('has hover shadow transition', () => {
      const { container } = render(<AuditLogMetrics {...defaultProps} />);

      const card = container.firstChild as HTMLElement;
      expect(card).toHaveClass('hover:shadow-md');
      expect(card).toHaveClass('transition-shadow');
    });

    it('has border and rounded corners', () => {
      const { container } = render(<AuditLogMetrics {...defaultProps} />);

      const card = container.firstChild as HTMLElement;
      expect(card).toHaveClass('border');
      expect(card).toHaveClass('rounded-lg');
    });
  });

  describe('different metric examples', () => {
    it('renders error events metric', () => {
      render(
        <AuditLogMetrics
          title="Error Events"
          value={42}
          icon={<Activity data-testid="error-icon" />}
          color="red"
          trend="+8%"
        />
      );

      expect(screen.getByText('Error Events')).toBeInTheDocument();
      expect(screen.getByText('42')).toBeInTheDocument();
    });

    it('renders success events metric', () => {
      render(
        <AuditLogMetrics
          title="Successful Logins"
          value={9876}
          icon={<Activity data-testid="success-icon" />}
          color="green"
          trend="-2%"
        />
      );

      expect(screen.getByText('Successful Logins')).toBeInTheDocument();
      expect(screen.getByText('9,876')).toBeInTheDocument();
    });
  });
});
