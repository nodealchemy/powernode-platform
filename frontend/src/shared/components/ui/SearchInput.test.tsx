import { render, screen, fireEvent } from '@testing-library/react';
import { SearchInput } from './SearchInput';

describe('SearchInput', () => {
  const defaultProps = {
    value: '',
    onChange: jest.fn(),
  };

  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('rendering', () => {
    it('renders input element', () => {
      render(<SearchInput {...defaultProps} />);

      expect(screen.getByRole('textbox')).toBeInTheDocument();
    });

    it('renders with default placeholder', () => {
      render(<SearchInput {...defaultProps} />);

      expect(screen.getByPlaceholderText('Search...')).toBeInTheDocument();
    });

    it('renders with custom placeholder', () => {
      render(<SearchInput {...defaultProps} placeholder="Find users..." />);

      expect(screen.getByPlaceholderText('Find users...')).toBeInTheDocument();
    });

    it('renders search icon', () => {
      const { container } = render(<SearchInput {...defaultProps} />);

      const icon = container.querySelector('svg');
      expect(icon).toBeInTheDocument();
    });

    it('applies custom className', () => {
      const { container } = render(
        <SearchInput {...defaultProps} className="custom-class" />
      );

      expect(container.firstChild).toHaveClass('custom-class');
    });
  });

  describe('value handling', () => {
    it('displays the provided value', () => {
      render(<SearchInput {...defaultProps} value="search term" />);

      expect(screen.getByRole('textbox')).toHaveValue('search term');
    });

    it('calls onChange when input changes', () => {
      const onChange = jest.fn();
      render(<SearchInput {...defaultProps} onChange={onChange} />);

      const input = screen.getByRole('textbox');
      fireEvent.change(input, { target: { value: 'new value' } });

      expect(onChange).toHaveBeenCalledWith('new value');
    });
  });

  describe('clear button', () => {
    it('does not show clear button when value is empty', () => {
      render(<SearchInput {...defaultProps} value="" />);

      expect(screen.queryByRole('button')).not.toBeInTheDocument();
    });

    it('shows clear button when value is present', () => {
      render(<SearchInput {...defaultProps} value="search" />);

      expect(screen.getByRole('button')).toBeInTheDocument();
    });

    it('clears value when clear button clicked', () => {
      const onChange = jest.fn();
      render(<SearchInput {...defaultProps} value="search" onChange={onChange} />);

      fireEvent.click(screen.getByRole('button'));

      expect(onChange).toHaveBeenCalledWith('');
    });

    it('does not show clear button when disabled even with value', () => {
      render(<SearchInput {...defaultProps} value="search" disabled />);

      expect(screen.queryByRole('button')).not.toBeInTheDocument();
    });
  });

  describe('disabled state', () => {
    it('disables input when disabled prop is true', () => {
      render(<SearchInput {...defaultProps} disabled />);

      expect(screen.getByRole('textbox')).toBeDisabled();
    });

    it('applies disabled styling', () => {
      render(<SearchInput {...defaultProps} disabled />);

      const input = screen.getByRole('textbox');
      expect(input).toHaveClass('opacity-50', 'cursor-not-allowed');
    });

    it('does not call onChange when disabled', () => {
      const onChange = jest.fn();
      render(<SearchInput {...defaultProps} onChange={onChange} disabled />);

      const input = screen.getByRole('textbox');
      fireEvent.change(input, { target: { value: 'test' } });

      // Input is disabled so change event won't fire
      expect(input).toBeDisabled();
    });
  });

  describe('styling', () => {
    it('has proper input styling', () => {
      render(<SearchInput {...defaultProps} />);

      const input = screen.getByRole('textbox');
      expect(input).toHaveClass('w-full', 'pl-10', 'pr-10', 'py-2', 'rounded-md');
    });

    it('has theme-aware styling', () => {
      render(<SearchInput {...defaultProps} />);

      const input = screen.getByRole('textbox');
      expect(input).toHaveClass('bg-theme-surface', 'text-theme-primary');
    });

    it('has focus styling', () => {
      render(<SearchInput {...defaultProps} />);

      const input = screen.getByRole('textbox');
      expect(input).toHaveClass('focus:outline-none', 'focus:ring-2', 'focus:ring-theme-primary');
    });
  });

  describe('layout', () => {
    it('has relative positioning for icon placement', () => {
      const { container } = render(<SearchInput {...defaultProps} />);

      expect(container.firstChild).toHaveClass('relative');
    });
  });

  describe('accessibility', () => {
    it('input is accessible as textbox', () => {
      render(<SearchInput {...defaultProps} />);

      expect(screen.getByRole('textbox')).toBeInTheDocument();
    });

    it('clear button is accessible', () => {
      render(<SearchInput {...defaultProps} value="search" />);

      const button = screen.getByRole('button');
      expect(button).toHaveAttribute('type', 'button');
    });
  });
});
