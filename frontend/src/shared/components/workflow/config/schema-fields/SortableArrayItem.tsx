import React from 'react';
import { ChevronUp, ChevronDown } from 'lucide-react';

interface SortableArrayItemProps {
  index: number;
  totalItems: number;
  onMoveUp?: () => void;
  onMoveDown?: () => void;
  disabled?: boolean;
  children: React.ReactNode;
}

/**
 * Wrapper component for array items that provides up/down reordering controls.
 * Uses simple button-based reordering instead of drag-and-drop for accessibility.
 */
export const SortableArrayItem: React.FC<SortableArrayItemProps> = ({
  index,
  totalItems,
  onMoveUp,
  onMoveDown,
  disabled = false,
  children,
}) => {
  return (
    <div className="relative group">
      {/* Reorder controls - shown on hover */}
      {!disabled && totalItems > 1 && (
        <div className="absolute left-0 top-1/2 -translate-y-1/2 -translate-x-full pr-1 opacity-0 group-hover:opacity-100 transition-opacity flex flex-col">
          <button
            type="button"
            onClick={onMoveUp}
            disabled={!onMoveUp}
            className={`p-0.5 rounded text-theme-tertiary hover:text-theme-primary hover:bg-theme-hover transition-colors ${
              !onMoveUp ? 'opacity-30 cursor-not-allowed' : ''
            }`}
            title={`Move item ${index + 1} up`}
            aria-label={`Move item ${index + 1} up`}
          >
            <ChevronUp className="h-4 w-4" />
          </button>
          <button
            type="button"
            onClick={onMoveDown}
            disabled={!onMoveDown}
            className={`p-0.5 rounded text-theme-tertiary hover:text-theme-primary hover:bg-theme-hover transition-colors ${
              !onMoveDown ? 'opacity-30 cursor-not-allowed' : ''
            }`}
            title={`Move item ${index + 1} down`}
            aria-label={`Move item ${index + 1} down`}
          >
            <ChevronDown className="h-4 w-4" />
          </button>
        </div>
      )}

      {/* Item content */}
      {children}
    </div>
  );
};

export default SortableArrayItem;
