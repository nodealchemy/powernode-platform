import React from 'react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Badge } from '@/shared/components/ui/Badge';

interface ExecutorAgentTabProps {
  taskKey: string;
  taskDescription: string;
  taskDependencies: string[];
  taskAcceptanceCriteria: string;
  availableTaskKeys: string[];
  onTaskKeyChange: (value: string) => void;
  onTaskDescriptionChange: (value: string) => void;
  onTaskDependenciesChange: (deps: string[]) => void;
  onTaskAcceptanceCriteriaChange: (value: string) => void;
}

export const ExecutorAgentTab: React.FC<ExecutorAgentTabProps> = ({
  taskKey,
  taskDescription,
  taskDependencies,
  taskAcceptanceCriteria,
  availableTaskKeys,
  onTaskKeyChange,
  onTaskDescriptionChange,
  onTaskDependenciesChange,
  onTaskAcceptanceCriteriaChange,
}) => {
  return (
    <div className="space-y-4">
      <div>
        <label className="block text-sm font-medium text-theme-text-primary mb-1">
          Task Key
        </label>
        <Input
          value={taskKey}
          onChange={(e) => onTaskKeyChange(e.target.value.replace(/\s/g, '_'))}
          placeholder="task_key"
          className="font-mono"
        />
        <p className="mt-1 text-xs text-theme-text-secondary">
          Unique identifier for this task (no spaces)
        </p>
      </div>

      <div>
        <label className="block text-sm font-medium text-theme-text-primary mb-1">
          Description
        </label>
        <Textarea
          value={taskDescription}
          onChange={(e) => onTaskDescriptionChange(e.target.value)}
          placeholder="Describe what this task should accomplish..."
          rows={3}
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-theme-text-primary mb-2">
          Dependencies
        </label>
        {availableTaskKeys.length > 0 ? (
          <div className="space-y-2 max-h-40 overflow-y-auto p-2 border border-theme-border-primary rounded-lg bg-theme-bg-primary">
            {availableTaskKeys
              .filter(key => key !== taskKey)
              .map((key) => (
                <label
                  key={key}
                  className="flex items-center gap-2 cursor-pointer hover:bg-theme-bg-secondary p-1.5 rounded"
                >
                  <input
                    type="checkbox"
                    checked={taskDependencies.includes(key)}
                    onChange={(e) => {
                      if (e.target.checked) onTaskDependenciesChange([...taskDependencies, key]);
                      else onTaskDependenciesChange(taskDependencies.filter(d => d !== key));
                    }}
                    className="w-4 h-4 rounded border-theme-border-primary text-theme-brand-primary focus:ring-theme-brand-primary"
                  />
                  <span className="font-mono text-sm text-theme-text-primary">{key}</span>
                </label>
              ))}
            {availableTaskKeys.filter(key => key !== taskKey).length === 0 && (
              <p className="text-sm text-theme-text-secondary py-2">No other tasks available</p>
            )}
          </div>
        ) : (
          <p className="text-sm text-theme-text-secondary p-2 border border-theme-border-primary rounded-lg">
            No other tasks available to select as dependencies
          </p>
        )}
        {taskDependencies.length > 0 && (
          <div className="flex flex-wrap gap-1.5 mt-2">
            {taskDependencies.map((dep) => (
              <Badge key={dep} variant="outline" size="sm">{dep}</Badge>
            ))}
          </div>
        )}
        <p className="mt-1 text-xs text-theme-text-secondary">
          Select tasks that must complete before this task can start
        </p>
      </div>

      <div>
        <label className="block text-sm font-medium text-theme-text-primary mb-1">
          Acceptance Criteria
        </label>
        <Textarea
          value={taskAcceptanceCriteria}
          onChange={(e) => onTaskAcceptanceCriteriaChange(e.target.value)}
          placeholder="Define what success looks like for this task..."
          rows={3}
        />
      </div>
    </div>
  );
};
