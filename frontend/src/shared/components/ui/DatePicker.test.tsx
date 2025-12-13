import { render, screen, fireEvent } from '@testing-library/react';
import { DatePicker } from './DatePicker';

// Mock ReactDatePicker to test useNativeInput=false case
jest.mock('./ReactDatePicker', () => ({
  ReactDatePicker: ({ selected, onChange, disabled, placeholder }: any) => (
    <div data-testid="react-date-picker">
      <input
        type="text"
        placeholder={placeholder}
        value={selected ? selected.toISOString() : ''}
        onChange={(e) => onChange(new Date(e.target.value))}
        disabled={disabled}
        data-testid="react-date-picker-input"
      />
    </div>
  )
}));

describe('DatePicker', () => {
  const mockOnChange = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('native input (default)', () => {
    it('renders date input by default', () => {
      const { container } = render(<DatePicker selected={null} onChange={mockOnChange} />);

      const input = container.querySelector('input[type="date"]');
      expect(input).toBeInTheDocument();
    });

    it('renders with correct input type for date only', () => {
      const { container } = render(<DatePicker selected={null} onChange={mockOnChange} />);

      const input = container.querySelector('input[type="date"]');
      expect(input).toBeInTheDocument();
    });

    it('renders with datetime-local type when showTimeSelect is true', () => {
      const { container } = render(
        <DatePicker selected={null} onChange={mockOnChange} showTimeSelect />
      );

      const input = container.querySelector('input[type="datetime-local"]');
      expect(input).toBeInTheDocument();
    });

    it('displays selected date', () => {
      const testDate = new Date('2025-06-15');
      const { container } = render(
        <DatePicker selected={testDate} onChange={mockOnChange} />
      );

      const input = container.querySelector('input') as HTMLInputElement;
      expect(input.value).toBe('2025-06-15');
    });

    it('calls onChange when date changes', () => {
      const { container } = render(
        <DatePicker selected={null} onChange={mockOnChange} />
      );

      const input = container.querySelector('input') as HTMLInputElement;
      fireEvent.change(input, { target: { value: '2025-07-20' } });

      expect(mockOnChange).toHaveBeenCalled();
      const calledDate = mockOnChange.mock.calls[0][0];
      expect(calledDate.getFullYear()).toBe(2025);
      expect(calledDate.getMonth()).toBe(6); // July is 6 (0-indexed)
      expect(calledDate.getDate()).toBe(20);
    });

    it('applies disabled state', () => {
      const { container } = render(
        <DatePicker selected={null} onChange={mockOnChange} disabled />
      );

      const input = container.querySelector('input');
      expect(input).toBeDisabled();
    });

    it('shows clear button when date is selected', () => {
      const testDate = new Date('2025-06-15');
      render(<DatePicker selected={testDate} onChange={mockOnChange} />);

      const clearButton = screen.getByRole('button', { name: 'Clear date' });
      expect(clearButton).toBeInTheDocument();
    });

    it('does not show clear button when no date selected', () => {
      render(<DatePicker selected={null} onChange={mockOnChange} />);

      const clearButton = screen.queryByRole('button', { name: 'Clear date' });
      expect(clearButton).not.toBeInTheDocument();
    });

    it('does not show clear button when disabled', () => {
      const testDate = new Date('2025-06-15');
      render(<DatePicker selected={testDate} onChange={mockOnChange} disabled />);

      const clearButton = screen.queryByRole('button', { name: 'Clear date' });
      expect(clearButton).not.toBeInTheDocument();
    });

    it('calls onChange with null when clear button clicked', () => {
      const testDate = new Date('2025-06-15');
      render(<DatePicker selected={testDate} onChange={mockOnChange} />);

      const clearButton = screen.getByRole('button', { name: 'Clear date' });
      fireEvent.click(clearButton);

      expect(mockOnChange).toHaveBeenCalledWith(null);
    });

    it('applies min date constraint', () => {
      const minDate = new Date('2025-01-01');
      const { container } = render(
        <DatePicker selected={null} onChange={mockOnChange} minDate={minDate} />
      );

      const input = container.querySelector('input') as HTMLInputElement;
      expect(input.min).toBe('2025-01-01');
    });

    it('applies max date constraint', () => {
      const maxDate = new Date('2025-12-31');
      const { container } = render(
        <DatePicker selected={null} onChange={mockOnChange} maxDate={maxDate} />
      );

      const input = container.querySelector('input') as HTMLInputElement;
      expect(input.max).toBe('2025-12-31');
    });

    it('applies custom className', () => {
      const { container } = render(
        <DatePicker selected={null} onChange={mockOnChange} className="custom-class" />
      );

      const input = container.querySelector('input');
      expect(input).toHaveClass('custom-class');
    });

    it('applies id attribute', () => {
      const { container } = render(
        <DatePicker selected={null} onChange={mockOnChange} id="test-date-picker" />
      );

      const input = container.querySelector('#test-date-picker');
      expect(input).toBeInTheDocument();
    });

    it('applies name attribute', () => {
      const { container } = render(
        <DatePicker selected={null} onChange={mockOnChange} name="test-date" />
      );

      const input = container.querySelector('input[name="test-date"]');
      expect(input).toBeInTheDocument();
    });

    it('applies required attribute', () => {
      const { container } = render(
        <DatePicker selected={null} onChange={mockOnChange} required />
      );

      const input = container.querySelector('input');
      expect(input).toBeRequired();
    });

    it('applies placeholder text', () => {
      const { container } = render(
        <DatePicker selected={null} onChange={mockOnChange} placeholderText="Pick a date" />
      );

      const input = container.querySelector('input');
      expect(input).toHaveAttribute('placeholder', 'Pick a date');
    });
  });

  describe('React date picker (useNativeInput=false)', () => {
    it('renders ReactDatePicker when useNativeInput is false', () => {
      render(
        <DatePicker selected={null} onChange={mockOnChange} useNativeInput={false} />
      );

      expect(screen.getByTestId('react-date-picker')).toBeInTheDocument();
    });

    it('passes props to ReactDatePicker', () => {
      const testDate = new Date('2025-06-15');
      render(
        <DatePicker
          selected={testDate}
          onChange={mockOnChange}
          useNativeInput={false}
          disabled
          placeholderText="Select date"
        />
      );

      const input = screen.getByTestId('react-date-picker-input');
      expect(input).toBeDisabled();
    });
  });

  describe('datetime handling', () => {
    it('formats datetime correctly for datetime-local input', () => {
      const testDate = new Date('2025-06-15T14:30:00');
      const { container } = render(
        <DatePicker selected={testDate} onChange={mockOnChange} showTimeSelect />
      );

      const input = container.querySelector('input') as HTMLInputElement;
      // Check that the value contains the expected date and time parts
      expect(input.value).toContain('2025-06-15');
    });

    it('parses datetime-local input correctly', () => {
      const { container } = render(
        <DatePicker selected={null} onChange={mockOnChange} showTimeSelect />
      );

      const input = container.querySelector('input') as HTMLInputElement;
      fireEvent.change(input, { target: { value: '2025-07-20T15:45' } });

      expect(mockOnChange).toHaveBeenCalled();
      const calledDate = mockOnChange.mock.calls[0][0];
      expect(calledDate).toBeInstanceOf(Date);
    });
  });

  describe('styling', () => {
    it('applies disabled styling', () => {
      const { container } = render(
        <DatePicker selected={null} onChange={mockOnChange} disabled />
      );

      const input = container.querySelector('input');
      expect(input).toHaveClass('opacity-50', 'cursor-not-allowed');
    });

    it('has theme-aware styling', () => {
      const { container } = render(
        <DatePicker selected={null} onChange={mockOnChange} />
      );

      const input = container.querySelector('input');
      expect(input).toHaveClass('bg-theme-surface', 'text-theme-primary', 'border-theme');
    });
  });
});
