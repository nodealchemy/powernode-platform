import React from 'react';
import { AlertTriangle } from 'lucide-react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from './types';

interface AiAgentNodeConfigProps extends NodeTypeConfigProps {
  nodeData?: {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    configuration?: Record<string, any>;
  };
  isAuthenticated: boolean;
  errors: Record<string, string>;
}

export const AiAgentNodeConfig: React.FC<AiAgentNodeConfigProps> = ({
  config,
  handleConfigChange,
  handlePositionsConfig,
  agents = [],
  loadingAgents = false,
  handleAgentChange,
  nodeData,
  isAuthenticated,
  errors
}) => {
  // Get agent ID from configuration - standardized as agent_id
  const agentId = config.configuration?.agent_id ||
                  nodeData?.configuration?.agent_id;

  const selectedAgent = agents?.find(a => a.id === agentId);

  return (
    <div className="space-y-4">
      {handlePositionsConfig}

      {/* Agent Selection */}
      <div>
        <EnhancedSelect
          label="Agent"
          value={agentId || ''}
          onChange={handleAgentChange || (() => {})}
          options={
            !agents || !Array.isArray(agents) || agents.length === 0
              ? []
              : agents.map(agent => ({
                  value: agent.id,
                  label: agent.name,
                  description: `${agent.agent_type} | Model: ${agent.mcp_metadata?.model_config?.model || 'Unknown'} | Provider: ${agent.ai_provider?.name || 'Unknown'}`
                }))
          }
          placeholder={
            !isAuthenticated ? "Login required to load agents" :
            loadingAgents ? "Loading agents..." :
            !agents || !Array.isArray(agents) || agents.length === 0 ? "No agents available" :
            "Select an agent..."
          }
          disabled={loadingAgents || !isAuthenticated}
          error={errors.agent}
        />
        {agentId && selectedAgent && !loadingAgents && (
          <div className="mt-2 p-3 bg-theme-surface border border-theme rounded-lg">
            <div className="grid grid-cols-2 gap-3 text-xs">
              <div>
                <span className="text-theme-muted">Type:</span>
                <span className="ml-1 text-theme-primary font-medium">
                  {selectedAgent.agent_type?.replace('_', ' ').replace(/\b\w/g, l => l.toUpperCase())}
                </span>
              </div>
              <div>
                <span className="text-theme-muted">Status:</span>
                <span className={`ml-1 font-medium ${
                  selectedAgent.status === 'active' ? 'text-theme-success' : 'text-theme-warning'
                }`}>
                  {selectedAgent.status}
                </span>
              </div>
              <div>
                <span className="text-theme-muted">Model:</span>
                <span className="ml-1 text-theme-secondary font-mono">
                  {selectedAgent.mcp_metadata?.model_config?.model || 'Not configured'}
                </span>
              </div>
              <div>
                <span className="text-theme-muted">Provider:</span>
                <span className="ml-1 text-theme-secondary">
                  {selectedAgent.ai_provider?.name || 'Not configured'}
                </span>
              </div>
            </div>
            {selectedAgent.description && (
              <p className="text-xs text-theme-muted mt-2 pt-2 border-t border-theme">
                {selectedAgent.description}
              </p>
            )}
          </div>
        )}
        {agentId && !selectedAgent && !loadingAgents && (
          <p className="text-xs mt-1 text-theme-warning">
            ⚠️ Selected agent not found or not accessible
          </p>
        )}
      </div>

      <div>
        <Textarea
          label="Prompt Template"
          value={config.configuration.prompt_template || ''}
          onChange={(e) => handleConfigChange('prompt_template', e.target.value)}
          placeholder="Enter prompt template with {{variables}}...&#10;&#10;Example:&#10;Analyze the following data: {{input}}&#10;Consider the context: {{context}}&#10;Provide detailed insights."
          rows={4}
        />
        {!config.configuration.prompt_template?.trim() && (
          <p className="text-xs text-theme-warning mt-1 flex items-center gap-1">
            <AlertTriangle className="h-3 w-3" />
            Prompt template is recommended for execution. You can save without it for now.
          </p>
        )}
        <p className="text-xs text-theme-muted mt-1">
          Use {'{{variableName}}'} to reference input variables. Standard variables: {'{{input}}, {{context}}, {{data}}'}
        </p>
      </div>

      <Input
        label="Temperature"
        type="number"
        value={config.configuration.temperature || 0.7}
        onChange={(e) => handleConfigChange('temperature', parseFloat(e.target.value))}
        min={0}
        max={2}
        step={0.1}
      />

      <Input
        label="Max Tokens"
        type="number"
        value={config.configuration.max_tokens || 1000}
        onChange={(e) => handleConfigChange('max_tokens', parseInt(e.target.value))}
        min={1}
        max={8000}
      />

      <div>
        <label className="block text-sm font-medium text-theme-primary mb-2">
          Input Variables
        </label>
        <Input
          value={(config.configuration.input_variables || ['input', 'context', 'data']).join(', ')}
          onChange={(e) => handleConfigChange('input_variables', e.target.value.split(',').map(v => v.trim()).filter(v => v))}
          placeholder="input, context, data"
        />
        <p className="text-xs text-theme-muted mt-1">
          Standard: input (main), context (metadata), data (structured)
        </p>
      </div>

      <div>
        <label className="block text-sm font-medium text-theme-primary mb-2">
          Output Variables
        </label>
        <Input
          value={(config.configuration.output_variables || ['output', 'result', 'data']).join(', ')}
          onChange={(e) => handleConfigChange('output_variables', e.target.value.split(',').map(v => v.trim()).filter(v => v))}
          placeholder="output, result, data"
        />
        <p className="text-xs text-theme-muted mt-1">
          Standard: output (main), result (processed), data (passthrough)
        </p>
      </div>
    </div>
  );
};
