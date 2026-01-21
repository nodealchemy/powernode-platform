// Node type configuration components
// Registry imports
import { StartNodeConfig } from './StartNodeConfig';
import { EndNodeConfig } from './EndNodeConfig';
import { AiAgentNodeConfig } from './AiAgentNodeConfig';
import { ApiCallNodeConfig } from './ApiCallNodeConfig';
import { ConditionNodeConfig } from './ConditionNodeConfig';
import { TransformNodeConfig } from './TransformNodeConfig';
import { LoopNodeConfig } from './LoopNodeConfig';
import { MergeNodeConfig } from './MergeNodeConfig';
import { SplitNodeConfig } from './SplitNodeConfig';
import { TriggerNodeConfig } from './TriggerNodeConfig';
import { HumanApprovalNodeConfig } from './HumanApprovalNodeConfig';
import { SubWorkflowNodeConfig } from './SubWorkflowNodeConfig';
import { WebhookNodeConfig } from './WebhookNodeConfig';
import { DatabaseNodeConfig } from './DatabaseNodeConfig';
import { EmailNodeConfig } from './EmailNodeConfig';
import { FileNodeConfig } from './FileNodeConfig';
import { FileTransformNodeConfig } from './FileTransformNodeConfig';
import { ValidatorNodeConfig } from './ValidatorNodeConfig';
import { PromptTemplateNodeConfig } from './PromptTemplateNodeConfig';
import { DataProcessorNodeConfig } from './DataProcessorNodeConfig';
import { NotificationNodeConfig } from './NotificationNodeConfig';
import { SchedulerNodeConfig } from './SchedulerNodeConfig';
import { DefaultNodeConfig } from './DefaultNodeConfig';
import { KbArticleCreateConfig } from './KbArticleCreateConfig';
import { KbArticleReadConfig } from './KbArticleReadConfig';
import { KbArticleUpdateConfig } from './KbArticleUpdateConfig';
import { KbArticleSearchConfig } from './KbArticleSearchConfig';
import { KbArticlePublishConfig } from './KbArticlePublishConfig';
import { KbArticleUnifiedConfig } from './KbArticleUnifiedConfig';
import { PageCreateConfig } from './PageCreateConfig';
import { PageReadConfig } from './PageReadConfig';
import { PageUpdateConfig } from './PageUpdateConfig';
import { PagePublishConfig } from './PagePublishConfig';
import { PageUnifiedConfig } from './PageUnifiedConfig';
import { McpToolNodeConfig } from './McpToolNodeConfig';
import { McpResourceNodeConfig } from './McpResourceNodeConfig';
import { McpPromptNodeConfig } from './McpPromptNodeConfig';
import { McpOperationConfig } from './McpOperationConfig';
import type { NodeTypeConfigComponent } from './types';

export { StartNodeConfig } from './StartNodeConfig';
export { EndNodeConfig } from './EndNodeConfig';
export { AiAgentNodeConfig } from './AiAgentNodeConfig';
export { ApiCallNodeConfig } from './ApiCallNodeConfig';
export { ConditionNodeConfig } from './ConditionNodeConfig';
export { TransformNodeConfig } from './TransformNodeConfig';
export { LoopNodeConfig } from './LoopNodeConfig';
export { MergeNodeConfig } from './MergeNodeConfig';
export { SplitNodeConfig } from './SplitNodeConfig';
export { TriggerNodeConfig } from './TriggerNodeConfig';
export { HumanApprovalNodeConfig } from './HumanApprovalNodeConfig';
export { SubWorkflowNodeConfig } from './SubWorkflowNodeConfig';
export { WebhookNodeConfig } from './WebhookNodeConfig';
export { DatabaseNodeConfig } from './DatabaseNodeConfig';
export { EmailNodeConfig } from './EmailNodeConfig';
export { FileNodeConfig } from './FileNodeConfig';
export { FileTransformNodeConfig } from './FileTransformNodeConfig';
export { ValidatorNodeConfig } from './ValidatorNodeConfig';
export { PromptTemplateNodeConfig } from './PromptTemplateNodeConfig';
export { DataProcessorNodeConfig } from './DataProcessorNodeConfig';
export { NotificationNodeConfig } from './NotificationNodeConfig';
export { SchedulerNodeConfig } from './SchedulerNodeConfig';
export { DefaultNodeConfig } from './DefaultNodeConfig';

// KB Article node configs
export { KbArticleCreateConfig } from './KbArticleCreateConfig';
export { KbArticleReadConfig } from './KbArticleReadConfig';
export { KbArticleUpdateConfig } from './KbArticleUpdateConfig';
export { KbArticleSearchConfig } from './KbArticleSearchConfig';
export { KbArticlePublishConfig } from './KbArticlePublishConfig';
export { KbArticleUnifiedConfig } from './KbArticleUnifiedConfig';

// Page node configs
export { PageCreateConfig } from './PageCreateConfig';
export { PageReadConfig } from './PageReadConfig';
export { PageUpdateConfig } from './PageUpdateConfig';
export { PagePublishConfig } from './PagePublishConfig';
export { PageUnifiedConfig } from './PageUnifiedConfig';

// MCP node configs
export { McpToolNodeConfig } from './McpToolNodeConfig';
export { McpResourceNodeConfig } from './McpResourceNodeConfig';
export { McpPromptNodeConfig } from './McpPromptNodeConfig';
export { McpOperationConfig } from './McpOperationConfig';

// Types
export type { NodeTypeConfigProps, NodeConfiguration, NodeTypeConfigComponent } from './types';
export { positionOptions } from './types';

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

  // Default fallback
  default: DefaultNodeConfig,
};

// Get config component for a node type
export const getNodeTypeConfig = (nodeType: string): NodeTypeConfigComponent => {
  return nodeTypeConfigRegistry[nodeType] || nodeTypeConfigRegistry.default;
};
