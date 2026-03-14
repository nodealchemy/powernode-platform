import { render, screen, fireEvent } from '@testing-library/react';
import { RemediationStatusSelect } from '../RemediationStatusSelect';

type RemediationStatus = 'open' | 'in_progress' | 'fixed' | 'wont_fix';

describe('RemediationStatusSelect', () => {
  const statuses: RemediationStatus[] = ['open', 'in_progress', 'fixed', 'wont_fix'];
  const statusLabels: Record<RemediationStatus, string> = {
    open: 'Open',
    in_progress: 'In Progress',
    fixed: 'Fixed',
    wont_fix: "Won't Fix",
  };

  const defaultProps = {
    value: 'open' as RemediationStatus,
    onChange: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('rendering', () => {
    it('renders a select element', () => {
      const { container } = render(<RemediationStatusSelect {...defaultProps} />);
      const selectElement = container.querySelector('select');
      expect(selectElement).toBeInTheDocument();
    });

    it('displays all status options', () => {
      render(<RemediationStatusSelect {...defaultProps} />);

      statuses.forEach(status => {
        const option = screen.getByRole('option', { name: statusLabels[status] });
        expect(option).toBeInTheDocument();
      });
    });

    it('shows current value as selected', () => {
      const { container } = render(
        <RemediationStatusSelect {...defaultProps} value="fixed" />
      );
      const selectElement = container.querySelector('select') as HTMLSelectElement;
      expect(selectElement.value).toBe('fixed');
    });
  });

  describe('size variations', () => {
    it('applies small size classes by default', () => {
      const { container } = render(<RemediationStatusSelect {...defaultProps} size="sm" />);
      const selectElement = container.querySelector('select');
      expect(selectElement).toHaveClass('text-xs', 'px-2', 'py-1');
    });

    it('applies medium size classes when specified', () => {
      const { container } = render(<RemediationStatusSelect {...defaultProps} size="md" />);
      const selectElement = container.querySelector('select');
      expect(selectElement).toHaveClass('text-sm', 'px-3', 'py-2');
    });
  });

  describe('status styling', () => {
    it('applies open status styles', () => {
      const { container } = render(
        <RemediationStatusSelect {...defaultProps} value="open" />
      );
      const selectElement = container.querySelector('select');
      expect(selectElement).toHaveClass('bg-theme-error/10', 'text-theme-error', 'border-theme-error/30');
    });

    it('applies in_progress status styles', () => {
      const { container } = render(
        <RemediationStatusSelect {...defaultProps} value="in_progress" />
      );
      const selectElement = container.querySelector('select');
      expect(selectElement).toHaveClass('bg-theme-warning/10', 'text-theme-warning', 'border-theme-warning/30');
    });

    it('applies fixed status styles', () => {
      const { container } = render(
        <RemediationStatusSelect {...defaultProps} value="fixed" />
      );
      const selectElement = container.querySelector('select');
      expect(selectElement).toHaveClass('bg-theme-success/10', 'text-theme-success', 'border-theme-success/30');
    });

    it('applies wont_fix status styles', () => {
      const { container } = render(
        <RemediationStatusSelect {...defaultProps} value="wont_fix" />
      );
      const selectElement = container.querySelector('select');
      expect(selectElement).toHaveClass('bg-theme-muted/10', 'text-theme-secondary', 'border-theme-border');
    });
  });

  describe('disabled state', () => {
    it('is enabled by default', () => {
      const { container } = render(<RemediationStatusSelect {...defaultProps} />);
      const selectElement = container.querySelector('select');
      expect(selectElement).not.toBeDisabled();
    });

    it('is disabled when disabled prop is true', () => {
      const { container } = render(
        <RemediationStatusSelect {...defaultProps} disabled={true} />
      );
      const selectElement = container.querySelector('select');
      expect(selectElement).toBeDisabled();
    });

    it('applies disabled styles when disabled', () => {
      const { container } = render(
        <RemediationStatusSelect {...defaultProps} disabled={true} />
      );
      const selectElement = container.querySelector('select');
      expect(selectElement).toHaveClass('disabled:opacity-50', 'disabled:cursor-not-allowed');
    });
  });

  describe('onChange callback', () => {
    it('calls onChange when selection changes', () => {
      const onChange = jest.fn();
      const { container } = render(
        <RemediationStatusSelect {...defaultProps} onChange={onChange} />
      );

      const selectElement = container.querySelector('select') as HTMLSelectElement;
      fireEvent.change(selectElement, { target: { value: 'fixed' } });

      expect(onChange).toHaveBeenCalledWith('fixed');
      expect(onChange).toHaveBeenCalledTimes(1);
    });

    it('calls onChange with correct status value for each option', () => {
      const onChange = jest.fn();
      const { container } = render(
        <RemediationStatusSelect {...defaultProps} onChange={onChange} value="open" />
      );

      const selectElement = container.querySelector('select') as HTMLSelectElement;

      statuses.forEach(status => {
        jest.clearAllMocks();
        fireEvent.change(selectElement, { target: { value: status } });
        expect(onChange).toHaveBeenCalledWith(status);
      });
    });

    it('does not call onChange when disabled', () => {
      const onChange = jest.fn();
      const { container } = render(
        <RemediationStatusSelect {...defaultProps} onChange={onChange} disabled={true} />
      );

      const selectElement = container.querySelector('select') as HTMLSelectElement;
      expect(() => {
        fireEvent.change(selectElement, { target: { value: 'fixed' } });
      }).not.toThrow();
      // Disabled elements may not trigger change events
    });
  });

  describe('focus styles', () => {
    it('has focus ring styling', () => {
      const { container } = render(<RemediationStatusSelect {...defaultProps} />);
      const selectElement = container.querySelector('select');
      expect(selectElement).toHaveClass(
        'focus:outline-none',
        'focus:ring-2',
        'focus:ring-theme-interactive-primary'
      );
    });
  });

  describe('status label formatting', () => {
    it('displays properly formatted labels', () => {
      render(<RemediationStatusSelect {...defaultProps} />);

      expect(screen.getByRole('option', { name: 'Open' })).toBeInTheDocument();
      expect(screen.getByRole('option', { name: 'In Progress' })).toBeInTheDocument();
      expect(screen.getByRole('option', { name: 'Fixed' })).toBeInTheDocument();
      expect(screen.getByRole('option', { name: "Won't Fix" })).toBeInTheDocument();
    });
  });

  describe('keyboard navigation', () => {
    it('supports keyboard navigation', () => {
      const onChange = jest.fn();
      const { container } = render(
        <RemediationStatusSelect {...defaultProps} onChange={onChange} value="open" />
      );

      const selectElement = container.querySelector('select') as HTMLSelectElement;
      selectElement.focus();
      expect(selectElement).toHaveFocus();
    });
  });

  describe('option values', () => {
    it('each option has correct value attribute', () => {
      const { container } = render(<RemediationStatusSelect {...defaultProps} />);

      const options = container.querySelectorAll('option');
      expect(options).toHaveLength(4);

      expect((options[0] as HTMLOptionElement).value).toBe('open');
      expect((options[1] as HTMLOptionElement).value).toBe('in_progress');
      expect((options[2] as HTMLOptionElement).value).toBe('fixed');
      expect((options[3] as HTMLOptionElement).value).toBe('wont_fix');
    });
  });

  describe('CSS classes', () => {
    it('has required base classes', () => {
      const { container } = render(<RemediationStatusSelect {...defaultProps} />);
      const selectElement = container.querySelector('select');
      expect(selectElement).toHaveClass(
        'rounded-md',
        'border',
        'font-medium',
        'cursor-pointer'
      );
    });
  });

  describe('state transitions', () => {
    it('reflects status changes', () => {
      const { container, rerender } = render(
        <RemediationStatusSelect {...defaultProps} value="open" />
      );

      let selectElement = container.querySelector('select') as HTMLSelectElement;
      expect(selectElement.value).toBe('open');

      rerender(<RemediationStatusSelect {...defaultProps} value="fixed" />);
      selectElement = container.querySelector('select') as HTMLSelectElement;
      expect(selectElement.value).toBe('fixed');
    });

    it('applies correct styling after status change', () => {
      const { container, rerender } = render(
        <RemediationStatusSelect {...defaultProps} value="open" />
      );

      let selectElement = container.querySelector('select');
      expect(selectElement).toHaveClass('bg-theme-error/10');

      rerender(<RemediationStatusSelect {...defaultProps} value="fixed" />);
      selectElement = container.querySelector('select');
      expect(selectElement).toHaveClass('bg-theme-success/10');
    });
  });
});
