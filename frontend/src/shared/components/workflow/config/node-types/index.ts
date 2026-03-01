// Node type configuration components
// Registry imports
import { StartNodeConfig } from '@/shared/components/workflow/config/node-types/StartNodeConfig';
import { EndNodeConfig } from '@/shared/components/workflow/config/node-types/EndNodeConfig';
import { AiAgentNodeConfig } from '@/shared/components/workflow/config/node-types/AiAgentNodeConfig';
import { ApiCallNodeConfig } from '@/shared/components/workflow/config/node-types/ApiCallNodeConfig';
import { ConditionNodeConfig } from '@/shared/components/workflow/config/node-types/ConditionNodeConfig';
import { TransformNodeConfig } from '@/shared/components/workflow/config/node-types/TransformNodeConfig';
import { LoopNodeConfig } from '@/shared/components/workflow/config/node-types/LoopNodeConfig';
import { MergeNodeConfig } from '@/shared/components/workflow/config/node-types/MergeNodeConfig';
import { SplitNodeConfig } from '@/shared/components/workflow/config/node-types/SplitNodeConfig';
import { TriggerNodeConfig } from '@/shared/components/workflow/config/node-types/TriggerNodeConfig';
import { HumanApprovalNodeConfig } from '@/shared/components/workflow/config/node-types/HumanApprovalNodeConfig';
import { SubWorkflowNodeConfig } from '@/shared/components/workflow/config/node-types/SubWorkflowNodeConfig';
import { WebhookNodeConfig } from '@/shared/components/workflow/config/node-types/WebhookNodeConfig';
import { DatabaseNodeConfig } from '@/shared/components/workflow/config/node-types/DatabaseNodeConfig';
import { EmailNodeConfig } from '@/shared/components/workflow/config/node-types/EmailNodeConfig';
import { FileNodeConfig } from '@/shared/components/workflow/config/node-types/FileNodeConfig';
import { FileTransformNodeConfig } from '@/shared/components/workflow/config/node-types/FileTransformNodeConfig';
import { ValidatorNodeConfig } from '@/shared/components/workflow/config/node-types/ValidatorNodeConfig';
import { PromptTemplateNodeConfig } from '@/shared/components/workflow/config/node-types/PromptTemplateNodeConfig';
import { DataProcessorNodeConfig } from '@/shared/components/workflow/config/node-types/DataProcessorNodeConfig';
import { NotificationNodeConfig } from '@/shared/components/workflow/config/node-types/NotificationNodeConfig';
import { SchedulerNodeConfig } from '@/shared/components/workflow/config/node-types/SchedulerNodeConfig';
import { DefaultNodeConfig } from '@/shared/components/workflow/config/node-types/DefaultNodeConfig';
import { KbArticleCreateConfig } from '@/shared/components/workflow/config/node-types/KbArticleCreateConfig';
import { KbArticleReadConfig } from '@/shared/components/workflow/config/node-types/KbArticleReadConfig';
import { KbArticleUpdateConfig } from '@/shared/components/workflow/config/node-types/KbArticleUpdateConfig';
import { KbArticleSearchConfig } from '@/shared/components/workflow/config/node-types/KbArticleSearchConfig';
import { KbArticlePublishConfig } from '@/shared/components/workflow/config/node-types/KbArticlePublishConfig';
import { KbArticleUnifiedConfig } from '@/shared/components/workflow/config/node-types/KbArticleUnifiedConfig';
import { PageCreateConfig } from '@/shared/components/workflow/config/node-types/PageCreateConfig';
import { PageReadConfig } from '@/shared/components/workflow/config/node-types/PageReadConfig';
import { PageUpdateConfig } from '@/shared/components/workflow/config/node-types/PageUpdateConfig';
import { PagePublishConfig } from '@/shared/components/workflow/config/node-types/PagePublishConfig';
import { PageUnifiedConfig } from '@/shared/components/workflow/config/node-types/PageUnifiedConfig';
import { McpToolNodeConfig } from '@/shared/components/workflow/config/node-types/McpToolNodeConfig';
import { McpResourceNodeConfig } from '@/shared/components/workflow/config/node-types/McpResourceNodeConfig';
import { McpPromptNodeConfig } from '@/shared/components/workflow/config/node-types/McpPromptNodeConfig';
import { McpOperationConfig } from '@/shared/components/workflow/config/node-types/McpOperationConfig';
import { RalphLoopConfig } from '@/shared/components/workflow/config/node-types/RalphLoopConfig';
import type { NodeTypeConfigComponent } from '@/shared/components/workflow/config/node-types/types';

export { StartNodeConfig } from '@/shared/components/workflow/config/node-types/StartNodeConfig';
export { EndNodeConfig } from '@/shared/components/workflow/config/node-types/EndNodeConfig';
export { AiAgentNodeConfig } from '@/shared/components/workflow/config/node-types/AiAgentNodeConfig';
export { ApiCallNodeConfig } from '@/shared/components/workflow/config/node-types/ApiCallNodeConfig';
export { ConditionNodeConfig } from '@/shared/components/workflow/config/node-types/ConditionNodeConfig';
export { TransformNodeConfig } from '@/shared/components/workflow/config/node-types/TransformNodeConfig';
export { LoopNodeConfig } from '@/shared/components/workflow/config/node-types/LoopNodeConfig';
export { MergeNodeConfig } from '@/shared/components/workflow/config/node-types/MergeNodeConfig';
export { SplitNodeConfig } from '@/shared/components/workflow/config/node-types/SplitNodeConfig';
export { TriggerNodeConfig } from '@/shared/components/workflow/config/node-types/TriggerNodeConfig';
export { HumanApprovalNodeConfig } from '@/shared/components/workflow/config/node-types/HumanApprovalNodeConfig';
export { SubWorkflowNodeConfig } from '@/shared/components/workflow/config/node-types/SubWorkflowNodeConfig';
export { WebhookNodeConfig } from '@/shared/components/workflow/config/node-types/WebhookNodeConfig';
export { DatabaseNodeConfig } from '@/shared/components/workflow/config/node-types/DatabaseNodeConfig';
export { EmailNodeConfig } from '@/shared/components/workflow/config/node-types/EmailNodeConfig';
export { FileNodeConfig } from '@/shared/components/workflow/config/node-types/FileNodeConfig';
export { FileTransformNodeConfig } from '@/shared/components/workflow/config/node-types/FileTransformNodeConfig';
export { ValidatorNodeConfig } from '@/shared/components/workflow/config/node-types/ValidatorNodeConfig';
export { PromptTemplateNodeConfig } from '@/shared/components/workflow/config/node-types/PromptTemplateNodeConfig';
export { DataProcessorNodeConfig } from '@/shared/components/workflow/config/node-types/DataProcessorNodeConfig';
export { NotificationNodeConfig } from '@/shared/components/workflow/config/node-types/NotificationNodeConfig';
export { SchedulerNodeConfig } from '@/shared/components/workflow/config/node-types/SchedulerNodeConfig';
export { DefaultNodeConfig } from '@/shared/components/workflow/config/node-types/DefaultNodeConfig';

// KB Article node configs
export { KbArticleCreateConfig } from '@/shared/components/workflow/config/node-types/KbArticleCreateConfig';
export { KbArticleReadConfig } from '@/shared/components/workflow/config/node-types/KbArticleReadConfig';
export { KbArticleUpdateConfig } from '@/shared/components/workflow/config/node-types/KbArticleUpdateConfig';
export { KbArticleSearchConfig } from '@/shared/components/workflow/config/node-types/KbArticleSearchConfig';
export { KbArticlePublishConfig } from '@/shared/components/workflow/config/node-types/KbArticlePublishConfig';
export { KbArticleUnifiedConfig } from '@/shared/components/workflow/config/node-types/KbArticleUnifiedConfig';

// Page node configs
export { PageCreateConfig } from '@/shared/components/workflow/config/node-types/PageCreateConfig';
export { PageReadConfig } from '@/shared/components/workflow/config/node-types/PageReadConfig';
export { PageUpdateConfig } from '@/shared/components/workflow/config/node-types/PageUpdateConfig';
export { PagePublishConfig } from '@/shared/components/workflow/config/node-types/PagePublishConfig';
export { PageUnifiedConfig } from '@/shared/components/workflow/config/node-types/PageUnifiedConfig';

// MCP node configs
export { McpToolNodeConfig } from '@/shared/components/workflow/config/node-types/McpToolNodeConfig';
export { McpResourceNodeConfig } from '@/shared/components/workflow/config/node-types/McpResourceNodeConfig';
export { McpPromptNodeConfig } from '@/shared/components/workflow/config/node-types/McpPromptNodeConfig';
export { McpOperationConfig } from '@/shared/components/workflow/config/node-types/McpOperationConfig';

// Ralph Loop config
export { RalphLoopConfig } from '@/shared/components/workflow/config/node-types/RalphLoopConfig';

// Types
export type { NodeTypeConfigProps, NodeConfiguration, NodeTypeConfigComponent } from '@/shared/components/workflow/config/node-types/types';
export { positionOptions } from '@/shared/components/workflow/config/node-types/types';

export const nodeTypeConfigRegistry: Record<string, NodeTypeConfigComponent> = {
  // Core workflow nodes
  start: StartNodeConfig,
  end: EndNodeConfig,
  trigger: TriggerNodeConfig,

  // AI nodes
  ai_agent: AiAgentNodeConfig as NodeTypeConfigComponent,

  // Logic nodes
  condition: ConditionNodeConfig,
  transform: TransformNodeConfig,
  loop: LoopNodeConfig,
  merge: MergeNodeConfig,
  split: SplitNodeConfig,

  // Integration nodes
  api_call: ApiCallNodeConfig,
  webhook: WebhookNodeConfig,
  database: DatabaseNodeConfig,
  email: EmailNodeConfig,
  file: FileNodeConfig,
  file_transform: FileTransformNodeConfig,
  notification: NotificationNodeConfig,

  // Workflow control nodes
  human_approval: HumanApprovalNodeConfig,
  sub_workflow: SubWorkflowNodeConfig,
  scheduler: SchedulerNodeConfig,

  // Processing nodes
  validator: ValidatorNodeConfig,
  prompt_template: PromptTemplateNodeConfig,
  data_processor: DataProcessorNodeConfig,

  // KB Article nodes
  kb_article_create: KbArticleCreateConfig,
  kb_article_read: KbArticleReadConfig,
  kb_article_update: KbArticleUpdateConfig,
  kb_article_search: KbArticleSearchConfig,
  kb_article_publish: KbArticlePublishConfig,
  kb_article: KbArticleUnifiedConfig,

  // Page nodes
  page_create: PageCreateConfig,
  page_read: PageReadConfig,
  page_update: PageUpdateConfig,
  page_publish: PagePublishConfig,
  page: PageUnifiedConfig,

  // MCP nodes
  mcp_tool: McpToolNodeConfig,
  mcp_resource: McpResourceNodeConfig,
  mcp_prompt: McpPromptNodeConfig,
  mcp_operation: McpOperationConfig,

  // Ralph Loop node
  ralph_loop: RalphLoopConfig,

  // Default fallback
  default: DefaultNodeConfig,
};

// Get config component for a node type
export const getNodeTypeConfig = (nodeType: string): NodeTypeConfigComponent => {
  return nodeTypeConfigRegistry[nodeType] || nodeTypeConfigRegistry.default;
};
