import React, { useState } from 'react';
import { RefreshCw, Clock, TrendingUp, AlertCircle, Settings, Info } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';

export interface RetryConfiguration {
  enabled: boolean;
  max_retries: number;
  strategy: 'exponential' | 'linear' | 'fixed' | 'custom';
  initial_delay_ms: number;
  max_delay_ms: number;
  backoff_multiplier?: number;
  linear_increment_ms?: number;
  fixed_delay_ms?: number;
  custom_delays_ms?: number[];
  jitter: boolean;
  retry_on_errors: string[];
}

export interface RetryConfigurationPanelProps {
  config: RetryConfiguration;
  onChange: (config: RetryConfiguration) => void;
  nodeLevel?: boolean;
  workflowDefault?: RetryConfiguration;
  disabled?: boolean;
  className?: string;
}

const DEFAULT_RETRY_ERRORS = [
  { value: 'timeout', label: 'Timeout' },
  { value: 'rate_limit', label: 'Rate Limit' },
  { value: 'temporary_failure', label: 'Temporary Failure' },
  { value: 'network_error', label: 'Network Error' },
  { value: '503_error', label: '503 Service Unavailable' },
  { value: '429_error', label: '429 Too Many Requests' }
];

export const RetryConfigurationPanel: React.FC<RetryConfigurationPanelProps> = ({
  config,
  onChange,
  nodeLevel = false,
  workflowDefault,
  disabled = false,
  className = ''
}) => {
  const [showAdvanced, setShowAdvanced] = useState(false);

  const handleConfigChange = (updates: Partial<RetryConfiguration>) => {
    onChange({ ...config, ...updates });
  };

  const calculateExampleDelays = () => {
    const delays: number[] = [];

    for (let attempt = 0; attempt < config.max_retries; attempt++) {
      let delay = 0;

      switch (config.strategy) {
        case 'exponential':
          delay = config.initial_delay_ms * Math.pow(config.backoff_multiplier || 2, attempt);
          break;
        case 'linear':
          delay = config.initial_delay_ms + (config.linear_increment_ms || 1000) * attempt;
          break;
        case 'fixed':
          delay = config.fixed_delay_ms || config.initial_delay_ms;
          break;
        case 'custom':
          delay = config.custom_delays_ms?.[attempt] || config.custom_delays_ms?.[config.custom_delays_ms.length - 1] || 5000;
          break;
      }

      // Apply max delay cap
      delay = Math.min(delay, config.max_delay_ms);
      delays.push(delay);
    }

    return delays;
  };

  const formatDelay = (ms: number) => {
    if (ms < 1000) return `${ms}ms`;
    return `${(ms / 1000).toFixed(1)}s`;
  };

  const isUsingWorkflowDefault = nodeLevel && !config.enabled && !!workflowDefault;
  const effectiveConfig = isUsingWorkflowDefault ? workflowDefault : config;

  return (
    <Card className={`p-4 ${className}`}>
      {/* Header */}
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <RefreshCw className="h-5 w-5 text-theme-interactive-primary" />
          <h3 className="text-lg font-semibold text-theme-primary">
            {nodeLevel ? 'Node Retry Configuration' : 'Workflow Retry Configuration'}
          </h3>
        </div>

        {nodeLevel && (
          <label className="flex items-center gap-2 cursor-pointer">
            <input
              type="checkbox"
              checked={config.enabled}
              onChange={(e) => handleConfigChange({ enabled: e.target.checked })}
              disabled={disabled}
              className="rounded border-theme text-theme-interactive-primary focus:ring-theme-interactive-primary"
            />
            <span className="text-sm text-theme-secondary">Override workflow default</span>
          </label>
        )}
      </div>

      {/* Workflow default indicator */}
      {isUsingWorkflowDefault && (
        <div className="mb-4 p-3 bg-theme-info/10 border border-theme-info/20 rounded-lg">
          <div className="flex items-start gap-2">
            <Info className="h-4 w-4 text-theme-info mt-0.5 flex-shrink-0" />
            <div className="text-sm text-theme-info">
              Using workflow default configuration. Enable override to customize for this node.
            </div>
          </div>
        </div>
      )}

      <div className="space-y-4">
        {/* Basic Configuration */}
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">
              Max Retries
            </label>
            <Input
              type="number"
              min="0"
              max="10"
              value={effectiveConfig.max_retries}
              onChange={(e) => handleConfigChange({ max_retries: parseInt(e.target.value) || 0 })}
              disabled={disabled || isUsingWorkflowDefault}
              className="w-full"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">
              Retry Strategy
            </label>
            <Select
              value={effectiveConfig.strategy}
              onChange={(value) => handleConfigChange({ strategy: value as RetryConfiguration['strategy'] })}
              disabled={disabled || isUsingWorkflowDefault}
              className="w-full"
            >
              <option value="exponential">Exponential Backoff</option>
              <option value="linear">Linear Backoff</option>
              <option value="fixed">Fixed Delay</option>
              <option value="custom">Custom Schedule</option>
            </Select>
          </div>
        </div>

        {/* Strategy-specific configuration */}
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">
              Initial Delay (ms)
            </label>
            <Input
              type="number"
              min="100"
              step="100"
              value={effectiveConfig.initial_delay_ms}
              onChange={(e) => handleConfigChange({ initial_delay_ms: parseInt(e.target.value) || 1000 })}
              disabled={disabled || isUsingWorkflowDefault}
              className="w-full"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">
              Max Delay (ms)
            </label>
            <Input
              type="number"
              min="1000"
              step="1000"
              value={effectiveConfig.max_delay_ms}
              onChange={(e) => handleConfigChange({ max_delay_ms: parseInt(e.target.value) || 60000 })}
              disabled={disabled || isUsingWorkflowDefault}
              className="w-full"
            />
          </div>
        </div>

        {/* Exponential backoff multiplier */}
        {effectiveConfig.strategy === 'exponential' && (
          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">
              Backoff Multiplier
            </label>
            <Input
              type="number"
              min="1.1"
              max="5"
              step="0.1"
              value={effectiveConfig.backoff_multiplier || 2}
              onChange={(e) => handleConfigChange({ backoff_multiplier: parseFloat(e.target.value) || 2 })}
              disabled={disabled || isUsingWorkflowDefault}
              className="w-full"
            />
            <p className="text-xs text-theme-muted mt-1">
              Each retry delay = previous delay × multiplier
            </p>
          </div>
        )}

        {/* Linear increment */}
        {effectiveConfig.strategy === 'linear' && (
          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">
              Linear Increment (ms)
            </label>
            <Input
              type="number"
              min="100"
              step="100"
              value={effectiveConfig.linear_increment_ms || 1000}
              onChange={(e) => handleConfigChange({ linear_increment_ms: parseInt(e.target.value) || 1000 })}
              disabled={disabled || isUsingWorkflowDefault}
              className="w-full"
            />
            <p className="text-xs text-theme-muted mt-1">
              Delay increases by this amount each retry
            </p>
          </div>
        )}

        {/* Fixed delay */}
        {effectiveConfig.strategy === 'fixed' && (
          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">
              Fixed Delay (ms)
            </label>
            <Input
              type="number"
              min="100"
              step="100"
              value={effectiveConfig.fixed_delay_ms || effectiveConfig.initial_delay_ms}
              onChange={(e) => handleConfigChange({ fixed_delay_ms: parseInt(e.target.value) || 1000 })}
              disabled={disabled || isUsingWorkflowDefault}
              className="w-full"
            />
          </div>
        )}

        {/* Custom delays */}
        {effectiveConfig.strategy === 'custom' && (
          <div>
            <label className="block text-sm font-medium text-theme-secondary mb-1">
              Custom Delay Schedule (ms, comma-separated)
            </label>
            <Input
              type="text"
              placeholder="1000, 2000, 5000, 10000"
              value={(effectiveConfig.custom_delays_ms || []).join(', ')}
              onChange={(e) => {
                const delays = e.target.value.split(',').map(d => parseInt(d.trim())).filter(d => !isNaN(d));
                handleConfigChange({ custom_delays_ms: delays });
              }}
              disabled={disabled || isUsingWorkflowDefault}
              className="w-full"
            />
            <p className="text-xs text-theme-muted mt-1">
              Specify exact delays for each retry attempt
            </p>
          </div>
        )}

        {/* Jitter toggle */}
        <label className="flex items-center gap-2 cursor-pointer">
          <input
            type="checkbox"
            checked={effectiveConfig.jitter}
            onChange={(e) => handleConfigChange({ jitter: e.target.checked })}
            disabled={disabled || isUsingWorkflowDefault}
            className="rounded border-theme text-theme-interactive-primary focus:ring-theme-interactive-primary"
          />
          <span className="text-sm text-theme-secondary">
            Add jitter (±10% randomization to prevent thundering herd)
          </span>
        </label>

        {/* Retryable errors */}
        <div>
          <label className="block text-sm font-medium text-theme-secondary mb-2">
            Retry on Error Types
          </label>
          <div className="space-y-2">
            {DEFAULT_RETRY_ERRORS.map(error => (
              <label key={error.value} className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={effectiveConfig.retry_on_errors.includes(error.value)}
                  onChange={(e) => {
                    const errors = e.target.checked
                      ? [...effectiveConfig.retry_on_errors, error.value]
                      : effectiveConfig.retry_on_errors.filter(err => err !== error.value);
                    handleConfigChange({ retry_on_errors: errors });
                  }}
                  disabled={disabled || isUsingWorkflowDefault}
                  className="rounded border-theme text-theme-interactive-primary focus:ring-theme-interactive-primary"
                />
                <span className="text-sm text-theme-primary">{error.label}</span>
              </label>
            ))}
          </div>
        </div>

        {/* Example delay preview */}
        {effectiveConfig.max_retries > 0 && (
          <div className="mt-4 p-3 bg-theme-background rounded-lg">
            <div className="flex items-center gap-2 mb-2">
              <TrendingUp className="h-4 w-4 text-theme-secondary" />
              <h4 className="text-sm font-medium text-theme-secondary">Retry Schedule Preview</h4>
            </div>
            <div className="flex flex-wrap gap-2">
              {calculateExampleDelays().map((delay, index) => (
                <div
                  key={index}
                  className="px-3 py-1 bg-theme-surface border border-theme rounded-lg"
                >
                  <div className="text-xs text-theme-muted">Attempt {index + 1}</div>
                  <div className="text-sm font-medium text-theme-primary">{formatDelay(delay)}</div>
                </div>
              ))}
            </div>
            <div className="mt-2 flex items-start gap-2 text-xs text-theme-muted">
              <Clock className="h-3 w-3 mt-0.5 flex-shrink-0" />
              <span>
                Total retry time: {formatDelay(calculateExampleDelays().reduce((sum, delay) => sum + delay, 0))}
                {effectiveConfig.jitter && ' (±10% with jitter)'}
              </span>
            </div>
          </div>
        )}

        {/* Warning if retries disabled */}
        {effectiveConfig.max_retries === 0 && (
          <div className="p-3 bg-theme-warning/10 border border-theme-warning/20 rounded-lg">
            <div className="flex items-start gap-2">
              <AlertCircle className="h-4 w-4 text-theme-warning mt-0.5 flex-shrink-0" />
              <div className="text-sm text-theme-warning">
                Retries are disabled. Nodes will fail immediately on error without retry attempts.
              </div>
            </div>
          </div>
        )}

        {/* Advanced settings toggle */}
        <button
          onClick={() => setShowAdvanced(!showAdvanced)}
          disabled={disabled || isUsingWorkflowDefault}
          className="flex items-center gap-2 text-sm text-theme-interactive-primary hover:underline"
        >
          <Settings className="h-4 w-4" />
          {showAdvanced ? 'Hide' : 'Show'} Advanced Settings
        </button>

        {/* Advanced settings */}
        {showAdvanced && (
          <div className="space-y-3 p-3 bg-theme-background rounded-lg">
            <p className="text-xs text-theme-muted">
              Advanced retry configuration options coming soon: custom error handlers, conditional retries, retry callbacks
            </p>
          </div>
        )}
      </div>
    </Card>
  );
};
