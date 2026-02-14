import React, { useState, useCallback, useEffect } from 'react';
import { FileText, Settings } from 'lucide-react';
import { Card, CardContent } from '@/shared/components/ui/Card';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/shared/components/ui/Tabs';
import { cn } from '@/shared/utils/cn';
import { agentsApi } from '@/shared/services/ai/AgentsApiService';
import { workflowsApi } from '@/shared/services/ai/WorkflowsApiService';
import { skillsApi } from '@/features/ai/skills/services/skillsApi';
import { ExecutorAgentTab } from './ExecutorAgentTab';
import { ExecutorWorkflowTab } from './ExecutorWorkflowTab';
import { ExecutorSkillTab } from './ExecutorSkillTab';
import { ExecutorManualTab } from './ExecutorManualTab';
import { DelegationConfigForm } from './DelegationConfigForm';
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
  taskKey: string;
  taskDescription: string;
  taskDependencies: string[];
  taskAcceptanceCriteria?: string;
  availableTaskKeys?: string[];
  executionType: RalphExecutionType;
  executorId?: string;
  requiredCapabilities?: string[];
  capabilityMatchStrategy?: RalphCapabilityMatchStrategy;
  delegationConfig?: RalphDelegationConfig;
  onSave: (taskDef: TaskDefinition, executorConfig: UpdateRalphTaskExecutorRequest) => void;
  onDelete?: () => void;
  onCancel?: () => void;
  isDeleting?: boolean;
  className?: string;
}

export const RalphTaskExecutorSelect: React.FC<RalphTaskExecutorSelectProps> = ({
  taskKey: initialTaskKey,
  taskDescription: initialTaskDescription,
  taskDependencies: initialTaskDependencies = [],
  taskAcceptanceCriteria: initialTaskAcceptanceCriteria,
  availableTaskKeys = [],
  executionType: initialType,
  executorId: initialExecutorId,
  requiredCapabilities: initialCapabilities = [],
  capabilityMatchStrategy: initialStrategy = 'all',
  delegationConfig: initialDelegationConfig = {},
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
  const [executorOptions, setExecutorOptions] = useState<ExecutorOption[]>([]);
  const [loadingExecutors, setLoadingExecutors] = useState(false);
  const [fallbackExecutorOptions, setFallbackExecutorOptions] = useState<ExecutorOption[]>([]);
  const [loadingFallbackExecutors, setLoadingFallbackExecutors] = useState(false);
  const [availableSkillsByCategory, setAvailableSkillsByCategory] = useState<Record<string, Array<{ slug: string; name: string }>>>({});
  const [loadingSkills, setLoadingSkills] = useState(true);

  // Fetch available skills on mount
  useEffect(() => {
    const loadSkills = async () => {
      setLoadingSkills(true);
      try {
        const response = await skillsApi.getSkills(1, 100);
        if (response.success && response.data?.skills) {
          const byCategory: Record<string, Array<{ slug: string; name: string }>> = {};
          for (const skill of response.data.skills) {
            const cat = skill.category || 'general';
            if (!byCategory[cat]) byCategory[cat] = [];
            byCategory[cat].push({ slug: skill.slug, name: skill.name });
          }
          setAvailableSkillsByCategory(byCategory);
        }
      } catch (_error) {
        setAvailableSkillsByCategory({});
      } finally {
        setLoadingSkills(false);
      }
    };
    loadSkills();
  }, []);

  const fetchExecutors = useCallback(async (type: RalphExecutionType): Promise<ExecutorOption[]> => {
    try {
      switch (type) {
        case 'agent': {
          const response = await agentsApi.getAgents({ per_page: 100 });
          return (response.items || []).map((agent) => ({ id: agent.id, name: agent.name, description: agent.description }));
        }
        case 'workflow': {
          const response = await workflowsApi.getWorkflows({ per_page: 100 });
          return (response.items || []).map((workflow) => ({ id: workflow.id, name: workflow.name, description: workflow.description }));
        }
        default:
          return [];
      }
    } catch (_error) {
      return [];
    }
  }, []);

  useEffect(() => {
    const loadExecutors = async () => {
      setLoadingExecutors(true);
      const options = await fetchExecutors(executionType);
      setExecutorOptions(options);
      setLoadingExecutors(false);
    };
    loadExecutors();
  }, [executionType, fetchExecutors]);

  useEffect(() => {
    const loadFallbackExecutors = async () => {
      if (!delegationConfig.fallback_executor_type) { setFallbackExecutorOptions([]); return; }
      setLoadingFallbackExecutors(true);
      const options = await fetchExecutors(delegationConfig.fallback_executor_type);
      setFallbackExecutorOptions(options);
      setLoadingFallbackExecutors(false);
    };
    loadFallbackExecutors();
  }, [delegationConfig.fallback_executor_type, fetchExecutors]);

  const handleAddCapability = useCallback(() => {
    const cap = newCapability.trim().toLowerCase();
    if (cap && !capabilities.includes(cap)) { setCapabilities([...capabilities, cap]); setNewCapability(''); }
  }, [newCapability, capabilities]);

  const handleSave = useCallback(() => {
    const taskDef: TaskDefinition = {
      key: taskKey.replace(/\s/g, '_'), description: taskDescription,
      dependencies: taskDependencies, acceptance_criteria: taskAcceptanceCriteria || undefined,
    };
    const executorConfig: UpdateRalphTaskExecutorRequest = {
      execution_type: executionType, executor_id: executorId || undefined,
      required_capabilities: capabilities, capability_match_strategy: matchStrategy,
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

          <TabsContent value="definition">
            <ExecutorAgentTab
              taskKey={taskKey}
              taskDescription={taskDescription}
              taskDependencies={taskDependencies}
              taskAcceptanceCriteria={taskAcceptanceCriteria}
              availableTaskKeys={availableTaskKeys}
              onTaskKeyChange={setTaskKey}
              onTaskDescriptionChange={setTaskDescription}
              onTaskDependenciesChange={setTaskDependencies}
              onTaskAcceptanceCriteriaChange={setTaskAcceptanceCriteria}
            />
          </TabsContent>

          <TabsContent value="executor" className="space-y-4">
            <ExecutorWorkflowTab
              executionType={executionType}
              executorId={executorId}
              executorOptions={executorOptions}
              loadingExecutors={loadingExecutors}
              onExecutionTypeChange={setExecutionType}
              onExecutorIdChange={setExecutorId}
            />

            <ExecutorSkillTab
              capabilities={capabilities}
              matchStrategy={matchStrategy}
              newCapability={newCapability}
              availableSkillsByCategory={availableSkillsByCategory}
              loadingSkills={loadingSkills}
              onCapabilitiesChange={setCapabilities}
              onMatchStrategyChange={setMatchStrategy}
              onNewCapabilityChange={setNewCapability}
              onAddCapability={handleAddCapability}
              onRemoveCapability={(cap) => setCapabilities(capabilities.filter(c => c !== cap))}
            />

            <ExecutorManualTab
              showAdvanced={showAdvanced}
              delegationConfig={delegationConfig}
              fallbackExecutorOptions={fallbackExecutorOptions}
              loadingFallbackExecutors={loadingFallbackExecutors}
              onToggleAdvanced={() => setShowAdvanced(!showAdvanced)}
              onDelegationConfigChange={setDelegationConfig}
            />
          </TabsContent>
        </Tabs>

        <DelegationConfigForm
          onSave={handleSave}
          onDelete={onDelete}
          onCancel={onCancel}
          isDeleting={isDeleting}
        />
      </CardContent>
    </Card>
  );
};

export default RalphTaskExecutorSelect;
