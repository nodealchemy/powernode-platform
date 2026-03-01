// Execute Team Modal - Collects task/prompt and context before executing a team

import React, { useState } from 'react';
import { Play, X } from 'lucide-react';
import Modal from '@/shared/components/ui/Modal';
import { AgentTeam, ExecuteTeamParams } from '../services/agentTeamsApi';

interface ExecuteTeamModalProps {
  isOpen: boolean;
  team: AgentTeam | null;
  onClose: () => void;
  onExecute: (team: AgentTeam, params: ExecuteTeamParams) => void;
}

export const ExecuteTeamModal: React.FC<ExecuteTeamModalProps> = ({
  isOpen,
  team,
  onClose,
  onExecute,
}) => {
  const [task, setTask] = useState('');
  const [context, setContext] = useState('');
  const [priority, setPriority] = useState('normal');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!team) return;

    const params: ExecuteTeamParams = {
      input: {
        task: task || `Execute ${team.name}`,
        ...(context ? { data: { additional_context: context } } : {}),
      },
      context: {
        priority,
        triggered_by: 'user',
      },
    };

    onExecute(team, params);
    handleClose();
  };

  const handleClose = () => {
    setTask('');
    setContext('');
    setPriority('normal');
    onClose();
  };

  if (!team) return null;

  return (
    <Modal
      isOpen={isOpen}
      onClose={handleClose}
      title={`Execute: ${team.name}`}
      maxWidth="md"
    >
      <form onSubmit={handleSubmit} className="space-y-5">
        <div className="flex items-center gap-3 p-3 bg-theme-info/10 border border-theme-info/20 rounded-lg">
          <Play size={18} className="text-theme-info flex-shrink-0" />
          <div className="text-sm">
            <p className="font-medium text-theme-primary">{team.name}</p>
            <p className="text-theme-secondary">
              {team.member_count} {team.member_count === 1 ? 'agent' : 'agents'} &middot; {team.coordination_strategy.replace('_', ' ')} strategy
            </p>
          </div>
        </div>

        <div>
          <label htmlFor="exec-task" className="block text-sm font-medium text-theme-primary mb-1.5">
            Task / Objective *
          </label>
          <textarea
            id="exec-task"
            value={task}
            onChange={(e) => setTask(e.target.value)}
            placeholder="Describe the task for the team to execute..."
            rows={3}
            required
            className="w-full px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-theme-info"
          />
        </div>

        <div>
          <label htmlFor="exec-context" className="block text-sm font-medium text-theme-primary mb-1.5">
            Additional Context
          </label>
          <textarea
            id="exec-context"
            value={context}
            onChange={(e) => setContext(e.target.value)}
            placeholder="Any additional context, constraints, or data for the agents..."
            rows={2}
            className="w-full px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary placeholder-theme-secondary focus:outline-none focus:ring-2 focus:ring-theme-info"
          />
        </div>

        <div>
          <label htmlFor="exec-priority" className="block text-sm font-medium text-theme-primary mb-1.5">
            Priority
          </label>
          <select
            id="exec-priority"
            value={priority}
            onChange={(e) => setPriority(e.target.value)}
            className="w-full px-3 py-2 text-sm border border-theme rounded-md bg-theme-surface text-theme-primary focus:outline-none focus:ring-2 focus:ring-theme-info"
          >
            <option value="low">Low</option>
            <option value="normal">Normal</option>
            <option value="high">High</option>
            <option value="critical">Critical</option>
          </select>
        </div>

        <div className="flex justify-end gap-3 pt-3 border-t border-theme">
          <button
            type="button"
            onClick={handleClose}
            className="btn-theme btn-theme-secondary btn-theme-md flex items-center gap-1.5"
          >
            <X size={16} />
            Cancel
          </button>
          <button
            type="submit"
            className="btn-theme btn-theme-primary btn-theme-md flex items-center gap-1.5"
          >
            <Play size={16} />
            Execute Team
          </button>
        </div>
      </form>
    </Modal>
  );
};
