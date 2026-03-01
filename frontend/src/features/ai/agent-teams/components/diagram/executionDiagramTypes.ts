// Types for Team Execution Diagram
import type { Node, Edge } from '@xyflow/react';
import type { AgentTeam, TeamMember } from '../../services/agentTeamsApi';

export type MemberExecutionStatus = 'idle' | 'running' | 'completed' | 'failed';
export type EdgeExecutionStatus = 'idle' | 'active' | 'completed' | 'failed';
export type DiagramDirection = 'LR' | 'TB';

export interface ExecutionMemberNodeData {
  memberName: string;
  role: string;
  isLead: boolean;
  status: MemberExecutionStatus;
  durationMs?: number;
  nodeKind: 'member' | 'input' | 'output';
  direction: DiagramDirection;
  capabilities?: string[];
  [key: string]: unknown;
}

export interface ExecutionFlowEdgeData {
  status: EdgeExecutionStatus;
  direction: DiagramDirection;
  [key: string]: unknown;
}

export type ExecutionNode = Node<ExecutionMemberNodeData>;
export type ExecutionEdge = Edge<ExecutionFlowEdgeData>;

export interface DiagramExecutionState {
  status: 'idle' | 'running' | 'paused' | 'completed' | 'failed' | 'cancelled';
  jobId?: string;
  executionId?: string;
  progress: number;
  currentMember?: string;
  startTime?: Date;
  endTime?: Date;
  result?: Record<string, unknown>;
  error?: string;
  trajectoryId?: string;
  reviewsActive?: number;
  worktreeCount?: number;
  tasksTotal: number;
  tasksCompleted: number;
  tasksFailed: number;
  updates: import('../../hooks/useTeamExecutionWebSocket').TeamExecutionUpdate[];
  memberResults: Map<string, { status: MemberExecutionStatus; durationMs?: number }>;
}

export interface MemberDetailPanel {
  nodeId: string;
  memberName: string;
  role: string;
  isLead: boolean;
  capabilities: string[];
  status: MemberExecutionStatus;
  durationMs?: number;
}

export interface TeamExecutionDiagramProps {
  teamId: string;
  team: AgentTeam;
  onExecutionComplete?: () => void;
  onViewTrajectory?: (trajectoryId: string) => void;
  onDismiss?: () => void;
}

export interface LayoutResult {
  nodes: ExecutionNode[];
  edges: ExecutionEdge[];
  direction: DiagramDirection;
  memberNameToNodeId: Map<string, string>;
}

export type { AgentTeam, TeamMember };
