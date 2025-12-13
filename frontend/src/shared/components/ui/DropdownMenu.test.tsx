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
      expect(deleteButton).toHaveClass('text-theme-error');
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
    it('aligns right by default', () => {
      renderDropdown();
      fireEvent.click(screen.getByText('Open Menu'));

      const menu = document.querySelector('.absolute.right-0');
      expect(menu).toBeInTheDocument();
    });

    it('aligns left when specified', () => {
      renderDropdown(defaultItems, { align: 'left' });
      fireEvent.click(screen.getByText('Open Menu'));

      const menu = document.querySelector('.absolute.left-0');
      expect(menu).toBeInTheDocument();
    });
  });

  describe('width', () => {
    it('uses default width', () => {
      renderDropdown();
      fireEvent.click(screen.getByText('Open Menu'));

      const menu = document.querySelector('.w-48');
      expect(menu).toBeInTheDocument();
    });

    it('uses custom width', () => {
      renderDropdown(defaultItems, { width: 'w-64' });
      fireEvent.click(screen.getByText('Open Menu'));

      const menu = document.querySelector('.w-64');
      expect(menu).toBeInTheDocument();
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
