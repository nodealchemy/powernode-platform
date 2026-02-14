import React, { useState, useEffect, useRef, useMemo, useCallback } from 'react';
import {
  useNodesState,
  useEdgesState,
} from '@xyflow/react';
import { useTeamExecutionWebSocket, TeamExecutionUpdate } from '../../hooks/useTeamExecutionWebSocket';
import { agentTeamsApi, TeamMember } from '../../services/agentTeamsApi';
import type { AgentTeam } from '../../services/agentTeamsApi';
import { buildExecutionGraph } from './executionDiagramLayout';
import type {
  DiagramExecutionState,
  ExecutionNode,
  ExecutionEdge,
  MemberDetailPanel,
  MemberExecutionStatus,
  ExecutionMemberNodeData,
  ExecutionFlowEdgeData,
} from './executionDiagramTypes';

const INPUT_NODE_ID = '__input__';
const OUTPUT_NODE_ID = '__output__';

interface UseExecutionDiagramStateOptions {
  teamId: string;
  team: AgentTeam;
  onExecutionComplete?: () => void;
}

export function useExecutionDiagramState({
  teamId,
  team,
  onExecutionComplete,
}: UseExecutionDiagramStateOptions) {
  const [members, setMembers] = useState<TeamMember[]>(team.members || []);
  const [loadError, setLoadError] = useState(false);
  const [selectedMember, setSelectedMember] = useState<MemberDetailPanel | null>(null);
  const [nodes, setNodes, onNodesChange] = useNodesState<ExecutionNode>([]);
  const [edges, setEdges, onEdgesChange] = useEdgesState<ExecutionEdge>([]);

  const [execState, setExecState] = useState<DiagramExecutionState>({
    status: 'idle',
    progress: 0,
    tasksTotal: 0,
    tasksCompleted: 0,
    tasksFailed: 0,
    updates: [],
    memberResults: new Map(),
  });

  const memberNameToNodeIdRef = useRef<Map<string, string>>(new Map());
  const completeFiredRef = useRef(false);

  // Load members if not already populated on the team object
  useEffect(() => {
    if (team.members && team.members.length > 0) {
      setMembers(team.members);
      return;
    }

    let cancelled = false;
    agentTeamsApi
      .getTeam(teamId)
      .then((fullTeam) => {
        if (!cancelled && fullTeam.members) {
          setMembers(fullTeam.members);
        }
      })
      .catch(() => {
        if (!cancelled) setLoadError(true);
      });

    return () => { cancelled = true; };
  }, [teamId, team.members]);

  // Build initial graph when members are available
  const layoutResult = useMemo(() => {
    if (members.length === 0) return null;
    return buildExecutionGraph(team, members);
  }, [team, members]);

  useEffect(() => {
    if (!layoutResult) return;
    setNodes(layoutResult.nodes);
    setEdges(layoutResult.edges);
    memberNameToNodeIdRef.current = layoutResult.memberNameToNodeId;
  }, [layoutResult, setNodes, setEdges]);

  // Update node data helper
  const updateNodeData = useCallback(
    (nodeId: string, patch: Partial<ExecutionMemberNodeData>) => {
      setNodes((nds) =>
        nds.map((n) =>
          n.id === nodeId ? { ...n, data: { ...n.data, ...patch } } : n
        )
      );
    },
    [setNodes]
  );

  // Update edge data helpers
  const updateEdgesForTarget = useCallback(
    (targetNodeId: string, patch: Partial<ExecutionFlowEdgeData>) => {
      setEdges((eds) =>
        eds.map((e) =>
          e.target === targetNodeId ? { ...e, data: { ...e.data, ...patch } as ExecutionFlowEdgeData } : e
        )
      );
    },
    [setEdges]
  );

  const updateEdgesFromSource = useCallback(
    (sourceNodeId: string, patch: Partial<ExecutionFlowEdgeData>) => {
      setEdges((eds) =>
        eds.map((e) =>
          e.source === sourceNodeId ? { ...e, data: { ...e.data, ...patch } as ExecutionFlowEdgeData } : e
        )
      );
    },
    [setEdges]
  );

  // WebSocket handler
  const handleUpdate = useCallback(
    (update: TeamExecutionUpdate) => {
      setExecState((prev) => {
        const next = { ...prev, memberResults: new Map(prev.memberResults) };

        switch (update.type) {
          case 'execution_started':
            next.status = 'running';
            next.jobId = update.job_id;
            next.executionId = update.execution_id;
            next.startTime = new Date(update.timestamp);
            next.progress = 0;
            next.tasksTotal = update.tasks_total || 0;
            next.tasksCompleted = 0;
            next.tasksFailed = 0;
            next.memberResults = new Map();
            completeFiredRef.current = false;
            updateNodeData(INPUT_NODE_ID, { status: 'completed' });
            updateEdgesFromSource(INPUT_NODE_ID, { status: 'active' });
            break;

          case 'execution_progress': {
            next.currentMember = update.current_member;
            next.tasksTotal = update.tasks_total || next.tasksTotal;
            next.tasksCompleted = update.tasks_completed || next.tasksCompleted;
            next.tasksFailed = update.tasks_failed || next.tasksFailed;
            if (next.tasksTotal > 0) {
              next.progress = Math.round((next.tasksCompleted / next.tasksTotal) * 100);
            } else {
              next.progress = update.progress || 0;
            }
            if (update.current_member) {
              const nodeId = memberNameToNodeIdRef.current.get(update.current_member);
              if (nodeId) {
                updateNodeData(nodeId, { status: 'running' });
                updateEdgesForTarget(nodeId, { status: 'active' });
              }
              next.memberResults.set(update.current_member, {
                status: 'running',
                ...(next.memberResults.get(update.current_member) || {}),
              });
            }
            break;
          }

          case 'member_completed': {
            next.tasksTotal = update.tasks_total || next.tasksTotal;
            next.tasksCompleted = update.tasks_completed || next.tasksCompleted;
            next.tasksFailed = update.tasks_failed || next.tasksFailed;
            if (next.tasksTotal > 0) {
              next.progress = Math.round((next.tasksCompleted / next.tasksTotal) * 100);
            }
            if (update.member_name) {
              const memberStatus: MemberExecutionStatus = update.member_success ? 'completed' : 'failed';
              const nodeId = memberNameToNodeIdRef.current.get(update.member_name);
              if (nodeId) {
                updateNodeData(nodeId, { status: memberStatus, durationMs: update.member_duration_ms });
                updateEdgesForTarget(nodeId, { status: memberStatus });
                updateEdgesFromSource(nodeId, { status: memberStatus });
              }
              next.memberResults.set(update.member_name, {
                status: memberStatus,
                durationMs: update.member_duration_ms,
              });
            }
            break;
          }

          case 'execution_completed':
            next.status = 'completed';
            next.progress = 100;
            next.endTime = new Date(update.timestamp);
            next.result = update.result as Record<string, unknown>;
            next.tasksTotal = update.tasks_total || next.tasksTotal;
            next.tasksCompleted = update.tasks_completed || next.tasksCompleted;
            next.tasksFailed = update.tasks_failed || next.tasksFailed;
            updateNodeData(OUTPUT_NODE_ID, { status: 'completed' });
            updateEdgesForTarget(OUTPUT_NODE_ID, { status: 'completed' });
            break;

          case 'execution_failed':
            next.status = 'failed';
            next.endTime = new Date(update.timestamp);
            next.error = update.error;
            next.tasksTotal = update.tasks_total || next.tasksTotal;
            next.tasksCompleted = update.tasks_completed || next.tasksCompleted;
            next.tasksFailed = update.tasks_failed || next.tasksFailed;
            updateNodeData(OUTPUT_NODE_ID, { status: 'failed' });
            updateEdgesForTarget(OUTPUT_NODE_ID, { status: 'failed' });
            break;

          case 'execution_paused':
            next.status = 'paused';
            break;

          case 'execution_resumed':
            next.status = 'running';
            break;

          case 'execution_cancelled':
            next.status = 'cancelled';
            next.endTime = new Date(update.timestamp);
            updateNodeData(OUTPUT_NODE_ID, { status: 'failed' });
            break;

          case 'execution_redirected':
            break;

          case 'execution_timeout':
            next.status = 'failed';
            next.endTime = new Date(update.timestamp);
            next.error = 'Execution timed out';
            updateNodeData(OUTPUT_NODE_ID, { status: 'failed' });
            break;
        }

        next.updates = [...prev.updates, update];
        return next;
      });
    },
    [updateNodeData, updateEdgesForTarget, updateEdgesFromSource]
  );

  const { isConnected, sendCommand } = useTeamExecutionWebSocket({
    teamId,
    enabled: true,
    onUpdate: handleUpdate,
  });

  // Fire onExecutionComplete side-effect
  useEffect(() => {
    if (execState.status === 'completed' && !completeFiredRef.current) {
      completeFiredRef.current = true;
      onExecutionComplete?.();
    }
  }, [execState.status, onExecutionComplete]);

  // Node click handler
  const onNodeClick = useCallback(
    (_event: React.MouseEvent, node: ExecutionNode) => {
      if (node.data.nodeKind !== 'member') return;

      const memberData = node.data;
      const memberResult = execState.memberResults.get(memberData.memberName);

      setSelectedMember({
        nodeId: node.id,
        memberName: memberData.memberName,
        role: memberData.role,
        isLead: memberData.isLead,
        capabilities: memberData.capabilities || [],
        status: memberResult?.status || memberData.status,
        durationMs: memberResult?.durationMs || memberData.durationMs,
      });
    },
    [execState.memberResults]
  );

  // MiniMap node color based on status
  const minimapNodeColor = useCallback((node: ExecutionNode) => {
    const status = node.data?.status;
    switch (status) {
      case 'running': return '#3b82f6';
      case 'completed': return '#22c55e';
      case 'failed': return '#ef4444';
      default: return '#6b7280';
    }
  }, []);

  return {
    members,
    loadError,
    selectedMember,
    setSelectedMember,
    nodes,
    edges,
    onNodesChange,
    onEdgesChange,
    execState,
    isConnected,
    sendCommand,
    onNodeClick,
    minimapNodeColor,
  };
}
