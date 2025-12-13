// Node type configuration components
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
export { ValidatorNodeConfig } from './ValidatorNodeConfig';
export { PromptTemplateNodeConfig } from './PromptTemplateNodeConfig';
export { DataProcessorNodeConfig } from './DataProcessorNodeConfig';
export { NotificationNodeConfig } from './NotificationNodeConfig';
export { SchedulerNodeConfig } from './SchedulerNodeConfig';
export { DefaultNodeConfig } from './DefaultNodeConfig';

// Types
export type { NodeTypeConfigProps, NodeConfiguration, NodeTypeConfigComponent } from './types';
export { positionOptions } from './types';

// Registry mapping node types to their config components
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
import { ValidatorNodeConfig } from './ValidatorNodeConfig';
import { PromptTemplateNodeConfig } from './PromptTemplateNodeConfig';
import { DataProcessorNodeConfig } from './DataProcessorNodeConfig';
import { NotificationNodeConfig } from './NotificationNodeConfig';
import { SchedulerNodeConfig } from './SchedulerNodeConfig';
import { DefaultNodeConfig } from './DefaultNodeConfig';
import type { NodeTypeConfigComponent } from './types';

export const nodeTypeConfigRegistry: Record<string, NodeTypeConfigComponent> = {
  start: StartNodeConfig,
  end: EndNodeConfig,
  ai_agent: AiAgentNodeConfig as NodeTypeConfigComponent,
  api_call: ApiCallNodeConfig,
  condition: ConditionNodeConfig,
  transform: TransformNodeConfig,
  loop: LoopNodeConfig,
  merge: MergeNodeConfig,
  split: SplitNodeConfig,
  trigger: TriggerNodeConfig,
  human_approval: HumanApprovalNodeConfig,
  sub_workflow: SubWorkflowNodeConfig,
  webhook: WebhookNodeConfig,
  database: DatabaseNodeConfig,
  email: EmailNodeConfig,
  file: FileNodeConfig,
  validator: ValidatorNodeConfig,
  prompt_template: PromptTemplateNodeConfig,
  data_processor: DataProcessorNodeConfig,
  notification: NotificationNodeConfig,
  scheduler: SchedulerNodeConfig,
  default: DefaultNodeConfig,
};

// Get config component for a node type
export const getNodeTypeConfig = (nodeType: string): NodeTypeConfigComponent => {
  return nodeTypeConfigRegistry[nodeType] || nodeTypeConfigRegistry.default;
};
