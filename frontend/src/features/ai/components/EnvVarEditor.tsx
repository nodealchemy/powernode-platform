import React from 'react';
import { Plus, Trash2 } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';

interface EnvVarEditorProps {
  envVars: { key: string; value: string }[];
  onEnvVarsChange: (envVars: { key: string; value: string }[]) => void;
}

export const EnvVarEditor: React.FC<EnvVarEditorProps> = ({
  envVars,
  onEnvVarsChange,
}) => {
  const addEnvVar = () => {
    onEnvVarsChange([...envVars, { key: '', value: '' }]);
  };

  const removeEnvVar = (index: number) => {
    onEnvVarsChange(envVars.filter((_, i) => i !== index));
  };

  const updateEnvVar = (index: number, field: 'key' | 'value', value: string) => {
    const newEnvVars = [...envVars];
    newEnvVars[index] = { ...newEnvVars[index], [field]: value };
    onEnvVarsChange(newEnvVars);
  };

  return (
    <div>
      <div className="flex items-center justify-between mb-2">
        <label className="text-sm font-medium text-theme-primary">
          Environment Variables
        </label>
        <Button
          type="button"
          variant="ghost"
          size="sm"
          onClick={addEnvVar}
        >
          <Plus className="h-4 w-4 mr-1" />
          Add Variable
        </Button>
      </div>
      <div className="space-y-2">
        {envVars.length === 0 ? (
          <p className="text-sm text-theme-tertiary">
            No environment variables configured.
          </p>
        ) : (
          envVars.map((env, index) => (
            <div key={index} className="flex items-center gap-2">
              <Input
                type="text"
                value={env.key}
                onChange={(e) => updateEnvVar(index, 'key', e.target.value)}
                placeholder="Variable name"
                className="w-1/3"
              />
              <span className="text-theme-tertiary">=</span>
              <Input
                type="text"
                value={env.value}
                onChange={(e) => updateEnvVar(index, 'value', e.target.value)}
                placeholder="Value"
                className="flex-1"
              />
              <Button
                type="button"
                variant="ghost"
                size="sm"
                onClick={() => removeEnvVar(index)}
                className="text-theme-error"
              >
                <Trash2 className="h-4 w-4" />
              </Button>
            </div>
          ))
        )}
      </div>
    </div>
  );
};
