import React, { useState, useEffect, useCallback } from 'react';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/shared/components/ui/Tabs';
import { McpServerSelector } from './McpServerSelector';
import { McpPromptSelector } from './McpPromptSelector';
import type { McpPromptForWorkflowBuilder } from '@/shared/types/workflow';

interface McpPromptConfigPanelProps {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  configuration: Record<string, any>;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  onConfigChange: (key: string, value: any) => void;
  errors?: Record<string, string>;
  disabled?: boolean;
}

/**
 * Configuration panel for MCP Prompt nodes in the workflow builder.
 */
export const McpPromptConfigPanel: React.FC<McpPromptConfigPanelProps> = ({
  configuration,
  onConfigChange,
  errors = {},
  disabled = false,
}) => {
  const [activeTab, setActiveTab] = useState<'form' | 'json'>('form');
  const [selectedPrompt, setSelectedPrompt] = useState<McpPromptForWorkflowBuilder | null>(null);
  const [jsonArguments, setJsonArguments] = useState('');

  // Initialize JSON arguments from configuration
  useEffect(() => {
    setJsonArguments(JSON.stringify(configuration.arguments || {}, null, 2));
  }, [configuration.prompt_name]);

  // Handle server change - reset prompt selection
  const handleServerChange = useCallback((serverId: string) => {
    onConfigChange('mcp_server_id', serverId);
    onConfigChange('mcp_server_name', '');
    onConfigChange('prompt_name', '');
    onConfigChange('prompt_description', '');
    onConfigChange('arguments_schema', undefined);
    onConfigChange('arguments', {});
    onConfigChange('argument_mappings', []);
    setSelectedPrompt(null);
  }, [onConfigChange]);

  // Handle prompt change
  const handlePromptChange = useCallback((promptName: string, prompt: McpPromptForWorkflowBuilder | null) => {
    onConfigChange('prompt_name', promptName);
    setSelectedPrompt(prompt);

    if (prompt) {
      onConfigChange('prompt_description', prompt.description || '');

      // Initialize arguments from prompt schema
      const defaults: Record<string, string> = {};
      if (prompt.arguments) {
        prompt.arguments.forEach((arg) => {
          defaults[arg.name] = '';
        });
      }
      onConfigChange('arguments', defaults);
      setJsonArguments(JSON.stringify(defaults, null, 2));
    }
  }, [onConfigChange]);

  // Handle argument change
  const handleArgumentChange = useCallback((argName: string, value: string) => {
    const newArgs = {
      ...configuration.arguments,
      [argName]: value,
    };
    onConfigChange('arguments', newArgs);
    setJsonArguments(JSON.stringify(newArgs, null, 2));
  }, [configuration.arguments, onConfigChange]);

  // Handle JSON editor changes
  const handleJsonChange = useCallback((value: string) => {
    setJsonArguments(value);
    try {
      const parsed = JSON.parse(value);
      onConfigChange('arguments', parsed);
    } catch {
      // Invalid JSON, don't update arguments
    }
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

      {/* Prompt Selection */}
      <McpPromptSelector
        serverId={configuration.mcp_server_id}
        value={configuration.prompt_name}
        onChange={handlePromptChange}
        error={errors.prompt}
        disabled={disabled || !configuration.mcp_server_id}
        required
      />

      {/* Arguments Section */}
      {selectedPrompt && selectedPrompt.arguments && selectedPrompt.arguments.length > 0 && (
        <div className="border border-theme rounded-lg p-3">
          <h4 className="text-sm font-medium text-theme-primary mb-3">Prompt Arguments</h4>

          <Tabs value={activeTab} onValueChange={(v) => setActiveTab(v as 'form' | 'json')}>
            <TabsList className="mb-3">
              <TabsTrigger value="form">Form</TabsTrigger>
              <TabsTrigger value="json">JSON</TabsTrigger>
            </TabsList>

            <TabsContent value="form" className="mt-0 space-y-3">
              {selectedPrompt.arguments.map((arg) => (
                <div key={arg.name}>
                  <Input
                    label={arg.required ? `${arg.name} *` : arg.name}
                    value={configuration.arguments?.[arg.name] || ''}
                    onChange={(e) => handleArgumentChange(arg.name, e.target.value)}
                    placeholder={`Enter ${arg.name} or use {{variable}}`}
                    disabled={disabled}
                    error={errors[`arg_${arg.name}`]}
                  />
                  {arg.description && (
                    <p className="text-xs text-theme-muted mt-1">{arg.description}</p>
                  )}
                </div>
              ))}
            </TabsContent>

            <TabsContent value="json" className="mt-0">
              <Textarea
                value={jsonArguments}
                onChange={(e) => handleJsonChange(e.target.value)}
                rows={8}
                className="font-mono text-sm"
                placeholder="{}"
                disabled={disabled}
              />
              <p className="text-xs text-theme-muted mt-2">
                Use {'{{variable}}'} syntax to reference workflow variables.
              </p>
            </TabsContent>
          </Tabs>
        </div>
      )}

      {/* Output Variable */}
      <Input
        label="Output Variable (Optional)"
        value={configuration.output_variable || ''}
        onChange={(e) => onConfigChange('output_variable', e.target.value)}
        placeholder="prompt_messages"
        disabled={disabled}
      />
      <p className="text-xs text-theme-muted -mt-2">
        Store the prompt messages in this variable for use in subsequent nodes (e.g., AI Agent).
      </p>

      {/* Info Box */}
      <div className="p-3 bg-theme-info-background border border-theme-info rounded-lg">
        <p className="text-xs text-theme-info">
          <strong>Tip:</strong> MCP Prompts return structured messages that can be passed to AI agents.
          The output includes role-based messages (system, user, assistant) that guide the AI's behavior.
        </p>
      </div>
    </div>
  );
};

export default McpPromptConfigPanel;
