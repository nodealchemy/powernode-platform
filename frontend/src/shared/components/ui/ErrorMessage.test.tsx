import { render, screen } from '@testing-library/react';
import { ErrorMessage } from './ErrorMessage';

describe('ErrorMessage', () => {
  describe('rendering', () => {
    it('renders with default title', () => {
      render(<ErrorMessage message="Something went wrong" />);

      expect(screen.getByText('Error')).toBeInTheDocument();
    });

    it('renders with custom title', () => {
      render(<ErrorMessage title="Connection Failed" message="Unable to connect" />);

      expect(screen.getByText('Connection Failed')).toBeInTheDocument();
    });

    it('renders the message', () => {
      render(<ErrorMessage message="Please try again later" />);

      expect(screen.getByText('Please try again later')).toBeInTheDocument();
    });

    it('renders alert icon', () => {
      const { container } = render(<ErrorMessage message="Error" />);

      expect(container.querySelector('svg')).toBeInTheDocument();
    });

    it('applies custom className', () => {
      const { container } = render(
        <ErrorMessage message="Error" className="custom-class" />
      );

      expect(container.firstChild).toHaveClass('custom-class');
    });
  });

  describe('styling', () => {
    it('has error background styling', () => {
      const { container } = render(<ErrorMessage message="Error" />);

      expect(container.firstChild).toHaveClass('bg-theme-error', 'bg-opacity-10');
    });

    it('has border styling', () => {
      const { container } = render(<ErrorMessage message="Error" />);

      expect(container.firstChild).toHaveClass('border', 'border-theme-error', 'rounded-lg');
    });

    it('has flex layout', () => {
      const { container } = render(<ErrorMessage message="Error" />);

      expect(container.firstChild).toHaveClass('flex', 'items-start', 'gap-3');
    });

    it('title has error styling', () => {
      render(<ErrorMessage title="Test Title" message="Test message" />);

      const title = screen.getByText('Test Title');
      expect(title).toHaveClass('text-sm', 'font-medium', 'text-theme-error');
    });

    it('message has secondary text color', () => {
      render(<ErrorMessage message="Error message text" />);

      const message = screen.getByText('Error message text');
      expect(message).toHaveClass('text-sm', 'text-theme-secondary');
    });

    it('has proper padding', () => {
      const { container } = render(<ErrorMessage message="Error" />);

      expect(container.firstChild).toHaveClass('p-4');
    });
  });
});
