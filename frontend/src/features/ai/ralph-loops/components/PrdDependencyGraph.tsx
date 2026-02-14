import React from 'react';
import { Search, FileText } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';

interface PrdDependencyGraphProps {
  taskCount: number;
  filteredCount: number;
  searchQuery: string;
  onSearchQueryChange: (query: string) => void;
  showSearch: boolean;
}

export const PrdDependencyGraph: React.FC<PrdDependencyGraphProps> = ({
  taskCount,
  filteredCount,
  searchQuery,
  onSearchQueryChange,
  showSearch,
}) => {
  return (
    <>
      {/* Search Bar */}
      {showSearch && (
        <div className="relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-theme-text-secondary" />
          <Input
            value={searchQuery}
            onChange={(e) => onSearchQueryChange(e.target.value)}
            placeholder="Search tasks..."
            className="pl-9"
          />
        </div>
      )}

      {/* Empty State */}
      {taskCount === 0 && (
        <div className="text-center py-12 text-theme-text-secondary">
          <FileText className="w-12 h-12 mx-auto mb-4 opacity-50" />
          <p className="font-medium">No tasks defined yet</p>
          <p className="text-sm mt-1">
            Click &quot;Add Task&quot; to create your first task, or import from JSON.
          </p>
        </div>
      )}

      {/* Search Empty State */}
      {taskCount > 0 && filteredCount === 0 && searchQuery && (
        <div className="text-center py-8 text-theme-text-secondary">
          <Search className="w-8 h-8 mx-auto mb-3 opacity-50" />
          <p>No tasks match &quot;{searchQuery}&quot;</p>
          <Button variant="ghost" size="sm" onClick={() => onSearchQueryChange('')} className="mt-2">
            Clear search
          </Button>
        </div>
      )}
    </>
  );
};
