import React from 'react';
import { Bot } from 'lucide-react';

interface AgentNode {
  id: string;
  name: string;
  status: 'active' | 'idle' | 'error';
  connections: string[];
}

interface ExecutionFlowVisualizationProps {
  agents?: AgentNode[];
}

const DEFAULT_AGENTS: AgentNode[] = [
  { id: '1', name: 'Coordinator', status: 'active', connections: ['2', '3'] },
  { id: '2', name: 'Executor A', status: 'active', connections: ['4'] },
  { id: '3', name: 'Executor B', status: 'idle', connections: ['4'] },
  { id: '4', name: 'Reviewer', status: 'idle', connections: [] }
];

const STATUS_COLORS: Record<string, string> = {
  active: 'bg-theme-success border-theme-success',
  idle: 'bg-theme-accent border-theme',
  error: 'bg-theme-error/20 border-theme-danger'
};

const PULSE_CLASS: Record<string, string> = {
  active: 'animate-pulse',
  idle: '',
  error: ''
};

export const ExecutionFlowVisualization: React.FC<ExecutionFlowVisualizationProps> = ({
  agents = DEFAULT_AGENTS
}) => {
  // Simple grid layout for agents
  const rows = Math.ceil(agents.length / 2);

  return (
    <div className="bg-theme-surface border border-theme rounded-lg p-6">
      <h4 className="text-sm font-semibold text-theme-primary mb-4">Execution Flow</h4>

      <div className="relative" style={{ minHeight: `${rows * 80}px` }}>
        {/* SVG connections */}
        <svg className="absolute inset-0 w-full h-full pointer-events-none" style={{ zIndex: 0 }}>
          {agents.map(agent =>
            agent.connections.map(targetId => {
              const sourceIdx = agents.findIndex(a => a.id === agent.id);
              const targetIdx = agents.findIndex(a => a.id === targetId);
              if (sourceIdx === -1 || targetIdx === -1) return null;

              const sourceCol = sourceIdx % 2;
              const sourceRow = Math.floor(sourceIdx / 2);
              const targetCol = targetIdx % 2;
              const targetRow = Math.floor(targetIdx / 2);

              const x1 = sourceCol * 50 + 25;
              const y1 = sourceRow * 80 + 30;
              const x2 = targetCol * 50 + 25;
              const y2 = targetRow * 80 + 30;

              return (
                <line
                  key={`${agent.id}-${targetId}`}
                  x1={`${x1}%`}
                  y1={y1}
                  x2={`${x2}%`}
                  y2={y2}
                  className="stroke-theme-secondary"
                  strokeWidth="1.5"
                  strokeDasharray={agent.status === 'active' ? 'none' : '4 4'}
                  opacity={0.4}
                />
              );
            })
          )}
        </svg>

        {/* Agent nodes */}
        <div className="relative grid grid-cols-2 gap-y-8" style={{ zIndex: 1 }}>
          {agents.map(agent => (
            <div key={agent.id} className="flex flex-col items-center gap-2">
              <div className={`relative h-12 w-12 rounded-full flex items-center justify-center border-2 ${STATUS_COLORS[agent.status]} ${PULSE_CLASS[agent.status]}`}>
                <Bot className={`h-5 w-5 ${
                  agent.status === 'active' ? 'text-theme-success' : 'text-theme-secondary'
                }`} />
                {agent.status === 'active' && (
                  <span className="absolute -top-1 -right-1 h-3 w-3 rounded-full bg-theme-success border-2 border-theme-surface" />
                )}
              </div>
              <span className="text-xs font-medium text-theme-primary text-center">{agent.name}</span>
              <span className={`text-xs capitalize ${
                agent.status === 'active' ? 'text-theme-success' : 'text-theme-secondary'
              }`}>
                {agent.status}
              </span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};
