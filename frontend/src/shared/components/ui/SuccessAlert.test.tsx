import { render, screen, fireEvent } from '@testing-library/react';
import SuccessAlert from './SuccessAlert';

describe('SuccessAlert', () => {
  describe('rendering', () => {
    it('renders the message', () => {
      render(<SuccessAlert message="Operation completed successfully" />);

      expect(screen.getByText('Operation completed successfully')).toBeInTheDocument();
    });

    it('renders check circle icon', () => {
      const { container } = render(<SuccessAlert message="Success" />);

      expect(container.querySelector('svg')).toBeInTheDocument();
    });
  });

  describe('close button', () => {
    it('does not render close button when onClose not provided', () => {
      render(<SuccessAlert message="Success" />);

      expect(screen.queryByRole('button')).not.toBeInTheDocument();
    });

    it('renders close button when onClose provided', () => {
      render(<SuccessAlert message="Success" onClose={jest.fn()} />);

      expect(screen.getByRole('button')).toBeInTheDocument();
    });

    it('calls onClose when close button clicked', () => {
      const onClose = jest.fn();
      render(<SuccessAlert message="Success" onClose={onClose} />);

      fireEvent.click(screen.getByRole('button'));

      expect(onClose).toHaveBeenCalledTimes(1);
    });
  });

  describe('styling', () => {
    it('has success background styling', () => {
      const { container } = render(<SuccessAlert message="Success" />);

      expect(container.firstChild).toHaveClass('bg-theme-success', 'bg-opacity-10');
    });

    it('has border styling', () => {
      const { container } = render(<SuccessAlert message="Success" />);

      expect(container.firstChild).toHaveClass('border', 'border-theme-success', 'rounded-lg');
    });

    it('has flex layout', () => {
      const { container } = render(<SuccessAlert message="Success" />);

      const innerDiv = container.querySelector('.flex.items-start.gap-3');
      expect(innerDiv).toBeInTheDocument();
    });

    it('message has success text color', () => {
      render(<SuccessAlert message="Success message" />);

      const message = screen.getByText('Success message');
      expect(message).toHaveClass('text-sm', 'text-theme-success');
    });
  });
});
