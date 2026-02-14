import { useState, useCallback, useMemo, useEffect } from 'react';
import type { PrdTask } from '@/shared/services/ai/types/ralph-types';
import { TASK_TEMPLATES } from './PrdTaskTemplates';

interface UsePrdEditorOptions {
  tasks: PrdTask[];
  onChange: (tasks: PrdTask[]) => void;
  onSave?: () => void | Promise<void>;
  readOnly: boolean;
}

export function usePrdEditor({ tasks, onChange, onSave, readOnly }: UsePrdEditorOptions) {
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
      task.dependencies?.forEach(dep => {
        if (!taskKeys.has(dep)) taskWarnings.push(`Dependency "${dep}" does not exist`);
      });
      if (task.dependencies?.includes(task.key)) taskWarnings.push('Task cannot depend on itself');
      task.dependencies?.forEach(dep => {
        const depTask = tasks.find(t => t.key === dep);
        if (depTask?.dependencies?.includes(task.key)) taskWarnings.push(`Circular dependency with "${dep}"`);
      });
      if (taskWarnings.length > 0) warnings[task.key] = taskWarnings;
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
    while (existingKeys.has(newKey)) { counter++; newKey = `task_${counter}`; }
    const newTask: PrdTask = { key: newKey, description: '', priority: tasks.length + 1, dependencies: [] };
    onChange([...tasks, newTask]);
    setExpandedTasks(prev => new Set([...prev, newKey]));
  }, [tasks, onChange]);

  const handleAddFromTemplate = useCallback((template: typeof TASK_TEMPLATES[0]) => {
    const existingKeys = new Set(tasks.map(t => t.key));
    let key = template.task.key;
    let counter = 1;
    while (existingKeys.has(key)) { key = `${template.task.key}_${counter}`; counter++; }
    const newTask: PrdTask = { ...template.task, key, priority: tasks.length + 1, dependencies: [] };
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
    newTasks.forEach((task, idx) => { task.priority = idx + 1; });
    onChange(newTasks);
    setExpandedTasks(prev => { const next = new Set(prev); next.delete(taskKey); return next; });
  }, [tasks, onChange]);

  const handleDuplicateTask = useCallback((index: number) => {
    const task = tasks[index];
    const existingKeys = new Set(tasks.map(t => t.key));
    let newKey = `${task.key}_copy`;
    let counter = 1;
    while (existingKeys.has(newKey)) { newKey = `${task.key}_copy_${counter}`; counter++; }
    const newTask: PrdTask = { ...task, key: newKey, priority: tasks.length + 1 };
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
    if (draggedIndex !== null && draggedIndex !== index) setDragOverIndex(index);
  };

  const handleDragEnd = () => {
    if (draggedIndex !== null && dragOverIndex !== null && draggedIndex !== dragOverIndex) {
      const newTasks = [...tasks];
      const [draggedTask] = newTasks.splice(draggedIndex, 1);
      newTasks.splice(dragOverIndex, 0, draggedTask);
      newTasks.forEach((task, idx) => { task.priority = idx + 1; });
      onChange(newTasks);
    }
    setDraggedIndex(null);
    setDragOverIndex(null);
  };

  const toggleExpanded = (key: string) => {
    setExpandedTasks(prev => {
      const next = new Set(prev);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  };

  const expandAll = () => setExpandedTasks(new Set(tasks.map(t => t.key)));
  const collapseAll = () => setExpandedTasks(new Set());

  const handleJsonImport = () => {
    try {
      const parsed = JSON.parse(jsonText);
      let importedTasks: PrdTask[];
      if (Array.isArray(parsed)) importedTasks = parsed;
      else if (Array.isArray(parsed.tasks)) importedTasks = parsed.tasks;
      else throw new Error('JSON must be an array of tasks or have a "tasks" array');

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
    } catch (err) {
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

  return {
    jsonMode,
    setJsonMode,
    jsonText,
    setJsonText,
    jsonError,
    saving,
    searchQuery,
    setSearchQuery,
    expandedTasks,
    showTemplates,
    setShowTemplates,
    draggedIndex,
    dragOverIndex,
    dependencyWarnings,
    filteredTasks,
    handleSave,
    handleAddTask,
    handleAddFromTemplate,
    handleUpdateTask,
    handleRemoveTask,
    handleDuplicateTask,
    handleDragStart,
    handleDragOver,
    handleDragEnd,
    toggleExpanded,
    expandAll,
    collapseAll,
    handleJsonImport,
    handleExportJson,
    handleDownloadJson,
  };
}
