import React from 'react';
import {
  Trash2,
  GripVertical,
  ChevronDown,
  ChevronRight,
  Copy,
  Link,
  AlertTriangle,
  CheckCircle2,
  Circle,
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { cn } from '@/shared/utils/cn';
import type { PrdTask } from '@/shared/services/ai/types/ralph-types';

interface PrdTaskRowProps {
  task: PrdTask;
  actualIndex: number;
  isExpanded: boolean;
  warnings?: string[];
  isDragging: boolean;
  isDragOver: boolean;
  readOnly: boolean;
  onToggleExpanded: (key: string) => void;
  onUpdateTask: (index: number, updates: Partial<PrdTask>) => void;
  onRemoveTask: (index: number) => void;
  onDuplicateTask: (index: number) => void;
  onDragStart: (e: React.DragEvent, index: number) => void;
  onDragOver: (e: React.DragEvent, index: number) => void;
  onDragEnd: () => void;
}

const getTaskStatusIcon = (task: PrdTask) => {
  if (!task.description) {
    return <Circle className="w-4 h-4 text-theme-text-secondary" />;
  }
  return <CheckCircle2 className="w-4 h-4 text-theme-status-success" />;
};

export const PrdTaskRow: React.FC<PrdTaskRowProps> = ({
  task,
  actualIndex,
  isExpanded,
  warnings,
  isDragging,
  isDragOver,
  readOnly,
  onToggleExpanded,
  onUpdateTask,
  onRemoveTask,
  onDuplicateTask,
  onDragStart,
  onDragOver,
  onDragEnd,
}) => {
  return (
    <Card
      className={cn(
        'overflow-visible transition-all',
        isDragging && 'opacity-50',
        isDragOver && 'ring-2 ring-theme-status-info',
        warnings && 'ring-1 ring-theme-status-warning'
      )}
      draggable={!readOnly}
      onDragStart={(e) => onDragStart(e, actualIndex)}
      onDragOver={(e) => onDragOver(e, actualIndex)}
      onDragEnd={onDragEnd}
    >
      <CardContent className="p-0">
        {/* Collapsed Header */}
        <div
          className={cn(
            'flex items-center gap-3 p-3 cursor-pointer hover:bg-theme-bg-secondary/50',
            isExpanded && 'border-b border-theme-border-primary'
          )}
          onClick={() => onToggleExpanded(task.key)}
        >
          {!readOnly && (
            <div
              className="cursor-grab active:cursor-grabbing p-1 hover:bg-theme-bg-secondary rounded"
              onClick={(e) => e.stopPropagation()}
            >
              <GripVertical className="w-4 h-4 text-theme-text-secondary" />
            </div>
          )}

          <div className="flex items-center gap-2">
            {isExpanded ? (
              <ChevronDown className="w-4 h-4 text-theme-text-secondary" />
            ) : (
              <ChevronRight className="w-4 h-4 text-theme-text-secondary" />
            )}
            {getTaskStatusIcon(task)}
          </div>

          <Badge variant="outline" size="sm" className="font-mono">{task.key}</Badge>

          <span className="flex-1 text-sm text-theme-text-primary truncate">
            {task.description || <span className="italic text-theme-text-secondary">No description</span>}
          </span>

          {task.dependencies && task.dependencies.length > 0 && (
            <Badge variant="secondary" size="sm" className="flex items-center gap-1">
              <Link className="w-3 h-3" />
              {task.dependencies.length}
            </Badge>
          )}

          {warnings && <AlertTriangle className="w-4 h-4 text-theme-status-warning" />}

          <span className="text-xs text-theme-text-secondary">#{actualIndex + 1}</span>
        </div>

        {/* Expanded Content */}
        {isExpanded && (
          <div className="p-4 space-y-4 bg-theme-bg-secondary/30">
            {/* Warnings */}
            {warnings && (
              <div className="p-3 rounded-lg bg-theme-status-warning/10 border border-theme-status-warning/20">
                <div className="flex items-start gap-2">
                  <AlertTriangle className="w-4 h-4 text-theme-status-warning flex-shrink-0 mt-0.5" />
                  <div className="space-y-1">
                    {warnings.map((warning, idx) => (
                      <p key={idx} className="text-sm text-theme-status-warning">{warning}</p>
                    ))}
                  </div>
                </div>
              </div>
            )}

            {/* Task Key */}
            <div className="grid grid-cols-[120px_1fr] gap-3 items-start">
              <label className="text-sm font-medium text-theme-text-secondary pt-2">Task Key</label>
              <Input
                value={task.key}
                onChange={(e) => onUpdateTask(actualIndex, { key: e.target.value.replace(/\s/g, '_') })}
                placeholder="task_key"
                className="font-mono"
                disabled={readOnly}
              />
            </div>

            {/* Description */}
            <div className="grid grid-cols-[120px_1fr] gap-3 items-start">
              <label className="text-sm font-medium text-theme-text-secondary pt-2">Description</label>
              <Textarea
                value={task.description}
                onChange={(e) => onUpdateTask(actualIndex, { description: e.target.value })}
                placeholder="Describe what this task should accomplish..."
                rows={3}
                disabled={readOnly}
              />
            </div>

            {/* Dependencies */}
            <div className="grid grid-cols-[120px_1fr] gap-3 items-start">
              <label className="text-sm font-medium text-theme-text-secondary pt-2">Dependencies</label>
              <div className="space-y-2">
                <Input
                  value={task.dependencies?.join(', ') || ''}
                  onChange={(e) => onUpdateTask(actualIndex, {
                    dependencies: e.target.value.split(',').map(d => d.trim()).filter(Boolean)
                  })}
                  placeholder="task_1, task_2"
                  disabled={readOnly}
                />
                <p className="text-xs text-theme-text-secondary">
                  Comma-separated list of task keys that must complete before this task
                </p>
              </div>
            </div>

            {/* Acceptance Criteria */}
            <div className="grid grid-cols-[120px_1fr] gap-3 items-start">
              <label className="text-sm font-medium text-theme-text-secondary pt-2">Acceptance</label>
              <Textarea
                value={task.acceptance_criteria || ''}
                onChange={(e) => onUpdateTask(actualIndex, { acceptance_criteria: e.target.value })}
                placeholder="Define what success looks like for this task..."
                rows={2}
                disabled={readOnly}
              />
            </div>

            {/* Actions */}
            {!readOnly && (
              <div className="flex items-center justify-end gap-2 pt-2 border-t border-theme-border-primary">
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => onDuplicateTask(actualIndex)}
                  className="text-theme-text-secondary"
                >
                  <Copy className="w-4 h-4 mr-1" />
                  Duplicate
                </Button>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => onRemoveTask(actualIndex)}
                  className="text-theme-status-error hover:bg-theme-status-error/10"
                >
                  <Trash2 className="w-4 h-4 mr-1" />
                  Delete
                </Button>
              </div>
            )}
          </div>
        )}
      </CardContent>
    </Card>
  );
};
