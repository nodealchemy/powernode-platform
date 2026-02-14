import React from 'react';

const inputClass = 'w-full px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-primary';
const labelClass = 'block text-sm font-medium text-theme-primary mb-1';

interface WorkflowTabProps {
  workflowText: string;
  workflowDefinition: Record<string, unknown>;
  jsonErrors: Record<string, string>;
  onWorkflowChange: (text: string) => void;
}

export const WorkflowTab: React.FC<WorkflowTabProps> = ({
  workflowText,
  workflowDefinition,
  jsonErrors,
  onWorkflowChange,
}) => {
  return (
    <div className="space-y-4">
      <div>
        <label className={labelClass}>
          Workflow Definition
          {jsonErrors.workflow_definition && <span className="text-theme-danger ml-2 font-normal">{jsonErrors.workflow_definition}</span>}
        </label>
        <p className="text-xs text-theme-secondary mb-2">
          Define the workflow pipeline with nodes and edges. Each node has an id, type (trigger, action, ai, condition), label, and config.
        </p>
        <textarea
          value={workflowText}
          onChange={(e) => onWorkflowChange(e.target.value)}
          rows={20}
          className={`${inputClass} font-mono text-xs ${jsonErrors.workflow_definition ? 'border-theme-danger' : ''}`}
          placeholder={`{
  "nodes": [
    {"id": "trigger", "type": "trigger", "label": "Event", "config": {}},
    {"id": "process", "type": "ai", "label": "Process", "config": {"model": "claude-sonnet-4-5-20250929"}},
    {"id": "output", "type": "action", "label": "Output", "config": {}}
  ],
  "edges": [
    {"source": "trigger", "target": "process"},
    {"source": "process", "target": "output"}
  ]
}`}
        />
      </div>
      {/* Preview */}
      {!jsonErrors.workflow_definition && workflowDefinition && (
        <div>
          <label className="block text-xs font-medium text-theme-secondary uppercase tracking-wide mb-2">Pipeline Preview</label>
          <div className="bg-theme-bg border border-theme rounded-lg p-4">
            {(workflowDefinition as { nodes?: Array<{ id: string; type: string; label: string }> }).nodes?.length ? (
              <div className="flex flex-wrap items-center gap-2">
                {((workflowDefinition as { nodes: Array<{ id: string; type: string; label: string }> }).nodes).map((node, i, arr) => {
                  const nodeColors: Record<string, { bg: string; text: string; border: string; dot: string }> = {
                    trigger: { bg: 'bg-theme-info/15', text: 'text-theme-info', border: 'border-theme-info/30', dot: 'bg-current' },
                    ai: { bg: 'bg-theme-primary/10', text: 'text-theme-primary', border: 'border-theme-primary/25', dot: 'bg-current' },
                    action: { bg: 'bg-theme-success/15', text: 'text-theme-success', border: 'border-theme-success/30', dot: 'bg-current' },
                    condition: { bg: 'bg-theme-warning/15', text: 'text-theme-warning', border: 'border-theme-warning/30', dot: 'bg-current' },
                  };
                  const colors = nodeColors[node.type] || { bg: 'bg-theme-danger/15', text: 'text-theme-danger', border: 'border-theme-danger/30', dot: 'bg-current' };
                  return (
                    <React.Fragment key={node.id || i}>
                      <div className={`inline-flex items-center gap-1.5 px-3 py-1.5 text-xs rounded-md font-medium border ${colors.bg} ${colors.text} ${colors.border}`}>
                        <span className={`w-2 h-2 rounded-full ${colors.dot}`} />
                        {node.label || node.id}
                      </div>
                      {i < arr.length - 1 && (
                        <span className="text-theme-secondary/60 text-sm">&rarr;</span>
                      )}
                    </React.Fragment>
                  );
                })}
              </div>
            ) : (
              <p className="text-xs text-theme-secondary">No workflow nodes defined yet.</p>
            )}
          </div>
          {/* Legend */}
          <div className="flex flex-wrap gap-3 mt-2 text-[10px] text-theme-secondary">
            <span className="flex items-center gap-1 text-theme-info"><span className="w-2 h-2 rounded-full bg-current" /> Trigger</span>
            <span className="flex items-center gap-1 text-theme-success"><span className="w-2 h-2 rounded-full bg-current" /> Action</span>
            <span className="flex items-center gap-1 text-theme-primary"><span className="w-2 h-2 rounded-full bg-current" /> AI</span>
            <span className="flex items-center gap-1 text-theme-warning"><span className="w-2 h-2 rounded-full bg-current" /> Condition</span>
          </div>
        </div>
      )}
    </div>
  );
};
