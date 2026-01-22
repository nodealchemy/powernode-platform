import { render, screen } from '@testing-library/react';
import { SeverityBadge } from '../SeverityBadge';

describe('SeverityBadge', () => {
  describe('rendering', () => {
    it('renders critical severity with correct styles', () => {
      const { container } = render(<SeverityBadge severity="critical" />);
      expect(screen.getByText('Critical')).toBeInTheDocument();
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('bg-theme-error/10');
      expect(badge).toHaveClass('text-theme-error');
    });

    it('renders high severity with correct styles', () => {
      const { container } = render(<SeverityBadge severity="high" />);
      expect(screen.getByText('High')).toBeInTheDocument();
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('bg-theme-warning/10');
      expect(badge).toHaveClass('text-theme-warning');
    });

    it('renders medium severity with correct styles', () => {
      const { container } = render(<SeverityBadge severity="medium" />);
      expect(screen.getByText('Medium')).toBeInTheDocument();
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('bg-theme-info/10');
      expect(badge).toHaveClass('text-theme-info');
    });

    it('renders low severity with correct styles', () => {
      const { container } = render(<SeverityBadge severity="low" />);
      expect(screen.getByText('Low')).toBeInTheDocument();
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('bg-theme-success/10');
      expect(badge).toHaveClass('text-theme-success');
    });

    it('renders severity indicator dot', () => {
      const { container } = render(<SeverityBadge severity="critical" />);
      const dot = container.querySelector('span span');
      expect(dot).toHaveClass('w-1.5');
      expect(dot).toHaveClass('h-1.5');
      expect(dot).toHaveClass('rounded-full');
      expect(dot).toHaveClass('bg-theme-error');
    });

    it('renders dot with correct color for each severity', () => {
      const severities: Array<'critical' | 'high' | 'medium' | 'low'> = [
        'critical',
        'high',
        'medium',
        'low',
      ];
      const expectedColors = [
        'bg-theme-error',
        'bg-theme-warning',
        'bg-theme-info',
        'bg-theme-success',
      ];

      severities.forEach((severity, index) => {
        const { container } = render(<SeverityBadge severity={severity} />);
        const dot = container.querySelector('span span');
        expect(dot).toHaveClass(expectedColors[index]);
      });
    });
  });

  describe('label prop', () => {
    it('displays label by default', () => {
      render(<SeverityBadge severity="critical" />);
      expect(screen.getByText('Critical')).toBeInTheDocument();
    });

    it('displays label when showLabel is true', () => {
      render(<SeverityBadge severity="high" showLabel={true} />);
      expect(screen.getByText('High')).toBeInTheDocument();
    });

    it('hides label when showLabel is false', () => {
      render(<SeverityBadge severity="medium" showLabel={false} />);
      expect(screen.queryByText('Medium')).not.toBeInTheDocument();
    });

    it('still renders dot when label is hidden', () => {
      const { container } = render(<SeverityBadge severity="critical" showLabel={false} />);
      const dot = container.querySelector('span span');
      expect(dot).toBeInTheDocument();
    });

    it('renders all severity labels when shown', () => {
      const labels = [
        { severity: 'critical' as const, label: 'Critical' },
        { severity: 'high' as const, label: 'High' },
        { severity: 'medium' as const, label: 'Medium' },
        { severity: 'low' as const, label: 'Low' },
      ];

      labels.forEach(({ severity, label }) => {
        const { unmount } = render(<SeverityBadge severity={severity} showLabel={true} />);
        expect(screen.getByText(label)).toBeInTheDocument();
        unmount();
      });
    });
  });

  describe('size prop', () => {
    it('applies small size classes', () => {
      const { container } = render(<SeverityBadge severity="critical" size="sm" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('px-1.5');
      expect(badge).toHaveClass('py-0.5');
      expect(badge).toHaveClass('text-xs');
    });

    it('applies medium size classes by default', () => {
      const { container } = render(<SeverityBadge severity="critical" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('px-2');
      expect(badge).toHaveClass('py-1');
      expect(badge).toHaveClass('text-xs');
    });

    it('applies medium size classes when explicitly set', () => {
      const { container } = render(<SeverityBadge severity="critical" size="md" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('px-2');
      expect(badge).toHaveClass('py-1');
      expect(badge).toHaveClass('text-xs');
    });

    it('renders dot with correct size for sm', () => {
      const { container } = render(<SeverityBadge severity="critical" size="sm" />);
      const dot = container.querySelector('span span');
      expect(dot).toHaveClass('w-1.5');
      expect(dot).toHaveClass('h-1.5');
    });

    it('renders dot with correct size for md', () => {
      const { container } = render(<SeverityBadge severity="critical" size="md" />);
      const dot = container.querySelector('span span');
      expect(dot).toHaveClass('w-1.5');
      expect(dot).toHaveClass('h-1.5');
    });
  });

  describe('combination of props', () => {
    it('renders small badge with label', () => {
      const { container } = render(<SeverityBadge severity="critical" size="sm" showLabel={true} />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('px-1.5');
      expect(badge).toHaveClass('py-0.5');
      expect(screen.getByText('Critical')).toBeInTheDocument();
    });

    it('renders medium badge without label', () => {
      const { container } = render(<SeverityBadge severity="high" size="md" showLabel={false} />);
      expect(screen.queryByText('High')).not.toBeInTheDocument();
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('px-2');
      expect(badge).toHaveClass('py-1');
    });

    it('renders small badge without label', () => {
      const { container } = render(<SeverityBadge severity="low" size="sm" showLabel={false} />);
      expect(screen.queryByText('Low')).not.toBeInTheDocument();
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('px-1.5');
      expect(badge).toHaveClass('py-0.5');
    });
  });

  describe('accessibility', () => {
    it('has proper semantic structure', () => {
      const { container } = render(<SeverityBadge severity="critical" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('inline-flex');
      expect(badge).toHaveClass('items-center');
      expect(badge).toHaveClass('gap-1');
      expect(badge).toHaveClass('rounded-full');
      expect(badge).toHaveClass('font-medium');
    });

    it('renders text that conveys severity information', () => {
      render(<SeverityBadge severity="critical" showLabel={true} />);
      expect(screen.getByText('Critical')).toBeInTheDocument();
    });
  });
});
