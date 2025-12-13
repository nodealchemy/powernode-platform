import type { HandlePosition, HandlePositions } from '../../nodes/DynamicNodeHandles';
import type { AiAgent } from '@/shared/types/ai';

// Node configuration state
export interface NodeConfiguration {
  name: string;
  description: string;
  isStartNode: boolean;
  isEndNode: boolean;
  isErrorHandler: boolean;
  timeoutSeconds: number;
  retryCount: number;
  handlePositions?: HandlePositions;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  configuration: Record<string, any>;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  metadata: Record<string, any>;
}

// Props passed to each node type config component
export interface NodeTypeConfigProps {
  config: NodeConfiguration;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  handleConfigChange: (key: string, value: any) => void;
  handlePositionsConfig: React.ReactNode;
  markAsChanged: () => void;
  // Optional - only for ai_agent nodes
  agents?: AiAgent[];
  loadingAgents?: boolean;
  handleAgentChange?: (agentId: string) => void;
  fetchAgentDetails?: (agentId: string) => Promise<void>;
}

// Position options for handle dropdowns
export const positionOptions = [
  { value: 'top', label: 'Top' },
  { value: 'bottom', label: 'Bottom' },
  { value: 'left', label: 'Left' },
  { value: 'right', label: 'Right' }
];

// Type for a node config component
export type NodeTypeConfigComponent = React.FC<NodeTypeConfigProps>;

// Handle position change handler type
export type HandlePositionChangeHandler = (handleId: string, position: HandlePosition) => void;
