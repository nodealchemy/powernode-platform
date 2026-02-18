import React, { useMemo } from 'react';
import { X, Loader2, AlertTriangle } from 'lucide-react';
import { Badge } from '@/shared/components/ui/Badge';
import { useSkillGraph } from '@/features/ai/knowledge-graph/api/skillGraphApi';
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
  const { data: graphData } = useSkillGraph();

  const assignedIds = useMemo(() => new Set(assignedSkills.map(s => s.id)), [assignedSkills]);

  // Check for dependency warnings
  const getAssignWarning = (skillId: string): string | null => {
    if (!graphData?.edges) return null;
    // Skill B requires Skill A — warn if Skill A is not assigned
    const requiredEdges = graphData.edges.filter(
      e => e.source_skill_id === skillId && e.relation_type === 'requires'
    );
    const missing = requiredEdges
      .filter(e => !assignedIds.has(e.target_skill_id))
      .map(e => e.target_skill_name || e.target_skill_id);
    if (missing.length > 0) {
      return `Requires: ${missing.join(', ')}`;
    }
    return null;
  };

  const getRemoveWarning = (skillId: string): string | null => {
    if (!graphData?.edges) return null;
    // Skill A is required by Skill B — warn if Skill B is still assigned
    const dependentEdges = graphData.edges.filter(
      e => e.target_skill_id === skillId && e.relation_type === 'requires'
    );
    const blocking = dependentEdges
      .filter(e => assignedIds.has(e.source_skill_id))
      .map(e => e.source_skill_name || e.source_skill_id);
    if (blocking.length > 0) {
      return `Required by: ${blocking.join(', ')}`;
    }
    return null;
  };
  return (
    <div className="space-y-4">
      <h4 className="text-sm font-semibold text-theme-primary border-b border-theme pb-2">
        Agent Skills
      </h4>

      {/* Assigned skills display */}
      {assignedSkills.length > 0 && (
        <div className="space-y-1">
          <div className="flex flex-wrap gap-2">
            {assignedSkills.map((skill) => {
              const removeWarn = getRemoveWarning(skill.id);
              return (
                <div key={skill.id} className="flex flex-col">
                  <Badge
                    variant="info"
                    size="sm"
                    className="flex items-center gap-1"
                  >
                    {skill.name}
                    <button
                      type="button"
                      onClick={() => onRemoveSkill(skill.id)}
                      className="ml-1 hover:text-theme-error"
                      title={removeWarn || undefined}
                    >
                      <X className="w-3 h-3" />
                    </button>
                  </Badge>
                  {removeWarn && (
                    <span className="flex items-center gap-0.5 text-[10px] text-theme-warning mt-0.5">
                      <AlertTriangle className="w-2.5 h-2.5" />
                      {removeWarn}
                    </span>
                  )}
                </div>
              );
            })}
          </div>
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
                      className="flex flex-col cursor-pointer hover:bg-theme-surface-hover p-1.5 rounded text-sm"
                    >
                      <div className="flex items-center gap-2">
                        <input
                          type="checkbox"
                          checked={isAssigned}
                          onChange={(e) => {
                            if (e.target.checked) onAssignSkill(skill.id);
                            else onRemoveSkill(skill.id);
                          }}
                          className="w-4 h-4 rounded border-theme text-theme-interactive-primary focus:ring-theme-interactive-primary"
                        />
                        <span className="text-theme-primary truncate" title={skill.name}>
                          {skill.name}
                        </span>
                      </div>
                      {!isAssigned && getAssignWarning(skill.id) && (
                        <span className="flex items-center gap-0.5 text-[10px] text-theme-warning ml-6 mt-0.5">
                          <AlertTriangle className="w-2.5 h-2.5" />
                          {getAssignWarning(skill.id)}
                        </span>
                      )}
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
