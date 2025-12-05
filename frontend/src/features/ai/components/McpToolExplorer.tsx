import React, { useState, useCallback } from 'react';
import { Play, Loader2, CheckCircle2, XCircle, Copy, Code, FileText } from 'lucide-react';
import { Modal } from '@/shared/components/ui/Modal';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Badge } from '@/shared/components/ui/Badge';
import { useNotifications } from '@/shared/hooks/useNotifications';
import type { McpTool } from '@/pages/app/ai/McpBrowserPage';

export interface McpToolExplorerProps {
  tool: McpTool;
  isOpen: boolean;
  onClose: () => void;
  onExecuteTool?: (toolId: string, params: Record<string, any>) => Promise<any>;
}

interface ToolParameter {
  name: string;
  type: string;
  description?: string;
  required: boolean;
  enum?: string[];
  default?: any;
}

interface ExecutionResult {
  success: boolean;
  result?: any;
  error?: string;
  execution_time_ms?: number;
}

export const McpToolExplorer: React.FC<McpToolExplorerProps> = ({
  tool,
  isOpen,
  onClose,
  onExecuteTool
}) => {
  const [parameters, setParameters] = useState<Record<string, any>>({});
  const [executing, setExecuting] = useState(false);
  const [executionResult, setExecutionResult] = useState<ExecutionResult | null>(null);
  const [showRawSchema, setShowRawSchema] = useState(false);

  const { addNotification } = useNotifications();

  // Extract parameters from JSON schema
  const extractedParameters: ToolParameter[] = React.useMemo(() => {
    if (!tool.input_schema || !tool.input_schema.properties) return [];

    const props = tool.input_schema.properties;
    const required = tool.input_schema.required || [];

    return Object.entries(props).map(([name, schema]: [string, any]) => ({
      name,
      type: schema.type || 'string',
      description: schema.description,
      required: required.includes(name),
      enum: schema.enum,
      default: schema.default
    }));
  }, [tool.input_schema]);

  // Initialize default values
  React.useEffect(() => {
    const defaults: Record<string, any> = {};
    extractedParameters.forEach(param => {
      if (param.default !== undefined) {
        defaults[param.name] = param.default;
      }
    });
    setParameters(defaults);
    setExecutionResult(null);
  }, [extractedParameters]);

  const handleParameterChange = (name: string, value: any) => {
    setParameters(prev => ({
      ...prev,
      [name]: value
    }));
  };

  const validateParameters = (): boolean => {
    // Check required parameters
    const missingRequired = extractedParameters
      .filter(p => p.required && !parameters[p.name])
      .map(p => p.name);

    if (missingRequired.length > 0) {
      addNotification({
        type: 'warning',
        title: 'Missing Required Parameters',
        message: `Please provide values for: ${missingRequired.join(', ')}`
      });
      return false;
    }

    // Validate array/object parameters (JSON)
    for (const param of extractedParameters) {
      if (['array', 'object'].includes(param.type) && parameters[param.name]) {
        try {
          JSON.parse(parameters[param.name]);
        } catch {
          addNotification({
            type: 'error',
            title: 'Invalid JSON',
            message: `Parameter "${param.name}" must be valid JSON`
          });
          return false;
        }
      }
    }

    return true;
  };

  const handleExecute = useCallback(async () => {
    if (!validateParameters()) return;

    try {
      setExecuting(true);
      setExecutionResult(null);

      // Convert parameters to appropriate types
      const processedParams: Record<string, any> = {};
      extractedParameters.forEach(param => {
        const value = parameters[param.name];
        if (value === undefined || value === '') return;

        switch (param.type) {
          case 'number':
          case 'integer':
            processedParams[param.name] = parseFloat(value);
            break;
          case 'boolean':
            processedParams[param.name] = value === 'true' || value === true;
            break;
          case 'array':
          case 'object':
            try {
              processedParams[param.name] = JSON.parse(value);
            } catch {
              processedParams[param.name] = value;
            }
            break;
          default:
            processedParams[param.name] = value;
        }
      });

      const startTime = Date.now();

      if (onExecuteTool) {
        const result = await onExecuteTool(tool.id, processedParams);
        const executionTime = Date.now() - startTime;

        setExecutionResult({
          success: true,
          result,
          execution_time_ms: executionTime
        });

        addNotification({
          type: 'success',
          title: 'Tool Executed',
          message: `${tool.name} executed successfully in ${executionTime}ms`
        });
      } else {
        // Mock execution for development
        await new Promise(resolve => setTimeout(resolve, 1000));
        const executionTime = Date.now() - startTime;

        setExecutionResult({
          success: true,
          result: {
            message: 'Mock execution successful',
            parameters: processedParams,
            timestamp: new Date().toISOString()
          },
          execution_time_ms: executionTime
        });

        addNotification({
          type: 'info',
          title: 'Mock Execution',
          message: 'This is a mock execution. Connect to a real MCP server for actual results.'
        });
      }
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error occurred';

      setExecutionResult({
        success: false,
        error: errorMessage
      });

      addNotification({
        type: 'error',
        title: 'Execution Failed',
        message: errorMessage
      });
    } finally {
      setExecuting(false);
    }
  }, [tool, parameters, extractedParameters, onExecuteTool, addNotification, validateParameters]);

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text);
    addNotification({
      type: 'success',
      title: 'Copied',
      message: 'Copied to clipboard'
    });
  };

  const renderParameterInput = (param: ToolParameter) => {
    const value = parameters[param.name] || '';

    if (param.enum) {
      return (
        <select
          value={value}
          onChange={(e) => handleParameterChange(param.name, e.target.value)}
          className="w-full px-3 py-2 bg-theme-input border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
        >
          <option value="">Select {param.name}...</option>
          {param.enum.map(option => (
            <option key={option} value={option}>{option}</option>
          ))}
        </select>
      );
    }

    if (param.type === 'boolean') {
      return (
        <select
          value={value.toString()}
          onChange={(e) => handleParameterChange(param.name, e.target.value)}
          className="w-full px-3 py-2 bg-theme-input border border-theme rounded-lg text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary"
        >
          <option value="">Select value...</option>
          <option value="true">true</option>
          <option value="false">false</option>
        </select>
      );
    }

    if (param.type === 'array' || param.type === 'object') {
      return (
        <textarea
          value={value}
          onChange={(e) => handleParameterChange(param.name, e.target.value)}
          placeholder={param.type === 'array' ? '["item1", "item2"]' : '{"key": "value"}'}
          className="w-full px-3 py-2 bg-theme-input border border-theme rounded-lg text-theme-primary font-mono text-sm focus:outline-none focus:ring-2 focus:ring-theme-interactive-primary resize-none"
          rows={3}
        />
      );
    }

    return (
      <Input
        type={param.type === 'number' || param.type === 'integer' ? 'number' : 'text'}
        value={value}
        onChange={(e) => handleParameterChange(param.name, e.target.value)}
        placeholder={`Enter ${param.name}...`}
      />
    );
  };

  return (
    <Modal
      isOpen={isOpen}
      onClose={onClose}
      title={`Test Tool: ${tool.name}`}
      size="lg"
    >
      <div className="space-y-6">
        {/* Tool Info */}
        <div className="p-4 bg-theme-surface rounded-lg">
          <div className="flex items-center justify-between mb-2">
            <h3 className="font-semibold text-theme-primary">{tool.name}</h3>
            <Badge variant="outline" size="sm">{tool.server_name}</Badge>
          </div>
          {tool.description && (
            <p className="text-sm text-theme-secondary mb-3">{tool.description}</p>
          )}
          {tool.category && (
            <Badge variant="outline" size="sm" className="capitalize">
              {tool.category}
            </Badge>
          )}
        </div>

        {/* Parameters */}
        {extractedParameters.length > 0 ? (
          <div>
            <h4 className="text-sm font-medium text-theme-primary mb-3">
              Parameters {extractedParameters.filter(p => p.required).length > 0 && (
                <span className="text-theme-tertiary">
                  ({extractedParameters.filter(p => p.required).length} required)
                </span>
              )}
            </h4>
            <div className="space-y-3">
              {extractedParameters.map(param => (
                <div key={param.name}>
                  <label className="block text-sm text-theme-primary mb-1">
                    {param.name}
                    {param.required && <span className="text-theme-error ml-1">*</span>}
                    <span className="text-theme-tertiary ml-2 text-xs">({param.type})</span>
                  </label>
                  {param.description && (
                    <p className="text-xs text-theme-tertiary mb-2">{param.description}</p>
                  )}
                  {renderParameterInput(param)}
                </div>
              ))}
            </div>
          </div>
        ) : (
          <div className="text-center py-6 text-theme-tertiary">
            <FileText className="h-8 w-8 mx-auto mb-2 opacity-50" />
            <p className="text-sm">This tool requires no parameters</p>
          </div>
        )}

        {/* Schema Toggle */}
        <div className="flex items-center justify-between pt-2 border-t border-theme">
          <button
            onClick={() => setShowRawSchema(!showRawSchema)}
            className="text-sm text-theme-interactive-primary hover:underline flex items-center gap-1"
          >
            <Code className="h-4 w-4" />
            {showRawSchema ? 'Hide' : 'Show'} JSON Schema
          </button>
        </div>

        {/* Raw Schema */}
        {showRawSchema && (
          <div className="relative">
            <pre className="p-4 bg-theme-surface border border-theme rounded-lg text-xs overflow-x-auto">
              <code className="text-theme-primary">
                {JSON.stringify(tool.input_schema, null, 2)}
              </code>
            </pre>
            <Button
              variant="ghost"
              size="sm"
              onClick={() => copyToClipboard(JSON.stringify(tool.input_schema, null, 2))}
              className="absolute top-2 right-2"
            >
              <Copy className="h-4 w-4" />
            </Button>
          </div>
        )}

        {/* Execution Result */}
        {executionResult && (
          <div className={`p-4 rounded-lg border ${
            executionResult.success
              ? 'bg-theme-success bg-opacity-5 border-theme-success'
              : 'bg-theme-error bg-opacity-5 border-theme-error'
          }`}>
            <div className="flex items-center gap-2 mb-3">
              {executionResult.success ? (
                <CheckCircle2 className="h-5 w-5 text-theme-success" />
              ) : (
                <XCircle className="h-5 w-5 text-theme-error" />
              )}
              <span className="font-medium text-theme-primary">
                {executionResult.success ? 'Execution Successful' : 'Execution Failed'}
              </span>
              {executionResult.execution_time_ms && (
                <Badge variant="outline" size="sm" className="ml-auto">
                  {executionResult.execution_time_ms}ms
                </Badge>
              )}
            </div>

            {executionResult.error && (
              <div className="text-sm text-theme-error">
                <p className="font-medium mb-1">Error:</p>
                <p>{executionResult.error}</p>
              </div>
            )}

            {executionResult.result && (
              <div className="relative">
                <p className="text-xs text-theme-tertiary mb-2">Result:</p>
                <pre className="p-3 bg-theme-surface rounded text-xs overflow-x-auto max-h-64">
                  <code className="text-theme-primary">
                    {JSON.stringify(executionResult.result, null, 2)}
                  </code>
                </pre>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => copyToClipboard(JSON.stringify(executionResult.result, null, 2))}
                  className="absolute top-6 right-2"
                >
                  <Copy className="h-4 w-4" />
                </Button>
              </div>
            )}
          </div>
        )}

        {/* Actions */}
        <div className="flex justify-end gap-3 pt-4 border-t border-theme">
          <Button
            variant="outline"
            onClick={onClose}
            disabled={executing}
          >
            Close
          </Button>
          <Button
            onClick={handleExecute}
            disabled={executing}
            className="flex items-center gap-2"
          >
            {executing ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin" />
                Executing...
              </>
            ) : (
              <>
                <Play className="h-4 w-4" />
                Execute Tool
              </>
            )}
          </Button>
        </div>
      </div>
    </Modal>
  );
};
