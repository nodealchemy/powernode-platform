import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { DropdownMenu, DropdownMenuItem } from './DropdownMenu';
import { Settings, Trash2 } from 'lucide-react';

describe('DropdownMenu', () => {
  const defaultItems: DropdownMenuItem[] = [
    { label: 'Edit', onClick: jest.fn() },
    { label: 'Settings', icon: Settings, onClick: jest.fn() },
    { label: 'Delete', icon: Trash2, danger: true, onClick: jest.fn() },
  ];

  const defaultTrigger = <button>Open Menu</button>;

  const renderDropdown = (
    items: DropdownMenuItem[] = defaultItems,
    props: Partial<React.ComponentProps<typeof DropdownMenu>> = {}
  ) => {
    return render(
      <DropdownMenu trigger={defaultTrigger} items={items} {...props} />
    );
  };

  describe('rendering', () => {
    it('renders trigger element', () => {
      renderDropdown();

      expect(screen.getByText('Open Menu')).toBeInTheDocument();
    });

    it('does not show menu by default', () => {
      renderDropdown();

      expect(screen.queryByText('Edit')).not.toBeInTheDocument();
    });

    it('shows menu when trigger clicked', () => {
      renderDropdown();

      fireEvent.click(screen.getByText('Open Menu'));

      expect(screen.getByText('Edit')).toBeInTheDocument();
      expect(screen.getByText('Settings')).toBeInTheDocument();
      expect(screen.getByText('Delete')).toBeInTheDocument();
    });

    it('applies custom className', () => {
      const { container } = renderDropdown(defaultItems, { className: 'custom-class' });

      expect(container.firstChild).toHaveClass('custom-class');
    });
  });

  describe('menu items', () => {
    it('renders item with icon', () => {
      renderDropdown();
      fireEvent.click(screen.getByText('Open Menu'));

      const settingsButton = screen.getByText('Settings').closest('button');
      expect(settingsButton?.querySelector('svg')).toBeInTheDocument();
    });

    it('calls onClick when item clicked', () => {
      const onClick = jest.fn();
      const items: DropdownMenuItem[] = [
        { label: 'Click Me', onClick },
      ];

      renderDropdown(items);
      fireEvent.click(screen.getByText('Open Menu'));
      fireEvent.click(screen.getByText('Click Me'));

      expect(onClick).toHaveBeenCalled();
    });

    it('closes menu after item click', () => {
      renderDropdown();

      fireEvent.click(screen.getByText('Open Menu'));
      expect(screen.getByText('Edit')).toBeInTheDocument();

      fireEvent.click(screen.getByText('Edit'));
      expect(screen.queryByText('Edit')).not.toBeInTheDocument();
    });

    it('renders danger item with error styling', () => {
      renderDropdown();
      fireEvent.click(screen.getByText('Open Menu'));

      const deleteButton = screen.getByText('Delete').closest('button');
      expect(deleteButton).toHaveClass('text-theme-error-fg');
    });
  });

  describe('disabled items', () => {
    it('renders disabled item', () => {
      const items: DropdownMenuItem[] = [
        { label: 'Disabled Item', disabled: true },
      ];

      renderDropdown(items);
      fireEvent.click(screen.getByText('Open Menu'));

      const button = screen.getByText('Disabled Item').closest('button');
      expect(button).toBeDisabled();
    });

    it('does not call onClick for disabled items', () => {
      const onClick = jest.fn();
      const items: DropdownMenuItem[] = [
        { label: 'Disabled', disabled: true, onClick },
      ];

      renderDropdown(items);
      fireEvent.click(screen.getByText('Open Menu'));
      fireEvent.click(screen.getByText('Disabled'));

      expect(onClick).not.toHaveBeenCalled();
    });

    it('has disabled styling', () => {
      const items: DropdownMenuItem[] = [
        { label: 'Disabled', disabled: true },
      ];

      renderDropdown(items);
      fireEvent.click(screen.getByText('Open Menu'));

      const button = screen.getByText('Disabled').closest('button');
      expect(button).toHaveClass('cursor-not-allowed', 'opacity-50');
    });
  });

  describe('divider', () => {
    it('renders divider between items', () => {
      const items: DropdownMenuItem[] = [
        { label: 'Item 1', onClick: jest.fn() },
        { label: 'divider', divider: true },
        { label: 'Item 2', onClick: jest.fn() },
      ];

      renderDropdown(items);
      fireEvent.click(screen.getByText('Open Menu'));

      // Divider has border-t class
      const divider = document.querySelector('[class*="border-t"][class*="my-1"]');
      expect(divider).toBeInTheDocument();
    });
  });

  describe('alignment', () => {
    // The menu is portaled to document.body and positioned via fixed inline
    // styles (computed from the trigger's bounding rect), not Tailwind
    // absolute/left-0/right-0 classes. Right-align anchors the menu's right
    // edge (inline `right` set, `left` unset); left-align anchors the left
    // edge (inline `left` set, `right` unset).
    it('aligns right by default', () => {
      renderDropdown();
      fireEvent.click(screen.getByText('Open Menu'));

      const menu = document.querySelector<HTMLElement>('.z-\\[10000\\]');
      expect(menu).toBeInTheDocument();
      expect(menu?.style.position).toBe('fixed');
      expect(menu?.style.right).not.toBe('');
      expect(menu?.style.left).toBe('');
    });

    it('aligns left when specified', () => {
      renderDropdown(defaultItems, { align: 'left' });
      fireEvent.click(screen.getByText('Open Menu'));

      const menu = document.querySelector<HTMLElement>('.z-\\[10000\\]');
      expect(menu).toBeInTheDocument();
      expect(menu?.style.position).toBe('fixed');
      expect(menu?.style.left).not.toBe('');
      expect(menu?.style.right).toBe('');
    });
  });

  describe('width', () => {
    // Width is applied as an inline style on the portaled menu, resolved from
    // the Tailwind `w-N` shorthand to rem (N * 0.25rem), rather than emitting
    // the `w-N` class directly. Default `w-48` -> 12rem; `w-64` -> 16rem.
    it('uses default width', () => {
      renderDropdown();
      fireEvent.click(screen.getByText('Open Menu'));

      const menu = document.querySelector<HTMLElement>('.z-\\[10000\\]');
      expect(menu).toBeInTheDocument();
      expect(menu?.style.width).toBe('12rem');
    });

    it('uses custom width', () => {
      renderDropdown(defaultItems, { width: 'w-64' });
      fireEvent.click(screen.getByText('Open Menu'));

      const menu = document.querySelector<HTMLElement>('.z-\\[10000\\]');
      expect(menu).toBeInTheDocument();
      expect(menu?.style.width).toBe('16rem');
    });
  });

  describe('closing behavior', () => {
    it('closes on escape key', () => {
      renderDropdown();

      fireEvent.click(screen.getByText('Open Menu'));
      expect(screen.getByText('Edit')).toBeInTheDocument();

      fireEvent.keyDown(document, { key: 'Escape' });
      expect(screen.queryByText('Edit')).not.toBeInTheDocument();
    });

    it('closes on click outside', () => {
      renderDropdown();

      fireEvent.click(screen.getByText('Open Menu'));
      expect(screen.getByText('Edit')).toBeInTheDocument();

      fireEvent.mouseDown(document.body);
      expect(screen.queryByText('Edit')).not.toBeInTheDocument();
    });

    it('toggles on trigger click', () => {
      renderDropdown();

      // Open
      fireEvent.click(screen.getByText('Open Menu'));
      expect(screen.getByText('Edit')).toBeInTheDocument();

      // Close
      fireEvent.click(screen.getByText('Open Menu'));
      expect(screen.queryByText('Edit')).not.toBeInTheDocument();
    });
  });

  describe('accessibility', () => {
    it('sets aria-expanded on trigger', () => {
      renderDropdown();

      fireEvent.click(screen.getByText('Open Menu'));

      const trigger = screen.getByText('Open Menu');
      expect(trigger).toHaveAttribute('aria-expanded', 'true');
    });

    it('sets aria-haspopup on trigger', () => {
      renderDropdown();

      fireEvent.click(screen.getByText('Open Menu'));

      const trigger = screen.getByText('Open Menu');
      expect(trigger).toHaveAttribute('aria-haspopup', 'true');
    });
  });
});
