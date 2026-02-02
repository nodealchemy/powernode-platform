import React, { useState, useCallback, useEffect } from 'react';
import {
  Bot,
  Workflow,
  GitBranch,
  Network,
  Container,
  User,
  Globe,
  Plus,
  X,
  Settings,
  Loader2,
  FileText,
  Trash2,
} from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Select } from '@/shared/components/ui/Select';
import { Button } from '@/shared/components/ui/Button';
import { Input } from '@/shared/components/ui/Input';
import { Textarea } from '@/shared/components/ui/Textarea';
import { Badge } from '@/shared/components/ui/Badge';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/shared/components/ui/Tabs';
import { cn } from '@/shared/utils/cn';
import { agentsApi } from '@/shared/services/ai/AgentsApiService';
import { workflowsApi } from '@/shared/services/ai/WorkflowsApiService';
import type {
  RalphExecutionType,
  RalphCapabilityMatchStrategy,
  RalphDelegationConfig,
  UpdateRalphTaskExecutorRequest,
} from '@/shared/services/ai/types/ralph-types';

interface ExecutorOption {
  id: string;
  name: string;
  description?: string;
}

interface TaskDefinition {
  key: string;
  description: string;
  dependencies: string[];
  acceptance_criteria?: string;
}

interface RalphTaskExecutorSelectProps {
  taskId: string;
  // Task definition fields
  taskKey: string;
  taskDescription: string;
  taskDependencies: string[];
  taskAcceptanceCriteria?: string;
  availableTaskKeys?: string[]; // Other task keys that can be selected as dependencies
  // Executor fields
  executionType: RalphExecutionType;
  executorId?: string;
  requiredCapabilities?: string[];
  capabilityMatchStrategy?: RalphCapabilityMatchStrategy;
  delegationConfig?: RalphDelegationConfig;
  // Callbacks
  onSave: (taskDef: TaskDefinition, executorConfig: UpdateRalphTaskExecutorRequest) => void;
  onDelete?: () => void;
  onCancel?: () => void;
  isDeleting?: boolean;
  className?: string;
}

const executionTypeConfig: Record<RalphExecutionType, {
  label: string;
  description: string;
  icon: React.FC<{ className?: string }>;
}> = {
  agent: {
    label: 'AI Agent',
    description: 'Execute via internal AI agent',
    icon: Bot,
  },
  workflow: {
    label: 'Workflow',
    description: 'Execute via multi-step workflow',
    icon: Workflow,
  },
  pipeline: {
    label: 'Pipeline',
    description: 'Execute via CI/CD pipeline',
    icon: GitBranch,
  },
  a2a_task: {
    label: 'A2A Task',
    description: 'Delegate via A2A protocol',
    icon: Network,
  },
  container: {
    label: 'Container',
    description: 'Execute in sandboxed container',
    icon: Container,
  },
  human: {
    label: 'Human Review',
    description: 'Queue for human review',
    icon: User,
  },
  community: {
    label: 'Community Agent',
    description: 'Execute via community agent',
    icon: Globe,
  },
};

const matchStrategyOptions = [
  { value: 'all', label: 'Match All', description: 'Executor must have all capabilities' },
  { value: 'any', label: 'Match Any', description: 'Executor must have at least one capability' },
  { value: 'weighted', label: 'Weighted', description: 'Score executors by capability overlap' },
];

export const RalphTaskExecutorSelect: React.FC<RalphTaskExecutorSelectProps> = ({
  // Task definition props
  taskKey: initialTaskKey,
  taskDescription: initialTaskDescription,
  taskDependencies: initialTaskDependencies = [],
  taskAcceptanceCriteria: initialTaskAcceptanceCriteria,
  availableTaskKeys = [],
  // Executor props
  executionType: initialType,
  executorId: initialExecutorId,
  requiredCapabilities: initialCapabilities = [],
  capabilityMatchStrategy: initialStrategy = 'all',
  delegationConfig: initialDelegationConfig = {},
  // Callbacks
  onSave,
  onDelete,
  onCancel,
  isDeleting = false,
  className,
}) => {
  // Task definition state
  const [taskKey, setTaskKey] = useState(initialTaskKey);
  const [taskDescription, setTaskDescription] = useState(initialTaskDescription);
  const [taskDependencies, setTaskDependencies] = useState<string[]>(initialTaskDependencies);
  const [taskAcceptanceCriteria, setTaskAcceptanceCriteria] = useState(initialTaskAcceptanceCriteria || '');

  // Executor state
  const [executionType, setExecutionType] = useState<RalphExecutionType>(initialType);
  const [executorId, setExecutorId] = useState<string>(initialExecutorId || '');
  const [capabilities, setCapabilities] = useState<string[]>(initialCapabilities);
  const [matchStrategy, setMatchStrategy] = useState<RalphCapabilityMatchStrategy>(initialStrategy);
  const [newCapability, setNewCapability] = useState('');
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [delegationConfig, setDelegationConfig] = useState<RalphDelegationConfig>(initialDelegationConfig);

  // UI state
  const [activeTab, setActiveTab] = useState<'definition' | 'executor'>('definition');

  // Executor options state
  const [executorOptions, setExecutorOptions] = useState<ExecutorOption[]>([]);
  const [loadingExecutors, setLoadingExecutors] = useState(false);
  const [fallbackExecutorOptions, setFallbackExecutorOptions] = useState<ExecutorOption[]>([]);
  const [loadingFallbackExecutors, setLoadingFallbackExecutors] = useState(false);

  // Available capabilities from API
  const [availableCapabilities, setAvailableCapabilities] = useState<Record<string, string[]>>({});
  const [loadingCapabilities, setLoadingCapabilities] = useState(true);

  // Fetch available capabilities on mount
  useEffect(() => {
    const loadCapabilities = async () => {
      setLoadingCapabilities(true);
      try {
        const response = await agentsApi.getCapabilities();
        setAvailableCapabilities(response.categorized || {});
      } catch {
        // If API fails, set empty - user can still add custom capabilities
        setAvailableCapabilities({});
      } finally {
        setLoadingCapabilities(false);
      }
    };
    loadCapabilities();
  }, []);

  // Fetch executors based on execution type
  const fetchExecutors = useCallback(async (type: RalphExecutionType): Promise<ExecutorOption[]> => {
    try {
      switch (type) {
        case 'agent': {
          const response = await agentsApi.getAgents({ per_page: 100 });
          return (response.items || []).map((agent) => ({
            id: agent.id,
            name: agent.name,
            description: agent.description,
          }));
        }
        case 'workflow': {
          const response = await workflowsApi.getWorkflows({ per_page: 100 });
          return (response.items || []).map((workflow) => ({
            id: workflow.id,
            name: workflow.name,
            description: workflow.description,
          }));
        }
        // For other types, we don't have a dedicated API yet
        // Return empty array and user can enter ID manually
        default:
          return [];
      }
    } catch {
      return [];
    }
  }, []);

  // Load executors when execution type changes
  useEffect(() => {
    const loadExecutors = async () => {
      setLoadingExecutors(true);
      const options = await fetchExecutors(executionType);
      setExecutorOptions(options);
      setLoadingExecutors(false);
    };
    loadExecutors();
  }, [executionType, fetchExecutors]);

  // Load fallback executors when fallback type changes
  useEffect(() => {
    const loadFallbackExecutors = async () => {
      if (!delegationConfig.fallback_executor_type) {
        setFallbackExecutorOptions([]);
        return;
      }
      setLoadingFallbackExecutors(true);
      const options = await fetchExecutors(delegationConfig.fallback_executor_type);
      setFallbackExecutorOptions(options);
      setLoadingFallbackExecutors(false);
    };
    loadFallbackExecutors();
  }, [delegationConfig.fallback_executor_type, fetchExecutors]);

  const handleAddCapability = useCallback(() => {
    const cap = newCapability.trim().toLowerCase();
    if (cap && !capabilities.includes(cap)) {
      setCapabilities([...capabilities, cap]);
      setNewCapability('');
    }
  }, [newCapability, capabilities]);

  const handleRemoveCapability = useCallback((cap: string) => {
    setCapabilities(capabilities.filter(c => c !== cap));
  }, [capabilities]);

  const handleSave = useCallback(() => {
    const taskDef: TaskDefinition = {
      key: taskKey.replace(/\s/g, '_'),
      description: taskDescription,
      dependencies: taskDependencies,
      acceptance_criteria: taskAcceptanceCriteria || undefined,
    };
    const executorConfig: UpdateRalphTaskExecutorRequest = {
      execution_type: executionType,
      executor_id: executorId || undefined,
      required_capabilities: capabilities,
      capability_match_strategy: matchStrategy,
      delegation_config: showAdvanced ? delegationConfig : undefined,
    };
    onSave(taskDef, executorConfig);
  }, [taskKey, taskDescription, taskDependencies, taskAcceptanceCriteria, executionType, executorId, capabilities, matchStrategy, delegationConfig, showAdvanced, onSave]);

  return (
    <Card className={cn('border-theme-border-primary', className)}>
      <CardContent className="pt-4">
        <Tabs value={activeTab} onValueChange={(v) => setActiveTab(v as 'definition' | 'executor')}>
          <TabsList className="mb-4">
            <TabsTrigger value="definition" className="flex items-center gap-1.5">
              <FileText className="w-4 h-4" />
              Definition
            </TabsTrigger>
            <TabsTrigger value="executor" className="flex items-center gap-1.5">
              <Settings className="w-4 h-4" />
              Executor
            </TabsTrigger>
          </TabsList>

          {/* Definition Tab */}
          <TabsContent value="definition" className="space-y-4">
            <div>
              <label className="block text-sm font-medium text-theme-text-primary mb-1">
                Task Key
              </label>
              <Input
                value={taskKey}
                onChange={(e) => setTaskKey(e.target.value.replace(/\s/g, '_'))}
                placeholder="task_key"
                className="font-mono"
              />
              <p className="mt-1 text-xs text-theme-text-secondary">
                Unique identifier for this task (no spaces)
              </p>
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-text-primary mb-1">
                Description
              </label>
              <Textarea
                value={taskDescription}
                onChange={(e) => setTaskDescription(e.target.value)}
                placeholder="Describe what this task should accomplish..."
                rows={3}
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-text-primary mb-2">
                Dependencies
              </label>
              {availableTaskKeys.length > 0 ? (
                <div className="space-y-2 max-h-40 overflow-y-auto p-2 border border-theme-border-primary rounded-lg bg-theme-bg-primary">
                  {availableTaskKeys
                    .filter(key => key !== taskKey) // Can't depend on self
                    .map((key) => (
                      <label
                        key={key}
                        className="flex items-center gap-2 cursor-pointer hover:bg-theme-bg-secondary p-1.5 rounded"
                      >
                        <input
                          type="checkbox"
                          checked={taskDependencies.includes(key)}
                          onChange={(e) => {
                            if (e.target.checked) {
                              setTaskDependencies([...taskDependencies, key]);
                            } else {
                              setTaskDependencies(taskDependencies.filter(d => d !== key));
                            }
                          }}
                          className="w-4 h-4 rounded border-theme-border-primary text-theme-brand-primary focus:ring-theme-brand-primary"
                        />
                        <span className="font-mono text-sm text-theme-text-primary">{key}</span>
                      </label>
                    ))}
                  {availableTaskKeys.filter(key => key !== taskKey).length === 0 && (
                    <p className="text-sm text-theme-text-secondary py-2">
                      No other tasks available
                    </p>
                  )}
                </div>
              ) : (
                <p className="text-sm text-theme-text-secondary p-2 border border-theme-border-primary rounded-lg">
                  No other tasks available to select as dependencies
                </p>
              )}
              {taskDependencies.length > 0 && (
                <div className="flex flex-wrap gap-1.5 mt-2">
                  {taskDependencies.map((dep) => (
                    <Badge key={dep} variant="outline" size="sm">
                      {dep}
                    </Badge>
                  ))}
                </div>
              )}
              <p className="mt-1 text-xs text-theme-text-secondary">
                Select tasks that must complete before this task can start
              </p>
            </div>

            <div>
              <label className="block text-sm font-medium text-theme-text-primary mb-1">
                Acceptance Criteria
              </label>
              <Textarea
                value={taskAcceptanceCriteria}
                onChange={(e) => setTaskAcceptanceCriteria(e.target.value)}
                placeholder="Define what success looks like for this task..."
                rows={3}
              />
            </div>
          </TabsContent>

          {/* Executor Tab */}
          <TabsContent value="executor" className="space-y-4">
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
                      onClick={() => setExecutionType(type)}
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

            {/* Executor ID (optional) */}
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
                  onChange={(value) => setExecutorId(value)}
                  className="w-full"
                >
                  <option value="">Auto-select based on capabilities</option>
                  {executorOptions.map((option) => (
                    <option key={option.id} value={option.id}>
                      {option.name}
                    </option>
                  ))}
                </Select>
              ) : (
                <Input
                  type="text"
                  placeholder="Enter executor ID manually"
                  value={executorId}
                  onChange={(e) => setExecutorId(e.target.value)}
                  className="w-full"
                />
              )}
              <p className="mt-1 text-xs text-theme-text-secondary">
                If specified, this executor will be used directly. Otherwise, capability matching will be used.
              </p>
            </div>

            {/* Required Capabilities */}
            <div>
              <label className="block text-sm font-medium text-theme-text-primary mb-2">
                Required Capabilities
              </label>

              {/* Selected capabilities display */}
              {capabilities.length > 0 && (
                <div className="flex flex-wrap gap-2 mb-3">
                  {capabilities.map((cap) => (
                    <Badge
                      key={cap}
                      variant="info"
                      size="sm"
                      className="flex items-center gap-1"
                    >
                      {cap}
                      <button
                        type="button"
                        onClick={() => handleRemoveCapability(cap)}
                        className="ml-1 hover:text-theme-status-error"
                      >
                        <X className="w-3 h-3" />
                      </button>
                    </Badge>
                  ))}
                </div>
              )}

              {/* Capability selection by category */}
              {loadingCapabilities ? (
                <div className="flex items-center justify-center gap-2 py-8 border border-theme-border-primary rounded-lg bg-theme-bg-primary">
                  <Loader2 className="w-4 h-4 animate-spin text-theme-text-secondary" />
                  <span className="text-sm text-theme-text-secondary">Loading capabilities...</span>
                </div>
              ) : Object.keys(availableCapabilities).length > 0 ? (
                <div className="max-h-64 overflow-y-auto border border-theme-border-primary rounded-lg bg-theme-bg-primary">
                  {Object.entries(availableCapabilities).map(([category, caps]) => (
                    <div key={category} className="border-b border-theme-border-primary last:border-b-0">
                      <div className="px-3 py-2 bg-theme-bg-secondary text-xs font-semibold text-theme-text-secondary uppercase tracking-wider">
                        {category}
                      </div>
                      <div className="grid grid-cols-2 gap-1 p-2">
                        {caps.map((cap) => (
                          <label
                            key={cap}
                            className="flex items-center gap-2 cursor-pointer hover:bg-theme-bg-secondary p-1.5 rounded text-sm"
                          >
                            <input
                              type="checkbox"
                              checked={capabilities.includes(cap)}
                              onChange={(e) => {
                                if (e.target.checked) {
                                  setCapabilities([...capabilities, cap]);
                                } else {
                                  setCapabilities(capabilities.filter(c => c !== cap));
                                }
                              }}
                              className="w-4 h-4 rounded border-theme-border-primary text-theme-brand-primary focus:ring-theme-brand-primary"
                            />
                            <span className="text-theme-text-primary truncate" title={cap}>
                              {cap.replace(/_/g, ' ')}
                            </span>
                          </label>
                        ))}
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <div className="py-4 px-3 border border-theme-border-primary rounded-lg bg-theme-bg-primary text-center">
                  <p className="text-sm text-theme-text-secondary">
                    No capabilities found. Add custom capabilities below.
                  </p>
                </div>
              )}

              {/* Custom capability input */}
              <div className="flex gap-2 mt-3">
                <Input
                  type="text"
                  placeholder="Add custom capability..."
                  value={newCapability}
                  onChange={(e) => setNewCapability(e.target.value)}
                  onKeyDown={(e) => e.key === 'Enter' && (e.preventDefault(), handleAddCapability())}
                  className="flex-1"
                />
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={handleAddCapability}
                  disabled={!newCapability.trim()}
                >
                  <Plus className="w-4 h-4" />
                </Button>
              </div>
              <p className="mt-1 text-xs text-theme-text-secondary">
                {Object.keys(availableCapabilities).length > 0
                  ? 'Select capabilities from the list above or add custom ones'
                  : 'Enter custom capability names'}
              </p>
            </div>

            {/* Capability Match Strategy */}
            {capabilities.length > 0 && (
              <div>
                <label className="block text-sm font-medium text-theme-text-primary mb-1">
                  Match Strategy
                </label>
                <Select
                  value={matchStrategy}
                  onChange={(value) => setMatchStrategy(value as RalphCapabilityMatchStrategy)}
                >
                  {matchStrategyOptions.map((opt) => (
                    <option key={opt.value} value={opt.value}>
                      {opt.label}
                    </option>
                  ))}
                </Select>
                <p className="mt-1 text-xs text-theme-text-secondary">
                  {matchStrategyOptions.find(o => o.value === matchStrategy)?.description}
                </p>
              </div>
            )}

            {/* Advanced Options Toggle */}
            <button
              type="button"
              onClick={() => setShowAdvanced(!showAdvanced)}
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
                    onChange={(e) => setDelegationConfig({
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
                    onChange={(value) => setDelegationConfig({
                      ...delegationConfig,
                      fallback_executor_type: (value as RalphExecutionType) || undefined,
                    })}
                  >
                    <option value="">No fallback</option>
                    {(Object.keys(executionTypeConfig) as RalphExecutionType[]).map((type) => (
                      <option key={type} value={type}>
                        {executionTypeConfig[type].label}
                      </option>
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
                        onChange={(value) => setDelegationConfig({
                          ...delegationConfig,
                          fallback_executor_id: value || undefined,
                        })}
                        className="w-full"
                      >
                        <option value="">Auto-select</option>
                        {fallbackExecutorOptions.map((option) => (
                          <option key={option.id} value={option.id}>
                            {option.name}
                          </option>
                        ))}
                      </Select>
                    ) : (
                      <Input
                        type="text"
                        placeholder="Enter executor ID manually"
                        value={delegationConfig.fallback_executor_id || ''}
                        onChange={(e) => setDelegationConfig({
                          ...delegationConfig,
                          fallback_executor_id: e.target.value || undefined,
                        })}
                      />
                    )}
                  </div>
                )}
              </div>
            )}
          </TabsContent>
        </Tabs>

        {/* Actions */}
        <div className="flex items-center justify-between pt-4 mt-4 border-t border-theme-border-primary">
          {onDelete ? (
            <Button
              variant="ghost"
              size="sm"
              onClick={onDelete}
              disabled={isDeleting}
              className="text-theme-status-error hover:bg-theme-status-error/10"
            >
              {isDeleting ? (
                <Loader2 className="w-4 h-4 mr-1 animate-spin" />
              ) : (
                <Trash2 className="w-4 h-4 mr-1" />
              )}
              Delete Task
            </Button>
          ) : (
            <div />
          )}
          <div className="flex gap-2">
            {onCancel && (
              <Button variant="outline" size="sm" onClick={onCancel}>
                Cancel
              </Button>
            )}
            <Button variant="primary" size="sm" onClick={handleSave}>
              Save Task
            </Button>
          </div>
        </div>
      </CardContent>
    </Card>
  );
};

export default RalphTaskExecutorSelect;
