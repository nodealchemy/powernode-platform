// Interactive team execution diagram with real-time WebSocket updates
import React, { useState, useEffect, useRef, useMemo, useCallback } from 'react';
import {
  ReactFlow,
  MiniMap,
  Controls,
  Background,
  useNodesState,
  useEdgesState,
  BackgroundVariant,
} from '@xyflow/react';
import '@xyflow/react/dist/style.css';
import {
  Clock,
  CheckCircle,
  XCircle,
  Loader,
  BookOpen,
  Shield,
  GitFork,
  X,
  Pause,
  Play,
  StopCircle,
} from 'lucide-react';
import { useTeamExecutionWebSocket, TeamExecutionUpdate } from '../../hooks/useTeamExecutionWebSocket';
import { agentTeamsApi, TeamMember } from '../../services/agentTeamsApi';
import { TeamExecutionMonitor } from '../TeamExecutionMonitor';
import { executionNodeTypes } from './ExecutionMemberNode';
import { executionEdgeTypes } from './ExecutionFlowEdge';
import { buildExecutionGraph } from './executionDiagramLayout';
import type {
  TeamExecutionDiagramProps,
  DiagramExecutionState,
  ExecutionNode,
  ExecutionEdge,
  MemberDetailPanel,
  MemberExecutionStatus,
  ExecutionMemberNodeData,
  ExecutionFlowEdgeData,
} from './executionDiagramTypes';

// Theme-aware ReactFlow styles
const diagramStyles = `
.execution-controls .react-flow__controls-button {
  background-color: var(--color-surface);
  border-color: var(--color-border);
  border-bottom-width: 1px;
  border-bottom-style: solid;
  fill: var(--color-text-primary);
  color: var(--color-text-primary);
}
.execution-controls .react-flow__controls-button:hover {
  background-color: var(--color-surface-hover);
}
.execution-controls .react-flow__controls-button svg {
  fill: var(--color-text-primary);
}
.react-flow__minimap-mask {
  fill: var(--color-bg, rgba(0,0,0,0.1));
  opacity: 0.6;
}
@keyframes execution-node-pulse {
  0%, 100% { box-shadow: 0 0 0 0 var(--color-info); }
  50% { box-shadow: 0 0 12px 2px var(--color-info); }
}
.execution-node-pulse {
  animation: execution-node-pulse 2s ease-in-out infinite;
}
`;

const INPUT_NODE_ID = '__input__';
const OUTPUT_NODE_ID = '__output__';

export const TeamExecutionDiagram: React.FC<TeamExecutionDiagramProps> = ({
  teamId,
  team,
  onExecutionComplete,
  onViewTrajectory,
  onDismiss,
}) => {
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

  // Update edge data helper
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

            // Mark input sentinel as active
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
                updateNodeData(nodeId, {
                  status: memberStatus,
                  durationMs: update.member_duration_ms,
                });
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
            // Continue running with new instructions
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

  // Helper functions
  const getElapsedTime = () => {
    if (!execState.startTime) return null;
    const endTime = execState.endTime || new Date();
    const elapsed = Math.floor((endTime.getTime() - execState.startTime.getTime()) / 1000);
    const minutes = Math.floor(elapsed / 60);
    const seconds = elapsed % 60;
    return `${minutes}:${seconds.toString().padStart(2, '0')}`;
  };

  const getStatusIcon = () => {
    switch (execState.status) {
      case 'running': return <Loader className="animate-spin text-theme-info" size={18} />;
      case 'paused': return <Pause className="text-theme-warning" size={18} />;
      case 'completed': return <CheckCircle className="text-theme-success" size={18} />;
      case 'failed': return <XCircle className="text-theme-danger" size={18} />;
      case 'cancelled': return <StopCircle className="text-theme-secondary" size={18} />;
      default: return <Clock className="text-theme-muted" size={18} />;
    }
  };

  const getStatusText = () => {
    switch (execState.status) {
      case 'running': return 'Executing...';
      case 'paused': return 'Paused';
      case 'completed': return 'Completed';
      case 'failed': return 'Failed';
      case 'cancelled': return 'Cancelled';
      default: return 'Waiting for execution...';
    }
  };

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

  // Fallback to text monitor if member load failed or no members
  if (loadError || (members.length === 0 && !team.members?.length)) {
    return (
      <TeamExecutionMonitor
        teamId={teamId}
        onExecutionComplete={onExecutionComplete}
        onViewTrajectory={onViewTrajectory}
        onDismiss={onDismiss}
      />
    );
  }

  // Don't render until graph is built
  if (nodes.length === 0) return null;

  // Hide when idle (same behavior as TeamExecutionMonitor)
  if (execState.status === 'idle') return null;

  return (
    <div className="bg-theme-surface border border-theme rounded-lg p-4 mb-6">
      <style>{diagramStyles}</style>

      {/* Header */}
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-2">
          {getStatusIcon()}
          <div>
            <h3 className="font-semibold text-theme-primary text-sm">{getStatusText()}</h3>
            {execState.executionId && (
              <p className="text-[10px] text-theme-secondary">Execution: {execState.executionId}</p>
            )}
          </div>
        </div>

        <div className="flex items-center gap-3">
          {/* Execution controls */}
          {execState.status === 'running' && execState.executionId && (
            <div className="flex items-center gap-1">
              <button
                type="button"
                onClick={() => sendCommand('pause', execState.executionId!)}
                className="p-1 rounded text-theme-warning hover:bg-theme-warning/10 transition-colors"
                title="Pause execution"
              >
                <Pause size={14} />
              </button>
              <button
                type="button"
                onClick={() => sendCommand('cancel', execState.executionId!)}
                className="p-1 rounded text-theme-danger hover:bg-theme-error/10 transition-colors"
                title="Cancel execution"
              >
                <StopCircle size={14} />
              </button>
            </div>
          )}
          {execState.status === 'paused' && execState.executionId && (
            <button
              type="button"
              onClick={() => sendCommand('resume', execState.executionId!)}
              className="flex items-center gap-1 px-2 py-1 text-xs rounded bg-theme-success/10 text-theme-success hover:bg-theme-success/20 transition-colors"
              title="Resume execution"
            >
              <Play size={12} /> Resume
            </button>
          )}
          {getElapsedTime() && (
            <div className="flex items-center gap-1.5 text-xs text-theme-secondary">
              <Clock size={14} />
              {getElapsedTime()}
            </div>
          )}
          <div className="flex items-center gap-1.5">
            <div className={`w-2 h-2 rounded-full ${isConnected ? 'bg-theme-success-solid' : 'bg-theme-danger-solid'}`} />
            <span className="text-[10px] text-theme-secondary">
              {isConnected ? 'Live' : 'Disconnected'}
            </span>
          </div>
          {onDismiss && ['completed', 'failed', 'cancelled'].includes(execState.status) && (
            <button
              type="button"
              onClick={onDismiss}
              className="text-xs text-theme-secondary hover:text-theme-primary"
            >
              Dismiss
            </button>
          )}
        </div>
      </div>

      {/* Progress counter */}
      {(execState.status === 'running' || execState.status === 'paused') && execState.tasksTotal > 0 && (
        <div className="flex items-center justify-between text-xs text-theme-secondary mb-3">
          <span>
            {execState.tasksCompleted}/{execState.tasksTotal} agents completed
            {execState.tasksFailed > 0 && (
              <span className="text-theme-danger ml-2">{execState.tasksFailed} failed</span>
            )}
          </span>
          <span>{execState.progress}%</span>
        </div>
      )}

      {/* ReactFlow diagram */}
      <div className="h-[350px] rounded-lg border border-theme bg-theme-surface relative">
        <ReactFlow
          nodes={nodes}
          edges={edges}
          onNodesChange={onNodesChange}
          onEdgesChange={onEdgesChange}
          onNodeClick={onNodeClick}
          nodeTypes={executionNodeTypes}
          edgeTypes={executionEdgeTypes}
          fitView
          fitViewOptions={{ padding: 0.3 }}
          minZoom={0.3}
          maxZoom={2}
          nodesDraggable={false}
          nodesConnectable={false}
          elementsSelectable={false}
          panOnDrag
          zoomOnScroll
        >
          <Background variant={BackgroundVariant.Dots} gap={16} size={1} />
          <Controls className="execution-controls" showInteractive={false} />
          <MiniMap
            nodeColor={minimapNodeColor}
            maskColor="rgba(0,0,0,0.1)"
            pannable
          />
        </ReactFlow>

        {/* Member detail overlay */}
        {selectedMember && (
          <div className="absolute top-3 right-3 w-56 bg-theme-surface border border-theme rounded-lg shadow-xl p-3 z-10">
            <div className="flex items-center justify-between mb-2">
              <span className="text-sm font-semibold text-theme-primary">{selectedMember.memberName}</span>
              <button
                type="button"
                onClick={() => setSelectedMember(null)}
                className="text-theme-secondary hover:text-theme-primary"
              >
                <X size={14} />
              </button>
            </div>
            <div className="space-y-1.5 text-xs">
              <div className="flex justify-between">
                <span className="text-theme-secondary">Role</span>
                <span className="text-theme-primary font-medium">{selectedMember.role}</span>
              </div>
              {selectedMember.isLead && (
                <div className="flex justify-between">
                  <span className="text-theme-secondary">Lead</span>
                  <span className="text-theme-warning font-medium">Yes</span>
                </div>
              )}
              <div className="flex justify-between">
                <span className="text-theme-secondary">Status</span>
                <span className={`font-medium ${
                  selectedMember.status === 'completed' ? 'text-theme-success' :
                  selectedMember.status === 'failed' ? 'text-theme-danger' :
                  selectedMember.status === 'running' ? 'text-theme-info' :
                  'text-theme-secondary'
                }`}>
                  {selectedMember.status}
                </span>
              </div>
              {selectedMember.durationMs !== undefined && (
                <div className="flex justify-between">
                  <span className="text-theme-secondary">Duration</span>
                  <span className="text-theme-primary">
                    {selectedMember.durationMs < 1000
                      ? `${selectedMember.durationMs}ms`
                      : `${(selectedMember.durationMs / 1000).toFixed(1)}s`}
                  </span>
                </div>
              )}
              {selectedMember.capabilities.length > 0 && (
                <div>
                  <span className="text-theme-secondary">Capabilities</span>
                  <div className="flex flex-wrap gap-1 mt-1">
                    {selectedMember.capabilities.map((cap) => (
                      <span key={cap} className="px-1.5 py-0.5 text-[10px] rounded bg-theme-accent text-theme-secondary">
                        {cap}
                      </span>
                    ))}
                  </div>
                </div>
              )}
            </div>
          </div>
        )}
      </div>

      {/* Completion summary */}
      {(execState.status === 'completed' || execState.status === 'failed') && execState.tasksTotal > 0 && (
        <div className={`p-3 rounded-md mt-3 ${
          execState.status === 'completed'
            ? 'bg-theme-success/10 border border-theme-success/30'
            : 'bg-theme-error/10 border border-theme-error/30'
        }`}>
          <div className="flex items-center gap-4 text-sm">
            <span className={execState.status === 'completed' ? 'text-theme-success' : 'text-theme-danger'}>
              {execState.tasksCompleted}/{execState.tasksTotal} agents completed
            </span>
            {execState.tasksFailed > 0 && (
              <span className="text-theme-danger">{execState.tasksFailed} failed</span>
            )}
            {getElapsedTime() && (
              <span className="text-theme-secondary">Duration: {getElapsedTime()}</span>
            )}
          </div>
        </div>
      )}

      {/* Error display */}
      {execState.status === 'failed' && execState.error && (
        <div className="p-3 bg-theme-error/10 border border-theme-error/30 rounded-md mt-3">
          <p className="text-sm text-theme-danger font-medium mb-1">Error</p>
          <p className="text-sm text-theme-danger">{execState.error}</p>
        </div>
      )}

      {/* Trajectory status */}
      {execState.status === 'running' && (
        <div className="flex items-center gap-2 text-xs text-theme-secondary mt-3 p-2 bg-theme-accent/50 rounded-md">
          <BookOpen size={14} className="text-theme-info" />
          <span>Trajectory building in progress...</span>
        </div>
      )}

      {execState.status === 'completed' && (
        <div className="flex items-center justify-between mt-3 p-3 bg-theme-info/5 border border-theme-info/20 rounded-md">
          <div className="flex items-center gap-2 text-sm text-theme-info">
            <BookOpen size={16} />
            <span>Trajectory captured</span>
          </div>
          {onViewTrajectory && execState.trajectoryId && (
            <button
              type="button"
              onClick={() => onViewTrajectory(execState.trajectoryId!)}
              className="text-xs text-theme-info hover:text-theme-primary underline"
            >
              View Trajectory
            </button>
          )}
        </div>
      )}

      {/* Worktree indicator */}
      {execState.worktreeCount !== undefined && execState.worktreeCount > 0 && (
        <div className="flex items-center gap-2 text-xs text-theme-info mt-2 p-2 bg-theme-info/5 border border-theme-info/20 rounded-md">
          <GitFork size={14} />
          <span>{execState.worktreeCount} worktree{execState.worktreeCount > 1 ? 's' : ''} active</span>
        </div>
      )}

      {/* Review status */}
      {execState.reviewsActive !== undefined && execState.reviewsActive > 0 && (
        <div className="flex items-center gap-2 text-xs text-theme-warning mt-2 p-2 bg-theme-warning/5 border border-theme-warning/20 rounded-md">
          <Shield size={14} />
          <span>{execState.reviewsActive} review{execState.reviewsActive > 1 ? 's' : ''} in progress</span>
        </div>
      )}

      {/* Activity Log */}
      {execState.updates.length > 0 && (
        <details className="mt-3">
          <summary className="text-sm font-medium text-theme-primary cursor-pointer hover:text-theme-info">
            Activity Log ({execState.updates.length} updates)
          </summary>
          <div className="mt-2 space-y-1 max-h-48 overflow-y-auto">
            {execState.updates.map((update, index) => (
              <div
                key={index}
                className="text-xs text-theme-secondary p-2 bg-theme-accent rounded"
              >
                <span className="font-medium">{new Date(update.timestamp).toLocaleTimeString()}</span>
                {' - '}
                <span>{update.type.replace(/_/g, ' ')}</span>
                {update.current_member && ` - ${update.current_member}`}
                {update.member_name && ` - ${update.member_name}`}
                {update.member_success !== undefined && ` (${update.member_success ? 'success' : 'failed'})`}
              </div>
            ))}
          </div>
        </details>
      )}
    </div>
  );
};
