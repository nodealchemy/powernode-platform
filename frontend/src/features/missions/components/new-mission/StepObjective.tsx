import React from 'react';
import { Target } from 'lucide-react';

interface StepObjectiveProps {
  objective: string;
  onObjectiveChange: (v: string) => void;
  description: string;
  onDescriptionChange: (v: string) => void;
}

export const StepObjective: React.FC<StepObjectiveProps> = ({
  objective,
  onObjectiveChange,
  description,
  onDescriptionChange,
}) => {
  return (
    <div className="space-y-5">
      <div className="flex items-center gap-3 p-4 bg-theme-surface rounded-lg">
        <Target className="w-5 h-5 text-theme-accent flex-shrink-0" />
        <div>
          <p className="text-sm font-medium text-theme-primary">Mission Objective</p>
          <p className="text-xs text-theme-tertiary">
            Describe what you want to accomplish. The AI will analyze your repository and suggest features based on this objective.
          </p>
        </div>
      </div>

      <div>
        <label className="block text-sm font-medium text-theme-primary mb-1.5">
          Objective <span className="text-xs text-theme-tertiary">(optional)</span>
        </label>
        <textarea
          value={objective}
          onChange={(e) => onObjectiveChange(e.target.value)}
          placeholder="e.g., Add user authentication with OAuth2 support and role-based access control"
          className="input-theme w-full min-h-[100px] resize-y"
          rows={4}
        />
        <p className="text-xs text-theme-tertiary mt-1">
          Leave empty to let AI analyze the repository and suggest features automatically.
        </p>
      </div>

      <div>
        <label className="block text-sm font-medium text-theme-primary mb-1.5">
          Description <span className="text-xs text-theme-tertiary">(optional)</span>
        </label>
        <textarea
          value={description}
          onChange={(e) => onDescriptionChange(e.target.value)}
          placeholder="Additional context or notes about this mission..."
          className="input-theme w-full min-h-[80px] resize-y"
          rows={3}
        />
      </div>
    </div>
  );
};
