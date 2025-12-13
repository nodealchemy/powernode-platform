import React from 'react';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import { useMcpToolsForWorkflow } from '@/shared/hooks/useMcpToolsForWorkflow';
import { Wrench, AlertTriangle, Loader2, FileJson } from 'lucide-react';
import type { McpToolForWorkflowBuilder } from '@/shared/types/workflow';

interface McpToolSelectorProps {
  serverId: string | undefined;
  value: string | undefined;
  onChange: (toolId: string, tool: McpToolForWorkflowBuilder | null) => void;
  error?: string;
  disabled?: boolean;
  label?: string;
  required?: boolean;
}

/**
 * Selector for MCP tools from a specific server.
 */
export const McpToolSelector: React.FC<McpToolSelectorProps> = ({
  serverId,
  value,
  onChange,
  error,
  disabled = false,
  label = 'Tool',
  required = false,
}) => {
  const { tools, loading, error: fetchError } = useMcpToolsForWorkflow(serverId);

  if (!serverId) {
    return (
      <div className="space-y-2">
        <label className="block text-sm font-medium text-theme-primary">
          {label}
          {required && <span className="text-theme-error ml-1">*</span>}
        </label>
        <div className="flex items-center gap-2 p-3 rounded-lg border border-theme bg-theme-surface text-theme-muted">
          <Wrench className="h-4 w-4" />
          <span className="text-sm">Select a server first to see available tools</span>
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
          <span className="text-sm text-theme-muted">Loading tools...</span>
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

  if (tools.length === 0) {
    return (
      <div className="space-y-2">
        <label className="block text-sm font-medium text-theme-primary">
          {label}
          {required && <span className="text-theme-error ml-1">*</span>}
        </label>
        <div className="flex items-center gap-2 p-3 rounded-lg border border-theme-warning bg-theme-warning-background">
          <Wrench className="h-4 w-4 text-theme-warning" />
          <span className="text-sm text-theme-warning">No tools available on this server</span>
        </div>
      </div>
    );
  }

  const options = tools.map((tool) => ({
    value: tool.id,
    label: tool.name,
    description: tool.description || 'No description',
  }));

  const selectedTool = tools.find(t => t.id === value);

  const handleChange = (toolId: string) => {
    const tool = tools.find(t => t.id === toolId) || null;
    onChange(toolId, tool);
  };

  return (
    <div className="space-y-2">
      <EnhancedSelect
        label={label}
        value={value || ''}
        onChange={handleChange}
        options={options}
        placeholder="Select a tool..."
        disabled={disabled}
        error={error}
      />

      {/* Tool Details */}
      {selectedTool && (
        <div className="p-3 bg-theme-surface border border-theme rounded-lg">
          <div className="flex items-start gap-3">
            <div className="w-8 h-8 bg-theme-interactive-primary/10 rounded-lg flex items-center justify-center">
              <Wrench className="h-4 w-4 text-theme-interactive-primary" />
            </div>
            <div className="flex-1 min-w-0">
              <div className="text-sm font-medium text-theme-primary">
                {selectedTool.name}
              </div>
              {selectedTool.description && (
                <p className="text-xs text-theme-muted mt-1 line-clamp-2">
                  {selectedTool.description}
                </p>
              )}
              {selectedTool.input_schema && (
                <div className="flex items-center gap-1 mt-2 text-xs text-theme-info">
                  <FileJson className="h-3 w-3" />
                  <span>
                    {Object.keys(selectedTool.input_schema.properties || selectedTool.input_schema || {}).length} parameters
                  </span>
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      <p className="text-xs text-theme-muted">
        {tools.length} tool{tools.length !== 1 ? 's' : ''} available
      </p>
    </div>
  );
};

export default McpToolSelector;
