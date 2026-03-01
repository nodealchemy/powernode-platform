// Interactive team execution diagram with real-time WebSocket updates
import React from 'react';
import {
  ReactFlow,
  MiniMap,
  Controls,
  Background,
  BackgroundVariant,
} from '@xyflow/react';
import '@xyflow/react/dist/style.css';
import { BookOpen, Shield, GitFork } from 'lucide-react';
import { TeamExecutionMonitor } from '../TeamExecutionMonitor';
import { executionNodeTypes } from './ExecutionMemberNode';
import { executionEdgeTypes } from './ExecutionFlowEdge';
import { useExecutionDiagramState } from './useExecutionDiagramState';
import { DiagramControls } from './DiagramControls';
import { MemberDetailSidebar } from './MemberDetailSidebar';
import type { TeamExecutionDiagramProps } from './executionDiagramTypes';

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

const getElapsedTime = (startTime?: Date, endTime?: Date) => {
  if (!startTime) return null;
  const end = endTime || new Date();
  const elapsed = Math.floor((end.getTime() - startTime.getTime()) / 1000);
  const minutes = Math.floor(elapsed / 60);
  const seconds = elapsed % 60;
  return `${minutes}:${seconds.toString().padStart(2, '0')}`;
};

export const TeamExecutionDiagram: React.FC<TeamExecutionDiagramProps> = ({
  teamId,
  team,
  onExecutionComplete,
  onViewTrajectory,
  onDismiss,
}) => {
  const {
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
  } = useExecutionDiagramState({ teamId, team, onExecutionComplete });

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

  if (nodes.length === 0) return null;
  if (execState.status === 'idle') return null;

  const elapsed = getElapsedTime(execState.startTime, execState.endTime);

  return (
    <div className="bg-theme-surface border border-theme rounded-lg p-4 mb-6">
      <style>{diagramStyles}</style>

      <DiagramControls
        execState={execState}
        isConnected={isConnected}
        executionId={execState.executionId}
        onPause={() => sendCommand('pause', execState.executionId!)}
        onCancel={() => sendCommand('cancel', execState.executionId!)}
        onResume={() => sendCommand('resume', execState.executionId!)}
        onDismiss={onDismiss}
      />

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
          <MiniMap nodeColor={minimapNodeColor} maskColor="rgba(0,0,0,0.1)" pannable />
        </ReactFlow>

        {selectedMember && (
          <MemberDetailSidebar member={selectedMember} onClose={() => setSelectedMember(null)} />
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
            {elapsed && <span className="text-theme-secondary">Duration: {elapsed}</span>}
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
              <div key={index} className="text-xs text-theme-secondary p-2 bg-theme-accent rounded">
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
