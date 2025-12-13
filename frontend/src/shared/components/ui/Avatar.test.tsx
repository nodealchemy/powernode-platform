import { render, screen, fireEvent } from '@testing-library/react';
import { Avatar } from './Avatar';

describe('Avatar', () => {
  describe('rendering', () => {
    it('renders default fallback when no props provided', () => {
      render(<Avatar />);

      expect(screen.getByText('U')).toBeInTheDocument();
    });

    it('renders initials when provided', () => {
      render(<Avatar initials="JD" />);

      expect(screen.getByText('JD')).toBeInTheDocument();
    });

    it('renders fallback text when provided', () => {
      render(<Avatar fallback="AB" />);

      expect(screen.getByText('AB')).toBeInTheDocument();
    });

    it('prioritizes initials over fallback', () => {
      render(<Avatar initials="JD" fallback="AB" />);

      expect(screen.getByText('JD')).toBeInTheDocument();
      expect(screen.queryByText('AB')).not.toBeInTheDocument();
    });

    it('applies custom className', () => {
      const { container } = render(<Avatar className="custom-class" />);

      expect(container.firstChild).toHaveClass('custom-class');
    });
  });

  describe('children rendering', () => {
    it('renders children directly', () => {
      render(
        <Avatar>
          <span data-testid="custom-content">Custom</span>
        </Avatar>
      );

      expect(screen.getByTestId('custom-content')).toBeInTheDocument();
    });

    it('children take precedence over other props', () => {
      render(
        <Avatar initials="JD" fallback="AB">
          <span>Child Content</span>
        </Avatar>
      );

      expect(screen.getByText('Child Content')).toBeInTheDocument();
      expect(screen.queryByText('JD')).not.toBeInTheDocument();
    });
  });

  describe('image rendering', () => {
    it('renders image when src provided', () => {
      render(<Avatar src="/path/to/image.jpg" alt="User avatar" />);

      const img = screen.getByRole('img');
      expect(img).toHaveAttribute('src', '/path/to/image.jpg');
      expect(img).toHaveAttribute('alt', 'User avatar');
    });

    it('uses default alt text', () => {
      render(<Avatar src="/path/to/image.jpg" />);

      const img = screen.getByRole('img');
      expect(img).toHaveAttribute('alt', 'Avatar');
    });

    it('shows fallback on image error', () => {
      render(<Avatar src="/invalid.jpg" initials="JD" />);

      const img = screen.getByRole('img');
      fireEvent.error(img);

      // Image should be hidden
      expect(img).toHaveStyle({ display: 'none' });
    });

    it('shows first letter of alt on error without initials', () => {
      render(<Avatar src="/invalid.jpg" alt="John" />);

      // Fallback content should show "J"
      expect(screen.getByText('J')).toBeInTheDocument();
    });
  });

  describe('sizes', () => {
    it('renders xs size', () => {
      const { container } = render(<Avatar size="xs" />);

      expect(container.firstChild).toHaveClass('h-6', 'w-6', 'text-xs');
    });

    it('renders sm size', () => {
      const { container } = render(<Avatar size="sm" />);

      expect(container.firstChild).toHaveClass('h-8', 'w-8', 'text-sm');
    });

    it('renders md size by default', () => {
      const { container } = render(<Avatar />);

      expect(container.firstChild).toHaveClass('h-10', 'w-10', 'text-base');
    });

    it('renders lg size', () => {
      const { container } = render(<Avatar size="lg" />);

      expect(container.firstChild).toHaveClass('h-12', 'w-12', 'text-lg');
    });

    it('renders xl size', () => {
      const { container } = render(<Avatar size="xl" />);

      expect(container.firstChild).toHaveClass('h-16', 'w-16', 'text-xl');
    });
  });

  describe('styling', () => {
    it('has rounded-full class', () => {
      const { container } = render(<Avatar />);

      expect(container.firstChild).toHaveClass('rounded-full');
    });

    it('has gradient background', () => {
      const { container } = render(<Avatar />);

      expect(container.firstChild).toHaveClass(
        'bg-gradient-to-br',
        'from-theme-interactive-primary',
        'to-theme-interactive-secondary'
      );
    });

    it('centers content', () => {
      const { container } = render(<Avatar />);

      expect(container.firstChild).toHaveClass(
        'flex',
        'items-center',
        'justify-center'
      );
    });

    it('has white text', () => {
      const { container } = render(<Avatar />);

      expect(container.firstChild).toHaveClass('text-white', 'font-semibold');
    });

    it('has overflow hidden for images', () => {
      const { container } = render(<Avatar src="/test.jpg" />);

      expect(container.firstChild).toHaveClass('overflow-hidden');
    });
  });

  describe('image styling', () => {
    it('image covers container', () => {
      render(<Avatar src="/test.jpg" />);

      const img = screen.getByRole('img');
      expect(img).toHaveClass('w-full', 'h-full', 'object-cover');
    });
  });
});
