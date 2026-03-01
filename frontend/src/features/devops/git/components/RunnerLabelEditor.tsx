import React, { useState } from 'react';
import { X, Plus } from 'lucide-react';

interface RunnerLabelEditorProps {
  labels: string[];
  onLabelsChange: (labels: string[]) => void;
  canEdit: boolean;
  saving?: boolean;
}

export const RunnerLabelEditor: React.FC<RunnerLabelEditorProps> = ({
  labels,
  onLabelsChange,
  canEdit,
  saving = false,
}) => {
  const [newLabel, setNewLabel] = useState('');

  const handleAddLabel = () => {
    const trimmed = newLabel.trim();
    if (trimmed && !labels.includes(trimmed)) {
      onLabelsChange([...labels, trimmed]);
      setNewLabel('');
    }
  };

  const handleRemoveLabel = (labelToRemove: string) => {
    onLabelsChange(labels.filter((l) => l !== labelToRemove));
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      handleAddLabel();
    }
  };

  return (
    <div>
      <div className="flex flex-wrap gap-2 mb-3">
        {labels.map((label) => (
          <span
            key={label}
            className="inline-flex items-center gap-1 px-3 py-1.5 rounded-lg text-sm bg-theme-primary/10 text-theme-primary"
          >
            {label}
            {canEdit && (
              <button
                onClick={() => handleRemoveLabel(label)}
                className="ml-1 hover:text-theme-error transition-colors"
                disabled={saving}
              >
                <X className="w-3.5 h-3.5" />
              </button>
            )}
          </span>
        ))}
        {labels.length === 0 && (
          <span className="text-sm text-theme-tertiary">No labels assigned</span>
        )}
      </div>
      {canEdit && (
        <div className="flex items-center gap-2">
          <input
            type="text"
            value={newLabel}
            onChange={(e) => setNewLabel(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Add a label..."
            className="flex-1 px-3 py-1.5 text-sm bg-theme-surface border border-theme rounded-lg text-theme-primary placeholder:text-theme-tertiary focus:outline-none focus:border-theme-primary"
            disabled={saving}
          />
          <button
            onClick={handleAddLabel}
            disabled={!newLabel.trim() || saving}
            className="p-1.5 rounded-lg bg-theme-primary/10 text-theme-primary hover:bg-theme-primary/20 disabled:opacity-50 transition-colors"
          >
            <Plus className="w-4 h-4" />
          </button>
        </div>
      )}
    </div>
  );
};
