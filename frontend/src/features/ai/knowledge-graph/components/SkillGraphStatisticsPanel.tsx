import React, { useMemo } from 'react';
import { Wrench, Link2, GitBranch, LayoutGrid } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import type { SkillGraphNode, SkillGraphEdge } from '../types/skillGraph';

interface SkillGraphStatisticsPanelProps {
  nodes: SkillGraphNode[];
  edges: SkillGraphEdge[];
}

export const SkillGraphStatisticsPanel: React.FC<SkillGraphStatisticsPanelProps> = ({ nodes, edges }) => {
  const stats = useMemo(() => {
    const totalSkills = nodes.length;
    const totalDeps = edges.length;
    const avgDeps = totalSkills > 0 ? totalDeps / totalSkills : 0;

    const categoryMap: Record<string, number> = {};
    for (const node of nodes) {
      categoryMap[node.category] = (categoryMap[node.category] || 0) + 1;
    }
    const categories = Object.entries(categoryMap).sort((a, b) => b[1] - a[1]);

    // Most connected: count edges per node
    const connectionCount: Record<string, number> = {};
    for (const edge of edges) {
      connectionCount[edge.source_skill_id] = (connectionCount[edge.source_skill_id] || 0) + 1;
      connectionCount[edge.target_skill_id] = (connectionCount[edge.target_skill_id] || 0) + 1;
    }
    const mostConnected = nodes
      .map(n => ({ ...n, connections: connectionCount[n.id] || 0 }))
      .sort((a, b) => b.connections - a.connections)
      .slice(0, 5);

    return { totalSkills, totalDeps, avgDeps, categories, mostConnected };
  }, [nodes, edges]);

  if (nodes.length === 0) return null;

  const summaryCards = [
    { label: 'Total Skills', value: stats.totalSkills, icon: Wrench, colorClass: 'text-theme-info', bgClass: 'bg-theme-info' },
    { label: 'Dependencies', value: stats.totalDeps, icon: Link2, colorClass: 'text-theme-success', bgClass: 'bg-theme-success' },
    { label: 'Avg Deps / Skill', value: stats.avgDeps.toFixed(1), icon: GitBranch, colorClass: 'text-theme-warning', bgClass: 'bg-theme-warning' },
    { label: 'Categories', value: stats.categories.length, icon: LayoutGrid, colorClass: 'text-theme-interactive-primary', bgClass: 'bg-theme-interactive-primary' },
  ];

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        {summaryCards.map((stat) => {
          const Icon = stat.icon;
          return (
            <Card key={stat.label} className="p-4">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-xs text-theme-tertiary">{stat.label}</p>
                  <p className="text-xl font-semibold text-theme-primary mt-1">
                    {typeof stat.value === 'number' ? stat.value.toLocaleString() : stat.value}
                  </p>
                </div>
                <div className={`h-10 w-10 ${stat.bgClass} bg-opacity-10 rounded-lg flex items-center justify-center`}>
                  <Icon className={`h-5 w-5 ${stat.colorClass}`} />
                </div>
              </div>
            </Card>
          );
        })}
      </div>

      {stats.categories.length > 0 && (
        <Card className="p-4">
          <h4 className="text-sm font-semibold text-theme-primary mb-3">Skills by Category</h4>
          <div className="flex flex-wrap gap-2">
            {stats.categories.map(([category, count]) => (
              <div
                key={category}
                className="flex items-center gap-2 px-3 py-1.5 rounded-lg border border-theme bg-theme-surface"
              >
                <span className="text-sm font-medium text-theme-primary">{category.replace(/_/g, ' ')}</span>
                <Badge variant="default" size="xs">{count}</Badge>
              </div>
            ))}
          </div>
        </Card>
      )}

      {stats.mostConnected.length > 0 && (
        <Card className="p-4">
          <h4 className="text-sm font-semibold text-theme-primary mb-3">Most Connected Skills</h4>
          <div className="space-y-2">
            {stats.mostConnected.map((node) => (
              <div
                key={node.id}
                className="flex items-center justify-between p-2 rounded-lg border border-theme bg-theme-surface"
              >
                <div className="flex items-center gap-2 min-w-0">
                  <span className="text-sm font-medium text-theme-primary truncate">{node.name}</span>
                  <Badge variant="info" size="xs">{node.category.replace(/_/g, ' ')}</Badge>
                </div>
                <span className="text-sm font-semibold text-theme-primary flex-shrink-0">
                  {node.connections} edges
                </span>
              </div>
            ))}
          </div>
        </Card>
      )}
    </div>
  );
};
