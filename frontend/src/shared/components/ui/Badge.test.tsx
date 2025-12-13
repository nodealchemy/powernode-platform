import { render, screen, fireEvent } from '@testing-library/react';
import { Badge } from './Badge';

describe('Badge', () => {
  describe('rendering', () => {
    it('renders children correctly', () => {
      render(<Badge>Status</Badge>);
      expect(screen.getByText('Status')).toBeInTheDocument();
    });

    it('renders with default props', () => {
      const { container } = render(<Badge>Default</Badge>);
      const badge = container.firstChild;
      expect(badge).toHaveClass('badge-theme');
      expect(badge).toHaveClass('badge-theme-default');
      expect(badge).toHaveClass('badge-theme-sm');
    });
  });

  describe('variants', () => {
    it.each([
      ['default', 'badge-theme-default'],
      ['primary', 'badge-theme-primary'],
      ['secondary', 'badge-theme-secondary'],
      ['success', 'badge-theme-success'],
      ['warning', 'badge-theme-warning'],
      ['danger', 'badge-theme-danger'],
      ['info', 'badge-theme-info'],
      ['outline', 'badge-theme-outline'],
    ])('renders %s variant correctly', (variant, expectedClass) => {
      const { container } = render(<Badge variant={variant as any}>Badge</Badge>);
      expect(container.firstChild).toHaveClass(expectedClass);
    });
  });

  describe('sizes', () => {
    it.each([
      ['xs', 'badge-theme-xs'],
      ['sm', 'badge-theme-sm'],
      ['md', 'badge-theme-md'],
      ['lg', 'badge-theme-lg'],
    ])('renders %s size correctly', (size, expectedClass) => {
      const { container } = render(<Badge size={size as any}>Badge</Badge>);
      expect(container.firstChild).toHaveClass(expectedClass);
    });
  });

  describe('rounded', () => {
    it.each([
      ['md', 'badge-theme-rounded-md'],
      ['lg', 'badge-theme-rounded-lg'],
      ['full', 'badge-theme-rounded-full'],
    ])('applies %s rounded class', (rounded, expectedClass) => {
      const { container } = render(<Badge rounded={rounded as any}>Badge</Badge>);
      expect(container.firstChild).toHaveClass(expectedClass);
    });
  });

  describe('dot indicator', () => {
    it('renders dot when dot prop is true', () => {
      const { container } = render(<Badge dot>Status</Badge>);
      const dotElements = container.querySelectorAll('.badge-dot');
      expect(dotElements.length).toBeGreaterThan(0);
    });

    it('does not render dot by default', () => {
      const { container } = render(<Badge>Status</Badge>);
      const dotElements = container.querySelectorAll('.badge-dot');
      expect(dotElements.length).toBe(0);
    });

    it('renders pulsing dot when pulse is true', () => {
      const { container } = render(<Badge dot pulse>Status</Badge>);
      const pulseElement = container.querySelector('.badge-dot-pulse');
      expect(pulseElement).toBeInTheDocument();
    });
  });

  describe('icon', () => {
    it('renders icon when provided', () => {
      render(<Badge icon={<span data-testid="icon">*</span>}>Status</Badge>);
      expect(screen.getByTestId('icon')).toBeInTheDocument();
    });

    it('does not render icon container when icon is not provided', () => {
      const { container } = render(<Badge>Status</Badge>);
      // Badge has 3 child spans by default (dot container if dot, icon container if icon, content)
      const spans = container.querySelectorAll('span > span');
      expect(spans.length).toBe(1); // Only the content span
    });
  });

  describe('removable', () => {
    it('renders remove button when removable and onRemove are provided', () => {
      render(<Badge removable onRemove={() => {}}>Status</Badge>);
      expect(screen.getByRole('button', { name: 'Remove' })).toBeInTheDocument();
    });

    it('does not render remove button when only removable is true', () => {
      render(<Badge removable>Status</Badge>);
      expect(screen.queryByRole('button', { name: 'Remove' })).not.toBeInTheDocument();
    });

    it('does not render remove button when only onRemove is provided', () => {
      render(<Badge onRemove={() => {}}>Status</Badge>);
      expect(screen.queryByRole('button', { name: 'Remove' })).not.toBeInTheDocument();
    });

    it('calls onRemove when remove button is clicked', () => {
      const handleRemove = jest.fn();
      render(<Badge removable onRemove={handleRemove}>Status</Badge>);
      fireEvent.click(screen.getByRole('button', { name: 'Remove' }));
      expect(handleRemove).toHaveBeenCalledTimes(1);
    });
  });

  describe('custom className', () => {
    it('merges custom className with default classes', () => {
      const { container } = render(<Badge className="custom-badge">Custom</Badge>);
      expect(container.firstChild).toHaveClass('custom-badge');
      expect(container.firstChild).toHaveClass('badge-theme');
    });
  });
});
