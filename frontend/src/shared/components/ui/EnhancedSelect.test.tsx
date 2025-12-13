import { render, screen, fireEvent } from '@testing-library/react';
import { EnhancedSelect, SelectOption } from './EnhancedSelect';

describe('EnhancedSelect', () => {
  const defaultOptions: SelectOption[] = [
    { value: 'option1', label: 'Option 1' },
    { value: 'option2', label: 'Option 2' },
    { value: 'option3', label: 'Option 3', description: 'Third option' }
  ];

  describe('rendering', () => {
    it('renders with placeholder', () => {
      render(<EnhancedSelect options={defaultOptions} placeholder="Select..." />);

      expect(screen.getByText('Select...')).toBeInTheDocument();
    });

    it('renders with label', () => {
      render(<EnhancedSelect options={defaultOptions} label="Choose option" />);

      expect(screen.getByText('Choose option')).toBeInTheDocument();
    });

    it('renders selected value', () => {
      render(<EnhancedSelect options={defaultOptions} value="option2" />);

      expect(screen.getByText('Option 2')).toBeInTheDocument();
    });

    it('does not show dropdown by default', () => {
      render(<EnhancedSelect options={defaultOptions} />);

      expect(screen.queryByRole('listbox')).not.toBeInTheDocument();
    });
  });

  describe('dropdown behavior', () => {
    it('opens dropdown when button clicked', () => {
      render(<EnhancedSelect options={defaultOptions} />);

      fireEvent.click(screen.getByRole('button'));

      expect(screen.getByRole('listbox')).toBeInTheDocument();
    });

    it('shows all options in dropdown', () => {
      render(<EnhancedSelect options={defaultOptions} />);

      fireEvent.click(screen.getByRole('button'));

      expect(screen.getByText('Option 1')).toBeInTheDocument();
      expect(screen.getByText('Option 2')).toBeInTheDocument();
      expect(screen.getByText('Option 3')).toBeInTheDocument();
    });

    it('closes dropdown when option selected', () => {
      render(<EnhancedSelect options={defaultOptions} />);

      fireEvent.click(screen.getByRole('button'));
      fireEvent.click(screen.getByText('Option 1'));

      expect(screen.queryByRole('listbox')).not.toBeInTheDocument();
    });

    it('closes dropdown when clicking outside', () => {
      render(<EnhancedSelect options={defaultOptions} />);

      fireEvent.click(screen.getByRole('button'));
      expect(screen.getByRole('listbox')).toBeInTheDocument();

      fireEvent.mouseDown(document.body);
      expect(screen.queryByRole('listbox')).not.toBeInTheDocument();
    });
  });

  describe('selection', () => {
    it('calls onChange when option selected', () => {
      const onChange = jest.fn();
      render(<EnhancedSelect options={defaultOptions} onChange={onChange} />);

      fireEvent.click(screen.getByRole('button'));
      fireEvent.click(screen.getByText('Option 2'));

      expect(onChange).toHaveBeenCalledWith('option2');
    });

    it('calls onValueChange when option selected', () => {
      const onValueChange = jest.fn();
      render(<EnhancedSelect options={defaultOptions} onValueChange={onValueChange} />);

      fireEvent.click(screen.getByRole('button'));
      fireEvent.click(screen.getByText('Option 1'));

      expect(onValueChange).toHaveBeenCalledWith('option1');
    });

    it('updates displayed value after selection', () => {
      render(<EnhancedSelect options={defaultOptions} placeholder="Select..." />);

      fireEvent.click(screen.getByRole('button'));
      fireEvent.click(screen.getByText('Option 2'));

      expect(screen.getByText('Option 2')).toBeInTheDocument();
      expect(screen.queryByText('Select...')).not.toBeInTheDocument();
    });
  });

  describe('disabled options', () => {
    it('shows disabled option with styling', () => {
      const options = [
        { value: 'enabled', label: 'Enabled' },
        { value: 'disabled', label: 'Disabled', disabled: true }
      ];

      render(<EnhancedSelect options={options} />);
      fireEvent.click(screen.getByRole('button'));

      const disabledOption = screen.getByText('Disabled').closest('li');
      expect(disabledOption).toHaveClass('opacity-50', 'cursor-not-allowed');
    });

    it('does not select disabled option', () => {
      const onChange = jest.fn();
      const options = [
        { value: 'enabled', label: 'Enabled' },
        { value: 'disabled', label: 'Disabled', disabled: true }
      ];

      render(<EnhancedSelect options={options} onChange={onChange} />);
      fireEvent.click(screen.getByRole('button'));
      fireEvent.click(screen.getByText('Disabled'));

      expect(onChange).not.toHaveBeenCalled();
    });
  });

  describe('disabled select', () => {
    it('is disabled when disabled prop is true', () => {
      render(<EnhancedSelect options={defaultOptions} disabled />);

      expect(screen.getByRole('button')).toBeDisabled();
    });

    it('does not open dropdown when disabled', () => {
      render(<EnhancedSelect options={defaultOptions} disabled />);

      fireEvent.click(screen.getByRole('button'));

      expect(screen.queryByRole('listbox')).not.toBeInTheDocument();
    });
  });

  describe('error state', () => {
    it('displays error message', () => {
      render(<EnhancedSelect options={defaultOptions} error="Required field" />);

      expect(screen.getByRole('alert')).toHaveTextContent('Required field');
    });

    it('has error styling on button', () => {
      render(<EnhancedSelect options={defaultOptions} error="Error" />);

      expect(screen.getByRole('button')).toHaveClass('border-theme-error');
    });
  });

  describe('option descriptions', () => {
    it('shows option description', () => {
      render(<EnhancedSelect options={defaultOptions} />);

      fireEvent.click(screen.getByRole('button'));

      expect(screen.getByText('Third option')).toBeInTheDocument();
    });
  });

  describe('keyboard navigation', () => {
    it('opens dropdown on Enter', () => {
      render(<EnhancedSelect options={defaultOptions} />);

      fireEvent.keyDown(screen.getByRole('button'), { key: 'Enter' });

      expect(screen.getByRole('listbox')).toBeInTheDocument();
    });

    it('opens dropdown on Space', () => {
      render(<EnhancedSelect options={defaultOptions} />);

      fireEvent.keyDown(screen.getByRole('button'), { key: ' ' });

      expect(screen.getByRole('listbox')).toBeInTheDocument();
    });

    it('closes dropdown on Escape', () => {
      render(<EnhancedSelect options={defaultOptions} />);

      fireEvent.click(screen.getByRole('button'));
      expect(screen.getByRole('listbox')).toBeInTheDocument();

      fireEvent.keyDown(screen.getByRole('button'), { key: 'Escape' });
      expect(screen.queryByRole('listbox')).not.toBeInTheDocument();
    });
  });

  describe('accessibility', () => {
    it('has aria-haspopup attribute', () => {
      render(<EnhancedSelect options={defaultOptions} />);

      expect(screen.getByRole('button')).toHaveAttribute('aria-haspopup', 'listbox');
    });

    it('has aria-expanded when open', () => {
      render(<EnhancedSelect options={defaultOptions} />);

      const button = screen.getByRole('button');
      expect(button).toHaveAttribute('aria-expanded', 'false');

      fireEvent.click(button);
      expect(button).toHaveAttribute('aria-expanded', 'true');
    });

    it('options have aria-selected', () => {
      render(<EnhancedSelect options={defaultOptions} value="option2" />);

      fireEvent.click(screen.getByRole('button'));

      const options = screen.getAllByRole('option');
      expect(options[0]).toHaveAttribute('aria-selected', 'false');
      expect(options[1]).toHaveAttribute('aria-selected', 'true');
    });
  });

  describe('custom render', () => {
    it('uses custom renderOption function', () => {
      const renderOption = (option: SelectOption) => (
        <span data-testid="custom-option">{option.label.toUpperCase()}</span>
      );

      render(
        <EnhancedSelect
          options={defaultOptions}
          renderOption={renderOption}
        />
      );

      fireEvent.click(screen.getByRole('button'));

      expect(screen.getAllByTestId('custom-option')).toHaveLength(3);
      expect(screen.getByText('OPTION 1')).toBeInTheDocument();
    });
  });
});
