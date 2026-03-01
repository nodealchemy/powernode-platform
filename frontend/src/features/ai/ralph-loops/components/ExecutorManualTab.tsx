import React from 'react';
import {
  Bot,
  Workflow,
  GitBranch,
  Network,
  Container,
  User,
  Globe,
  Loader2,
} from 'lucide-react';
import { Input } from '@/shared/components/ui/Input';
import { Select } from '@/shared/components/ui/Select';
import type { RalphExecutionType, RalphDelegationConfig } from '@/shared/services/ai/types/ralph-types';

interface ExecutorOption {
  id: string;
  name: string;
  description?: string;
}

const executionTypeConfig: Record<RalphExecutionType, {
  label: string;
  icon: React.FC<{ className?: string }>;
}> = {
  agent: { label: 'AI Agent', icon: Bot },
  workflow: { label: 'Workflow', icon: Workflow },
  pipeline: { label: 'Pipeline', icon: GitBranch },
  a2a_task: { label: 'A2A Task', icon: Network },
  container: { label: 'Container', icon: Container },
  human: { label: 'Human Review', icon: User },
  community: { label: 'Community Agent', icon: Globe },
};

interface ExecutorManualTabProps {
  showAdvanced: boolean;
  delegationConfig: RalphDelegationConfig;
  fallbackExecutorOptions: ExecutorOption[];
  loadingFallbackExecutors: boolean;
  onToggleAdvanced: () => void;
  onDelegationConfigChange: (config: RalphDelegationConfig) => void;
}

export const ExecutorManualTab: React.FC<ExecutorManualTabProps> = ({
  showAdvanced,
  delegationConfig,
  fallbackExecutorOptions,
  loadingFallbackExecutors,
  onToggleAdvanced,
  onDelegationConfigChange,
}) => {
  return (
    <div className="space-y-4">
      {/* Advanced Options Toggle */}
      <button
        type="button"
        onClick={onToggleAdvanced}
        className="text-sm text-theme-brand-primary hover:underline"
      >
        {showAdvanced ? 'Hide' : 'Show'} Advanced Options
      </button>

      {/* Advanced: Delegation Config */}
      {showAdvanced && (
        <div className="space-y-3 pt-3 border-t border-theme-border-primary">
          <div>
            <label className="block text-sm font-medium text-theme-text-primary mb-1">
              Timeout (seconds)
            </label>
            <Input
              type="number"
              min={60}
              max={86400}
              placeholder="3600"
              value={delegationConfig.timeout_seconds || ''}
              onChange={(e) => onDelegationConfigChange({
                ...delegationConfig,
                timeout_seconds: parseInt(e.target.value) || undefined,
              })}
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-theme-text-primary mb-1">
              Fallback Executor Type
            </label>
            <Select
              value={delegationConfig.fallback_executor_type || ''}
              onChange={(value) => onDelegationConfigChange({
                ...delegationConfig,
                fallback_executor_type: (value as RalphExecutionType) || undefined,
              })}
            >
              <option value="">No fallback</option>
              {(Object.keys(executionTypeConfig) as RalphExecutionType[]).map((type) => (
                <option key={type} value={type}>{executionTypeConfig[type].label}</option>
              ))}
            </Select>
          </div>

          {delegationConfig.fallback_executor_type && (
            <div>
              <label className="block text-sm font-medium text-theme-text-primary mb-1">
                Fallback {executionTypeConfig[delegationConfig.fallback_executor_type]?.label}
              </label>
              {loadingFallbackExecutors ? (
                <div className="flex items-center gap-2 py-2">
                  <Loader2 className="w-4 h-4 animate-spin text-theme-text-secondary" />
                  <span className="text-sm text-theme-text-secondary">Loading executors...</span>
                </div>
              ) : fallbackExecutorOptions.length > 0 ? (
                <Select
                  value={delegationConfig.fallback_executor_id || ''}
                  onChange={(value) => onDelegationConfigChange({
                    ...delegationConfig,
                    fallback_executor_id: value || undefined,
                  })}
                  className="w-full"
                >
                  <option value="">Auto-select</option>
                  {fallbackExecutorOptions.map((option) => (
                    <option key={option.id} value={option.id}>{option.name}</option>
                  ))}
                </Select>
              ) : (
                <Input
                  type="text"
                  placeholder="Enter executor ID manually"
                  value={delegationConfig.fallback_executor_id || ''}
                  onChange={(e) => onDelegationConfigChange({
                    ...delegationConfig,
                    fallback_executor_id: e.target.value || undefined,
                  })}
                />
              )}
            </div>
          )}
        </div>
      )}
    </div>
  );
};
