import React, { useState } from 'react';
import { Eye, Edit3 } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { cn } from '@/shared/utils/cn';
import { RalphTaskList } from './RalphTaskList';
import { RalphPrdEditor } from './RalphPrdEditor';
import type { PrdTask, RalphTaskSummary } from '@/shared/services/ai/types/ralph-types';

interface RalphTasksPanelProps {
  loopId: string;
  tasks: PrdTask[];
  onTasksChange: (tasks: PrdTask[]) => void;
  onSave: () => Promise<void>;
  isRunning?: boolean;
  onSelectTask?: (task: RalphTaskSummary) => void;
  className?: string;
}

type ViewMode = 'view' | 'edit';

export const RalphTasksPanel: React.FC<RalphTasksPanelProps> = ({
  loopId,
  tasks,
  onTasksChange,
  onSave,
  isRunning = false,
  onSelectTask,
  className,
}) => {
  const [mode, setMode] = useState<ViewMode>('view');

  return (
    <div className={cn('space-y-4', className)}>
      {/* Mode Toggle */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-1 p-1 bg-theme-bg-secondary rounded-lg">
          <Button
            variant={mode === 'view' ? 'primary' : 'ghost'}
            size="sm"
            onClick={() => setMode('view')}
            className="flex items-center gap-2"
          >
            <Eye className="w-4 h-4" />
            View
          </Button>
          <Button
            variant={mode === 'edit' ? 'primary' : 'ghost'}
            size="sm"
            onClick={() => setMode('edit')}
            disabled={isRunning}
            className="flex items-center gap-2"
            title={isRunning ? 'Cannot edit while loop is running' : 'Edit PRD tasks'}
          >
            <Edit3 className="w-4 h-4" />
            Edit
          </Button>
        </div>

        {mode === 'view' && (
          <p className="text-xs text-theme-text-secondary">
            Showing task execution status
          </p>
        )}
        {mode === 'edit' && (
          <p className="text-xs text-theme-text-secondary">
            {isRunning ? 'Editing disabled while running' : 'Edit PRD task definitions'}
          </p>
        )}
      </div>

      {/* Content */}
      {mode === 'view' ? (
        <RalphTaskList
          loopId={loopId}
          onSelectTask={onSelectTask}
        />
      ) : (
        <RalphPrdEditor
          tasks={tasks}
          onChange={onTasksChange}
          onSave={onSave}
          readOnly={isRunning}
        />
      )}
    </div>
  );
};

export default RalphTasksPanel;
