import React from 'react';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import { Input } from '@/shared/components/ui/Input';
import { useMcpResourcesForWorkflow } from '@/shared/hooks/useMcpToolsForWorkflow';
import { Database, AlertTriangle, Loader2 } from 'lucide-react';

interface McpResourceSelectorProps {
  serverId: string | undefined;
  value: string | undefined;
  onChange: (resourceUri: string) => void;
  error?: string;
  disabled?: boolean;
  label?: string;
  required?: boolean;
  allowCustomUri?: boolean;
}

/**
 * Selector for MCP resources from a specific server.
 */
export const McpResourceSelector: React.FC<McpResourceSelectorProps> = ({
  serverId,
  value,
  onChange,
  error,
  disabled = false,
  label = 'Resource',
  required = false,
  allowCustomUri = true,
}) => {
  const { resources, loading, error: fetchError } = useMcpResourcesForWorkflow(serverId);
  const [useCustomUri, setUseCustomUri] = React.useState(false);

  if (!serverId) {
    return (
      <div className="space-y-2">
        <label className="block text-sm font-medium text-theme-primary">
          {label}
          {required && <span className="text-theme-error ml-1">*</span>}
        </label>
        <div className="flex items-center gap-2 p-3 rounded-lg border border-theme bg-theme-surface text-theme-muted">
          <Database className="h-4 w-4" />
          <span className="text-sm">Select a server first to see available resources</span>
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
          <span className="text-sm text-theme-muted">Loading resources...</span>
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

  // If no resources available or using custom URI
  if (resources.length === 0 || useCustomUri) {
    return (
      <div className="space-y-2">
        <Input
          label={label}
          value={value || ''}
          onChange={(e) => onChange(e.target.value)}
          placeholder="file://path/to/resource or {{variable}}"
          disabled={disabled}
          error={error}
          required={required}
        />
        {resources.length === 0 && (
          <p className="text-xs text-theme-muted">
            No resources discovered. Enter a URI manually or use a workflow variable.
          </p>
        )}
        {allowCustomUri && resources.length > 0 && (
          <button
            type="button"
            onClick={() => setUseCustomUri(false)}
            className="text-xs text-theme-interactive-primary hover:underline"
          >
            Select from discovered resources
          </button>
        )}
      </div>
    );
  }

  const options = resources.map((resource) => ({
    value: resource.uri,
    label: resource.name || resource.uri,
    description: resource.mime_type || resource.description || resource.uri,
  }));

  const selectedResource = resources.find(r => r.uri === value);

  return (
    <div className="space-y-2">
      <EnhancedSelect
        label={label}
        value={value || ''}
        onChange={onChange}
        options={options}
        placeholder="Select a resource..."
        disabled={disabled}
        error={error}
      />

      {/* Resource Details */}
      {selectedResource && (
        <div className="p-3 bg-theme-surface border border-theme rounded-lg">
          <div className="flex items-start gap-3">
            <div className="w-8 h-8 bg-theme-info/10 rounded-lg flex items-center justify-center">
              <Database className="h-4 w-4 text-theme-info" />
            </div>
            <div className="flex-1 min-w-0">
              <div className="text-sm font-medium text-theme-primary">
                {selectedResource.name || 'Resource'}
              </div>
              <div className="text-xs text-theme-muted font-mono mt-1 truncate">
                {selectedResource.uri}
              </div>
              {selectedResource.mime_type && (
                <div className="text-xs text-theme-secondary mt-1">
                  Type: {selectedResource.mime_type}
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {allowCustomUri && (
        <button
          type="button"
          onClick={() => setUseCustomUri(true)}
          className="text-xs text-theme-interactive-primary hover:underline"
        >
          Enter custom URI instead
        </button>
      )}

      <p className="text-xs text-theme-muted">
        {resources.length} resource{resources.length !== 1 ? 's' : ''} discovered
      </p>
    </div>
  );
};

export default McpResourceSelector;
