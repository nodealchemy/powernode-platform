import React from 'react';
import { Plus, Trash2 } from 'lucide-react';

interface TemplateVariable {
  name: string;
  default: string;
  description: string;
}

const inputClass = 'w-full px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary';

interface VariablesTabProps {
  variables: TemplateVariable[];
  onAddVariable: () => void;
  onUpdateVariable: (index: number, updates: Partial<TemplateVariable>) => void;
  onRemoveVariable: (index: number) => void;
}

export const VariablesTab: React.FC<VariablesTabProps> = ({
  variables,
  onAddVariable,
  onUpdateVariable,
  onRemoveVariable,
}) => {
  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <p className="text-sm text-theme-secondary">Template variables that users can configure when installing.</p>
        <button onClick={onAddVariable} className="btn-theme btn-theme-secondary btn-theme-sm flex items-center gap-1">
          <Plus size={14} /> Add Variable
        </button>
      </div>
      {variables.length === 0 ? (
        <div className="text-center py-8 text-theme-secondary text-sm border border-dashed border-theme rounded-lg">
          No variables defined. Click &quot;Add Variable&quot; to create one.
        </div>
      ) : (
        <div className="space-y-3">
          {variables.map((variable, i) => (
            <div key={i} className="bg-theme-bg border border-theme rounded-lg p-3">
              <div className="flex items-start justify-between gap-2">
                <div className="flex-1 grid grid-cols-3 gap-3">
                  <div>
                    <label className="block text-xs text-theme-secondary mb-1">Name *</label>
                    <input
                      type="text"
                      value={variable.name}
                      onChange={(e) => onUpdateVariable(i, { name: e.target.value })}
                      placeholder="variable_name"
                      className={`${inputClass} font-mono`}
                    />
                  </div>
                  <div>
                    <label className="block text-xs text-theme-secondary mb-1">Default Value</label>
                    <input
                      type="text"
                      value={variable.default}
                      onChange={(e) => onUpdateVariable(i, { default: e.target.value })}
                      placeholder="default"
                      className={inputClass}
                    />
                  </div>
                  <div>
                    <label className="block text-xs text-theme-secondary mb-1">Description</label>
                    <input
                      type="text"
                      value={variable.description}
                      onChange={(e) => onUpdateVariable(i, { description: e.target.value })}
                      placeholder="What this variable controls"
                      className={inputClass}
                    />
                  </div>
                </div>
                <button onClick={() => onRemoveVariable(i)} className="mt-5 p-1.5 text-theme-secondary hover:text-theme-danger rounded transition-colors">
                  <Trash2 size={14} />
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};
