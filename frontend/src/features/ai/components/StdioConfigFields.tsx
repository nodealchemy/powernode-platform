import React from 'react';
import { Plus, Trash2 } from 'lucide-react';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';

interface StdioConfigFieldsProps {
  command: string;
  onCommandChange: (value: string) => void;
  commandError?: string;
  args: string[];
  onArgsChange: (args: string[]) => void;
}

export const StdioConfigFields: React.FC<StdioConfigFieldsProps> = ({
  command,
  onCommandChange,
  commandError,
  args,
  onArgsChange,
}) => {
  const addArg = () => {
    onArgsChange([...args, '']);
  };

  const removeArg = (index: number) => {
    onArgsChange(args.filter((_, i) => i !== index));
  };

  const updateArg = (index: number, value: string) => {
    const newArgs = [...args];
    newArgs[index] = value;
    onArgsChange(newArgs);
  };

  return (
    <>
      <div>
        <label className="block text-sm font-medium text-theme-primary mb-1">
          Command *
        </label>
        <Input
          type="text"
          value={command}
          onChange={(e) => onCommandChange(e.target.value)}
          placeholder="e.g., node, python, /usr/local/bin/mcp-server"
          className={commandError ? 'border-theme-error' : ''}
        />
        {commandError && (
          <p className="mt-1 text-sm text-theme-error">{commandError}</p>
        )}
      </div>

      <div>
        <div className="flex items-center justify-between mb-2">
          <label className="text-sm font-medium text-theme-primary">
            Command Arguments
          </label>
          <Button
            type="button"
            variant="ghost"
            size="sm"
            onClick={addArg}
          >
            <Plus className="h-4 w-4 mr-1" />
            Add Argument
          </Button>
        </div>
        <div className="space-y-2">
          {args.length === 0 ? (
            <p className="text-sm text-theme-tertiary">
              No arguments configured. Click &quot;Add Argument&quot; to add command line arguments.
            </p>
          ) : (
            args.map((arg, index) => (
              <div key={index} className="flex items-center gap-2">
                <Input
                  type="text"
                  value={arg}
                  onChange={(e) => updateArg(index, e.target.value)}
                  placeholder={`Argument ${index + 1}`}
                  className="flex-1"
                />
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  onClick={() => removeArg(index)}
                  className="text-theme-error"
                >
                  <Trash2 className="h-4 w-4" />
                </Button>
              </div>
            ))
          )}
        </div>
      </div>
    </>
  );
};
