import React from 'react';
import { AlertTriangle } from 'lucide-react';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Checkbox } from '@/shared/components/ui/Checkbox';
import { EnhancedSelect } from '@/shared/components/ui/EnhancedSelect';
import type { NodeTypeConfigProps } from './types';

interface AiAgentNodeConfigProps extends NodeTypeConfigProps {
  nodeData?: {
     
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
  const useModelOverride = config.configuration?.use_model_override === true;

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
                  description: `${agent.agent_type} | Model: ${agent.model || 'Unknown'} | Provider: ${agent.provider?.name || 'Unknown'}`
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
                  {selectedAgent.model || 'Not configured'}
                </span>
              </div>
              <div>
                <span className="text-theme-muted">Provider:</span>
                <span className="ml-1 text-theme-secondary">
                  {selectedAgent.provider?.name || 'Not configured'}
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
            Warning: Selected agent not found or not accessible
          </p>
        )}
      </div>

      {/* Model Override */}
      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <Checkbox
          label="Override Model Settings"
          description="Use custom model settings instead of agent defaults"
          checked={useModelOverride}
          onCheckedChange={(checked) => handleConfigChange('use_model_override', checked)}
        />

        {useModelOverride && (
          <div className="mt-3 space-y-3 pt-3 border-t border-theme">
            <EnhancedSelect
              label="Model"
              value={config.configuration.model_override || ''}
              onChange={(value) => handleConfigChange('model_override', value)}
              options={[
                { value: 'gpt-4o', label: 'GPT-4o' },
                { value: 'gpt-4o-mini', label: 'GPT-4o Mini' },
                { value: 'gpt-4-turbo', label: 'GPT-4 Turbo' },
                { value: 'claude-3-5-sonnet-latest', label: 'Claude 3.5 Sonnet' },
                { value: 'claude-3-5-haiku-latest', label: 'Claude 3.5 Haiku' },
                { value: 'claude-3-opus-latest', label: 'Claude 3 Opus' }
              ]}
              placeholder="Select model..."
            />

            <Input
              label="Temperature"
              type="number"
              value={config.configuration.temperature ?? 0.7}
              onChange={(e) => handleConfigChange('temperature', parseFloat(e.target.value))}
              min={0}
              max={2}
              step={0.1}
              description="0 = deterministic, 2 = creative"
            />

            <Input
              label="Max Tokens"
              type="number"
              value={config.configuration.max_tokens || 1000}
              onChange={(e) => handleConfigChange('max_tokens', parseInt(e.target.value))}
              min={1}
              max={128000}
              description="Maximum tokens in response"
            />
          </div>
        )}
      </div>

      {/* System Prompt */}
      <Textarea
        label="System Prompt"
        value={config.configuration.system_prompt || ''}
        onChange={(e) => handleConfigChange('system_prompt', e.target.value)}
        placeholder="You are a helpful assistant that specializes in...&#10;&#10;Guidelines:&#10;- Be concise and accurate&#10;- Format output as JSON when requested"
        rows={4}
        description="Instructions that define the agent's behavior and role"
      />

      {/* User Prompt Template */}
      <div>
        <Textarea
          label="User Prompt Template"
          value={config.configuration.prompt_template || ''}
          onChange={(e) => handleConfigChange('prompt_template', e.target.value)}
          placeholder="Analyze the following data: {{input}}&#10;&#10;Context: {{context}}&#10;&#10;Provide detailed insights and recommendations."
          rows={4}
          description="The main prompt with {{variable}} placeholders"
        />
        {!config.configuration.prompt_template?.trim() && (
          <p className="text-xs text-theme-warning mt-1 flex items-center gap-1">
            <AlertTriangle className="h-3 w-3" />
            Prompt template is recommended for execution
          </p>
        )}
      </div>

      {/* Additional Context */}
      <Textarea
        label="Additional Context"
        value={config.configuration.context || ''}
        onChange={(e) => handleConfigChange('context', e.target.value)}
        placeholder="Background information, domain knowledge, or reference data..."
        rows={3}
        description="Extra context passed to every execution"
      />

      {/* Input Mapping */}
      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-sm font-medium text-theme-primary mb-3">Input Mapping</p>
        <Textarea
          label="Variable Mappings (JSON)"
          value={
            typeof config.configuration.input_mapping === 'object'
              ? JSON.stringify(config.configuration.input_mapping, null, 2)
              : config.configuration.input_mapping || ''
          }
          onChange={(e) => {
            try {
              const parsed = JSON.parse(e.target.value);
              handleConfigChange('input_mapping', parsed);
            } catch {
              handleConfigChange('input_mapping', e.target.value);
            }
          }}
          placeholder={'{\n  "input": "{{previous_node.output}}",\n  "user_data": "{{start.user_info}}",\n  "context": "{{api_call.response.data}}"\n}'}
          rows={4}
          description="Map variables from previous nodes to prompt placeholders"
        />
      </div>

      {/* Output Configuration */}
      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-sm font-medium text-theme-primary mb-3">Output Configuration</p>

        <div className="space-y-3">
          <Input
            label="Output Variable Name"
            value={config.configuration.output_variable || 'output'}
            onChange={(e) => handleConfigChange('output_variable', e.target.value)}
            placeholder="output"
            description="Variable name to store the agent response"
          />

          <EnhancedSelect
            label="Output Format"
            value={config.configuration.output_format || 'text'}
            onChange={(value) => handleConfigChange('output_format', value)}
            options={[
              { value: 'text', label: 'Plain Text' },
              { value: 'json', label: 'JSON (parsed)' },
              { value: 'markdown', label: 'Markdown' }
            ]}
          />

          {config.configuration.output_format === 'json' && (
            <Checkbox
              label="Validate JSON Output"
              description="Fail if agent response is not valid JSON"
              checked={config.configuration.validate_json === true}
              onCheckedChange={(checked) => handleConfigChange('validate_json', checked)}
            />
          )}
        </div>
      </div>

      {/* Output Variables Reference */}
      <div className="p-3 bg-theme-surface-elevated rounded-lg border border-theme">
        <p className="text-xs text-theme-secondary">
          <strong>Output Variables:</strong>
        </p>
        <ul className="text-xs text-theme-muted mt-1 space-y-0.5">
          <li><code className="text-theme-accent">output</code> - Agent response (or custom name)</li>
          <li><code className="text-theme-accent">tokens_used</code> - Total tokens consumed</li>
          <li><code className="text-theme-accent">model</code> - Model used for execution</li>
          <li><code className="text-theme-accent">duration_ms</code> - Execution time</li>
        </ul>
      </div>
    </div>
  );
};
