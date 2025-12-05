import React from 'react';
import { WorkflowAgentManager } from './WorkflowAgentManager';

interface WorkflowAgentAssignment {
  id?: string;
  agent_id: string;
  agent_role: 'operations' | 'optimizer' | 'assistant' | 'monitor' | 'custom';
  priority: number;
  is_active: boolean;
  configuration: Record<string, any>;
}

interface NodeAgentManagerProps {
  nodeId: string;
  assignments: WorkflowAgentAssignment[];
  onAssignmentsChange: (assignments: WorkflowAgentAssignment[]) => void;
  workflowAssignments?: WorkflowAgentAssignment[];
}

export const NodeAgentManager: React.FC<NodeAgentManagerProps> = ({
  nodeId,
  assignments,
  onAssignmentsChange,
  workflowAssignments = []
}) => {
  return (
    <div className="space-y-6">
      {/* Workflow-level agents (inherited) */}
      {workflowAssignments.length > 0 && (
        <div>
          <h4 className="text-md font-medium text-theme-primary mb-3">
            Inherited from Workflow
          </h4>
          <div className="space-y-2">
            {workflowAssignments
              .filter(assignment => assignment.is_active)
              .sort((a, b) => a.priority - b.priority)
              .map((assignment, index) => (
                <div
                  key={assignment.id || index}
                  className="p-3 border border-theme-muted bg-theme-muted/5 rounded-lg"
                >
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-medium text-theme-primary">
                        {assignment.agent_role}
                      </span>
                      <span className="text-xs text-theme-muted">
                        Priority: {assignment.priority}
                      </span>
                      <span className="px-2 py-1 bg-blue-100 text-theme-info text-xs rounded-full">
                        Inherited
                      </span>
                    </div>
                    <div className="text-xs text-theme-muted">
                      Can be overridden below
                    </div>
                  </div>
                </div>
              ))}
          </div>
        </div>
      )}

      {/* Node-specific agents */}
      <div>
        <h4 className="text-md font-medium text-theme-primary mb-3">
          Node-Specific Agents
        </h4>
        <WorkflowAgentManager
          assignments={assignments}
          onAssignmentsChange={onAssignmentsChange}
          scope="node"
          scopeId={nodeId}
        />

        {assignments.length === 0 && workflowAssignments.length > 0 && (
          <div className="mt-4 p-3 bg-blue-50 border border-blue-200 rounded-lg">
            <p className="text-sm text-theme-info">
              This node will use the inherited workflow agents. Add node-specific agents above to override workflow assignments for specific roles.
            </p>
          </div>
        )}
      </div>
    </div>
  );
};