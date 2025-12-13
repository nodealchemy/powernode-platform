import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { Button } from './Button';

describe('Button', () => {
  describe('rendering', () => {
    it('renders children correctly', () => {
      render(<Button>Click me</Button>);
      expect(screen.getByRole('button', { name: 'Click me' })).toBeInTheDocument();
    });

    it('renders with default props', () => {
      render(<Button>Default</Button>);
      const button = screen.getByRole('button');
      expect(button).toHaveClass('btn-theme');
      expect(button).toHaveClass('btn-theme-primary');
      expect(button).toHaveClass('btn-theme-md');
    });
  });

  describe('variants', () => {
    it.each([
      ['primary', 'btn-theme-primary'],
      ['secondary', 'btn-theme-secondary'],
      ['danger', 'btn-theme-danger'],
      ['success', 'btn-theme-success'],
      ['warning', 'btn-theme-warning'],
      ['ghost', 'btn-theme-ghost'],
      ['outline', 'btn-theme-outline'],
    ])('renders %s variant correctly', (variant, expectedClass) => {
      render(<Button variant={variant as any}>Button</Button>);
      expect(screen.getByRole('button')).toHaveClass(expectedClass);
    });
  });

  describe('sizes', () => {
    it.each([
      ['xs', 'btn-theme-xs'],
      ['sm', 'btn-theme-sm'],
      ['md', 'btn-theme-md'],
      ['lg', 'btn-theme-lg'],
      ['xl', 'btn-theme-xl'],
    ])('renders %s size correctly', (size, expectedClass) => {
      render(<Button size={size as any}>Button</Button>);
      expect(screen.getByRole('button')).toHaveClass(expectedClass);
    });
  });

  describe('states', () => {
    it('disables button when disabled prop is true', () => {
      render(<Button disabled>Disabled</Button>);
      expect(screen.getByRole('button')).toBeDisabled();
    });

    it('disables button when loading', () => {
      render(<Button loading>Loading</Button>);
      expect(screen.getByRole('button')).toBeDisabled();
    });

    it('shows loading spinner when loading', () => {
      render(<Button loading>Loading</Button>);
      expect(screen.getByRole('button').querySelector('svg')).toBeInTheDocument();
    });

    it('applies loading class when loading', () => {
      render(<Button loading>Loading</Button>);
      expect(screen.getByRole('button')).toHaveClass('btn-theme-loading');
    });
  });

  describe('fullWidth', () => {
    it('applies full width class when fullWidth is true', () => {
      render(<Button fullWidth>Full Width</Button>);
      expect(screen.getByRole('button')).toHaveClass('btn-theme-full');
    });

    it('does not apply full width class by default', () => {
      render(<Button>Normal</Button>);
      expect(screen.getByRole('button')).not.toHaveClass('btn-theme-full');
    });
  });

  describe('iconOnly', () => {
    it('applies icon-only classes when iconOnly is true', () => {
      render(<Button iconOnly size="md">X</Button>);
      const button = screen.getByRole('button');
      expect(button).toHaveClass('btn-theme-icon-md');
      expect(button).toHaveClass('bg-transparent');
    });
  });

  describe('rounded', () => {
    it.each([
      ['md', 'rounded-md'],
      ['lg', 'rounded-lg'],
      ['xl', 'rounded-xl'],
      ['full', 'rounded-full'],
    ])('applies %s rounded class', (rounded, expectedClass) => {
      render(<Button rounded={rounded as any}>Button</Button>);
      expect(screen.getByRole('button')).toHaveClass(expectedClass);
    });
  });

  describe('pulse', () => {
    it('applies pulse animation when pulse is true and not disabled', () => {
      render(<Button pulse>Pulse</Button>);
      expect(screen.getByRole('button')).toHaveClass('animate-pulse');
    });

    it('does not apply pulse animation when disabled', () => {
      render(<Button pulse disabled>Pulse</Button>);
      expect(screen.getByRole('button')).not.toHaveClass('animate-pulse');
    });
  });

  describe('interactions', () => {
    it('calls onClick handler when clicked', () => {
      const handleClick = jest.fn();
      render(<Button onClick={handleClick}>Click</Button>);
      fireEvent.click(screen.getByRole('button'));
      expect(handleClick).toHaveBeenCalledTimes(1);
    });

    it('does not call onClick when disabled', () => {
      const handleClick = jest.fn();
      render(<Button onClick={handleClick} disabled>Click</Button>);
      fireEvent.click(screen.getByRole('button'));
      expect(handleClick).not.toHaveBeenCalled();
    });

    it('does not call onClick when loading', () => {
      const handleClick = jest.fn();
      render(<Button onClick={handleClick} loading>Click</Button>);
      fireEvent.click(screen.getByRole('button'));
      expect(handleClick).not.toHaveBeenCalled();
    });
  });

  describe('ref forwarding', () => {
    it('forwards ref correctly', () => {
      const ref = React.createRef<HTMLButtonElement>();
      render(<Button ref={ref}>Ref Button</Button>);
      expect(ref.current).toBeInstanceOf(HTMLButtonElement);
    });
  });

  describe('custom className', () => {
    it('merges custom className with default classes', () => {
      render(<Button className="custom-class">Custom</Button>);
      const button = screen.getByRole('button');
      expect(button).toHaveClass('custom-class');
      expect(button).toHaveClass('btn-theme');
    });
  });

  describe('HTML attributes', () => {
    it('passes through HTML button attributes', () => {
      render(<Button type="submit" name="submit-btn" data-testid="test">Submit</Button>);
      const button = screen.getByRole('button');
      expect(button).toHaveAttribute('type', 'submit');
      expect(button).toHaveAttribute('name', 'submit-btn');
      expect(button).toHaveAttribute('data-testid', 'test');
    });
  });
});
