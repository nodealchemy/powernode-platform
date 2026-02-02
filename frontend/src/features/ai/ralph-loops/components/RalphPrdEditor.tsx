import React, { useState, useCallback, useMemo, useEffect } from 'react';
import {
  Plus,
  Trash2,
  GripVertical,
  Save,
  Upload,
  Download,
  AlertCircle,
  Loader2,
  ChevronDown,
  ChevronRight,
  Search,
  Copy,
  Wand2,
  Link,
  AlertTriangle,
  CheckCircle2,
  Circle,
  FileText,
  Code,
  Database,
  TestTube,
  Settings,
  Layers,
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { cn } from '@/shared/utils/cn';
import type { PrdTask } from '@/shared/services/ai/types/ralph-types';

// Task templates for quick creation
const TASK_TEMPLATES = [
  {
    icon: FileText,
    label: 'Documentation',
    task: { key: 'docs', description: 'Write documentation for the feature', acceptance_criteria: 'README updated, inline comments added' }
  },
  {
    icon: Code,
    label: 'Implementation',
    task: { key: 'implement', description: 'Implement the core functionality', acceptance_criteria: 'Feature works as specified' }
  },
  {
    icon: TestTube,
    label: 'Testing',
    task: { key: 'tests', description: 'Write unit and integration tests', acceptance_criteria: 'Test coverage > 80%, all tests pass' }
  },
  {
    icon: Database,
    label: 'Database',
    task: { key: 'migration', description: 'Create database migrations', acceptance_criteria: 'Migrations run successfully, rollback works' }
  },
  {
    icon: Settings,
    label: 'Configuration',
    task: { key: 'config', description: 'Set up configuration and environment', acceptance_criteria: 'Config validated, environment variables documented' }
  },
  {
    icon: Layers,
    label: 'Refactoring',
    task: { key: 'refactor', description: 'Refactor existing code for improvement', acceptance_criteria: 'No regression, improved code quality' }
  },
];

interface RalphPrdEditorProps {
  tasks: PrdTask[];
  onChange: (tasks: PrdTask[]) => void;
  onSave?: () => void | Promise<void>;
  readOnly?: boolean;
  className?: string;
}

export const RalphPrdEditor: React.FC<RalphPrdEditorProps> = ({
  tasks,
  onChange,
  onSave,
  readOnly = false,
  className,
}) => {
  const [jsonMode, setJsonMode] = useState(false);
  const [jsonText, setJsonText] = useState('');
  const [jsonError, setJsonError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [expandedTasks, setExpandedTasks] = useState<Set<string>>(new Set());
  const [showTemplates, setShowTemplates] = useState(false);
  const [draggedIndex, setDraggedIndex] = useState<number | null>(null);
  const [dragOverIndex, setDragOverIndex] = useState<number | null>(null);

  // Keyboard shortcut for save
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key === 's' && onSave && !readOnly) {
        e.preventDefault();
        handleSave();
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [onSave, readOnly]);

  // Validate dependencies
  const dependencyWarnings = useMemo(() => {
    const warnings: Record<string, string[]> = {};
    const taskKeys = new Set(tasks.map(t => t.key));

    tasks.forEach(task => {
      const taskWarnings: string[] = [];

      // Check for missing dependencies
      task.dependencies?.forEach(dep => {
        if (!taskKeys.has(dep)) {
          taskWarnings.push(`Dependency "${dep}" does not exist`);
        }
      });

      // Check for self-dependency
      if (task.dependencies?.includes(task.key)) {
        taskWarnings.push('Task cannot depend on itself');
      }

      // Check for circular dependencies (simple check)
      task.dependencies?.forEach(dep => {
        const depTask = tasks.find(t => t.key === dep);
        if (depTask?.dependencies?.includes(task.key)) {
          taskWarnings.push(`Circular dependency with "${dep}"`);
        }
      });

      if (taskWarnings.length > 0) {
        warnings[task.key] = taskWarnings;
      }
    });

    return warnings;
  }, [tasks]);

  // Filter tasks by search query
  const filteredTasks = useMemo(() => {
    if (!searchQuery.trim()) return tasks;
    const query = searchQuery.toLowerCase();
    return tasks.filter(task =>
      task.key.toLowerCase().includes(query) ||
      task.description.toLowerCase().includes(query) ||
      task.acceptance_criteria?.toLowerCase().includes(query)
    );
  }, [tasks, searchQuery]);

  const handleSave = async () => {
    if (!onSave || saving) return;
    try {
      setSaving(true);
      await onSave();
    } finally {
      setSaving(false);
    }
  };

  const handleAddTask = useCallback(() => {
    const existingKeys = new Set(tasks.map(t => t.key));
    let counter = tasks.length + 1;
    let newKey = `task_${counter}`;
    while (existingKeys.has(newKey)) {
      counter++;
      newKey = `task_${counter}`;
    }

    const newTask: PrdTask = {
      key: newKey,
      description: '',
      priority: tasks.length + 1,
      dependencies: [],
    };

    onChange([...tasks, newTask]);
    setExpandedTasks(prev => new Set([...prev, newKey]));
  }, [tasks, onChange]);

  const handleAddFromTemplate = useCallback((template: typeof TASK_TEMPLATES[0]) => {
    const existingKeys = new Set(tasks.map(t => t.key));
    let key = template.task.key;
    let counter = 1;
    while (existingKeys.has(key)) {
      key = `${template.task.key}_${counter}`;
      counter++;
    }

    const newTask: PrdTask = {
      ...template.task,
      key,
      priority: tasks.length + 1,
      dependencies: [],
    };

    onChange([...tasks, newTask]);
    setExpandedTasks(prev => new Set([...prev, key]));
    setShowTemplates(false);
  }, [tasks, onChange]);

  const handleUpdateTask = useCallback((index: number, updates: Partial<PrdTask>) => {
    const newTasks = [...tasks];
    newTasks[index] = { ...newTasks[index], ...updates };
    onChange(newTasks);
  }, [tasks, onChange]);

  const handleRemoveTask = useCallback((index: number) => {
    const taskKey = tasks[index].key;
    const newTasks = tasks.filter((_, i) => i !== index);
    // Update priorities
    newTasks.forEach((task, idx) => {
      task.priority = idx + 1;
    });
    onChange(newTasks);
    setExpandedTasks(prev => {
      const next = new Set(prev);
      next.delete(taskKey);
      return next;
    });
  }, [tasks, onChange]);

  const handleDuplicateTask = useCallback((index: number) => {
    const task = tasks[index];
    const existingKeys = new Set(tasks.map(t => t.key));
    let newKey = `${task.key}_copy`;
    let counter = 1;
    while (existingKeys.has(newKey)) {
      newKey = `${task.key}_copy_${counter}`;
      counter++;
    }

    const newTask: PrdTask = {
      ...task,
      key: newKey,
      priority: tasks.length + 1,
    };

    onChange([...tasks, newTask]);
    setExpandedTasks(prev => new Set([...prev, newKey]));
  }, [tasks, onChange]);

  // Drag and drop handlers
  const handleDragStart = (e: React.DragEvent, index: number) => {
    setDraggedIndex(index);
    e.dataTransfer.effectAllowed = 'move';
  };

  const handleDragOver = (e: React.DragEvent, index: number) => {
    e.preventDefault();
    if (draggedIndex !== null && draggedIndex !== index) {
      setDragOverIndex(index);
    }
  };

  const handleDragEnd = () => {
    if (draggedIndex !== null && dragOverIndex !== null && draggedIndex !== dragOverIndex) {
      const newTasks = [...tasks];
      const [draggedTask] = newTasks.splice(draggedIndex, 1);
      newTasks.splice(dragOverIndex, 0, draggedTask);
      // Update priorities
      newTasks.forEach((task, idx) => {
        task.priority = idx + 1;
      });
      onChange(newTasks);
    }
    setDraggedIndex(null);
    setDragOverIndex(null);
  };

  const toggleExpanded = (key: string) => {
    setExpandedTasks(prev => {
      const next = new Set(prev);
      if (next.has(key)) {
        next.delete(key);
      } else {
        next.add(key);
      }
      return next;
    });
  };

  const expandAll = () => {
    setExpandedTasks(new Set(tasks.map(t => t.key)));
  };

  const collapseAll = () => {
    setExpandedTasks(new Set());
  };

  const handleJsonImport = () => {
    try {
      const parsed = JSON.parse(jsonText);
      let importedTasks: PrdTask[];

      if (Array.isArray(parsed)) {
        importedTasks = parsed;
      } else if (Array.isArray(parsed.tasks)) {
        importedTasks = parsed.tasks;
      } else {
        throw new Error('JSON must be an array of tasks or have a "tasks" array');
      }

      // Validate and normalize tasks
      importedTasks = importedTasks.map((task, idx) => ({
        key: task.key || `task_${idx + 1}`,
        description: task.description || '',
        priority: task.priority || idx + 1,
        dependencies: Array.isArray(task.dependencies) ? task.dependencies : [],
        acceptance_criteria: task.acceptance_criteria || '',
      }));

      onChange(importedTasks);
      setJsonMode(false);
      setJsonError(null);
    } catch {
      setJsonError(err instanceof Error ? err.message : 'Invalid JSON');
    }
  };

  const handleExportJson = () => {
    const json = JSON.stringify({ tasks }, null, 2);
    setJsonText(json);
    setJsonMode(true);
  };

  const handleDownloadJson = () => {
    const json = JSON.stringify({ tasks }, null, 2);
    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'prd-tasks.json';
    a.click();
    URL.revokeObjectURL(url);
  };

  const getTaskStatusIcon = (task: PrdTask) => {
    // This could be enhanced to show actual execution status
    if (!task.description) {
      return <Circle className="w-4 h-4 text-theme-text-secondary" />;
    }
    return <CheckCircle2 className="w-4 h-4 text-theme-status-success" />;
  };

  // JSON Mode View
  if (jsonMode) {
    return (
      <div className={cn('space-y-4', className)}>
        <div className="flex items-center justify-between">
          <h3 className="font-medium text-theme-text-primary">PRD JSON Editor</h3>
          <div className="flex items-center gap-2">
            <Button variant="ghost" size="sm" onClick={() => setJsonMode(false)}>
              Cancel
            </Button>
            <Button variant="outline" size="sm" onClick={handleDownloadJson}>
              <Download className="w-4 h-4 mr-1" />
              Download
            </Button>
            <Button variant="primary" size="sm" onClick={handleJsonImport}>
              <Upload className="w-4 h-4 mr-1" />
              Import
            </Button>
          </div>
        </div>

        {jsonError && (
          <div className="flex items-center gap-2 p-3 rounded-lg bg-theme-status-error/10 text-theme-status-error">
            <AlertCircle className="w-4 h-4 flex-shrink-0" />
            <span className="text-sm">{jsonError}</span>
          </div>
        )}

        <div className="relative">
          <textarea
            className="w-full h-[500px] p-4 font-mono text-sm bg-theme-bg-secondary border border-theme-border-primary rounded-lg focus:outline-none focus:ring-2 focus:ring-theme-status-info resize-none"
            value={jsonText}
            onChange={(e) => {
              setJsonText(e.target.value);
              setJsonError(null);
            }}
            placeholder='{"tasks": [{"key": "task_1", "description": "...", "dependencies": [], "acceptance_criteria": "..."}]}'
            spellCheck={false}
          />
          <div className="absolute bottom-2 right-2 text-xs text-theme-text-secondary">
            {jsonText.length} characters
          </div>
        </div>

        <p className="text-xs text-theme-text-secondary">
          Tip: You can paste a JSON array of tasks directly, or an object with a &quot;tasks&quot; property.
        </p>
      </div>
    );
  }

  // Visual Editor View
  return (
    <div className={cn('space-y-4', className)}>
      {/* Header */}
      <div className="flex items-center justify-between gap-4">
        <div className="flex items-center gap-3">
          <h3 className="font-medium text-theme-text-primary">PRD Tasks</h3>
          <Badge variant="secondary" size="sm">
            {tasks.length} {tasks.length === 1 ? 'task' : 'tasks'}
          </Badge>
          {Object.keys(dependencyWarnings).length > 0 && (
            <Badge variant="warning" size="sm" className="flex items-center gap-1">
              <AlertTriangle className="w-3 h-3" />
              {Object.keys(dependencyWarnings).length} warnings
            </Badge>
          )}
        </div>

        {!readOnly && (
          <div className="flex items-center gap-2">
            <Button variant="ghost" size="sm" onClick={expandAll} title="Expand all">
              <ChevronDown className="w-4 h-4" />
            </Button>
            <Button variant="ghost" size="sm" onClick={collapseAll} title="Collapse all">
              <ChevronRight className="w-4 h-4" />
            </Button>
            <div className="w-px h-4 bg-theme-border-primary" />
            <Button variant="ghost" size="sm" onClick={handleExportJson}>
              JSON
            </Button>
            {onSave && (
              <Button variant="primary" size="sm" onClick={handleSave} disabled={saving}>
                {saving ? (
                  <Loader2 className="w-4 h-4 mr-1 animate-spin" />
                ) : (
                  <Save className="w-4 h-4 mr-1" />
                )}
                {saving ? 'Saving...' : 'Save'}
              </Button>
            )}
          </div>
        )}
      </div>

      {/* Search Bar */}
      {tasks.length > 3 && (
        <div className="relative">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-theme-text-secondary" />
          <Input
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search tasks..."
            className="pl-9"
          />
        </div>
      )}

      {/* Task List */}
      <div className="space-y-2">
        {filteredTasks.map((task) => {
          const isExpanded = expandedTasks.has(task.key);
          const warnings = dependencyWarnings[task.key];
          const actualIndex = tasks.findIndex(t => t.key === task.key);
          const isDragging = draggedIndex === actualIndex;
          const isDragOver = dragOverIndex === actualIndex;

          return (
            <Card
              key={task.key}
              className={cn(
                'overflow-visible transition-all',
                isDragging && 'opacity-50',
                isDragOver && 'ring-2 ring-theme-status-info',
                warnings && 'ring-1 ring-theme-status-warning'
              )}
              draggable={!readOnly}
              onDragStart={(e) => handleDragStart(e, actualIndex)}
              onDragOver={(e) => handleDragOver(e, actualIndex)}
              onDragEnd={handleDragEnd}
            >
              <CardContent className="p-0">
                {/* Collapsed Header */}
                <div
                  className={cn(
                    'flex items-center gap-3 p-3 cursor-pointer hover:bg-theme-bg-secondary/50',
                    isExpanded && 'border-b border-theme-border-primary'
                  )}
                  onClick={() => toggleExpanded(task.key)}
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

                  <Badge variant="outline" size="sm" className="font-mono">
                    {task.key}
                  </Badge>

                  <span className="flex-1 text-sm text-theme-text-primary truncate">
                    {task.description || <span className="italic text-theme-text-secondary">No description</span>}
                  </span>

                  {task.dependencies && task.dependencies.length > 0 && (
                    <Badge variant="secondary" size="sm" className="flex items-center gap-1">
                      <Link className="w-3 h-3" />
                      {task.dependencies.length}
                    </Badge>
                  )}

                  {warnings && (
                    <AlertTriangle className="w-4 h-4 text-theme-status-warning" />
                  )}

                  <span className="text-xs text-theme-text-secondary">
                    #{actualIndex + 1}
                  </span>
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
                      <label className="text-sm font-medium text-theme-text-secondary pt-2">
                        Task Key
                      </label>
                      <Input
                        value={task.key}
                        onChange={(e) => handleUpdateTask(actualIndex, { key: e.target.value.replace(/\s/g, '_') })}
                        placeholder="task_key"
                        className="font-mono"
                        disabled={readOnly}
                      />
                    </div>

                    {/* Description */}
                    <div className="grid grid-cols-[120px_1fr] gap-3 items-start">
                      <label className="text-sm font-medium text-theme-text-secondary pt-2">
                        Description
                      </label>
                      <Textarea
                        value={task.description}
                        onChange={(e) => handleUpdateTask(actualIndex, { description: e.target.value })}
                        placeholder="Describe what this task should accomplish..."
                        rows={3}
                        disabled={readOnly}
                      />
                    </div>

                    {/* Dependencies */}
                    <div className="grid grid-cols-[120px_1fr] gap-3 items-start">
                      <label className="text-sm font-medium text-theme-text-secondary pt-2">
                        Dependencies
                      </label>
                      <div className="space-y-2">
                        <Input
                          value={task.dependencies?.join(', ') || ''}
                          onChange={(e) => handleUpdateTask(actualIndex, {
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
                      <label className="text-sm font-medium text-theme-text-secondary pt-2">
                        Acceptance
                      </label>
                      <Textarea
                        value={task.acceptance_criteria || ''}
                        onChange={(e) => handleUpdateTask(actualIndex, { acceptance_criteria: e.target.value })}
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
                          onClick={() => handleDuplicateTask(actualIndex)}
                          className="text-theme-text-secondary"
                        >
                          <Copy className="w-4 h-4 mr-1" />
                          Duplicate
                        </Button>
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => handleRemoveTask(actualIndex)}
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
        })}
      </div>

      {/* Add Task Section */}
      {!readOnly && (
        <div className="space-y-2">
          {/* Template Dropdown */}
          {showTemplates && (
            <Card className="p-3">
              <p className="text-sm font-medium text-theme-text-primary mb-3">Quick Add from Template</p>
              <div className="grid grid-cols-2 md:grid-cols-3 gap-2">
                {TASK_TEMPLATES.map((template) => (
                  <Button
                    key={template.label}
                    variant="outline"
                    size="sm"
                    onClick={() => handleAddFromTemplate(template)}
                    className="justify-start"
                  >
                    <template.icon className="w-4 h-4 mr-2" />
                    {template.label}
                  </Button>
                ))}
              </div>
            </Card>
          )}

          <div className="flex items-center gap-2">
            <Button variant="outline" onClick={handleAddTask} className="flex-1">
              <Plus className="w-4 h-4 mr-2" />
              Add Task
            </Button>
            <Button
              variant="ghost"
              onClick={() => setShowTemplates(!showTemplates)}
              className={cn(showTemplates && 'bg-theme-bg-secondary')}
            >
              <Wand2 className="w-4 h-4" />
            </Button>
          </div>
        </div>
      )}

      {/* Empty State */}
      {tasks.length === 0 && (
        <div className="text-center py-12 text-theme-text-secondary">
          <FileText className="w-12 h-12 mx-auto mb-4 opacity-50" />
          <p className="font-medium">No tasks defined yet</p>
          {!readOnly && (
            <p className="text-sm mt-1">
              Click &quot;Add Task&quot; to create your first task, or import from JSON.
            </p>
          )}
        </div>
      )}

      {/* Search Empty State */}
      {tasks.length > 0 && filteredTasks.length === 0 && searchQuery && (
        <div className="text-center py-8 text-theme-text-secondary">
          <Search className="w-8 h-8 mx-auto mb-3 opacity-50" />
          <p>No tasks match &quot;{searchQuery}&quot;</p>
          <Button variant="ghost" size="sm" onClick={() => setSearchQuery('')} className="mt-2">
            Clear search
          </Button>
        </div>
      )}

      {/* Keyboard Shortcuts Hint */}
      {!readOnly && tasks.length > 0 && (
        <p className="text-xs text-theme-text-secondary text-center">
          Tip: Press <kbd className="px-1.5 py-0.5 rounded bg-theme-bg-secondary border border-theme-border-primary font-mono">Ctrl+S</kbd> to save
        </p>
      )}
    </div>
  );
};

export default RalphPrdEditor;
