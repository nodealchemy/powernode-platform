import React from 'react';
import { X, Loader2 } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import type { AiAgentSkill } from '@/shared/services/ai/types/agent-api-types';
import type { SkillOption } from './useEditAgentForm';

interface AgentSkillsSectionProps {
  assignedSkills: AiAgentSkill[];
  availableSkills: SkillOption[];
  loadingSkills: boolean;
  onAssignSkill: (skillId: string) => void;
  onRemoveSkill: (skillId: string) => void;
}

export const AgentSkillsSection: React.FC<AgentSkillsSectionProps> = ({
  assignedSkills,
  availableSkills,
  loadingSkills,
  onAssignSkill,
  onRemoveSkill,
}) => {
  return (
    <div className="space-y-4">
      <h4 className="text-sm font-semibold text-theme-primary border-b border-theme pb-2">
        Agent Skills
      </h4>

      {/* Assigned skills display */}
      {assignedSkills.length > 0 && (
        <div className="flex flex-wrap gap-2">
          {assignedSkills.map((skill) => (
            <Badge
              key={skill.id}
              variant="info"
              size="sm"
              className="flex items-center gap-1"
            >
              {skill.name}
              <button
                type="button"
                onClick={() => onRemoveSkill(skill.id)}
                className="ml-1 hover:text-theme-status-error"
              >
                <X className="w-3 h-3" />
              </button>
            </Badge>
          ))}
        </div>
      )}

      {/* Skill selection by category */}
      {loadingSkills ? (
        <div className="flex items-center justify-center gap-2 py-8 border border-theme rounded-lg bg-theme-surface">
          <Loader2 className="w-4 h-4 animate-spin text-theme-secondary" />
          <span className="text-sm text-theme-secondary">Loading skills...</span>
        </div>
      ) : availableSkills.length > 0 ? (
        <div className="max-h-48 overflow-y-auto border border-theme rounded-lg bg-theme-surface">
          {Object.entries(
            availableSkills.reduce<Record<string, SkillOption[]>>((acc, skill) => {
              const cat = skill.category || 'general';
              if (!acc[cat]) acc[cat] = [];
              acc[cat].push(skill);
              return acc;
            }, {})
          ).map(([category, skills]) => (
            <div key={category} className="border-b border-theme last:border-b-0">
              <div className="px-3 py-2 bg-theme-surface-hover text-xs font-semibold text-theme-secondary uppercase tracking-wider">
                {category.replace(/_/g, ' ')}
              </div>
              <div className="grid grid-cols-2 md:grid-cols-3 gap-1 p-2">
                {skills.map((skill) => {
                  const isAssigned = assignedSkills.some(as => as.id === skill.id);
                  return (
                    <label
                      key={skill.id}
                      className="flex items-center gap-2 cursor-pointer hover:bg-theme-surface-hover p-1.5 rounded text-sm"
                    >
                      <input
                        type="checkbox"
                        checked={isAssigned}
                        onChange={(e) => {
                          if (e.target.checked) onAssignSkill(skill.id);
                          else onRemoveSkill(skill.id);
                        }}
                        className="w-4 h-4 rounded border-theme text-theme-brand focus:ring-theme-brand"
                      />
                      <span className="text-theme-primary truncate" title={skill.name}>
                        {skill.name}
                      </span>
                    </label>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div className="py-4 px-3 border border-theme rounded-lg bg-theme-surface text-center">
          <p className="text-sm text-theme-secondary">
            No skills available. Create skills in the Skills page first.
          </p>
        </div>
      )}

      <p className="text-xs text-theme-secondary">
        Skills define what this agent can do and are used for task matching in Ralph Loops
      </p>
    </div>
  );
};
