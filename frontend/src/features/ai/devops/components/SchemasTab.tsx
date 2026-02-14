import React from 'react';

const inputClass = 'w-full px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary';
const labelClass = 'block text-sm font-medium text-theme-primary mb-1';

interface SchemasTabProps {
  inputSchemaText: string;
  outputSchemaText: string;
  jsonErrors: Record<string, string>;
  onInputSchemaChange: (text: string) => void;
  onOutputSchemaChange: (text: string) => void;
}

export const SchemasTab: React.FC<SchemasTabProps> = ({
  inputSchemaText,
  outputSchemaText,
  jsonErrors,
  onInputSchemaChange,
  onOutputSchemaChange,
}) => {
  return (
    <div className="space-y-4">
      <div>
        <label className={labelClass}>
          Input Schema
          {jsonErrors.input_schema && <span className="text-theme-danger ml-2 font-normal">{jsonErrors.input_schema}</span>}
        </label>
        <p className="text-xs text-theme-secondary mb-2">Define the expected input parameters for this template.</p>
        <textarea
          value={inputSchemaText}
          onChange={(e) => onInputSchemaChange(e.target.value)}
          rows={10}
          className={`${inputClass} font-mono text-xs ${jsonErrors.input_schema ? 'border-theme-danger' : ''}`}
          placeholder='{"param_name": {"type": "string", "required": true, "description": "..."}}'
        />
      </div>
      <div>
        <label className={labelClass}>
          Output Schema
          {jsonErrors.output_schema && <span className="text-theme-danger ml-2 font-normal">{jsonErrors.output_schema}</span>}
        </label>
        <p className="text-xs text-theme-secondary mb-2">Define the expected output structure from this template.</p>
        <textarea
          value={outputSchemaText}
          onChange={(e) => onOutputSchemaChange(e.target.value)}
          rows={10}
          className={`${inputClass} font-mono text-xs ${jsonErrors.output_schema ? 'border-theme-danger' : ''}`}
          placeholder='{"result": {"type": "string"}, "findings": {"type": "array"}}'
        />
      </div>
    </div>
  );
};
