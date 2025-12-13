import React from 'react';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import { useMcpPromptsForWorkflow } from '@/shared/hooks/useMcpToolsForWorkflow';
import { MessageSquareText, AlertTriangle, Loader2, FileJson } from 'lucide-react';
import type { McpPromptForWorkflowBuilder } from '@/shared/types/workflow';

interface McpPromptSelectorProps {
  serverId: string | undefined;
  value: string | undefined;
  onChange: (promptName: string, prompt: McpPromptForWorkflowBuilder | null) => void;
  error?: string;
  disabled?: boolean;
  label?: string;
  required?: boolean;
}

/**
 * Selector for MCP prompts from a specific server.
 */
export const McpPromptSelector: React.FC<McpPromptSelectorProps> = ({
  serverId,
  value,
  onChange,
  error,
  disabled = false,
  label = 'Prompt',
  required = false,
}) => {
  const { prompts, loading, error: fetchError } = useMcpPromptsForWorkflow(serverId);

  if (!serverId) {
    return (
      <div className="space-y-2">
        <label className="block text-sm font-medium text-theme-primary">
          {label}
          {required && <span className="text-theme-error ml-1">*</span>}
        </label>
        <div className="flex items-center gap-2 p-3 rounded-lg border border-theme bg-theme-surface text-theme-muted">
          <MessageSquareText className="h-4 w-4" />
          <span className="text-sm">Select a server first to see available prompts</span>
        </div>
      </div>
    );
  }

  if (loading) {
    return (
      <div className="space-y-2">
        <label className="block text-sm font-medium text-theme-primary">
          {label}
          {required && <span className="text-theme-error ml-1">*</span>}
        </label>
        <div className="flex items-center gap-2 p-3 rounded-lg border border-theme bg-theme-surface">
          <Loader2 className="h-4 w-4 animate-spin text-theme-muted" />
          <span className="text-sm text-theme-muted">Loading prompts...</span>
        </div>
      </div>
    );
  }

  if (fetchError) {
    return (
      <div className="space-y-2">
        <label className="block text-sm font-medium text-theme-primary">
          {label}
          {required && <span className="text-theme-error ml-1">*</span>}
        </label>
        <div className="flex items-center gap-2 p-3 rounded-lg border border-theme-error bg-theme-error-background">
          <AlertTriangle className="h-4 w-4 text-theme-error" />
          <span className="text-sm text-theme-error">{fetchError}</span>
        </div>
      </div>
    );
  }

  if (prompts.length === 0) {
    return (
      <div className="space-y-2">
        <label className="block text-sm font-medium text-theme-primary">
          {label}
          {required && <span className="text-theme-error ml-1">*</span>}
        </label>
        <div className="flex items-center gap-2 p-3 rounded-lg border border-theme-warning bg-theme-warning-background">
          <MessageSquareText className="h-4 w-4 text-theme-warning" />
          <span className="text-sm text-theme-warning">No prompts available on this server</span>
        </div>
      </div>
    );
  }

  const options = prompts.map((prompt) => ({
    value: prompt.name,
    label: prompt.name,
    description: prompt.description || 'No description',
  }));

  const selectedPrompt = prompts.find(p => p.name === value);

  const handleChange = (promptName: string) => {
    const prompt = prompts.find(p => p.name === promptName) || null;
    onChange(promptName, prompt);
  };

  return (
    <div className="space-y-2">
      <EnhancedSelect
        label={label}
        value={value || ''}
        onChange={handleChange}
        options={options}
        placeholder="Select a prompt..."
        disabled={disabled}
        error={error}
      />

      {/* Prompt Details */}
      {selectedPrompt && (
        <div className="p-3 bg-theme-surface border border-theme rounded-lg">
          <div className="flex items-start gap-3">
            <div className="w-8 h-8 bg-theme-warning/10 rounded-lg flex items-center justify-center">
              <MessageSquareText className="h-4 w-4 text-theme-warning" />
            </div>
            <div className="flex-1 min-w-0">
              <div className="text-sm font-medium text-theme-primary">
                {selectedPrompt.name}
              </div>
              {selectedPrompt.description && (
                <p className="text-xs text-theme-muted mt-1 line-clamp-2">
                  {selectedPrompt.description}
                </p>
              )}
              {selectedPrompt.arguments && selectedPrompt.arguments.length > 0 && (
                <div className="flex items-center gap-1 mt-2 text-xs text-theme-info">
                  <FileJson className="h-3 w-3" />
                  <span>
                    {selectedPrompt.arguments.length} argument{selectedPrompt.arguments.length !== 1 ? 's' : ''}
                  </span>
                </div>
              )}
            </div>
          </div>

          {/* Arguments Preview */}
          {selectedPrompt.arguments && selectedPrompt.arguments.length > 0 && (
            <div className="mt-3 pt-3 border-t border-theme">
              <div className="text-xs font-medium text-theme-primary mb-2">Arguments:</div>
              <div className="space-y-1">
                {selectedPrompt.arguments.map((arg) => (
                  <div key={arg.name} className="flex items-center gap-2 text-xs">
                    <span className="font-mono text-theme-secondary">{arg.name}</span>
                    {arg.required && (
                      <span className="text-theme-error">*</span>
                    )}
                    {arg.description && (
                      <span className="text-theme-muted truncate">- {arg.description}</span>
                    )}
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      <p className="text-xs text-theme-muted">
        {prompts.length} prompt{prompts.length !== 1 ? 's' : ''} available
      </p>
    </div>
  );
};

export default McpPromptSelector;
