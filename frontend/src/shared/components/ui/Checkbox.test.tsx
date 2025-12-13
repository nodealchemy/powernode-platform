import { render, screen, fireEvent } from '@testing-library/react';
import { Checkbox } from './Checkbox';

describe('Checkbox', () => {
  describe('rendering', () => {
    it('renders checkbox input', () => {
      render(<Checkbox />);

      expect(screen.getByRole('checkbox')).toBeInTheDocument();
    });

    it('renders with label', () => {
      render(<Checkbox label="Accept terms" />);

      expect(screen.getByText('Accept terms')).toBeInTheDocument();
    });

    it('renders with description', () => {
      render(<Checkbox description="By checking this, you agree to our terms" />);

      expect(screen.getByText('By checking this, you agree to our terms')).toBeInTheDocument();
    });

    it('renders with both label and description', () => {
      render(
        <Checkbox
          label="Terms"
          description="You must accept the terms"
        />
      );

      expect(screen.getByText('Terms')).toBeInTheDocument();
      expect(screen.getByText('You must accept the terms')).toBeInTheDocument();
    });

    it('applies custom className', () => {
      render(<Checkbox className="custom-class" />);

      const checkbox = screen.getByRole('checkbox');
      expect(checkbox).toHaveClass('custom-class');
    });
  });

  describe('id handling', () => {
    it('uses provided id', () => {
      render(<Checkbox id="my-checkbox" label="Test" />);

      const checkbox = screen.getByRole('checkbox');
      expect(checkbox).toHaveAttribute('id', 'my-checkbox');
    });

    it('generates random id when not provided', () => {
      render(<Checkbox label="Test" />);

      const checkbox = screen.getByRole('checkbox');
      expect(checkbox).toHaveAttribute('id');
      expect(checkbox.id).toMatch(/^checkbox-/);
    });

    it('associates label with checkbox', () => {
      render(<Checkbox id="test-cb" label="Click me" />);

      const label = screen.getByText('Click me');
      expect(label).toHaveAttribute('for', 'test-cb');
    });
  });

  describe('checked state', () => {
    it('renders unchecked by default', () => {
      render(<Checkbox />);

      expect(screen.getByRole('checkbox')).not.toBeChecked();
    });

    it('renders checked when checked prop is true', () => {
      render(<Checkbox checked />);

      expect(screen.getByRole('checkbox')).toBeChecked();
    });

    it('calls onCheckedChange when checkbox is clicked', () => {
      const onCheckedChange = jest.fn();
      render(<Checkbox onCheckedChange={onCheckedChange} />);

      fireEvent.click(screen.getByRole('checkbox'));

      expect(onCheckedChange).toHaveBeenCalledWith(true);
    });

    it('passes correct value on toggle', () => {
      const onCheckedChange = jest.fn();
      render(<Checkbox checked onCheckedChange={onCheckedChange} />);

      fireEvent.click(screen.getByRole('checkbox'));

      expect(onCheckedChange).toHaveBeenCalledWith(false);
    });
  });

  describe('indeterminate state', () => {
    it('sets indeterminate property', () => {
      render(<Checkbox indeterminate />);

      const checkbox = screen.getByRole('checkbox') as HTMLInputElement;
      expect(checkbox.indeterminate).toBe(true);
    });

    it('updates indeterminate when prop changes', () => {
      const { rerender } = render(<Checkbox indeterminate={false} />);

      const checkbox = screen.getByRole('checkbox') as HTMLInputElement;
      expect(checkbox.indeterminate).toBe(false);

      rerender(<Checkbox indeterminate />);
      expect(checkbox.indeterminate).toBe(true);
    });
  });

  describe('disabled state', () => {
    it('disables checkbox when disabled prop is true', () => {
      render(<Checkbox disabled />);

      expect(screen.getByRole('checkbox')).toBeDisabled();
    });
  });

  describe('error handling', () => {
    it('displays error message when label present', () => {
      render(<Checkbox label="Terms" error="This field is required" />);

      expect(screen.getByText('This field is required')).toBeInTheDocument();
    });

    it('shows error with alert role', () => {
      render(<Checkbox label="Terms" error="Error" />);

      expect(screen.getByRole('alert')).toBeInTheDocument();
    });

    it('applies error styling to checkbox', () => {
      render(<Checkbox error="Error" />);

      const checkbox = screen.getByRole('checkbox');
      expect(checkbox).toHaveClass('border-theme-error');
    });
  });

  describe('accessibility', () => {
    it('has aria-describedby referencing error', () => {
      render(<Checkbox id="test" label="Terms" error="Error message" />);

      const checkbox = screen.getByRole('checkbox');
      expect(checkbox).toHaveAttribute('aria-describedby', 'test-error');
    });

    it('has aria-describedby referencing description when no error', () => {
      render(<Checkbox id="test" description="Description text" />);

      const checkbox = screen.getByRole('checkbox');
      expect(checkbox).toHaveAttribute('aria-describedby', 'test-description');
    });

    it('error has correct id', () => {
      render(<Checkbox id="test" label="Terms" error="Error" />);

      const error = screen.getByRole('alert');
      expect(error).toHaveAttribute('id', 'test-error');
    });

    it('description has correct id', () => {
      render(<Checkbox id="test" description="Help text" />);

      const description = screen.getByText('Help text');
      expect(description).toHaveAttribute('id', 'test-description');
    });
  });

  describe('styling', () => {
    it('has proper checkbox styling', () => {
      render(<Checkbox />);

      const checkbox = screen.getByRole('checkbox');
      expect(checkbox).toHaveClass('h-4', 'w-4', 'rounded');
    });

    it('has proper label styling', () => {
      render(<Checkbox label="Test label" />);

      const label = screen.getByText('Test label');
      expect(label).toHaveClass('text-sm', 'font-medium', 'cursor-pointer');
    });

    it('has proper layout', () => {
      const { container } = render(<Checkbox label="Test" />);

      expect(container.firstChild).toHaveClass('flex', 'items-start', 'gap-3');
    });
  });

  describe('native props', () => {
    it('passes through native checkbox props', () => {
      render(<Checkbox name="myCheckbox" value="test" />);

      const checkbox = screen.getByRole('checkbox');
      expect(checkbox).toHaveAttribute('name', 'myCheckbox');
      expect(checkbox).toHaveAttribute('value', 'test');
    });

    it('supports required attribute', () => {
      render(<Checkbox required />);

      expect(screen.getByRole('checkbox')).toBeRequired();
    });
  });
});
