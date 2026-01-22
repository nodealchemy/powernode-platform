import { render, screen } from '@testing-library/react';
import { StatusBadge } from '../StatusBadge';

type StatusType =
  | 'verified'
  | 'unverified'
  | 'quarantined'
  | 'active'
  | 'inactive'
  | 'pending'
  | 'error'
  | 'draft'
  | 'completed'
  | 'failed'
  | 'expired'
  | 'running'
  | 'in_progress'
  | 'suspended'
  | 'queued';

describe('StatusBadge', () => {
  const statuses: Array<{ status: StatusType; label: string; bg: string; text: string }> = [
    { status: 'verified', label: 'Verified', bg: 'bg-theme-success/10', text: 'text-theme-success' },
    { status: 'unverified', label: 'Unverified', bg: 'bg-theme-muted/10', text: 'text-theme-muted' },
    { status: 'quarantined', label: 'Quarantined', bg: 'bg-theme-error/10', text: 'text-theme-error' },
    { status: 'active', label: 'Active', bg: 'bg-theme-success/10', text: 'text-theme-success' },
    { status: 'inactive', label: 'Inactive', bg: 'bg-theme-muted/10', text: 'text-theme-muted' },
    { status: 'pending', label: 'Pending', bg: 'bg-theme-warning/10', text: 'text-theme-warning' },
    { status: 'error', label: 'Error', bg: 'bg-theme-error/10', text: 'text-theme-error' },
    { status: 'draft', label: 'Draft', bg: 'bg-theme-muted/10', text: 'text-theme-muted' },
    { status: 'completed', label: 'Completed', bg: 'bg-theme-success/10', text: 'text-theme-success' },
    { status: 'failed', label: 'Failed', bg: 'bg-theme-error/10', text: 'text-theme-error' },
    { status: 'expired', label: 'Expired', bg: 'bg-theme-warning/10', text: 'text-theme-warning' },
    { status: 'running', label: 'Running', bg: 'bg-theme-info/10', text: 'text-theme-info' },
    { status: 'in_progress', label: 'In Progress', bg: 'bg-theme-info/10', text: 'text-theme-info' },
    { status: 'suspended', label: 'Suspended', bg: 'bg-theme-error/10', text: 'text-theme-error' },
    { status: 'queued', label: 'Queued', bg: 'bg-theme-muted/10', text: 'text-theme-muted' },
  ];

  describe('rendering all status types', () => {
    statuses.forEach(({ status, label, bg, text }) => {
      it(`renders ${status} status with correct label`, () => {
        render(<StatusBadge status={status} />);
        expect(screen.getByText(label)).toBeInTheDocument();
      });

      it(`renders ${status} status with correct styles`, () => {
        const { container } = render(<StatusBadge status={status} />);
        const badge = container.querySelector('span');
        expect(badge).toHaveClass(bg);
        expect(badge).toHaveClass(text);
      });
    });
  });

  describe('status labels', () => {
    it('displays correct label for each status', () => {
      statuses.forEach(({ status, label }) => {
        const { unmount } = render(<StatusBadge status={status} />);
        expect(screen.getByText(label)).toBeInTheDocument();
        unmount();
      });
    });

    it('handles status with underscores in label', () => {
      render(<StatusBadge status="in_progress" />);
      expect(screen.getByText('In Progress')).toBeInTheDocument();
    });
  });

  describe('color classes', () => {
    it('applies success colors for verified status', () => {
      const { container } = render(<StatusBadge status="verified" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('bg-theme-success/10');
      expect(badge).toHaveClass('text-theme-success');
    });

    it('applies error colors for quarantined status', () => {
      const { container } = render(<StatusBadge status="quarantined" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('bg-theme-error/10');
      expect(badge).toHaveClass('text-theme-error');
    });

    it('applies warning colors for pending status', () => {
      const { container } = render(<StatusBadge status="pending" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('bg-theme-warning/10');
      expect(badge).toHaveClass('text-theme-warning');
    });

    it('applies info colors for running status', () => {
      const { container } = render(<StatusBadge status="running" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('bg-theme-info/10');
      expect(badge).toHaveClass('text-theme-info');
    });

    it('applies muted colors for unverified status', () => {
      const { container } = render(<StatusBadge status="unverified" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('bg-theme-muted/10');
      expect(badge).toHaveClass('text-theme-muted');
    });
  });

  describe('size prop', () => {
    it('applies small size classes by default', () => {
      const { container } = render(<StatusBadge status="verified" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('px-2');
      expect(badge).toHaveClass('py-1');
      expect(badge).toHaveClass('text-xs');
    });

    it('applies small size classes when explicitly set', () => {
      const { container } = render(<StatusBadge status="verified" size="sm" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('px-1.5');
      expect(badge).toHaveClass('py-0.5');
      expect(badge).toHaveClass('text-xs');
    });

    it('applies medium size classes', () => {
      const { container } = render(<StatusBadge status="verified" size="md" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('px-2');
      expect(badge).toHaveClass('py-1');
      expect(badge).toHaveClass('text-xs');
    });

    it('applies correct size for each status', () => {
      statuses.forEach(({ status }) => {
        const { container } = render(<StatusBadge status={status} size="sm" />);
        const badge = container.querySelector('span');
        expect(badge).toHaveClass('px-1.5');
        expect(badge).toHaveClass('py-0.5');
      });
    });
  });

  describe('semantic structure', () => {
    it('has proper badge styling classes', () => {
      const { container } = render(<StatusBadge status="verified" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('inline-flex');
      expect(badge).toHaveClass('items-center');
      expect(badge).toHaveClass('rounded-full');
      expect(badge).toHaveClass('font-medium');
    });

    it('renders as inline-flex container', () => {
      const { container } = render(<StatusBadge status="active" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('inline-flex');
    });
  });

  describe('error handling', () => {
    it('falls back to pending for unknown status', () => {
      const { container } = render(<StatusBadge status={'unknown' as StatusType} />);
      expect(screen.getByText('Pending')).toBeInTheDocument();
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('bg-theme-warning/10');
      expect(badge).toHaveClass('text-theme-warning');
    });
  });

  describe('combinations', () => {
    it('renders small completed badge', () => {
      const { container } = render(<StatusBadge status="completed" size="sm" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('px-1.5');
      expect(badge).toHaveClass('py-0.5');
      expect(badge).toHaveClass('bg-theme-success/10');
    });

    it('renders medium failed badge', () => {
      const { container } = render(<StatusBadge status="failed" size="md" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('px-2');
      expect(badge).toHaveClass('py-1');
      expect(badge).toHaveClass('bg-theme-error/10');
    });

    it('renders different sizes for different statuses', () => {
      const { rerender, container } = render(<StatusBadge status="verified" size="sm" />);
      expect(container.querySelector('span')).toHaveClass('px-1.5');

      rerender(<StatusBadge status="verified" size="md" />);
      expect(container.querySelector('span')).toHaveClass('px-2');
    });
  });

  describe('visual consistency', () => {
    it('all badges have consistent base structure', () => {
      statuses.slice(0, 5).forEach(({ status }) => {
        const { container } = render(<StatusBadge status={status} />);
        const badge = container.querySelector('span');
        expect(badge).toHaveClass('inline-flex');
        expect(badge).toHaveClass('items-center');
        expect(badge).toHaveClass('rounded-full');
        expect(badge).toHaveClass('font-medium');
      });
    });

    it('all badges use text-xs font size', () => {
      statuses.slice(0, 5).forEach(({ status }) => {
        const { container } = render(<StatusBadge status={status} />);
        const badge = container.querySelector('span');
        expect(badge).toHaveClass('text-xs');
      });
    });
  });
});
