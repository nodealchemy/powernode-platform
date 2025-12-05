import React, { useState, useRef, useEffect } from 'react';
import { LucideIcon } from 'lucide-react';

export interface DropdownMenuItem {
  icon?: LucideIcon;
  label: string;
  onClick?: () => void;
  href?: string;
  disabled?: boolean;
  danger?: boolean;
  divider?: boolean;
}

export interface DropdownMenuProps {
  trigger: React.ReactElement;
  items: DropdownMenuItem[];
  align?: 'left' | 'right';
  width?: string;
  className?: string;
  columns?: number;
}

export const DropdownMenu: React.FC<DropdownMenuProps> = ({
  trigger,
  items,
  align = 'right',
  width = 'w-48',
  className = '',
  columns = 1
}) => {
  const [isOpen, setIsOpen] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  // Close dropdown when clicking outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };

    if (isOpen) {
      // Use capture phase to ensure we catch the event before React Flow or other components
      // might call stopPropagation()
      document.addEventListener('mousedown', handleClickOutside, true);
      document.addEventListener('click', handleClickOutside, true);
      return () => {
        document.removeEventListener('mousedown', handleClickOutside, true);
        document.removeEventListener('click', handleClickOutside, true);
      };
    }
  }, [isOpen]);

  // Close dropdown on escape key
  useEffect(() => {
    const handleEscapeKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        setIsOpen(false);
      }
    };

    if (isOpen) {
      document.addEventListener('keydown', handleEscapeKey);
      return () => {
        document.removeEventListener('keydown', handleEscapeKey);
      };
    }
  }, [isOpen]);

  const handleItemClick = (item: DropdownMenuItem) => {
    if (item.disabled) return;
    
    if (item.onClick) {
      item.onClick();
    }
    
    if (item.href) {
      window.location.href = item.href;
    }
    
    setIsOpen(false);
  };

  const alignmentClasses = {
    left: 'left-0',
    right: 'right-0'
  };

  // Group items for multi-column layout
  const groupItemsForColumns = (items: DropdownMenuItem[], columns: number) => {
    if (columns === 1) return [items];

    const itemsPerColumn = Math.ceil(items.length / columns);
    const groups: DropdownMenuItem[][] = [];

    for (let i = 0; i < columns; i++) {
      const start = i * itemsPerColumn;
      const end = start + itemsPerColumn;
      groups.push(items.slice(start, end));
    }

    return groups;
  };

  const columnGroups = groupItemsForColumns(items, columns);
  const columnClasses = {
    1: 'grid-cols-1',
    2: 'grid-cols-2',
    3: 'grid-cols-3'
  };

  const renderMenuItem = (item: DropdownMenuItem, index: number, groupIndex: number) => {
    const key = `${groupIndex}-${index}`;

    // Skip empty/spacer items
    if (!item.label && !item.icon) {
      return <div key={key} className="h-2" />; // Small spacer
    }

    // Render divider
    if (item.divider) {
      return (
        <div key={key} className="border-t border-theme my-1 col-span-full" />
      );
    }

    return (
      <button
        key={key}
        onClick={() => handleItemClick(item)}
        disabled={item.disabled}
        data-menu-item={item.label}
        className={`
          w-full flex items-center px-3 py-2 text-sm text-left transition-colors duration-150
          ${item.disabled
            ? 'text-theme-tertiary cursor-not-allowed opacity-50'
            : item.danger
              ? 'text-theme-error hover:bg-theme-error-background'
              : 'text-theme-primary hover:bg-theme-surface-hover'
          }
        `}
      >
        {item.icon && (
          <div className={`mr-2 h-4 w-4 flex-shrink-0 ${
            item.disabled
              ? 'text-theme-tertiary'
              : item.danger
                ? 'text-theme-error'
                : 'text-theme-secondary'
          }`}>
            <item.icon className="h-4 w-4" />
          </div>
        )}
        <span className="truncate">{item.label}</span>
      </button>
    );
  };

  return (
    <div className={`relative ${className}`} ref={dropdownRef}>
      {/* Trigger */}
      <div onClick={(e) => {
        e.stopPropagation();
        setIsOpen(!isOpen);
      }}>
        {React.cloneElement(trigger as React.ReactElement<any>, {
          'aria-expanded': isOpen,
          'aria-haspopup': true
        })}
      </div>

      {/* Dropdown Menu */}
      {isOpen && (
        <div
          className={`
            absolute mt-2 ${width} bg-theme-surface rounded-lg shadow-lg border border-theme z-[9999] py-1
            ${alignmentClasses[align]}
          `}
        >
          <div className={`grid ${columnClasses[columns as keyof typeof columnClasses] || 'grid-cols-1'} gap-1`}>
            {columnGroups.map((group, groupIndex) => (
              <div key={groupIndex} className="flex flex-col">
                {group.map((item, itemIndex) => renderMenuItem(item, itemIndex, groupIndex))}
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
};

export default DropdownMenu;