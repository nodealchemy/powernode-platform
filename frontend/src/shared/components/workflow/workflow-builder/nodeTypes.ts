// Custom Node Components
import { StartNode } from '@/shared/components/workflow/nodes/StartNode';
import { EndNode } from '@/shared/components/workflow/nodes/EndNode';
import { AiAgentNode } from '@/shared/components/workflow/nodes/AiAgentNode';
import { ApiCallNode } from '@/shared/components/workflow/nodes/ApiCallNode';
import { ConditionNode } from '@/shared/components/workflow/nodes/ConditionNode';
import { TriggerNode } from '@/shared/components/workflow/nodes/TriggerNode';
import { TransformNode } from '@/shared/components/workflow/nodes/TransformNode';
import { LoopNode } from '@/shared/components/workflow/nodes/LoopNode';
import { DelayNode } from '@/shared/components/workflow/nodes/DelayNode';
import { HumanApprovalNode } from '@/shared/components/workflow/nodes/HumanApprovalNode';
import { SubWorkflowNode } from '@/shared/components/workflow/nodes/SubWorkflowNode';
import { MergeNode } from '@/shared/components/workflow/nodes/MergeNode';
import { SplitNode } from '@/shared/components/workflow/nodes/SplitNode';
import { WebhookNode } from '@/shared/components/workflow/nodes/WebhookNode';
// Data Manipulation Nodes
import { DatabaseNode } from '@/shared/components/workflow/nodes/DatabaseNode';
import { EmailNode } from '@/shared/components/workflow/nodes/EmailNode';
import { FileNode } from '@/shared/components/workflow/nodes/FileNode';
import { ValidatorNode } from '@/shared/components/workflow/nodes/ValidatorNode';
// AI-Specific Nodes
import { PromptTemplateNode } from '@/shared/components/workflow/nodes/PromptTemplateNode';
import { DataProcessorNode } from '@/shared/components/workflow/nodes/DataProcessorNode';
// Integration Nodes
import { SchedulerNode } from '@/shared/components/workflow/nodes/SchedulerNode';
import { NotificationNode } from '@/shared/components/workflow/nodes/NotificationNode';
// Consolidated Node Components (Phase 1A)
import { KbArticleNode } from '@/shared/components/workflow/nodes/KbArticleNode';
import { PageNode } from '@/shared/components/workflow/nodes/PageNode';
import { McpOperationNode } from '@/shared/components/workflow/nodes/McpOperationNode';
// DevOps Orchestration Nodes (for AI workflow integration with DevOps pipelines)
import { DevopsTriggerNode } from '@/shared/components/workflow/nodes/DevopsTriggerNode';
import { DevopsWaitStatusNode } from '@/shared/components/workflow/nodes/DevopsWaitStatusNode';
import { DevopsGetLogsNode } from '@/shared/components/workflow/nodes/DevopsGetLogsNode';
// Ralph Loop Node
import { RalphLoopNode } from '@/shared/components/workflow/nodes/RalphLoopNode';

// Node types mapping for React Flow
export const NODE_TYPES = {
  // Core Flow Nodes
  start: StartNode,
  end: EndNode,
  trigger: TriggerNode,
  condition: ConditionNode,
  loop: LoopNode,
  delay: DelayNode,
  merge: MergeNode,
  split: SplitNode,
  // AI & Processing Nodes
  ai_agent: AiAgentNode,
  prompt_template: PromptTemplateNode,
  data_processor: DataProcessorNode,
  transform: TransformNode,
  // Data Operations Nodes
  database: DatabaseNode,
  file: FileNode,
  validator: ValidatorNode,
  // Communication Nodes
  email: EmailNode,
  notification: NotificationNode,
  // Integration Nodes
  api_call: ApiCallNode,
  webhook: WebhookNode,
  scheduler: SchedulerNode,
  // Process Nodes
  human_approval: HumanApprovalNode,
  sub_workflow: SubWorkflowNode,
  // Consolidated Node Types (Phase 1A)
  // KB Article: unified node with action parameter (create, read, update, search, publish)
  kb_article: KbArticleNode,
  // Page: unified node with action parameter (create, read, update, publish)
  page: PageNode,
  // MCP Operation: unified node with operation_type parameter (tool, resource, prompt)
  mcp_operation: McpOperationNode,
  // DevOps Orchestration Nodes (for AI workflow integration with DevOps pipelines)
  devops_trigger: DevopsTriggerNode,
  devops_wait_status: DevopsWaitStatusNode,
  devops_get_logs: DevopsGetLogsNode,
  // Ralph Loop Node
  ralph_loop: RalphLoopNode,
} as const;

export type NodeTypeKey = keyof typeof NODE_TYPES;
