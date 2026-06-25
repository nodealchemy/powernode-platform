import React, { useState, useRef, useEffect, useCallback } from 'react';
import { createPortal } from 'react-dom';
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
  const [position, setPosition] = useState<{ top: number; left: number; right: number } | null>(null);
  // Per-item armed state for destructive actions. Per platform convention
  // (memory `feedback_destructive_confirm`), items with `danger: true`
  // require two clicks: first arms with visual change, second within the
  // arm window commits. Keyed by `${groupIndex}-${itemIndex}` so a menu
  // with multiple danger items tracks each independently.
  const [armedKey, setArmedKey] = useState<string | null>(null);
  const armTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const ARM_WINDOW_MS = 5000;
  const triggerWrapRef = useRef<HTMLDivElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);

  const disarm = useCallback(() => {
    setArmedKey(null);
    if (armTimerRef.current) {
      clearTimeout(armTimerRef.current);
      armTimerRef.current = null;
    }
  }, []);

  // Disarm on close
  useEffect(() => {
    if (!isOpen) disarm();
  }, [isOpen, disarm]);

  // Cleanup timer on unmount
  useEffect(() => () => { if (armTimerRef.current) clearTimeout(armTimerRef.current); }, []);

  const visibleItems = items.filter((i) => i.divider || i.label || i.icon);

  const computePosition = useCallback(() => {
    const trig = triggerWrapRef.current;
    if (!trig) return;
    const rect = trig.getBoundingClientRect();
    setPosition({
      top: rect.bottom + 8, // mt-2 equivalent
      left: rect.left,
      right: window.innerWidth - rect.right,
    });
  }, []);

  useEffect(() => {
    if (!isOpen) return;
    computePosition();
    window.addEventListener('scroll', computePosition, true);
    window.addEventListener('resize', computePosition);
    return () => {
      window.removeEventListener('scroll', computePosition, true);
      window.removeEventListener('resize', computePosition);
    };
  }, [isOpen, computePosition]);

  // Close on outside click. Includes the menu itself in the "inside" check
  // since the menu is portaled to body and otherwise wouldn't be a descendant
  // of the trigger wrapper.
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      const target = event.target as Node;
      if (
        triggerWrapRef.current?.contains(target) ||
        menuRef.current?.contains(target)
      ) return;
      setIsOpen(false);
    };

    if (isOpen) {
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

  // If every item disappears while the menu is open, close it. The component
  // renders null when empty (below); without this, isOpen would persist and the
  // menu would reappear already-open if items later return.
  useEffect(() => {
    if (isOpen && visibleItems.length === 0) setIsOpen(false);
  }, [isOpen, visibleItems.length]);

  // Don't render the trigger at all when there are no actions to show.
  // Previously this rendered an empty popup on click, which surfaced as an
  // unclickable artifact for messages with no available actions. This guard
  // MUST come after every hook above so the hook order stays identical across
  // renders (Rules of Hooks) — `items` can change from populated to empty.
  if (visibleItems.length === 0) return null;

  const handleItemClick = (item: DropdownMenuItem, key: string) => {
    if (item.disabled) return;

    // Arm-and-confirm for destructive items. First click arms with visual
    // change; second click within ARM_WINDOW_MS commits. The dropdown stays
    // open during the armed state so the user can see the warning.
    if (item.danger && armedKey !== key) {
      setArmedKey(key);
      if (armTimerRef.current) clearTimeout(armTimerRef.current);
      armTimerRef.current = setTimeout(() => {
        setArmedKey((prev) => (prev === key ? null : prev));
        armTimerRef.current = null;
      }, ARM_WINDOW_MS);
      return;
    }

    if (armTimerRef.current) {
      clearTimeout(armTimerRef.current);
      armTimerRef.current = null;
    }
    setArmedKey(null);

    if (item.onClick) {
      item.onClick();
    }

    if (item.href) {
      window.location.href = item.href;
    }

    setIsOpen(false);
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

  const columnGroups = groupItemsForColumns(visibleItems, columns);
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

    const isArmed = item.danger && armedKey === key;
    const displayLabel = isArmed ? `Click to confirm ${item.label.toLowerCase()}` : item.label;

    return (
      <button
        key={key}
        onClick={() => handleItemClick(item, key)}
        disabled={item.disabled}
        data-menu-item={item.label}
        data-armed={isArmed ? 'true' : undefined}
        className={`
          w-full flex items-center px-3 py-2 text-sm text-left transition-colors duration-150
          ${item.disabled
            ? 'text-theme-tertiary cursor-not-allowed opacity-50'
            : isArmed
              ? 'bg-theme-error-bg text-white font-medium'
              : item.danger
                ? 'text-theme-error-fg hover:bg-theme-error-bg'
                : 'text-theme-primary hover:bg-theme-surface-hover'
          }
        `}
      >
        {item.icon && (
          <div className={`mr-2 h-4 w-4 flex-shrink-0 ${
            item.disabled
              ? 'text-theme-tertiary'
              : isArmed
                ? 'text-white'
                : item.danger
                  ? 'text-theme-error-fg'
                  : 'text-theme-secondary'
          }`}>
            <item.icon className="h-4 w-4" />
          </div>
        )}
        <span className="truncate">{displayLabel}</span>
      </button>
    );
  };

  // Resolve width string ("w-48" → 12rem) for the portaled menu's inline
  // style. Tailwind class shorthand maps to 0.25rem * N.
  const widthMatch = /^w-(\d+)$/.exec(width);
  const widthRem = widthMatch ? `${parseInt(widthMatch[1], 10) * 0.25}rem` : undefined;

  // Position the portaled menu relative to the viewport. Use right-align
  // when the prop says so to keep the dropdown anchored to the trigger's
  // right edge (typical for action menus floating off message bubbles).
  const menuStyle: React.CSSProperties = position
    ? {
        position: 'fixed',
        top: position.top,
        ...(align === 'right' ? { right: position.right } : { left: position.left }),
        width: widthRem,
      }
    : { display: 'none' };

  return (
    <>
      <div className={`relative inline-flex ${className}`} ref={triggerWrapRef}>
        <div onClick={(e) => {
          e.stopPropagation();
          setIsOpen(!isOpen);
        }}>
          {React.cloneElement(trigger as React.ReactElement<Record<string, unknown>>, {
            'aria-expanded': isOpen,
            'aria-haspopup': true
          })}
        </div>
      </div>

      {isOpen && createPortal(
        <div
          ref={menuRef}
          style={menuStyle}
          className="bg-theme-background border border-theme rounded-lg shadow-xl py-1 z-[10000]"
        >
          <div className={`grid ${columnClasses[columns as keyof typeof columnClasses] || 'grid-cols-1'} gap-1`}>
            {columnGroups.map((group, groupIndex) => (
              <div key={groupIndex} className="flex flex-col">
                {group.map((item, itemIndex) => renderMenuItem(item, itemIndex, groupIndex))}
              </div>
            ))}
          </div>
        </div>,
        document.body
      )}
    </>
  );
};

export default DropdownMenu;
