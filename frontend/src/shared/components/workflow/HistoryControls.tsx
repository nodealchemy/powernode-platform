import React from 'react';
import { Undo2, Redo2, History } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';

export interface HistoryControlsProps {
  canUndo: boolean;
  canRedo: boolean;
  onUndo: () => void;
  onRedo: () => void;
  historySize?: number;
  currentIndex?: number;
  className?: string;
}

export const HistoryControls: React.FC<HistoryControlsProps> = ({
  canUndo,
  canRedo,
  onUndo,
  onRedo,
  historySize = 0,
  currentIndex = 0,
  className = ''
}) => {
  return (
    <div className={`flex items-center gap-1 ${className}`}>
      {/* Undo Button */}
      <Button
        variant="ghost"
        size="sm"
        onClick={onUndo}
        disabled={!canUndo}
        title={`Undo (Ctrl+Z) - ${currentIndex} steps back available`}
        className="relative group"
      >
        <Undo2 className="h-4 w-4" />
        <span className="sr-only">Undo</span>

        {/* Tooltip */}
        {canUndo && (
          <div className="absolute bottom-full left-1/2 -translate-x-1/2 mb-2 px-2 py-1 bg-theme-surface-tooltip text-theme-primary text-xs rounded shadow-lg opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap pointer-events-none">
            Undo (Ctrl+Z)
          </div>
        )}
      </Button>

      {/* Redo Button */}
      <Button
        variant="ghost"
        size="sm"
        onClick={onRedo}
        disabled={!canRedo}
        title={`Redo (Ctrl+Y) - ${historySize - currentIndex - 1} steps forward available`}
        className="relative group"
      >
        <Redo2 className="h-4 w-4" />
        <span className="sr-only">Redo</span>

        {/* Tooltip */}
        {canRedo && (
          <div className="absolute bottom-full left-1/2 -translate-x-1/2 mb-2 px-2 py-1 bg-theme-surface-tooltip text-theme-primary text-xs rounded shadow-lg opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap pointer-events-none">
            Redo (Ctrl+Y)
          </div>
        )}
      </Button>

      {/* History Indicator */}
      <div className="flex items-center gap-1 px-2 text-xs text-theme-secondary">
        <History className="h-3 w-3" />
        <span>{currentIndex + 1}/{historySize}</span>
      </div>
    </div>
  );
};
