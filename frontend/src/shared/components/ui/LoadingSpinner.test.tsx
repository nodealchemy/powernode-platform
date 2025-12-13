import { render, screen, fireEvent } from '@testing-library/react';
import { LoadingSpinner } from './LoadingSpinner';

describe('LoadingSpinner', () => {
  describe('rendering', () => {
    it('renders spinner element', () => {
      const { container } = render(<LoadingSpinner />);

      const spinner = container.querySelector('.animate-spin');
      expect(spinner).toBeInTheDocument();
    });

    it('applies custom className', () => {
      const { container } = render(<LoadingSpinner className="custom-class" />);

      expect(container.firstChild).toHaveClass('custom-class');
    });
  });

  describe('sizes', () => {
    it('renders small size', () => {
      const { container } = render(<LoadingSpinner size="sm" />);

      const spinner = container.querySelector('.animate-spin');
      expect(spinner).toHaveClass('h-4', 'w-4');
    });

    it('renders medium size by default', () => {
      const { container } = render(<LoadingSpinner />);

      const spinner = container.querySelector('.animate-spin');
      expect(spinner).toHaveClass('h-8', 'w-8');
    });

    it('renders large size', () => {
      const { container } = render(<LoadingSpinner size="lg" />);

      const spinner = container.querySelector('.animate-spin');
      expect(spinner).toHaveClass('h-12', 'w-12');
    });

    it('renders extra large size', () => {
      const { container } = render(<LoadingSpinner size="xl" />);

      const spinner = container.querySelector('.animate-spin');
      expect(spinner).toHaveClass('h-16', 'w-16');
    });
  });

  describe('message', () => {
    it('does not render message by default', () => {
      render(<LoadingSpinner />);

      // No paragraph should be present without message
      expect(screen.queryByText(/./)).not.toBeInTheDocument();
    });

    it('renders message when provided', () => {
      render(<LoadingSpinner message="Loading data..." />);

      expect(screen.getByText('Loading data...')).toBeInTheDocument();
    });

    it('has proper message styling', () => {
      render(<LoadingSpinner message="Loading..." />);

      const message = screen.getByText('Loading...');
      expect(message).toHaveClass('text-theme-secondary', 'text-sm');
    });
  });

  describe('auth fallback', () => {
    it('does not render fallback button by default', () => {
      render(<LoadingSpinner />);

      expect(screen.queryByRole('button')).not.toBeInTheDocument();
    });

    it('does not render fallback button without callback', () => {
      render(<LoadingSpinner showAuthFallback />);

      expect(screen.queryByRole('button')).not.toBeInTheDocument();
    });

    it('renders fallback button when both props provided', () => {
      const onFallback = jest.fn();
      render(<LoadingSpinner showAuthFallback onAuthFallback={onFallback} />);

      expect(screen.getByRole('button')).toBeInTheDocument();
      expect(screen.getByText('Continue without loading')).toBeInTheDocument();
    });

    it('calls onAuthFallback when button clicked', () => {
      const onFallback = jest.fn();
      render(<LoadingSpinner showAuthFallback onAuthFallback={onFallback} />);

      fireEvent.click(screen.getByRole('button'));

      expect(onFallback).toHaveBeenCalledTimes(1);
    });

    it('has proper fallback button styling', () => {
      const onFallback = jest.fn();
      render(<LoadingSpinner showAuthFallback onAuthFallback={onFallback} />);

      const button = screen.getByRole('button');
      expect(button).toHaveClass('text-theme-interactive-primary', 'underline');
    });
  });

  describe('layout', () => {
    it('centers content', () => {
      const { container } = render(<LoadingSpinner />);

      expect(container.firstChild).toHaveClass(
        'flex',
        'flex-col',
        'items-center',
        'justify-center'
      );
    });

    it('has proper spacing', () => {
      const { container } = render(<LoadingSpinner message="Loading" />);

      expect(container.firstChild).toHaveClass('space-y-4');
    });
  });

  describe('spinner styling', () => {
    it('has animation class', () => {
      const { container } = render(<LoadingSpinner />);

      const spinner = container.querySelector('.animate-spin');
      expect(spinner).toBeInTheDocument();
    });

    it('has rounded border', () => {
      const { container } = render(<LoadingSpinner />);

      const spinner = container.querySelector('.animate-spin');
      expect(spinner).toHaveClass('rounded-full', 'border-2');
    });
  });
});
