import { render, screen } from '@testing-library/react';
import { Progress } from './Progress';

describe('Progress', () => {
  describe('rendering', () => {
    it('renders progress bar', () => {
      const { container } = render(<Progress value={50} />);

      expect(container.querySelector('.rounded-full')).toBeInTheDocument();
    });

    it('applies custom className', () => {
      const { container } = render(<Progress value={50} className="custom-class" />);

      expect(container.firstChild).toHaveClass('custom-class');
    });

    it('renders full width by default', () => {
      const { container } = render(<Progress value={50} />);

      expect(container.firstChild).toHaveClass('w-full');
    });
  });

  describe('value calculation', () => {
    it('calculates percentage based on value and max', () => {
      const { container } = render(<Progress value={50} max={100} />);

      const progressBar = container.querySelector('.transition-all');
      expect(progressBar).toHaveStyle({ width: '50%' });
    });

    it('uses default max of 100', () => {
      const { container } = render(<Progress value={25} />);

      const progressBar = container.querySelector('.transition-all');
      expect(progressBar).toHaveStyle({ width: '25%' });
    });

    it('handles custom max value', () => {
      const { container } = render(<Progress value={3} max={10} />);

      const progressBar = container.querySelector('.transition-all');
      expect(progressBar).toHaveStyle({ width: '30%' });
    });

    it('caps at 100% when value exceeds max', () => {
      const { container } = render(<Progress value={150} max={100} />);

      const progressBar = container.querySelector('.transition-all');
      expect(progressBar).toHaveStyle({ width: '100%' });
    });

    it('does not go below 0%', () => {
      const { container } = render(<Progress value={-10} max={100} />);

      const progressBar = container.querySelector('.transition-all');
      expect(progressBar).toHaveStyle({ width: '0%' });
    });

    it('handles zero value', () => {
      const { container } = render(<Progress value={0} max={100} />);

      const progressBar = container.querySelector('.transition-all');
      expect(progressBar).toHaveStyle({ width: '0%' });
    });
  });

  describe('sizes', () => {
    it('renders small size', () => {
      const { container } = render(<Progress value={50} size="sm" />);

      const track = container.querySelector('.rounded-full');
      expect(track).toHaveClass('h-1');
    });

    it('renders medium size by default', () => {
      const { container } = render(<Progress value={50} />);

      const track = container.querySelector('.rounded-full');
      expect(track).toHaveClass('h-2');
    });

    it('renders large size', () => {
      const { container } = render(<Progress value={50} size="lg" />);

      const track = container.querySelector('.rounded-full');
      expect(track).toHaveClass('h-3');
    });
  });

  describe('variants', () => {
    it('renders default variant', () => {
      const { container } = render(<Progress value={50} />);

      const progressBar = container.querySelector('.transition-all');
      expect(progressBar).toHaveClass('bg-theme-interactive-primary');
    });

    it('renders success variant', () => {
      const { container } = render(<Progress value={50} variant="success" />);

      const progressBar = container.querySelector('.transition-all');
      expect(progressBar).toHaveClass('bg-theme-success');
    });

    it('renders warning variant', () => {
      const { container } = render(<Progress value={50} variant="warning" />);

      const progressBar = container.querySelector('.transition-all');
      expect(progressBar).toHaveClass('bg-theme-warning');
    });

    it('renders error variant', () => {
      const { container } = render(<Progress value={50} variant="error" />);

      const progressBar = container.querySelector('.transition-all');
      expect(progressBar).toHaveClass('bg-theme-error');
    });
  });

  describe('label', () => {
    it('does not show label by default', () => {
      render(<Progress value={50} />);

      expect(screen.queryByText('50%')).not.toBeInTheDocument();
    });

    it('shows label when showLabel is true', () => {
      render(<Progress value={50} showLabel />);

      expect(screen.getByText('50%')).toBeInTheDocument();
    });

    it('shows value and max in label', () => {
      render(<Progress value={50} max={100} showLabel />);

      expect(screen.getByText('50 / 100')).toBeInTheDocument();
    });

    it('rounds percentage in label', () => {
      render(<Progress value={33} max={100} showLabel />);

      expect(screen.getByText('33%')).toBeInTheDocument();
    });

    it('handles fractional percentages', () => {
      render(<Progress value={1} max={3} showLabel />);

      // 1/3 = 33.33%, rounds to 33%
      expect(screen.getByText('33%')).toBeInTheDocument();
      expect(screen.getByText('1 / 3')).toBeInTheDocument();
    });
  });

  describe('styling', () => {
    it('track has background color', () => {
      const { container } = render(<Progress value={50} />);

      const track = container.querySelector('.rounded-full');
      expect(track).toHaveClass('bg-theme-surface-secondary');
    });

    it('progress bar has transition', () => {
      const { container } = render(<Progress value={50} />);

      const progressBar = container.querySelector('.transition-all');
      expect(progressBar).toHaveClass('duration-300', 'ease-out');
    });

    it('track has overflow hidden', () => {
      const { container } = render(<Progress value={50} />);

      const track = container.querySelector('.rounded-full');
      expect(track).toHaveClass('overflow-hidden');
    });
  });
});
