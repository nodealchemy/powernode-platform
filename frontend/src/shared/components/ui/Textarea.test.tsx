import { render, screen, fireEvent } from '@testing-library/react';
import { Textarea } from './Textarea';

describe('Textarea', () => {
  describe('rendering', () => {
    it('renders textarea element', () => {
      render(<Textarea />);

      expect(screen.getByRole('textbox')).toBeInTheDocument();
    });

    it('renders with label', () => {
      render(<Textarea label="Description" />);

      expect(screen.getByLabelText('Description')).toBeInTheDocument();
    });

    it('renders with placeholder', () => {
      render(<Textarea placeholder="Enter text..." />);

      expect(screen.getByPlaceholderText('Enter text...')).toBeInTheDocument();
    });

    it('renders with value', () => {
      render(<Textarea value="Test content" onChange={() => {}} />);

      expect(screen.getByDisplayValue('Test content')).toBeInTheDocument();
    });
  });

  describe('error state', () => {
    it('displays error message', () => {
      render(<Textarea error="This field is required" />);

      expect(screen.getByText('This field is required')).toBeInTheDocument();
    });

    it('error has role alert', () => {
      render(<Textarea error="Error message" />);

      expect(screen.getByRole('alert')).toHaveTextContent('Error message');
    });

    it('textarea has error styling', () => {
      render(<Textarea error="Error" />);

      expect(screen.getByRole('textbox')).toHaveClass('border-theme-error');
    });

    it('textarea is connected to error via aria-describedby', () => {
      render(<Textarea error="Error message" id="test-textarea" />);

      const textarea = screen.getByRole('textbox');
      expect(textarea).toHaveAttribute('aria-describedby', 'test-textarea-error');
    });
  });

  describe('fullWidth', () => {
    it('has full width by default', () => {
      const { container } = render(<Textarea />);

      expect(container.firstChild).toHaveClass('w-full');
    });

    it('can disable full width', () => {
      const { container } = render(<Textarea fullWidth={false} />);

      expect(container.firstChild).not.toHaveClass('w-full');
    });
  });

  describe('interaction', () => {
    it('calls onChange when text changes', () => {
      const handleChange = jest.fn();
      render(<Textarea onChange={handleChange} />);

      fireEvent.change(screen.getByRole('textbox'), { target: { value: 'New text' } });

      expect(handleChange).toHaveBeenCalled();
    });

    it('supports disabled state', () => {
      render(<Textarea disabled />);

      expect(screen.getByRole('textbox')).toBeDisabled();
    });

    it('supports rows prop', () => {
      render(<Textarea rows={5} />);

      expect(screen.getByRole('textbox')).toHaveAttribute('rows', '5');
    });
  });

  describe('styling', () => {
    it('applies base styling', () => {
      render(<Textarea />);

      const textarea = screen.getByRole('textbox');
      expect(textarea).toHaveClass('px-3', 'py-2', 'border', 'rounded-md');
    });

    it('applies theme classes', () => {
      render(<Textarea />);

      const textarea = screen.getByRole('textbox');
      expect(textarea).toHaveClass('bg-theme-surface', 'text-theme-primary');
    });

    it('applies custom className', () => {
      render(<Textarea className="custom-class" />);

      expect(screen.getByRole('textbox')).toHaveClass('custom-class');
    });
  });

  describe('accessibility', () => {
    it('label is associated with textarea via htmlFor', () => {
      render(<Textarea label="Notes" id="notes-field" />);

      const label = screen.getByText('Notes');
      expect(label).toHaveAttribute('for', 'notes-field');
    });

    it('generates unique id if not provided', () => {
      render(<Textarea label="Notes" />);

      const textarea = screen.getByRole('textbox');
      expect(textarea).toHaveAttribute('id');
      expect(textarea.id).toMatch(/^textarea-/);
    });
  });
});
