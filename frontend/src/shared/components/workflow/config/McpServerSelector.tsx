import React from 'react';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import { useMcpServersForWorkflow } from '@/shared/hooks/useMcpServersForWorkflow';
import { Server, AlertTriangle, Loader2 } from 'lucide-react';

interface McpServerSelectorProps {
  value: string | undefined;
  onChange: (serverId: string) => void;
  error?: string;
  disabled?: boolean;
  label?: string;
  required?: boolean;
}

/**
 * Selector for MCP servers in the workflow builder.
 * Only shows connected servers that are ready for use.
 */
export const McpServerSelector: React.FC<McpServerSelectorProps> = ({
  value,
  onChange,
  error,
  disabled = false,
  label = 'MCP Server',
  required = false,
}) => {
  const { servers, loading, error: fetchError, totalTools } = useMcpServersForWorkflow();

  if (loading) {
    return (
      <div className="space-y-2">
        <label className="block text-sm font-medium text-theme-primary">
          {label}
          {required && <span className="text-theme-error ml-1">*</span>}
        </label>
        <div className="flex items-center gap-2 p-3 rounded-lg border border-theme bg-theme-surface">
          <Loader2 className="h-4 w-4 animate-spin text-theme-muted" />
          <span className="text-sm text-theme-muted">Loading servers...</span>
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
          <span className="text-sm text-theme-error">Failed to load servers: {fetchError}</span>
        </div>
      </div>
    );
  }

  if (servers.length === 0) {
    return (
      <div className="space-y-2">
        <label className="block text-sm font-medium text-theme-primary">
          {label}
          {required && <span className="text-theme-error ml-1">*</span>}
        </label>
        <div className="flex items-center gap-2 p-3 rounded-lg border border-theme-warning bg-theme-warning-background">
          <Server className="h-4 w-4 text-theme-warning" />
          <div>
            <span className="text-sm text-theme-warning font-medium">No connected servers</span>
            <p className="text-xs text-theme-muted mt-1">
              Connect an MCP server in the MCP Browser to use it in workflows.
            </p>
          </div>
        </div>
      </div>
    );
  }

  const options = servers.map((server) => ({
    value: server.id,
    label: server.name,
    description: `${server.tools.length} tools | ${server.connection_type}`,
  }));

  const selectedServer = servers.find(s => s.id === value);

  return (
    <div className="space-y-2">
      <EnhancedSelect
        label={label}
        value={value || ''}
        onChange={onChange}
        options={options}
        placeholder="Select an MCP server..."
        disabled={disabled}
        error={error}
      />

      {/* Server Info Display */}
      {selectedServer && (
        <div className="p-3 bg-theme-surface border border-theme rounded-lg">
          <div className="flex items-start gap-3">
            <div className="w-8 h-8 bg-theme-info/10 rounded-lg flex items-center justify-center">
              <Server className="h-4 w-4 text-theme-info" />
            </div>
            <div className="flex-1 min-w-0">
              <div className="text-sm font-medium text-theme-primary">
                {selectedServer.name}
              </div>
              {selectedServer.description && (
                <p className="text-xs text-theme-muted mt-1 line-clamp-2">
                  {selectedServer.description}
                </p>
              )}
              <div className="flex gap-4 mt-2 text-xs">
                <span className="text-theme-muted">
                  <span className="font-medium text-theme-primary">{selectedServer.tools.length}</span> tools
                </span>
                <span className="text-theme-muted">
                  <span className="font-medium text-theme-primary">{selectedServer.resources.length}</span> resources
                </span>
                <span className="text-theme-muted">
                  <span className="font-medium text-theme-primary">{selectedServer.prompts.length}</span> prompts
                </span>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Summary */}
      <p className="text-xs text-theme-muted">
        {servers.length} server{servers.length !== 1 ? 's' : ''} connected with {totalTools} total tools
      </p>
    </div>
  );
};

export default McpServerSelector;
