import React, { useCallback } from 'react';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import { Input } from '@/shared/components/ui/Input';
import { McpServerSelector } from './McpServerSelector';
import { McpResourceSelector } from './McpResourceSelector';

interface McpResourceConfigPanelProps {
   
  configuration: Record<string, any>;
   
  onConfigChange: (key: string, value: any) => void;
  errors?: Record<string, string>;
  disabled?: boolean;
}

/**
 * Configuration panel for MCP Resource nodes in the workflow builder.
 */
export const McpResourceConfigPanel: React.FC<McpResourceConfigPanelProps> = ({
  configuration,
  onConfigChange,
  errors = {},
  disabled = false,
}) => {
  // Handle server change - reset resource selection
  const handleServerChange = useCallback((serverId: string) => {
    onConfigChange('mcp_server_id', serverId);
    onConfigChange('mcp_server_name', '');
    onConfigChange('resource_uri', '');
    onConfigChange('resource_name', '');
    onConfigChange('mime_type', '');
  }, [onConfigChange]);

  // Handle resource change
  const handleResourceChange = useCallback((resourceUri: string) => {
    onConfigChange('resource_uri', resourceUri);
  }, [onConfigChange]);

  return (
    <div className="space-y-4">
      {/* Connection Orientation */}
      <div className="mb-4">
        <EnhancedSelect
          label="Handle Position"
          value={configuration.orientation || 'vertical'}
          onChange={(value) => onConfigChange('orientation', value)}
          options={[
            { value: 'vertical', label: 'Vertical (Top/Bottom)' },
            { value: 'horizontal', label: 'Horizontal (Left/Right)' }
          ]}
          disabled={disabled}
        />
      </div>

      {/* Server Selection */}
      <McpServerSelector
        value={configuration.mcp_server_id}
        onChange={handleServerChange}
        error={errors.server}
        disabled={disabled}
        required
      />

      {/* Resource Selection / URI Input */}
      <McpResourceSelector
        serverId={configuration.mcp_server_id}
        value={configuration.resource_uri}
        onChange={handleResourceChange}
        error={errors.resource}
        disabled={disabled || !configuration.mcp_server_id}
        required
        allowCustomUri
      />

      {/* Output Variable */}
      <Input
        label="Output Variable (Optional)"
        value={configuration.output_variable || ''}
        onChange={(e) => onConfigChange('output_variable', e.target.value)}
        placeholder="resource_content"
        disabled={disabled}
      />
      <p className="text-xs text-theme-muted -mt-2">
        Store the resource content in this variable for use in subsequent nodes.
      </p>

      {/* Cache Configuration */}
      <div className="border border-theme rounded-lg p-3">
        <h4 className="text-sm font-medium text-theme-primary mb-3">Caching Options</h4>

        <div className="space-y-3">
          <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
            <input
              type="checkbox"
              checked={configuration.enable_caching !== false}
              onChange={(e) => onConfigChange('enable_caching', e.target.checked)}
              disabled={disabled}
              className="mt-0.5 rounded border-theme-border"
            />
            <div className="flex-1">
              <label className="text-sm font-medium text-theme-primary">
                Enable Caching
              </label>
              <p className="text-xs text-theme-muted mt-1">
                Cache resource content to avoid repeated fetches.
              </p>
            </div>
          </div>

          {configuration.enable_caching !== false && (
            <Input
              label="Cache Duration (seconds)"
              type="number"
              value={configuration.cache_duration_seconds || 300}
              onChange={(e) => onConfigChange('cache_duration_seconds', parseInt(e.target.value) || 300)}
              min={0}
              max={86400}
              disabled={disabled}
            />
          )}
        </div>
      </div>

      {/* Variable Substitution Info */}
      <div className="p-3 bg-theme-info-background border border-theme-info rounded-lg">
        <p className="text-xs text-theme-info">
          <strong>Tip:</strong> You can use workflow variables in the resource URI, e.g.,{' '}
          <code className="font-mono">file://{'{{path}}'}</code> or{' '}
          <code className="font-mono">db://users/{'{{user_id}}'}</code>
        </p>
      </div>
    </div>
  );
};

export default McpResourceConfigPanel;
