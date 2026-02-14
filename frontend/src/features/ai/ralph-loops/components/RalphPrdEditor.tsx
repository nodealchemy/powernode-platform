import React from 'react';
import {
  ChevronDown,
  ChevronRight,
  Save,
  Loader2,
  AlertTriangle,
} from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Badge } from '@/shared/components/ui/Badge';
import { cn } from '@/shared/utils/cn';
import { PrdTaskRow } from './PrdTaskRow';
import { PrdTaskTemplates } from './PrdTaskTemplates';
import { PrdDependencyGraph } from './PrdDependencyGraph';
import { PrdImportExport } from './PrdImportExport';
import { usePrdEditor } from './usePrdEditor';
import type { PrdTask } from '@/shared/services/ai/types/ralph-types';

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
  const {
    jsonMode,
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
    setJsonMode,
  } = usePrdEditor({ tasks, onChange, onSave, readOnly });

  // JSON Mode View
  if (jsonMode) {
    return (
      <PrdImportExport
        tasks={tasks}
        jsonText={jsonText}
        jsonError={jsonError}
        onJsonTextChange={setJsonText}
        onJsonImport={handleJsonImport}
        onJsonExport={handleExportJson}
        onDownloadJson={handleDownloadJson}
        onCancel={() => setJsonMode(false)}
        className={className}
      />
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

      <PrdDependencyGraph
        taskCount={tasks.length}
        filteredCount={filteredTasks.length}
        searchQuery={searchQuery}
        onSearchQueryChange={setSearchQuery}
        showSearch={tasks.length > 3}
      />

      {/* Task List */}
      <div className="space-y-2">
        {filteredTasks.map((task) => {
          const actualIndex = tasks.findIndex(t => t.key === task.key);
          return (
            <PrdTaskRow
              key={task.key}
              task={task}
              actualIndex={actualIndex}
              isExpanded={expandedTasks.has(task.key)}
              warnings={dependencyWarnings[task.key]}
              isDragging={draggedIndex === actualIndex}
              isDragOver={dragOverIndex === actualIndex}
              readOnly={readOnly}
              onToggleExpanded={toggleExpanded}
              onUpdateTask={handleUpdateTask}
              onRemoveTask={handleRemoveTask}
              onDuplicateTask={handleDuplicateTask}
              onDragStart={handleDragStart}
              onDragOver={handleDragOver}
              onDragEnd={handleDragEnd}
            />
          );
        })}
      </div>

      {/* Add Task Section */}
      {!readOnly && (
        <PrdTaskTemplates
          showTemplates={showTemplates}
          onToggleTemplates={() => setShowTemplates(!showTemplates)}
          onAddTask={handleAddTask}
          onAddFromTemplate={handleAddFromTemplate}
        />
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
