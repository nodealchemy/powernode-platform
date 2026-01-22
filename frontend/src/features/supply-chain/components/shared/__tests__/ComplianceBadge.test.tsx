import { render, screen } from '@testing-library/react';
import { ComplianceBadge } from '../ComplianceBadge';
import { CheckCircle, XCircle, HelpCircle } from 'lucide-react';

jest.mock('lucide-react', () => ({
  CheckCircle: ({ className }: { className?: string }) => (
    <span data-testid="check-circle" className={className} />
  ),
  XCircle: ({ className }: { className?: string }) => (
    <span data-testid="x-circle" className={className} />
  ),
  HelpCircle: ({ className }: { className?: string }) => (
    <span data-testid="help-circle" className={className} />
  ),
}));

describe('ComplianceBadge', () => {
  describe('rendering compliance statuses', () => {
    it('renders compliant status with correct label', () => {
      render(<ComplianceBadge status="compliant" />);
      expect(screen.getByText('Compliant')).toBeInTheDocument();
    });

    it('renders non_compliant status with correct label', () => {
      render(<ComplianceBadge status="non_compliant" />);
      expect(screen.getByText('Non-Compliant')).toBeInTheDocument();
    });

    it('renders unknown status with correct label', () => {
      render(<ComplianceBadge status="unknown" />);
      expect(screen.getByText('Unknown')).toBeInTheDocument();
    });

    it('renders pending status with correct label', () => {
      render(<ComplianceBadge status="pending" />);
      expect(screen.getByText('Pending')).toBeInTheDocument();
    });
  });

  describe('default labels', () => {
    it('displays default label for compliant', () => {
      render(<ComplianceBadge status="compliant" />);
      expect(screen.getByText('Compliant')).toBeInTheDocument();
    });

    it('displays default label for non_compliant', () => {
      render(<ComplianceBadge status="non_compliant" />);
      expect(screen.getByText('Non-Compliant')).toBeInTheDocument();
    });

    it('displays default label for unknown', () => {
      render(<ComplianceBadge status="unknown" />);
      expect(screen.getByText('Unknown')).toBeInTheDocument();
    });

    it('displays default label for pending', () => {
      render(<ComplianceBadge status="pending" />);
      expect(screen.getByText('Pending')).toBeInTheDocument();
    });
  });

  describe('custom labels', () => {
    it('uses custom label when provided', () => {
      render(<ComplianceBadge status="compliant" label="Approved" />);
      expect(screen.getByText('Approved')).toBeInTheDocument();
      expect(screen.queryByText('Compliant')).not.toBeInTheDocument();
    });

    it('uses custom label for non_compliant', () => {
      render(<ComplianceBadge status="non_compliant" label="Violation" />);
      expect(screen.getByText('Violation')).toBeInTheDocument();
      expect(screen.queryByText('Non-Compliant')).not.toBeInTheDocument();
    });

    it('uses custom label for unknown', () => {
      render(<ComplianceBadge status="unknown" label="Unchecked" />);
      expect(screen.getByText('Unchecked')).toBeInTheDocument();
      expect(screen.queryByText('Unknown')).not.toBeInTheDocument();
    });

    it('uses custom label for pending', () => {
      render(<ComplianceBadge status="pending" label="In Review" />);
      expect(screen.getByText('In Review')).toBeInTheDocument();
      expect(screen.queryByText('Pending')).not.toBeInTheDocument();
    });

    it('falls back to default label when empty string provided', () => {
      render(<ComplianceBadge status="compliant" label="" />);
      expect(screen.getByText('Compliant')).toBeInTheDocument();
    });
  });

  describe('icon rendering', () => {
    it('renders CheckCircle icon for compliant status', () => {
      render(<ComplianceBadge status="compliant" />);
      expect(screen.getByTestId('check-circle')).toBeInTheDocument();
    });

    it('renders XCircle icon for non_compliant status', () => {
      render(<ComplianceBadge status="non_compliant" />);
      expect(screen.getByTestId('x-circle')).toBeInTheDocument();
    });

    it('renders HelpCircle icon for unknown status', () => {
      render(<ComplianceBadge status="unknown" />);
      expect(screen.getByTestId('help-circle')).toBeInTheDocument();
    });

    it('renders HelpCircle icon for pending status', () => {
      render(<ComplianceBadge status="pending" />);
      expect(screen.getByTestId('help-circle')).toBeInTheDocument();
    });
  });

  describe('color classes by status', () => {
    it('applies success colors for compliant status', () => {
      const { container } = render(<ComplianceBadge status="compliant" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('bg-theme-success/10');
      expect(badge).toHaveClass('text-theme-success');
    });

    it('applies error colors for non_compliant status', () => {
      const { container } = render(<ComplianceBadge status="non_compliant" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('bg-theme-error/10');
      expect(badge).toHaveClass('text-theme-error');
    });

    it('applies muted colors for unknown status', () => {
      const { container } = render(<ComplianceBadge status="unknown" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('bg-theme-muted/10');
      expect(badge).toHaveClass('text-theme-muted');
    });

    it('applies info colors for pending status', () => {
      const { container } = render(<ComplianceBadge status="pending" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('bg-theme-info/10');
      expect(badge).toHaveClass('text-theme-info');
    });
  });

  describe('size prop', () => {
    it('applies medium size classes by default', () => {
      const { container } = render(<ComplianceBadge status="compliant" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('px-2');
      expect(badge).toHaveClass('py-1');
      expect(badge).toHaveClass('text-xs');
    });

    it('applies small size classes when size is sm', () => {
      const { container } = render(<ComplianceBadge status="compliant" size="sm" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('px-1.5');
      expect(badge).toHaveClass('py-0.5');
      expect(badge).toHaveClass('text-xs');
    });

    it('applies medium size classes when size is md', () => {
      const { container } = render(<ComplianceBadge status="compliant" size="md" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('px-2');
      expect(badge).toHaveClass('py-1');
      expect(badge).toHaveClass('text-xs');
    });
  });

  describe('icon sizes', () => {
    it('applies small icon size for sm badge', () => {
      render(<ComplianceBadge status="compliant" size="sm" />);
      const icon = screen.getByTestId('check-circle');
      expect(icon).toHaveClass('w-3');
      expect(icon).toHaveClass('h-3');
    });

    it('applies medium icon size for md badge', () => {
      render(<ComplianceBadge status="compliant" size="md" />);
      const icon = screen.getByTestId('check-circle');
      expect(icon).toHaveClass('w-3.5');
      expect(icon).toHaveClass('h-3.5');
    });

    it('applies small icon size by default', () => {
      render(<ComplianceBadge status="compliant" />);
      const icon = screen.getByTestId('check-circle');
      expect(icon).toHaveClass('w-3.5');
      expect(icon).toHaveClass('h-3.5');
    });
  });

  describe('semantic structure', () => {
    it('has proper badge styling', () => {
      const { container } = render(<ComplianceBadge status="compliant" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('inline-flex');
      expect(badge).toHaveClass('items-center');
      expect(badge).toHaveClass('gap-1');
      expect(badge).toHaveClass('rounded-full');
      expect(badge).toHaveClass('font-medium');
    });

    it('maintains consistent base structure for all statuses', () => {
      const statuses: Array<'compliant' | 'non_compliant' | 'unknown' | 'pending'> = [
        'compliant',
        'non_compliant',
        'unknown',
        'pending',
      ];

      statuses.forEach((status) => {
        const { container } = render(<ComplianceBadge status={status} />);
        const badge = container.querySelector('span');
        expect(badge).toHaveClass('inline-flex');
        expect(badge).toHaveClass('items-center');
        expect(badge).toHaveClass('gap-1');
        expect(badge).toHaveClass('rounded-full');
        expect(badge).toHaveClass('font-medium');
      });
    });
  });

  describe('combinations', () => {
    it('renders small compliant badge with custom label', () => {
      const { container } = render(<ComplianceBadge status="compliant" size="sm" label="Approved" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('px-1.5');
      expect(badge).toHaveClass('py-0.5');
      expect(badge).toHaveClass('bg-theme-success/10');
    });

    it('renders medium non-compliant badge with custom label', () => {
      const { container } = render(<ComplianceBadge status="non_compliant" size="md" label="Failed" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('px-2');
      expect(badge).toHaveClass('py-1');
      expect(badge).toHaveClass('bg-theme-error/10');
    });

    it('renders small pending badge with default label', () => {
      render(<ComplianceBadge status="pending" size="sm" />);
      expect(screen.getByText('Pending')).toBeInTheDocument();
      expect(screen.getByTestId('help-circle')).toHaveClass('w-3');
      expect(screen.getByTestId('help-circle')).toHaveClass('h-3');
    });
  });

  describe('label and icon alignment', () => {
    it('renders icon before label', () => {
      const { container } = render(<ComplianceBadge status="compliant" />);
      const badge = container.querySelector('span');
      const children = badge?.childNodes;
      expect(children?.[0]).toContainElement(screen.getByTestId('check-circle'));
    });

    it('maintains gap between icon and label', () => {
      const { container } = render(<ComplianceBadge status="compliant" />);
      const badge = container.querySelector('span');
      expect(badge).toHaveClass('gap-1');
    });
  });

  describe('status transitions', () => {
    it('transitions from compliant to non_compliant', () => {
      const { rerender } = render(<ComplianceBadge status="compliant" />);
      expect(screen.getByText('Compliant')).toBeInTheDocument();
      expect(screen.getByTestId('check-circle')).toBeInTheDocument();

      rerender(<ComplianceBadge status="non_compliant" />);
      expect(screen.getByText('Non-Compliant')).toBeInTheDocument();
      expect(screen.getByTestId('x-circle')).toBeInTheDocument();
    });

    it('transitions from pending to compliant', () => {
      const { rerender } = render(<ComplianceBadge status="pending" />);
      expect(screen.getByText('Pending')).toBeInTheDocument();
      expect(screen.getByTestId('help-circle')).toBeInTheDocument();

      rerender(<ComplianceBadge status="compliant" />);
      expect(screen.getByText('Compliant')).toBeInTheDocument();
      expect(screen.getByTestId('check-circle')).toBeInTheDocument();
    });
  });
});
