// Custom Node Components
import { StartNode } from '../nodes/StartNode';
import { EndNode } from '../nodes/EndNode';
import { AiAgentNode } from '../nodes/AiAgentNode';
import { ApiCallNode } from '../nodes/ApiCallNode';
import { ConditionNode } from '../nodes/ConditionNode';
import { TriggerNode } from '../nodes/TriggerNode';
import { TransformNode } from '../nodes/TransformNode';
import { LoopNode } from '../nodes/LoopNode';
import { DelayNode } from '../nodes/DelayNode';
import { HumanApprovalNode } from '../nodes/HumanApprovalNode';
import { SubWorkflowNode } from '../nodes/SubWorkflowNode';
import { MergeNode } from '../nodes/MergeNode';
import { SplitNode } from '../nodes/SplitNode';
import { WebhookNode } from '../nodes/WebhookNode';
// Data Manipulation Nodes
import { DatabaseNode } from '../nodes/DatabaseNode';
import { EmailNode } from '../nodes/EmailNode';
import { FileNode } from '../nodes/FileNode';
import { ValidatorNode } from '../nodes/ValidatorNode';
// AI-Specific Nodes
import { PromptTemplateNode } from '../nodes/PromptTemplateNode';
import { DataProcessorNode } from '../nodes/DataProcessorNode';
// Integration Nodes
import { SchedulerNode } from '../nodes/SchedulerNode';
import { NotificationNode } from '../nodes/NotificationNode';
// Consolidated Node Components (Phase 1A)
import { KbArticleNode } from '../nodes/KbArticleNode';
import { PageNode } from '../nodes/PageNode';
import { McpOperationNode } from '../nodes/McpOperationNode';
// DevOps Orchestration Nodes (for AI workflow integration with DevOps pipelines)
import { DevopsTriggerNode } from '../nodes/DevopsTriggerNode';
import { DevopsWaitStatusNode } from '../nodes/DevopsWaitStatusNode';
import { DevopsGetLogsNode } from '../nodes/DevopsGetLogsNode';
// Ralph Loop Node
import { RalphLoopNode } from '../nodes/RalphLoopNode';

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
