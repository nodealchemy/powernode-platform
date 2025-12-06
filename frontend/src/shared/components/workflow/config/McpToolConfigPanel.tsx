import React, { useState, useEffect, useCallback, useMemo } from 'react';
import { AlertCircle, CheckCircle } from 'lucide-react';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import { Input } from '@/shared/components/ui/Input';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/shared/components/ui/Tabs';
import { McpServerSelector } from './McpServerSelector';
import { McpToolSelector } from './McpToolSelector';
import { JsonSchemaForm } from './JsonSchemaForm';
import { Textarea } from '@/shared/components/ui/Textarea';
import { useSchemaValidation } from './validation/useSchemaValidation';
import type { McpToolForWorkflowBuilder } from '@/shared/types/workflow';

interface McpToolConfigPanelProps {
  configuration: Record<string, any>;
  onConfigChange: (key: string, value: any) => void;
  errors?: Record<string, string>;
  disabled?: boolean;
}

/**
 * Configuration panel for MCP Tool nodes in the workflow builder.
 */
export const McpToolConfigPanel: React.FC<McpToolConfigPanelProps> = ({
  configuration,
  onConfigChange,
  errors = {},
  disabled = false,
}) => {
  const [activeTab, setActiveTab] = useState<'form' | 'json'>('form');
  const [selectedTool, setSelectedTool] = useState<McpToolForWorkflowBuilder | null>(null);
  const [jsonParameters, setJsonParameters] = useState('');
  const [jsonError, setJsonError] = useState<string | null>(null);

  // Schema validation using AJV
  const schema = useMemo(() => selectedTool?.input_schema || null, [selectedTool]);
  const { validate, isSchemaValid } = useSchemaValidation(schema);

  // Validate current parameters
  const validationResult = useMemo(() => {
    if (!schema || !configuration.parameters) {
      return { isValid: true, errors: {} };
    }
    return validate(configuration.parameters);
  }, [schema, configuration.parameters, validate]);

  // Initialize JSON parameters from configuration
  useEffect(() => {
    setJsonParameters(JSON.stringify(configuration.parameters || {}, null, 2));
  }, [configuration.mcp_tool_id]);

  // Handle server change - reset tool selection
  const handleServerChange = useCallback((serverId: string) => {
    onConfigChange('mcp_server_id', serverId);
    onConfigChange('mcp_server_name', ''); // Will be set from server data
    onConfigChange('mcp_tool_id', '');
    onConfigChange('mcp_tool_name', '');
    onConfigChange('mcp_tool_description', '');
    onConfigChange('input_schema', undefined);
    onConfigChange('parameters', {});
    onConfigChange('parameter_mappings', []);
    setSelectedTool(null);
  }, [onConfigChange]);

  // Handle tool change
  const handleToolChange = useCallback((toolId: string, tool: McpToolForWorkflowBuilder | null) => {
    onConfigChange('mcp_tool_id', toolId);
    setSelectedTool(tool);

    if (tool) {
      onConfigChange('mcp_tool_name', tool.name);
      onConfigChange('mcp_tool_description', tool.description || '');
      onConfigChange('input_schema', tool.input_schema);

      // Initialize parameters with defaults from schema
      const defaults: Record<string, unknown> = {};
      const schema = tool.input_schema;
      if (schema?.properties) {
        Object.entries(schema.properties).forEach(([key, prop]: [string, any]) => {
          if (prop.default !== undefined) {
            defaults[key] = prop.default;
          }
        });
      }
      onConfigChange('parameters', defaults);
      setJsonParameters(JSON.stringify(defaults, null, 2));
    }
  }, [onConfigChange]);

  // Handle parameter changes from form
  const handleParametersChange = useCallback((params: Record<string, unknown>) => {
    onConfigChange('parameters', params);
    setJsonParameters(JSON.stringify(params, null, 2));
  }, [onConfigChange]);

  // Handle JSON editor changes
  const handleJsonChange = useCallback((value: string) => {
    setJsonParameters(value);
    try {
      const parsed = JSON.parse(value);
      onConfigChange('parameters', parsed);
      setJsonError(null);
    } catch (e) {
      // Invalid JSON, don't update parameters
      setJsonError(e instanceof Error ? e.message : 'Invalid JSON');
    }
  }, [onConfigChange]);

  // Combine validation errors with external errors
  const combinedErrors = useMemo(() => ({
    ...errors,
    ...validationResult.errors,
  }), [errors, validationResult.errors]);

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

      {/* Tool Selection */}
      <McpToolSelector
        serverId={configuration.mcp_server_id}
        value={configuration.mcp_tool_id}
        onChange={handleToolChange}
        error={errors.tool}
        disabled={disabled || !configuration.mcp_server_id}
        required
      />

      {/* Execution Mode */}
      <EnhancedSelect
        label="Execution Mode"
        value={configuration.execution_mode || 'sync'}
        onChange={(value) => onConfigChange('execution_mode', value)}
        options={[
          { value: 'sync', label: 'Synchronous', description: 'Wait for result before continuing' },
          { value: 'async', label: 'Asynchronous', description: 'Continue immediately, get result later' }
        ]}
        disabled={disabled}
      />

      {/* Timeout */}
      <Input
        label="Timeout (seconds)"
        type="number"
        value={configuration.timeout_seconds || 300}
        onChange={(e) => onConfigChange('timeout_seconds', parseInt(e.target.value) || 300)}
        min={1}
        max={3600}
        disabled={disabled}
      />

      {/* Parameters Section */}
      {selectedTool && selectedTool.input_schema && (
        <div className="border border-theme rounded-lg p-3">
          <div className="flex items-center justify-between mb-3">
            <h4 className="text-sm font-medium text-theme-primary">Tool Parameters</h4>
            {/* Validation Status Indicator */}
            {isSchemaValid && (
              <div className="flex items-center gap-1.5">
                {validationResult.isValid ? (
                  <>
                    <CheckCircle className="h-4 w-4 text-theme-success" />
                    <span className="text-xs text-theme-success">Valid</span>
                  </>
                ) : (
                  <>
                    <AlertCircle className="h-4 w-4 text-theme-error" />
                    <span className="text-xs text-theme-error">
                      {Object.keys(validationResult.errors).length} error(s)
                    </span>
                  </>
                )}
              </div>
            )}
          </div>

          <Tabs value={activeTab} onValueChange={(v) => setActiveTab(v as 'form' | 'json')}>
            <TabsList className="mb-3">
              <TabsTrigger value="form">Form</TabsTrigger>
              <TabsTrigger value="json">JSON</TabsTrigger>
            </TabsList>

            <TabsContent value="form" className="mt-0">
              <JsonSchemaForm
                schema={selectedTool.input_schema}
                values={configuration.parameters || {}}
                onChange={handleParametersChange}
                errors={combinedErrors}
                disabled={disabled}
              />
            </TabsContent>

            <TabsContent value="json" className="mt-0">
              <Textarea
                value={jsonParameters}
                onChange={(e) => handleJsonChange(e.target.value)}
                rows={8}
                className={`font-mono text-sm ${jsonError ? 'border-theme-error' : ''}`}
                placeholder="{}"
                disabled={disabled}
              />
              {jsonError && (
                <p className="text-xs text-theme-error mt-1 flex items-center gap-1">
                  <AlertCircle className="h-3 w-3" />
                  {jsonError}
                </p>
              )}
              <p className="text-xs text-theme-muted mt-2">
                Use {'{{variable}}'} syntax to reference workflow variables.
              </p>
              {/* Show validation errors in JSON mode too */}
              {!jsonError && !validationResult.isValid && (
                <div className="mt-2 p-2 bg-theme-error/10 rounded border border-theme-error">
                  <p className="text-xs text-theme-error font-medium mb-1">Validation Errors:</p>
                  <ul className="text-xs text-theme-error space-y-0.5">
                    {Object.entries(validationResult.errors).map(([field, msg]) => (
                      <li key={field}>• {field}: {msg}</li>
                    ))}
                  </ul>
                </div>
              )}
            </TabsContent>
          </Tabs>
        </div>
      )}

      {/* Output Variable */}
      <Input
        label="Output Variable (Optional)"
        value={configuration.output_variable || ''}
        onChange={(e) => onConfigChange('output_variable', e.target.value)}
        placeholder="tool_result"
        disabled={disabled}
      />
      <p className="text-xs text-theme-muted -mt-2">
        Store the tool result in this variable for use in subsequent nodes.
      </p>

      {/* Retry Configuration */}
      <div className="flex items-start gap-3 p-3 rounded-lg border border-theme-border bg-theme-surface">
        <input
          type="checkbox"
          checked={configuration.retry_on_failure || false}
          onChange={(e) => onConfigChange('retry_on_failure', e.target.checked)}
          disabled={disabled}
          className="mt-0.5 rounded border-theme-border"
        />
        <div className="flex-1">
          <label className="text-sm font-medium text-theme-primary">
            Retry on Failure
          </label>
          <p className="text-xs text-theme-muted mt-1">
            Automatically retry the tool execution if it fails.
          </p>
        </div>
      </div>
    </div>
  );
};

export default McpToolConfigPanel;
