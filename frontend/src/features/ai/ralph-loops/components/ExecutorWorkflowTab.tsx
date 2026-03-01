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
import { Select } from '@/shared/components/ui/Select';
import { Input } from '@/shared/components/ui/Input';
import { cn } from '@/shared/utils/cn';
import type { RalphExecutionType } from '@/shared/services/ai/types/ralph-types';

interface ExecutorOption {
  id: string;
  name: string;
  description?: string;
}

const executionTypeConfig: Record<RalphExecutionType, {
  label: string;
  description: string;
  icon: React.FC<{ className?: string }>;
}> = {
  agent: { label: 'AI Agent', description: 'Execute via internal AI agent', icon: Bot },
  workflow: { label: 'Workflow', description: 'Execute via multi-step workflow', icon: Workflow },
  pipeline: { label: 'Pipeline', description: 'Execute via CI/CD pipeline', icon: GitBranch },
  a2a_task: { label: 'A2A Task', description: 'Delegate via A2A protocol', icon: Network },
  container: { label: 'Container', description: 'Execute in sandboxed container', icon: Container },
  human: { label: 'Human Review', description: 'Queue for human review', icon: User },
  community: { label: 'Community Agent', description: 'Execute via community agent', icon: Globe },
};

interface ExecutorWorkflowTabProps {
  executionType: RalphExecutionType;
  executorId: string;
  executorOptions: ExecutorOption[];
  loadingExecutors: boolean;
  onExecutionTypeChange: (type: RalphExecutionType) => void;
  onExecutorIdChange: (id: string) => void;
}

export const ExecutorWorkflowTab: React.FC<ExecutorWorkflowTabProps> = ({
  executionType,
  executorId,
  executorOptions,
  loadingExecutors,
  onExecutionTypeChange,
  onExecutorIdChange,
}) => {
  return (
    <div className="space-y-4">
      {/* Execution Type Selection */}
      <div>
        <label className="block text-sm font-medium text-theme-text-primary mb-2">
          Execution Type
        </label>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-2">
          {(Object.keys(executionTypeConfig) as RalphExecutionType[]).map((type) => {
            const config = executionTypeConfig[type];
            const Icon = config.icon;
            const isSelected = executionType === type;
            return (
              <button
                key={type}
                type="button"
                onClick={() => onExecutionTypeChange(type)}
                className={cn(
                  'relative flex flex-col items-center justify-center p-3 h-20 rounded-lg border-2 transition-all',
                  'hover:border-theme-brand-primary/50 hover:bg-theme-brand-primary/5',
                  isSelected
                    ? 'border-theme-brand-primary bg-theme-brand-primary/20 ring-2 ring-theme-brand-primary/30'
                    : 'border-theme-border-primary bg-theme-bg-primary'
                )}
              >
                <Icon className={cn(
                  'w-6 h-6 mb-1',
                  isSelected ? 'text-theme-brand-primary' : 'text-theme-text-secondary'
                )} />
                <span className={cn(
                  'text-xs font-medium text-center',
                  isSelected ? 'text-theme-brand-primary font-semibold' : 'text-theme-text-primary'
                )}>
                  {config.label}
                </span>
                {isSelected && (
                  <div className="absolute top-1 right-1 w-2 h-2 rounded-full bg-theme-brand-primary" />
                )}
              </button>
            );
          })}
        </div>
        <p className="mt-2 text-xs text-theme-text-secondary">
          {executionTypeConfig[executionType].description}
        </p>
      </div>

      {/* Executor ID */}
      <div>
        <label className="block text-sm font-medium text-theme-text-primary mb-1">
          Specific Executor {executionTypeConfig[executionType]?.label} (Optional)
        </label>
        {loadingExecutors ? (
          <div className="flex items-center gap-2 py-2">
            <Loader2 className="w-4 h-4 animate-spin text-theme-text-secondary" />
            <span className="text-sm text-theme-text-secondary">Loading executors...</span>
          </div>
        ) : executorOptions.length > 0 ? (
          <Select
            value={executorId}
            onChange={(value) => onExecutorIdChange(value)}
            className="w-full"
          >
            <option value="">Auto-select based on capabilities</option>
            {executorOptions.map((option) => (
              <option key={option.id} value={option.id}>{option.name}</option>
            ))}
          </Select>
        ) : (
          <Input
            type="text"
            placeholder="Enter executor ID manually"
            value={executorId}
            onChange={(e) => onExecutorIdChange(e.target.value)}
            className="w-full"
          />
        )}
        <p className="mt-1 text-xs text-theme-text-secondary">
          If specified, this executor will be used directly. Otherwise, capability matching will be used.
        </p>
      </div>
    </div>
  );
};
