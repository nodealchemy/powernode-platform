import { SkillGraphVisualization } from '@/features/ai/knowledge-graph/components/SkillGraphVisualization';

export function SkillGraphEmbed() {
  return (
    <div className="h-[600px] border border-theme rounded-lg overflow-hidden" data-testid="skill-graph-embed">
      <SkillGraphVisualization />
    </div>
  );
}
