import { SkillGraphVisualization } from '@/features/ai/knowledge-graph/components/SkillGraphVisualization';

interface SkillGraphEmbedProps {
  focusSkillId?: string;
  onViewSkill?: (skillId: string) => void;
}

export function SkillGraphEmbed({ focusSkillId, onViewSkill }: SkillGraphEmbedProps) {
  return (
    <div data-testid="skill-graph-embed">
      <SkillGraphVisualization focusSkillId={focusSkillId} onViewSkill={onViewSkill} />
    </div>
  );
}
