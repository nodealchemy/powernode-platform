import React from 'react';
import { Plus, X, Loader2 } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Card, CardContent } from '@/shared/components/ui/Card';
import type { PrdTask } from '@/shared/services/ai/types/ralph-types';

interface RalphTaskEditFormProps {
  newTask: PrdTask;
  onNewTaskChange: (task: PrdTask) => void;
  onAddTask: () => void;
  onClose: () => void;
  isSaving: boolean;
}

export const RalphTaskEditForm: React.FC<RalphTaskEditFormProps> = ({
  newTask,
  onNewTaskChange,
  onAddTask,
  onClose,
  isSaving,
}) => {
  return (
    <Card className="border-dashed border-2 border-theme-status-info/50">
      <CardContent className="p-4 space-y-3">
        <div className="flex items-center justify-between">
          <span className="text-sm font-medium text-theme-text-primary">New Task</span>
          <Button variant="ghost" size="sm" onClick={onClose}>
            <X className="w-4 h-4" />
          </Button>
        </div>
        <div className="grid grid-cols-[120px_1fr] gap-3 items-start">
          <label className="text-sm text-theme-text-secondary pt-2">Task Key</label>
          <Input
            value={newTask.key}
            onChange={(e) => onNewTaskChange({ ...newTask, key: e.target.value })}
            placeholder="task_key"
            className="font-mono"
          />
        </div>
        <div className="grid grid-cols-[120px_1fr] gap-3 items-start">
          <label className="text-sm text-theme-text-secondary pt-2">Description</label>
          <Textarea
            value={newTask.description}
            onChange={(e) => onNewTaskChange({ ...newTask, description: e.target.value })}
            placeholder="Task description..."
            rows={2}
          />
        </div>
        <div className="grid grid-cols-[120px_1fr] gap-3 items-start">
          <label className="text-sm text-theme-text-secondary pt-2">Dependencies</label>
          <Input
            value={newTask.dependencies?.join(', ') || ''}
            onChange={(e) => onNewTaskChange({
              ...newTask,
              dependencies: e.target.value.split(',').map(d => d.trim()).filter(Boolean)
            })}
            placeholder="task_1, task_2"
          />
        </div>
        <div className="grid grid-cols-[120px_1fr] gap-3 items-start">
          <label className="text-sm text-theme-text-secondary pt-2">Acceptance</label>
          <Input
            value={newTask.acceptance_criteria || ''}
            onChange={(e) => onNewTaskChange({ ...newTask, acceptance_criteria: e.target.value })}
            placeholder="Acceptance criteria..."
          />
        </div>
        <div className="flex justify-end gap-2 pt-2">
          <Button variant="ghost" size="sm" onClick={onClose}>
            Cancel
          </Button>
          <Button
            variant="primary"
            size="sm"
            onClick={onAddTask}
            disabled={!newTask.key.trim() || isSaving}
          >
            {isSaving ? (
              <Loader2 className="w-4 h-4 mr-1 animate-spin" />
            ) : (
              <Plus className="w-4 h-4 mr-1" />
            )}
            Add Task
          </Button>
        </div>
      </CardContent>
    </Card>
  );
};
