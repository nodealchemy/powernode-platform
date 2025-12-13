import { render, screen, fireEvent } from '@testing-library/react';
import { Select, SelectOption } from './Select';

describe('Select', () => {
  const defaultOptions: SelectOption[] = [
    { value: 'option1', label: 'Option 1' },
    { value: 'option2', label: 'Option 2' },
    { value: 'option3', label: 'Option 3' },
  ];

  describe('rendering', () => {
    it('renders select element', () => {
      render(<Select options={defaultOptions} />);

      expect(screen.getByRole('combobox')).toBeInTheDocument();
    });

    it('renders with label', () => {
      render(<Select label="Choose option" options={defaultOptions} />);

      expect(screen.getByText('Choose option')).toBeInTheDocument();
    });

    it('renders without label when not provided', () => {
      render(<Select options={defaultOptions} />);

      expect(screen.queryByText(/label/i)).not.toBeInTheDocument();
    });

    it('renders all options', () => {
      render(<Select options={defaultOptions} />);

      expect(screen.getByText('Option 1')).toBeInTheDocument();
      expect(screen.getByText('Option 2')).toBeInTheDocument();
      expect(screen.getByText('Option 3')).toBeInTheDocument();
    });

    it('renders children when provided instead of options', () => {
      render(
        <Select>
          <option value="child1">Child 1</option>
          <option value="child2">Child 2</option>
        </Select>
      );

      expect(screen.getByText('Child 1')).toBeInTheDocument();
      expect(screen.getByText('Child 2')).toBeInTheDocument();
    });

    it('applies custom className', () => {
      render(<Select options={defaultOptions} className="custom-class" />);

      const select = screen.getByRole('combobox');
      expect(select).toHaveClass('custom-class');
    });
  });

  describe('value handling', () => {
    it('displays selected value', () => {
      render(<Select options={defaultOptions} value="option2" />);

      const select = screen.getByRole('combobox') as HTMLSelectElement;
      expect(select.value).toBe('option2');
    });

    it('calls onChange when selection changes', () => {
      const onChange = jest.fn();
      render(<Select options={defaultOptions} onChange={onChange} />);

      const select = screen.getByRole('combobox');
      fireEvent.change(select, { target: { value: 'option2' } });

      expect(onChange).toHaveBeenCalledWith('option2');
    });

    it('calls onValueChange when selection changes', () => {
      const onValueChange = jest.fn();
      render(<Select options={defaultOptions} onValueChange={onValueChange} />);

      const select = screen.getByRole('combobox');
      fireEvent.change(select, { target: { value: 'option3' } });

      expect(onValueChange).toHaveBeenCalledWith('option3');
    });

    it('calls both onChange and onValueChange', () => {
      const onChange = jest.fn();
      const onValueChange = jest.fn();
      render(
        <Select
          options={defaultOptions}
          onChange={onChange}
          onValueChange={onValueChange}
        />
      );

      const select = screen.getByRole('combobox');
      fireEvent.change(select, { target: { value: 'option1' } });

      expect(onChange).toHaveBeenCalledWith('option1');
      expect(onValueChange).toHaveBeenCalledWith('option1');
    });
  });

  describe('disabled options', () => {
    it('renders disabled option', () => {
      const optionsWithDisabled: SelectOption[] = [
        { value: 'enabled', label: 'Enabled' },
        { value: 'disabled', label: 'Disabled', disabled: true },
      ];

      render(<Select options={optionsWithDisabled} />);

      const disabledOption = screen.getByText('Disabled') as HTMLOptionElement;
      expect(disabledOption).toBeDisabled();
    });
  });

  describe('disabled state', () => {
    it('disables select when disabled prop is true', () => {
      render(<Select options={defaultOptions} disabled />);

      expect(screen.getByRole('combobox')).toBeDisabled();
    });

    it('applies disabled styling', () => {
      render(<Select options={defaultOptions} disabled />);

      const select = screen.getByRole('combobox');
      expect(select).toHaveClass('disabled:bg-theme-background', 'disabled:text-theme-secondary');
    });
  });

  describe('error handling', () => {
    it('displays error message', () => {
      render(<Select options={defaultOptions} error="Please select an option" />);

      expect(screen.getByText('Please select an option')).toBeInTheDocument();
    });

    it('applies error styling to select', () => {
      render(<Select options={defaultOptions} error="Error" />);

      const select = screen.getByRole('combobox');
      expect(select).toHaveClass('border-theme-error', 'focus:ring-theme-error');
    });
  });

  describe('fullWidth', () => {
    it('is full width by default', () => {
      render(<Select options={defaultOptions} />);

      const select = screen.getByRole('combobox');
      expect(select).toHaveClass('w-full');
    });

    it('is not full width when fullWidth is false', () => {
      render(<Select options={defaultOptions} fullWidth={false} />);

      const select = screen.getByRole('combobox');
      expect(select).not.toHaveClass('w-full');
    });

    it('container is full width by default', () => {
      const { container } = render(<Select options={defaultOptions} />);

      expect(container.firstChild).toHaveClass('w-full');
    });
  });

  describe('styling', () => {
    it('has proper select styling', () => {
      render(<Select options={defaultOptions} />);

      const select = screen.getByRole('combobox');
      expect(select).toHaveClass('px-3', 'py-2', 'rounded-md');
    });

    it('has theme-aware styling', () => {
      render(<Select options={defaultOptions} />);

      const select = screen.getByRole('combobox');
      expect(select).toHaveClass('bg-theme-surface', 'text-theme-primary', 'border-theme');
    });

    it('has focus styling', () => {
      render(<Select options={defaultOptions} />);

      const select = screen.getByRole('combobox');
      expect(select).toHaveClass('focus:outline-none', 'focus:ring-2', 'focus:ring-theme-primary');
    });
  });

  describe('native props', () => {
    it('passes through native select props', () => {
      render(<Select options={defaultOptions} name="mySelect" id="select-id" />);

      const select = screen.getByRole('combobox');
      expect(select).toHaveAttribute('name', 'mySelect');
      expect(select).toHaveAttribute('id', 'select-id');
    });

    it('supports required attribute', () => {
      render(<Select options={defaultOptions} required />);

      expect(screen.getByRole('combobox')).toBeRequired();
    });
  });
});
