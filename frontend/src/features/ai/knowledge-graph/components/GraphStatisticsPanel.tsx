import React from 'react';
import { GitBranch, Circle, Link2, BarChart3 } from 'lucide-react';
import { Card } from '@/shared/components/ui/Card';
import { Badge } from '@/shared/components/ui/Badge';
import { LoadingSpinner } from '@/shared/components/ui/LoadingSpinner';
import { useGraphStatistics } from '../api/knowledgeGraphApi';
import type { EntityType } from '../types/knowledgeGraph';

const ENTITY_TYPE_COLORS: Record<EntityType, string> = {
  concept: 'text-theme-info',
  entity: 'text-theme-success',
  document: 'text-theme-warning',
  agent: 'text-theme-interactive-primary',
  skill: 'text-theme-accent',
  context: 'text-theme-error',
  learning: 'text-theme-success',
};

export const GraphStatisticsPanel: React.FC = () => {
  const { data: stats, isLoading } = useGraphStatistics();

  if (isLoading) {
    return <LoadingSpinner size="sm" className="py-4" />;
  }

  if (!stats) {
    return null;
  }

  const summaryCards = [
    {
      label: 'Total Nodes',
      value: stats.node_count,
      icon: Circle,
      colorClass: 'text-theme-info',
      bgClass: 'bg-theme-info',
    },
    {
      label: 'Total Edges',
      value: stats.edge_count,
      icon: Link2,
      colorClass: 'text-theme-success',
      bgClass: 'bg-theme-success',
    },
    {
      label: 'Avg Degree',
      value: (stats.avg_degree ?? 0).toFixed(1),
      icon: GitBranch,
      colorClass: 'text-theme-warning',
      bgClass: 'bg-theme-warning',
    },
    {
      label: 'Entity Types',
      value: Object.keys(stats.by_entity_type || {}).length,
      icon: BarChart3,
      colorClass: 'text-theme-error',
      bgClass: 'bg-theme-error',
    },
  ];

  return (
    <div className="space-y-4">
      {/* Summary Cards */}
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

      {/* Entity Type Breakdown */}
      {stats.by_entity_type && Object.keys(stats.by_entity_type).length > 0 && (
        <Card className="p-4">
          <h4 className="text-sm font-semibold text-theme-primary mb-3">Nodes by Type</h4>
          <div className="flex flex-wrap gap-2">
            {Object.entries(stats.by_entity_type).map(([type, count]) => (
              <div
                key={type}
                className="flex items-center gap-2 px-3 py-1.5 rounded-lg border border-theme bg-theme-surface"
              >
                <span className={`text-sm font-medium ${ENTITY_TYPE_COLORS[type as EntityType] || 'text-theme-primary'}`}>
                  {type}
                </span>
                <Badge variant="default" size="xs">{count}</Badge>
              </div>
            ))}
          </div>
        </Card>
      )}

      {/* Edges by Type */}
      {stats.by_relation_type && Object.keys(stats.by_relation_type).length > 0 && (
        <Card className="p-4">
          <h4 className="text-sm font-semibold text-theme-primary mb-3">Edges by Type</h4>
          <div className="flex flex-wrap gap-2">
            {Object.entries(stats.by_relation_type).map(([type, count]) => (
              <div
                key={type}
                className="flex items-center gap-2 px-3 py-1.5 rounded-lg border border-theme bg-theme-surface"
              >
                <span className="text-sm font-medium text-theme-primary">
                  {type.replace(/_/g, ' ')}
                </span>
                <Badge variant="default" size="xs">{count}</Badge>
              </div>
            ))}
          </div>
        </Card>
      )}

      {/* Most Connected Nodes */}
      {stats.top_connected_nodes && stats.top_connected_nodes.length > 0 && (
        <Card className="p-4">
          <h4 className="text-sm font-semibold text-theme-primary mb-3">Most Connected Nodes</h4>
          <div className="space-y-2">
            {stats.top_connected_nodes.map((node) => (
              <div
                key={node.id}
                className="flex items-center justify-between p-2 rounded-lg border border-theme bg-theme-surface"
              >
                <div className="flex items-center gap-2 min-w-0">
                  <span className="text-sm font-medium text-theme-primary">
                    {node.name}
                  </span>
                  <Badge variant="info" size="xs">{node.node_type}</Badge>
                </div>
                <span className="text-sm font-semibold text-theme-primary flex-shrink-0">
                  {node.degree} edges
                </span>
              </div>
            ))}
          </div>
        </Card>
      )}
    </div>
  );
};
