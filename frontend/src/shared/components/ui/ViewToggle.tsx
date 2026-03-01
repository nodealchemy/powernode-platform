import React from 'react';
import { LayoutGrid, List } from 'lucide-react';
import { cn } from '@/shared/utils/cn';

interface ViewToggleProps {
  viewMode: 'grid' | 'list';
  onViewModeChange: (mode: 'grid' | 'list') => void;
}

export const ViewToggle: React.FC<ViewToggleProps> = ({ viewMode, onViewModeChange }) => (
  <div className="flex items-center gap-1 border border-theme rounded-md overflow-hidden">
    <button
      type="button"
      onClick={() => onViewModeChange('grid')}
      className={cn(
        'p-1.5 transition-colors',
        viewMode === 'grid' ? 'bg-theme-interactive-primary text-white' : 'bg-theme-surface text-theme-secondary hover:text-theme-primary'
      )}
      title="Grid view"
    >
      <LayoutGrid size={16} />
    </button>
    <button
      type="button"
      onClick={() => onViewModeChange('list')}
      className={cn(
        'p-1.5 transition-colors',
        viewMode === 'list' ? 'bg-theme-interactive-primary text-white' : 'bg-theme-surface text-theme-secondary hover:text-theme-primary'
      )}
      title="List view"
    >
      <List size={16} />
    </button>
  </div>
);
