import React, { useState, useEffect } from 'react';
import { Loader2 } from 'lucide-react';
import { AgentSkillsSection } from '../AgentSkillsSection';
import { agentsApi } from '@/shared/services/ai';
import { skillsApi } from '@/features/ai/skills/services/skillsApi';
import { usePermissions } from '@/shared/hooks/usePermissions';
import { useNotification } from '@/shared/hooks/useNotification';
import type { AiAgentSkill } from '@/shared/services/ai/types/agent-api-types';
import type { SkillOption } from '../useEditAgentForm';

interface AgentSkillsTabProps {
  agentId: string;
}

export const AgentSkillsTab: React.FC<AgentSkillsTabProps> = ({ agentId }) => {
  const { hasPermission } = usePermissions();
  const { showNotification } = useNotification();
  const canManage = hasPermission('ai.agents.manage');

  const [assignedSkills, setAssignedSkills] = useState<AiAgentSkill[]>([]);
  const [availableSkills, setAvailableSkills] = useState<SkillOption[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;

    async function load() {
      try {
        setLoading(true);
        const [agentSkills, allSkillsRes] = await Promise.all([
          agentsApi.getAgentSkills(agentId),
          skillsApi.getSkills(1, 100),
        ]);
        if (!cancelled) {
          // getAgentSkills returns AiAgentSkill[] directly
          setAssignedSkills(agentSkills);
          // getSkills returns SkillsListResponse with data.skills
          const skills = allSkillsRes.data?.skills || [];
          setAvailableSkills(
            skills.map((s) => ({
              id: s.id,
              name: s.name,
              slug: s.slug,
              category: s.category,
            }))
          );
        }
      } catch {
        // Silently fail
      } finally {
        if (!cancelled) setLoading(false);
      }
    }

    load();
    return () => { cancelled = true; };
  }, [agentId]);

  const handleAssignSkill = async (skillId: string) => {
    try {
      await agentsApi.assignSkill(agentId, skillId);
      const updatedSkills = await agentsApi.getAgentSkills(agentId);
      setAssignedSkills(updatedSkills);
      showNotification('Skill assigned', 'success');
    } catch {
      showNotification('Failed to assign skill', 'error');
    }
  };

  const handleRemoveSkill = async (skillId: string) => {
    try {
      await agentsApi.removeSkill(agentId, skillId);
      setAssignedSkills(prev => prev.filter(s => s.id !== skillId));
      showNotification('Skill removed', 'success');
    } catch {
      showNotification('Failed to remove skill', 'error');
    }
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader2 className="w-5 h-5 text-theme-secondary animate-spin" />
      </div>
    );
  }

  if (!canManage) {
    // Read-only view: just show assigned skills as list
    return (
      <div className="space-y-2">
        {assignedSkills.length === 0 ? (
          <p className="text-sm text-theme-secondary text-center py-8">No skills assigned</p>
        ) : (
          assignedSkills.map((skill) => (
            <div
              key={skill.id}
              className="flex items-center justify-between px-4 py-2 border border-theme rounded-lg bg-theme-surface"
            >
              <span className="text-sm text-theme-primary">{skill.name}</span>
              <span className="text-xs text-theme-tertiary">{skill.category}</span>
            </div>
          ))
        )}
      </div>
    );
  }

  return (
    <AgentSkillsSection
      assignedSkills={assignedSkills}
      availableSkills={availableSkills}
      loadingSkills={loading}
      onAssignSkill={handleAssignSkill}
      onRemoveSkill={handleRemoveSkill}
    />
  );
};
