import React, { useState } from 'react';
import { Wrench, Users, AlertTriangle, CheckCircle, Lightbulb } from 'lucide-react';
import { EntityLink } from '@/shared/components/entity';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { Button } from '@/shared/components/ui/Button';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useSkillCoverage, useSkillRecommendations } from '@/features/ai/knowledge-graph/api/skillGraphApi';
import type { SkillRecommendation } from '@/features/ai/knowledge-graph/types/skillGraph';

interface TeamSkillCoverageTabProps {
  teamId: string;
}

function getCoverageColor(ratio: number): string {
  if (ratio >= 0.7) return 'text-theme-success-fg';
  if (ratio >= 0.4) return 'text-theme-warning-fg';
  return 'text-theme-error-fg';
}

function getCoverageBgColor(ratio: number): string {
  if (ratio >= 0.7) return 'bg-theme-success-bg';
  if (ratio >= 0.4) return 'bg-theme-warning-bg';
  return 'bg-theme-error-bg';
}

function getCoverageLabel(ratio: number): string {
  if (ratio >= 0.7) return 'Healthy';
  if (ratio >= 0.4) return 'Moderate';
  return 'Low';
}

export const TeamSkillCoverageTab: React.FC<TeamSkillCoverageTabProps> = ({ teamId }) => {
  const { data: coverage, isLoading } = useSkillCoverage(teamId);
  const recommendMutation = useSkillRecommendations();
  const [recommendations, setRecommendations] = useState<SkillRecommendation[]>([]);

  const handleSuggest = () => {
    recommendMutation.mutate({ teamId }, {
      onSuccess: (data) => setRecommendations(data),
    });
  };

  if (isLoading) {
    return <LoadingSpinner size="sm" className="py-8" message="Loading coverage data..." />;
  }

  if (!coverage) {
    return (
      <div className="text-center py-12 bg-theme-surface border border-theme rounded-lg">
        <Wrench size={48} className="mx-auto text-theme-secondary mb-4" />
        <h3 className="text-lg font-semibold text-theme-primary mb-2">No skill coverage data</h3>
        <p className="text-theme-secondary">Sync skills to the graph first to see coverage data.</p>
      </div>
    );
  }

  const coveragePct = Math.round(coverage.coverage_ratio * 100);

  return (
    <div className="space-y-6">
      {/* Coverage Banner */}
      <Card className="p-6">
        <div className="flex items-center gap-6">
          {/* Circular Progress */}
          <div className="relative h-24 w-24 flex-shrink-0">
            <svg className="h-24 w-24 -rotate-90" viewBox="0 0 100 100">
              <circle
                cx="50" cy="50" r="42"
                fill="none"
                className="stroke-theme-surface-secondary"
                strokeWidth="8"
              />
              <circle
                cx="50" cy="50" r="42"
                fill="none"
                className={getCoverageBgColor(coverage.coverage_ratio).replace('bg-', 'stroke-')}
                strokeWidth="8"
                strokeLinecap="round"
                strokeDasharray={`${coverage.coverage_ratio * 264} 264`}
              />
            </svg>
            <div className="absolute inset-0 flex items-center justify-center">
              <span className={`text-xl font-bold ${getCoverageColor(coverage.coverage_ratio)}`}>{coveragePct}%</span>
            </div>
          </div>

          <div className="flex-1">
            <div className="flex items-center gap-2 mb-2">
              <h3 className="text-lg font-semibold text-theme-primary">Skill Coverage</h3>
              <Badge
                variant={coverage.coverage_ratio >= 0.7 ? 'success' : coverage.coverage_ratio >= 0.4 ? 'warning' : 'danger'}
                size="sm"
              >
                {getCoverageLabel(coverage.coverage_ratio)}
              </Badge>
            </div>
            <div className="grid grid-cols-3 gap-4 text-sm">
              <div>
                <span className="text-theme-tertiary">Covered</span>
                <div className="font-semibold text-theme-success-fg">{coverage.covered_count}</div>
              </div>
              <div>
                <span className="text-theme-tertiary">Uncovered</span>
                <div className="font-semibold text-theme-error-fg">{coverage.uncovered_count}</div>
              </div>
              <div>
                <span className="text-theme-tertiary">Total</span>
                <div className="font-semibold text-theme-primary">{coverage.total_skill_nodes}</div>
              </div>
            </div>
          </div>
        </div>
      </Card>

      {/* Agent-to-Skill Matrix */}
      {coverage.agent_skill_mapping?.length > 0 && (
        <Card className="p-4">
          <h4 className="text-sm font-semibold text-theme-primary mb-3 flex items-center gap-2">
            <Users size={16} />
            Agent Skill Mapping
          </h4>
          <div className="space-y-3">
            {coverage.agent_skill_mapping.map(agent => (
              <div key={agent.agent_id} className="p-3 rounded-lg border border-theme bg-theme-surface">
                <div className="flex items-center justify-between mb-2">
                  <EntityLink type="agent" id={agent.agent_id} label={agent.agent_name} className="text-sm font-medium" />
                  <Badge variant="default" size="xs">{agent.role}</Badge>
                </div>
                <div className="flex flex-wrap gap-1">
                  {agent.skills.map(skill => (
                    <EntityLink
                      key={skill.id}
                      type="skill"
                      id={skill.id}
                      label={skill.name}
                      className="px-2 py-0.5 text-xs rounded bg-theme-info-bg text-theme-info-fg"
                    />
                  ))}
                  {agent.skills.length === 0 && (
                    <span className="text-xs text-theme-tertiary">No skills assigned</span>
                  )}
                </div>
              </div>
            ))}
          </div>
        </Card>
      )}

      {/* Skill Gaps */}
      {coverage.uncovered_skills?.length > 0 && (
        <Card className="p-4">
          <h4 className="text-sm font-semibold text-theme-primary mb-3 flex items-center gap-2">
            <AlertTriangle size={16} className="text-theme-warning-fg" />
            Skill Gaps ({coverage.uncovered_skills.length})
          </h4>
          <div className="space-y-1">
            {coverage.uncovered_skills.map((skill, idx) => (
              <div
                key={skill.id || skill.name || idx}
                className="flex items-center justify-between p-2 rounded-lg border border-theme bg-theme-surface"
              >
                <EntityLink type="skill" id={skill.id} label={skill.name} className="text-sm" />
                <Badge variant="default" size="xs">{skill.category.replace(/_/g, ' ')}</Badge>
              </div>
            ))}
          </div>
        </Card>
      )}

      {/* Suggest Agents */}
      <div>
        <Button
          variant="secondary"
          size="sm"
          onClick={handleSuggest}
          disabled={recommendMutation.isPending}
        >
          <Lightbulb className="h-3.5 w-3.5 mr-1.5" />
          {recommendMutation.isPending ? 'Finding agents...' : 'Suggest Agents to Fill Gaps'}
        </Button>
      </div>

      {/* Recommendations */}
      {recommendations.length > 0 && (
        <Card className="p-4">
          <h4 className="text-sm font-semibold text-theme-primary mb-3 flex items-center gap-2">
            <CheckCircle size={16} className="text-theme-success-fg" />
            Recommendations
          </h4>
          <div className="space-y-3">
            {recommendations.map(rec => (
              <div key={rec.agent_id} className="p-3 rounded-lg border border-theme bg-theme-surface">
                <div className="flex items-center justify-between mb-2">
                  <EntityLink type="agent" id={rec.agent_id} label={rec.agent_name} className="text-sm font-medium" />
                  <Badge variant="success" size="xs">Fills {rec.fills_count} skill{rec.fills_count !== 1 ? 's' : ''}</Badge>
                </div>
                <div className="flex flex-wrap gap-1">
                  {rec.fills_skills.map(skill => (
                    <EntityLink
                      key={skill.id}
                      type="skill"
                      id={skill.id}
                      label={skill.name}
                      className="px-2 py-0.5 text-xs rounded bg-theme-success-bg text-theme-success-fg"
                    />
                  ))}
                </div>
              </div>
            ))}
          </div>
        </Card>
      )}
    </div>
  );
};
