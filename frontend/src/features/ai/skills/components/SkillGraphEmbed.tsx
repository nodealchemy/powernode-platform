import { SkillGraphVisualization } from '@/features/ai/knowledge-graph/components/SkillGraphVisualization';

interface SkillGraphEmbedProps {
  onViewSkill?: (skillId: string) => void;
}

export function SkillGraphEmbed({ onViewSkill }: SkillGraphEmbedProps) {
  return (
    <div data-testid="skill-graph-embed">
      <SkillGraphVisualization onViewSkill={onViewSkill} />
    </div>
  );
}
